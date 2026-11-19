import Foundation
@testable import TNWTrackerKit

/// In-memory server for sync tests. It keeps the contract of
/// `SupabaseTrainingRemoteStore` (the same scenarios run against both in
/// TNWTrackerTests/Sync): rows stored by id, a server `updated_at` per write
/// (rows written together share it, as in one Postgres statement), keyset
/// pulls, and the server rules a push can break (parents first, rows only
/// referring to exercises and routines the server holds, no set on a skipped
/// entry), refused as `RemoteStoreError.rejected` with the server's SQLSTATE.
///
/// It can fail the next call of an operation, or a push part way, to simulate
/// the network dropping, and run an action in the middle of the next push.
actor InMemoryTrainingRemoteStore: TrainingRemoteStore {
    enum Operation: Hashable, Sendable {
        case pushSession, upsert, pull
    }

    /// The writes of a push, in the order the real store makes them.
    enum PushStep: Int, Comparable, Sendable {
        case deleteSets, deleteEntries, session, entries, sets

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Call: Equatable, Sendable {
        case pushSession(UUID)
        case upsert(RemoteTable, count: Int)
        case pull(RemoteTable, after: RemoteCursor?, limit: Int)
    }

    static let networkDown = URLError(.notConnectedToInternet)

    /// What the server answers for a broken foreign key or check.
    static func foreignKeyViolation(_ constraint: String) -> RemoteStoreError {
        .rejected(code: "23503", message: constraint)
    }

    static let skippedEntryWithSets = RemoteStoreError.rejected(code: "23514", message: "a skipped entry has no sets")

    private(set) var calls: [Call] = []
    private var failures: [Operation: [any Error]] = [:]
    private var pushFailure: (step: PushStep, error: any Error)?
    private var tables: [RemoteTable: [UUID: any RemoteRow]] = [:]
    private var clock = 0
    /// The curated catalogue of supabase/seed.sql, which every user can refer to.
    private let catalogue: Set<UUID>
    private var duringNextPush: (@Sendable () async -> Void)?

    init(catalogue: Set<UUID> = TrainingRemoteStoreContract.catalogue) {
        self.catalogue = catalogue
    }

    // MARK: - Test controls

    /// The next call of `operation` throws `error` and changes nothing.
    func failNext(_ operation: Operation, with error: any Error = networkDown) {
        failures[operation, default: []].append(error)
    }

    /// The next push writes the steps before `step`, then throws `error`.
    func failNextPush(at step: PushStep, with error: any Error = networkDown) {
        pushFailure = (step, error)
    }

    /// The next push runs `action` once its session row is written, before its
    /// entries and sets: as if the user edited the data while it uploads.
    func duringNextPush(_ action: @escaping @Sendable () async -> Void) {
        duringNextPush = action
    }

    /// Writes a row as another client would (an importer, another device).
    func insertOnServer<Row: RemoteRow>(_ row: Row) throws {
        try write([row])
    }

    /// Rows of `type` stored now, in cursor order.
    func stored<Row: RemoteRow>(_ type: Row.Type) -> [Row] {
        ordered(type)
    }

    // MARK: - TrainingRemoteStore

    func pushSession(_ aggregate: RemoteSessionAggregate) async throws {
        calls.append(.pushSession(aggregate.session.id))
        try throwIfFailing(.pushSession)
        try aggregate.validate()
        let failure = pushFailure
        pushFailure = nil

        func run(_ step: PushStep, _ write: () throws -> Void) throws {
            if let failure, failure.step == step { throw failure.error }
            try write()
        }
        let entryIds = Set(aggregate.entries.map(\.id) + aggregate.removedEntryIds)
        try run(.deleteSets) {
            let sets = aggregate.removedSetIds.filter { id in
                (tables[.sets]?[id] as? RemoteSetRow).map { entryIds.contains($0.entryId) } ?? false
            }
            delete(sets, from: .sets)
        }
        try run(.deleteEntries) {
            deleteEntries(aggregate.removedEntryIds.filter { id in
                (tables[.entries]?[id] as? RemoteEntryRow)?.sessionId == aggregate.session.id
            })
        }
        try run(.session) { try write([aggregate.session]) }
        if let action = duringNextPush {
            duringNextPush = nil
            await action()
        }
        try run(.entries) { try write(aggregate.entries) }
        try run(.sets) { try write(aggregate.sets) }
    }

    func upsert<Row: RemoteRow>(_ rows: [Row]) async throws {
        calls.append(.upsert(Row.table, count: rows.count))
        try throwIfFailing(.upsert)
        try write(rows)
    }

    func pull<Row: RemoteRow>(
        _ type: Row.Type,
        after cursor: RemoteCursor?,
        limit: Int
    ) async throws -> RemotePage<Row> {
        calls.append(.pull(Row.table, after: cursor, limit: limit))
        try throwIfFailing(.pull)
        let rows = ordered(type).filter { row in
            guard let cursor, let updatedAt = row.updatedAt else { return true }
            return (updatedAt, Self.key(row.id)) > (cursor.updatedAt, Self.key(cursor.id))
        }
        return RemotePage(rows: Array(rows.prefix(limit)), limit: limit)
    }

    // MARK: - Storage

    private func throwIfFailing(_ operation: Operation) throws {
        guard var queue = failures[operation], !queue.isEmpty else { return }
        let error = queue.removeFirst()
        failures[operation] = queue
        throw error
    }

    /// One statement: every row gets the same new `updated_at`, or none is written.
    private func write<Row: RemoteRow>(_ rows: [Row]) throws {
        guard !rows.isEmpty else { return }
        for row in rows {
            try check(row)
        }
        clock += 1
        let now = Self.timestamp(clock)
        for var row in rows {
            row.updatedAt = now
            tables[Row.table, default: [:]][row.id] = row
        }
    }

    private func check(_ row: some RemoteRow) throws {
        switch row {
        case let session as RemoteSessionRow:
            try require(session.routineId, in: .routines, "sessions_routine_fkey")
        case let entry as RemoteEntryRow:
            try check(entry)
        case let set as RemoteSetRow:
            guard let entry = tables[.entries]?[set.entryId] as? RemoteEntryRow else {
                throw Self.foreignKeyViolation("sets_entry_fkey")
            }
            if entry.status == .skipped { throw Self.skippedEntryWithSets }
        case let group as RemoteMuscleGroupRow:
            try require(group.exerciseId, in: .exercises, "exercise_muscle_groups_exercise_id_fkey")
        case let item as RemoteRoutineItemRow:
            try require(item.routineId, in: .routines, "routine_items_routine_fkey")
            try requireExercise(item.exerciseId, "routine_items_exercise_id_fkey")
        default:
            break
        }
    }

    private func check(_ entry: RemoteEntryRow) throws {
        try require(entry.sessionId, in: .sessions, "entries_session_fkey")
        try requireExercise(entry.exerciseId, "entries_exercise_id_fkey")
        try requireExercise(entry.replacedExerciseId, "entries_replaced_exercise_id_fkey")
        if entry.status == .skipped, !setsOf(entry.id).isEmpty { throw Self.skippedEntryWithSets }
    }

    /// A `nil` reference refers to nothing, so it always holds.
    private func require(_ id: UUID?, in table: RemoteTable, _ constraint: String) throws {
        guard let id, tables[table]?[id] == nil else { return }
        throw Self.foreignKeyViolation(constraint)
    }

    private func requireExercise(_ id: UUID?, _ constraint: String) throws {
        guard let id else { return }
        guard catalogue.contains(id) || tables[.exercises]?[id] != nil else {
            throw Self.foreignKeyViolation(constraint)
        }
    }

    private func setsOf(_ entryId: UUID) -> [RemoteSetRow] {
        (tables[.sets]?.values.compactMap { $0 as? RemoteSetRow } ?? []).filter { $0.entryId == entryId }
    }

    private func delete(_ ids: [UUID], from table: RemoteTable) {
        for id in ids {
            tables[table]?[id] = nil
        }
    }

    /// Deleting an entry cascades to its sets.
    private func deleteEntries(_ ids: [UUID]) {
        for id in ids {
            delete(setsOf(id).map(\.id), from: .sets)
        }
        delete(ids, from: .entries)
    }

    private func ordered<Row: RemoteRow>(_ type: Row.Type) -> [Row] {
        (tables[Row.table]?.values.compactMap { $0 as? Row } ?? []).sorted {
            ($0.updatedAt ?? "", Self.key($0.id)) < ($1.updatedAt ?? "", Self.key($1.id))
        }
    }

    /// Postgres orders uuids by their bytes, which is the order of the lower-case text.
    private static func key(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    private static func timestamp(_ tick: Int) -> String {
        String(format: "2026-01-01T00:00:%02d.%06d+00:00", tick / 1_000_000, tick % 1_000_000)
    }
}
