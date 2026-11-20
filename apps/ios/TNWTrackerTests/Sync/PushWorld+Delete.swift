import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

/// Helpers for the delete tests (S11): data the device deletes through its
/// own commands, and the local tombstones they leave. Invented data only.
@MainActor
extension PushWorld {
    /// A machine exercise of the imported bundles. Its id follows the user, so
    /// throwaway users on the local stack never share it.
    var press: Exercise {
        let id = UUID(uuidString: "e5000000" + userId.uuidString.dropFirst(8)) ?? userId
        return Exercise(id: id, externalRef: ref("ex-press"), name: "Chest Press Machine", type: .strength)
    }

    /// Two import-only sessions, on Monday and Wednesday, pushed; then a
    /// re-import regroups Wednesday's entry under Monday, which removes
    /// Wednesday on the device and leaves its tombstone (D8). Pushes with
    /// `engine`, the world's own by default.
    func importThenRegroup(using engine: TrainingSyncEngine? = nil) async throws -> (monday: UUID, wednesday: UUID) {
        func entry(_ ref: String) -> ImportedEntry {
            ImportedEntry(exerciseId: press.id, externalRef: self.ref(ref), sets: [
                ImportedSet(externalRef: self.ref("\(ref)#1"), order: 1, values: SetValues(reps: 10, weight: .kg(40)))
            ])
        }
        func bundle(_ ref: String, day: Double, _ entries: [ImportedEntry]) -> BundleSession {
            BundleSession(
                id: UUID(), externalRef: self.ref(ref), completedAt: t0.addingTimeInterval(day * 86_400),
                timeZone: "UTC", entries: entries
            )
        }
        let monday = bundle("w-1", day: 0, [entry("e-1")])
        let wednesday = bundle("w-2", day: 2, [entry("e-2")])
        let first = try store.importer.importBundle(TrainingBundle(exercises: [press], sessions: [monday, wednesday]))
        let mondayId = try #require(first.sessionIds[monday.id])
        let wednesdayId = try #require(first.sessionIds[wednesday.id])
        try await (engine ?? self.engine).push()
        try store.importer.importBundle(
            TrainingBundle(exercises: [press], sessions: [bundle("w-1", day: 0, [entry("e-1"), entry("e-2")])])
        )
        #expect(try store.sessions.session(id: wednesdayId) == nil)
        #expect(try store.syncState.tombstones().map(\.id) == [wednesdayId])
        return (mondayId, wednesdayId)
    }

    /// Every local tombstone, children of sessions included.
    func localTombstones() throws -> [SyncTombstoneModel] {
        try store.context.fetch(FetchDescriptor<SyncTombstoneModel>())
    }

    /// Deletes a sent session and a user exercise only it used, as a command
    /// would, leaving their tombstones. No command deletes exercises yet, so the
    /// exercise's tombstone is written here the way the session's is.
    func deleteLocally(session id: UUID, andExercise exerciseId: UUID) throws {
        let context = store.context
        let session = try #require(try context.fetchSession(id: id))
        try context.recordDeletion(of: session)
        context.delete(session)
        let exercise = try #require(try context.fetchExercise(id: exerciseId))
        context.insert(SyncTombstoneModel(
            kindRaw: SyncTombstoneKind.exercise.rawValue, rowId: exerciseId, sessionId: nil,
            revision: exercise.syncRevision + 1, deletedAt: Date()
        ))
        context.delete(exercise)
        try context.save()
    }

    /// Server tombstones as `table:row` text.
    func serverTombstones() async -> Set<String> {
        await Set(server.stored(RemoteTombstoneRow.self).map { "\($0.tableName):\($0.rowId)" })
    }
}
