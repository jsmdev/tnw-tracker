import Foundation
@testable import TNWTrackerKit

/// In-memory server for sync tests. It keeps the contract of
/// `SupabaseTrainingRemoteStore` (the same scenarios run against both in
/// TNWTrackerTests/Sync): rows stored by id, a server `updated_at` per write
/// (rows written together share it, as in one Postgres statement), keyset
/// pulls, and the server rules a push can break (parents first, rows only
/// referring to exercises and routines the server holds, no set on a skipped
/// entry, one row per user and external ref, one muscle group per muscle of an
/// exercise and one item per routine position, one done entry per exercise of
/// a session, no delete of an exercise in use), refused as
/// `RemoteStoreError.rejected` with the server's SQLSTATE. A row naming an
/// exercise the server does not hold is refused by row-level security (42501),
/// as the server's policies check it before the foreign key.
/// Like the server's triggers, every delete records a tombstone of each deleted
/// session, entry, set, routine, user exercise, muscle group, routine item and
/// exercise setting (a session's cascade included; the children deleted with
/// their exercise or routine leave none), and writing a row again under its id
/// clears its tombstone.
///
/// Exercise settings are stored by their exercise id, which is their key for
/// the one user a fake serves.
///
/// Like a network request, a call made from a cancelled task throws
/// `CancellationError` and is not made (it is not recorded either).
///
/// It can fail the next call of an operation, the next pull of a table, or a
/// push part way, to simulate the network dropping, and run an action in the
/// middle of the next push. Its clock ticks one microsecond per statement and
/// can jump ahead, to place writes outside the pull's overlap window.
actor InMemoryTrainingRemoteStore: TrainingRemoteStore {
    enum Operation: Hashable, Sendable {
        case pushSession, upsert, delete, deleteChildren, pull
    }

    /// The writes of a push, in the order the real store makes them.
    enum PushStep: Int, Comparable, Sendable {
        case deleteSets, deleteEntries, session, entries, sets

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Call: Equatable, Sendable {
        case pushSession(UUID)
        case upsert(RemoteTable, count: Int)
        case delete(RemoteTable, ids: [UUID])
        case deleteChildren(RemoteTable, parentId: UUID, keeping: [UUID])
        case pull(RemoteTable, after: RemoteCursor?, limit: Int)
    }

    static let networkDown = URLError(.notConnectedToInternet)

    /// What the server answers for a broken foreign key or check.
    static func foreignKeyViolation(_ constraint: String) -> RemoteStoreError {
        .rejected(code: "23503", message: constraint)
    }

    /// What the server answers for a row whose policy names an exercise the user cannot see.
    static func rowLevelSecurity(_ table: RemoteTable) -> RemoteStoreError {
        .rejected(code: "42501", message: "new row violates row-level security policy for table \"\(table.rawValue)\"")
    }

    static let skippedEntryWithSets = RemoteStoreError.rejected(code: "23514", message: "a skipped entry has no sets")

    /// What the server answers for a second row of the user with the same external ref.
    static func duplicateExternalRef(_ table: RemoteTable) -> RemoteStoreError {
        .rejected(code: "23505", message: "\(table.rawValue)_external_ref_key")
    }

    private(set) var calls: [Call] = []
    private var failures: [Operation: [any Error]] = [:]
    private var pullFailures: [RemoteTable: (pagesFirst: Int, error: any Error)] = [:]
    private var pushFailure: (step: PushStep, error: any Error)?
    /// Rows by table and id. Internal for the delete half (`+Deletes.swift`).
    var tables: [RemoteTable: [UUID: any RemoteRow]] = [:]
    var clock = 0
    /// The curated catalogue of supabase/seed.sql, which every user can refer to.
    private let catalogue: Set<UUID>
    private var duringNextPush: (@Sendable () async -> Void)?
    private var duringNextPull: (table: RemoteTable?, action: @Sendable () async -> Void)?
    private var duringNextUpsert: (table: RemoteTable, action: @Sendable () async -> Void)?

    init(catalogue: Set<UUID> = TrainingRemoteStoreContract.catalogue) {
        self.catalogue = catalogue
    }

    // MARK: - Test controls

    /// The next call of `operation` throws `error` and changes nothing.
    func failNext(_ operation: Operation, with error: any Error = networkDown) {
        failures[operation, default: []].append(error)
    }

    /// A pull of `table` throws `error` and returns nothing, once `pages` more
    /// pulls of it have succeeded.
    func failNextPull(of table: RemoteTable, afterPages pages: Int = 0, with error: any Error = networkDown) {
        pullFailures[table] = (pages, error)
    }

    /// Moves the server clock `seconds` ahead: the next write is that much later.
    func advanceClock(seconds: Int) {
        clock += seconds * 1_000_000
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

    /// The next upsert of `table` runs `action` once its rows are written: as if
    /// the user edited the data while it uploads.
    func duringNextUpsert(of table: RemoteTable, _ action: @escaping @Sendable () async -> Void) {
        duringNextUpsert = (table, action)
    }

    /// The next pull (of `table`, when given) runs `action` before it answers:
    /// as if the device or another client changed data while the pages were read.
    func duringNextPull(of table: RemoteTable? = nil, _ action: @escaping @Sendable () async -> Void) {
        duringNextPull = (table, action)
    }

    /// Writes a row as another client would (an importer, another device).
    func insertOnServer<Row: RemoteRow>(_ row: Row) throws {
        try write([row], asClient: false)
    }

    /// Deletes rows as another client would (an importer, another device),
    /// with the cascades and tombstones of the server.
    func deleteOnServer(_ table: RemoteTable, ids: [UUID]) throws {
        try remove(table, ids: ids)
    }

    /// Writes a row whose transaction committed late: its `updated_at` is
    /// `seconds` behind the clock, so a cursor may already be past it.
    func insertLateOnServer<Row: RemoteRow>(_ row: Row, secondsBehind seconds: Int) throws {
        try check(row)
        try checkExternalRefs([row])
        var row = row
        row.updatedAt = Self.timestamp(clock - seconds * 1_000_000)
        let inserted = tables[Row.table]?[row.id] == nil
        tables[Row.table, default: [:]][row.id] = row
        if inserted { clearTombstones(Row.table, ids: [row.id]) }
    }

    /// Rows of `type` stored now, in cursor order.
    func stored<Row: RemoteRow>(_ type: Row.Type) -> [Row] {
        ordered(type)
    }

    // MARK: - TrainingRemoteStore

    func pushSession(_ aggregate: RemoteSessionAggregate) async throws {
        try Task.checkCancellation()
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
            try remove(.sets, ids: sets)
        }
        try run(.deleteEntries) {
            let removed = aggregate.removedEntryIds.filter { id in
                (tables[.entries]?[id] as? RemoteEntryRow)?.sessionId == aggregate.session.id
            }
            // A set the aggregate does not list is one the device never saw: its entry stays.
            let listed = Set(aggregate.sets.map(\.id))
            let kept = removed.filter { id in setsOf(id).contains { !listed.contains($0.id) } }
            try remove(.entries, ids: removed.filter { !kept.contains($0) })
            touch(entries: kept)
        }
        try run(.session) { try write([aggregate.session], asClient: true) }
        if let action = duringNextPush {
            duringNextPush = nil
            await action()
        }
        try run(.entries) { try write(aggregate.entries, asClient: true) }
        try run(.sets) { try write(aggregate.sets, asClient: true) }
    }

    func upsert<Row: RemoteRow>(_ rows: [Row]) async throws {
        try Task.checkCancellation()
        calls.append(.upsert(Row.table, count: rows.count))
        try throwIfFailing(.upsert)
        try write(rows, asClient: true)
        if let hook = duringNextUpsert, hook.table == Row.table {
            duringNextUpsert = nil
            await hook.action()
        }
    }

    func delete(_ table: RemoteTable, ids: [UUID]) async throws {
        try Task.checkCancellation()
        calls.append(.delete(table, ids: ids))
        try throwIfFailing(.delete)
        try remove(table, ids: ids)
    }

    func deleteChildren(_ table: RemoteTable, of parentId: UUID, keeping ids: [UUID]) async throws {
        try Task.checkCancellation()
        calls.append(.deleteChildren(table, parentId: parentId, keeping: ids))
        try throwIfFailing(.deleteChildren)
        let keep = Set(ids)
        let children: [UUID] = switch table {
        case .exerciseMuscleGroups: rows(RemoteMuscleGroupRow.self).filter { $0.exerciseId == parentId }.map(\.id)
        case .routineItems: rows(RemoteRoutineItemRow.self).filter { $0.routineId == parentId }.map(\.id)
        default: throw RemoteStoreError.invalidAggregate("\(table.rawValue) has no parent to delete children of")
        }
        try remove(table, ids: children.filter { !keep.contains($0) })
    }

    func pull<Row: RemoteRow>(
        _ type: Row.Type,
        after cursor: RemoteCursor?,
        limit: Int
    ) async throws -> RemotePage<Row> {
        try Task.checkCancellation()
        calls.append(.pull(Row.table, after: cursor, limit: limit))
        try throwIfFailing(.pull)
        if let hook = duringNextPull, hook.table == nil || hook.table == Row.table {
            duringNextPull = nil
            await hook.action()
        }
        if let failure = pullFailures[Row.table] {
            if failure.pagesFirst == 0 {
                pullFailures[Row.table] = nil
                throw failure.error
            }
            pullFailures[Row.table]?.pagesFirst -= 1
        }
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
    /// `asClient`: an app upsert, which never sends the columns the app only
    /// reads (`related_videos`); like the server, the stored value stays.
    private func write<Row: RemoteRow>(_ rows: [Row], asClient: Bool) throws {
        guard !rows.isEmpty else { return }
        for row in rows {
            try check(row)
        }
        try checkExternalRefs(rows)
        try checkNaturalKeys(rows)
        let inserted = rows.map(\.id).filter { tables[Row.table]?[$0] == nil }
        clock += 1
        let now = Self.timestamp(clock)
        for var row in rows {
            row.updatedAt = now
            if asClient, var exercise = row as? RemoteExerciseRow {
                exercise.relatedVideos = (tables[Row.table]?[row.id] as? RemoteExerciseRow)?.relatedVideos
                if let typed = exercise as? Row { row = typed }
            }
            tables[Row.table, default: [:]][row.id] = row
        }
        clearTombstones(Row.table, ids: inserted)
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
            // The policy: the user's own exercise.
            guard tables[.exercises]?[group.exerciseId] != nil else {
                throw Self.rowLevelSecurity(.exerciseMuscleGroups)
            }
        case let item as RemoteRoutineItemRow:
            try requireExercise(item.exerciseId, .routineItems)
            try require(item.routineId, in: .routines, "routine_items_routine_fkey")
        case let setting as RemoteExerciseSettingRow:
            try requireExercise(setting.exerciseId, .exerciseSettings)
        default:
            break
        }
    }

    private func check(_ entry: RemoteEntryRow) throws {
        try requireExercise(entry.exerciseId, .entries)
        try requireExercise(entry.replacedExerciseId, .entries)
        try require(entry.sessionId, in: .sessions, "entries_session_fkey")
        if entry.status == .skipped, !setsOf(entry.id).isEmpty { throw Self.skippedEntryWithSets }
    }

    /// `UNIQUE (user_id, external_provider, external_id)`: another row of the
    /// user, stored or in the same statement, holding the ref refuses the write.
    private func checkExternalRefs<Row: RemoteRow>(_ rows: [Row]) throws {
        let written = Set(rows.map(\.id))
        let stored = (tables[Row.table]?.values.compactMap { $0 as? Row } ?? []).filter { !written.contains($0.id) }
        var seen: [UUID: String] = [:]
        for row in rows + stored {
            if let key = Self.externalRefKey(row) { seen[row.id] = key }
        }
        guard Set(seen.values).count == seen.count else { throw Self.duplicateExternalRef(Row.table) }
    }

    /// `exercise_muscle_groups_key`, `routine_items_position_key` and
    /// `entries_one_done_per_exercise`: a row under another id holding the same
    /// muscle of an exercise, the same position of a routine, or a done entry of
    /// the same exercise in a session, refuses the write.
    private func checkNaturalKeys<Row: RemoteRow>(_ rows: [Row]) throws {
        let written = Set(rows.map(\.id))
        let stored = (tables[Row.table]?.values.compactMap { $0 as? Row } ?? []).filter { !written.contains($0.id) }
        let keys = (rows + stored).compactMap { row -> String? in
            switch row {
            case let group as RemoteMuscleGroupRow: "\(group.exerciseId)/\(group.muscle)/\(group.role)"
            case let item as RemoteRoutineItemRow: "\(item.routineId)/\(item.position)"
            case let entry as RemoteEntryRow where entry.status == .done: "\(entry.sessionId)/\(entry.exerciseId)"
            default: nil
            }
        }
        guard Set(keys).count == keys.count else {
            throw RemoteStoreError.rejected(code: "23505", message: "\(Row.table.rawValue) natural key")
        }
    }

    private static func externalRefKey(_ row: some RemoteRow) -> String? {
        let owned: (UUID?, ExternalRef?)? = switch row {
        case let row as RemoteSessionRow: (row.userId, row.externalRef)
        case let row as RemoteEntryRow: (row.userId, row.externalRef)
        case let row as RemoteSetRow: (row.userId, row.externalRef)
        case let row as RemoteRoutineRow: (row.userId, row.externalRef)
        case let row as RemoteExerciseRow: (row.userId, row.externalRef)
        default: nil
        }
        guard let owned, let ref = owned.1 else { return nil }
        return "\(owned.0?.uuidString ?? "catalogue")/\(ref.provider)/\(ref.id)"
    }

    /// A `nil` reference refers to nothing, so it always holds.
    private func require(_ id: UUID?, in table: RemoteTable, _ constraint: String) throws {
        guard let id, tables[table]?[id] == nil else { return }
        throw Self.foreignKeyViolation(constraint)
    }

    /// Row-level security of `table`: the exercise is one the user can see.
    private func requireExercise(_ id: UUID?, _ table: RemoteTable) throws {
        guard let id else { return }
        guard catalogue.contains(id) || tables[.exercises]?[id] != nil else {
            throw Self.rowLevelSecurity(table)
        }
    }

    func setsOf(_ entryId: UUID) -> [RemoteSetRow] {
        (tables[.sets]?.values.compactMap { $0 as? RemoteSetRow } ?? []).filter { $0.entryId == entryId }
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

    /// `tick` microseconds after 2026-01-01T00:00:00Z, written as Postgres does.
    static func timestamp(_ tick: Int) -> String {
        let date = Date(timeIntervalSince1970: 1_767_225_600 + TimeInterval(tick / 1_000_000))
        let seconds = ISO8601DateFormatter().string(from: date).dropLast() // drops the "Z"
        return seconds + String(format: ".%06d+00:00", tick % 1_000_000)
    }
}
