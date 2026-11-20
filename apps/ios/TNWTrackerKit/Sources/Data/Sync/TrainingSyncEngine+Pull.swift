import Foundation

/// The rows one pull read, per table, each in cursor order.
struct PulledBatch: Sendable {
    var exercises: [RemoteExerciseRow] = []
    var muscleGroups: [RemoteMuscleGroupRow] = []
    var routines: [RemoteRoutineRow] = []
    var routineItems: [RemoteRoutineItemRow] = []
    var sessions: [RemoteSessionRow] = []
    var entries: [RemoteEntryRow] = []
    var sets: [RemoteSetRow] = []
}

/// Pull rules (docs/database-schema.md, "Sync"):
/// - Only when the store's owner is the signed-in user (S10), checked again
///   before anything is applied.
/// - Every table is read from its cursor, rewound by `pullOverlap`, page by page
///   until a page is not full. Children are read before their parents, so the
///   parent of every child read is read too, or was already on the device.
/// - Nothing is applied until every table is read; then everything, cursors
///   included, is applied in one save, parents first. A failure anywhere leaves
///   the store and the cursors as they were (S4).
extension TrainingSyncEngine {
    func pullChanges() async throws -> SyncPullReport {
        try requireOwner()
        var batch = PulledBatch()
        batch.sets = try await readAll(RemoteSetRow.self)
        batch.entries = try await readAll(RemoteEntryRow.self)
        batch.sessions = try await readAll(RemoteSessionRow.self)
        batch.routineItems = try await readAll(RemoteRoutineItemRow.self)
        batch.routines = try await readAll(RemoteRoutineRow.self)
        batch.muscleGroups = try await readAll(RemoteMuscleGroupRow.self)
        batch.exercises = try await readAll(RemoteExerciseRow.self)
        // The store may have changed hands while the pages were read.
        try requireOwner()
        return try store.pulled.apply(batch, userId: userId)
    }

    private func requireOwner() throws {
        let owner = try store.ownership.owner()
        guard owner == userId else { throw TrainingSyncError.storeNotOwned(userId: userId, owner: owner) }
    }

    private func readAll<Row: RemoteRow>(_ type: Row.Type) async throws -> [Row] {
        let stored = try store.pulled.cursor(Row.table, userId: userId)
        var cursor = stored.map { $0.rewound(by: pullOverlap) ?? $0 }
        var rows: [Row] = []
        while true {
            let page = try await remote.pull(type, after: cursor, limit: pageSize)
            rows += page.rows
            guard page.mayHaveMore, let next = page.next else { return rows }
            cursor = next
        }
    }
}
