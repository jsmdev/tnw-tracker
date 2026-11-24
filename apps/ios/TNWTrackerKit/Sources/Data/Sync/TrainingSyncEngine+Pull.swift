import Foundation

/// The rows one pull read, per table, each in cursor order.
struct PulledBatch: Sendable {
    var tombstones: [RemoteTombstoneRow] = []
    var exercises: [RemoteExerciseRow] = []
    var muscleGroups: [RemoteMuscleGroupRow] = []
    var routines: [RemoteRoutineRow] = []
    var routineItems: [RemoteRoutineItemRow] = []
    var sessions: [RemoteSessionRow] = []
    var entries: [RemoteEntryRow] = []
    var sets: [RemoteSetRow] = []
    var exerciseSettings: [RemoteExerciseSettingRow] = []
    var exerciseLinks: [RemoteExerciseLinkRow] = []

    /// Every user a row of the batch belongs to. Catalogue exercises belong to
    /// nobody; muscle groups follow their exercise. A link is its user's, also
    /// on a catalogue exercise.
    var userIds: Set<UUID> {
        var ids = Set(tombstones.map(\.userId))
        ids.formUnion(exercises.compactMap(\.userId))
        ids.formUnion(routines.map(\.userId))
        ids.formUnion(routineItems.map(\.userId))
        ids.formUnion(sessions.map(\.userId))
        ids.formUnion(entries.map(\.userId))
        ids.formUnion(sets.map(\.userId))
        ids.formUnion(exerciseSettings.map(\.userId))
        ids.formUnion(exerciseLinks.map(\.userId))
        return ids
    }
}

/// Pull rules (docs/database-schema.md, "Sync"):
/// - Only when the store's owner is the signed-in user (S10), checked again
///   before anything is applied.
/// - Every table is read from its cursor, rewound by `pullOverlap`, page by page
///   until a page is not full. The tombstones go first, then children before
///   their parents, so the parent of every child read is read too, or was
///   already on the device, and a row read after its tombstone exists again.
/// - Nothing is applied until every table is read; then everything, cursors
///   included, is applied in one save, parents first. A failure anywhere leaves
///   the store and the cursors as they were (S4).
/// - A batch with any row of another user is not applied at all (S10), nor is
///   one read by an engine stopped meanwhile (a sign-out).
extension TrainingSyncEngine {
    func pullChanges() async throws -> SyncPullReport {
        try requireOwner()
        var batch = PulledBatch()
        batch.tombstones = try await readAll(RemoteTombstoneRow.self)
        batch.sets = try await readAll(RemoteSetRow.self)
        batch.entries = try await readAll(RemoteEntryRow.self)
        batch.sessions = try await readAll(RemoteSessionRow.self)
        batch.routineItems = try await readAll(RemoteRoutineItemRow.self)
        batch.routines = try await readAll(RemoteRoutineRow.self)
        batch.muscleGroups = try await readAll(RemoteMuscleGroupRow.self)
        batch.exerciseSettings = try await readAll(RemoteExerciseSettingRow.self)
        batch.exerciseLinks = try await readAll(RemoteExerciseLinkRow.self)
        batch.exercises = try await readAll(RemoteExerciseRow.self)
        // The store may have changed hands while the pages were read.
        try requireOwner()
        try checkRunning()
        guard batch.userIds.isSubset(of: [userId]) else { throw TrainingSyncError.pulledRowsOfAnotherUser }
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
            try checkRunning()
            let page = try await remote.pull(type, after: cursor, limit: pageSize)
            rows += page.rows
            guard page.mayHaveMore, let next = page.next else { return rows }
            cursor = next
        }
    }
}
