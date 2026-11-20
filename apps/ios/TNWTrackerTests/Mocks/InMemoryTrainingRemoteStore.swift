import Foundation
@testable import TNWTrackerKit

/// In-memory server for sync tests. It keeps the contract of
/// `SupabaseTrainingRemoteStore` (the same scenarios run against both in
/// TNWTrackerTests/Sync): rows stored by id, a server `updated_at` per write
/// (rows written together share it, as in one Postgres statement), keyset
/// pulls, and the server rules a push can break (parents first, no set on a
/// skipped entry).
///
/// It can fail the next call of an operation, or a push part way, to simulate
/// the network dropping.
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

    /// The server refused a write (what Postgres reports as a constraint or trigger error).
    struct Rejected: Error, Equatable {
        let reason: String
    }

    static let networkDown = URLError(.notConnectedToInternet)

    private(set) var calls: [Call] = []
    private var failures: [Operation: [any Error]] = [:]
    private var pushFailure: (step: PushStep, error: any Error)?
    private var tables: [RemoteTable: [UUID: any RemoteRow]] = [:]
    private var clock = 0

    // MARK: - Test controls

    /// The next call of `operation` throws `error` and changes nothing.
    func failNext(_ operation: Operation, with error: any Error = networkDown) {
        failures[operation, default: []].append(error)
    }

    /// The next push writes the steps before `step`, then throws `error`.
    func failNextPush(at step: PushStep, with error: any Error = networkDown) {
        pushFailure = (step, error)
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
        case let entry as RemoteEntryRow:
            guard tables[.sessions]?[entry.sessionId] != nil else { throw Rejected(reason: "entries_session_fkey") }
            if entry.status == .skipped, !setsOf(entry.id).isEmpty {
                throw Rejected(reason: "a skipped entry has no sets")
            }
        case let set as RemoteSetRow:
            guard let entry = tables[.entries]?[set.entryId] as? RemoteEntryRow else {
                throw Rejected(reason: "sets_entry_fkey")
            }
            if entry.status == .skipped { throw Rejected(reason: "a skipped entry has no sets") }
        default:
            break
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
