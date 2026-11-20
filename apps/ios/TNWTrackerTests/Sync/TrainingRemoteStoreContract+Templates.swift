import Foundation
import Testing
@testable import TNWTrackerKit

/// Muscle groups, routine items and exercise settings (T6): behaviour every
/// `TrainingRemoteStore` keeps, run against the fake and the local stack like
/// the rest of `TrainingRemoteStoreContract`.
extension TrainingRemoteStoreContract {
    /// Deleting the children a parent no longer lists removes only those, each
    /// leaving a tombstone of the owner; an empty list removes them all, and
    /// sending it again is harmless. Muscle positions read back as written.
    static func childrenNoLongerListedAreDeleted(_ harness: RemoteStoreHarness) async throws {
        let exercise = RemoteExerciseRow(id: UUID(), userId: harness.userId, name: "Lunge", type: .strength)
        let muscles = [
            RemoteMuscleGroupRow(exerciseId: exercise.id, muscle: .quadriceps, role: .primary, position: 1),
            RemoteMuscleGroupRow(exerciseId: exercise.id, muscle: .glutes, role: .secondary, position: 2),
            RemoteMuscleGroupRow(exerciseId: exercise.id, muscle: .hamstrings, role: .secondary, position: 3)
        ]
        let routine = RemoteRoutineRow(id: UUID(), userId: harness.userId, name: "Legs")
        let items = (1 ... 2).map { position in
            RemoteRoutineItemRow(
                id: RemoteRoutineItemRow.id(routineId: routine.id, position: position), userId: harness.userId,
                routineId: routine.id, position: position, exerciseId: exercise.id
            )
        }
        try await harness.store.upsert([exercise])
        try await harness.store.upsert(muscles)
        try await harness.store.upsert([routine])
        try await harness.store.upsert(items)

        for _ in 0 ..< 2 {
            try await harness.store.deleteChildren(.exerciseMuscleGroups, of: exercise.id, keeping: [
                muscles[2].id, muscles[0].id
            ])
            try await harness.store.deleteChildren(.routineItems, of: routine.id, keeping: [])
        }

        let groups = try await pullAll(RemoteMuscleGroupRow.self, from: harness.store)
            .filter { $0.exerciseId == exercise.id }
        #expect(groups.map(withoutServerFields).sorted { $0.position < $1.position } == [muscles[0], muscles[2]])
        #expect(try await pullAll(RemoteRoutineItemRow.self, from: harness.store).isEmpty)
        let tombstones = try await pullAll(RemoteTombstoneRow.self, from: harness.store)
        let expected = ["exercise_muscle_groups:\(muscles[1].id)"] + items.map { "routine_items:\($0.id)" }
        #expect(tombstones.map { "\($0.tableName):\($0.rowId)" }.sorted() == expected.sorted())
        #expect(tombstones.allSatisfy { $0.userId == harness.userId })
        #expect(try await pullAll(RemoteRoutineRow.self, from: harness.store).map(\.id) == [routine.id])
        // Only muscle groups and routine items have a parent to delete by.
        await #expect(throws: RemoteStoreError.self) {
            try await harness.store.deleteChildren(.sessions, of: routine.id, keeping: [])
        }
    }

    /// Settings are one row per exercise for their owner: an upsert updates it,
    /// the pull pages them by (updated_at, exercise id), and deleting one leaves
    /// a tombstone keyed by the exercise that writing it again clears.
    static func settingsAreKeyedByExercise(_ harness: RemoteStoreHarness) async throws {
        let own = RemoteExerciseRow(id: UUID(), userId: harness.userId, name: "Lunge", type: .strength)
        try await harness.store.upsert([own])
        var settings = [benchPress, shoulderPress, own.id].map { exerciseId in
            RemoteExerciseSettingRow(exerciseId: exerciseId, userId: harness.userId, restEnabled: true, restSeconds: 60)
        }
        try await harness.store.upsert(settings)
        settings[0].restEnabled = false
        settings[0].restSeconds = 30
        try await harness.store.upsert([settings[0]])

        let stored = try await pullAll(RemoteExerciseSettingRow.self, from: harness.store)
        #expect(stored.count == 3)
        #expect(stored.map(withoutServerFields).sorted(by: byId) == settings.sorted(by: byId))
        #expect(stored.last?.id == settings[0].id, "the row written last is read last")

        try await harness.store.delete(.exerciseSettings, ids: [settings[1].id])
        #expect(try await pullAll(RemoteExerciseSettingRow.self, from: harness.store).count == 2)
        let tombstones = try await pullAll(RemoteTombstoneRow.self, from: harness.store)
        #expect(tombstones.map { "\($0.tableName):\($0.rowId)" } == ["exercise_settings:\(shoulderPress)"])

        try await harness.store.upsert([settings[1]])
        #expect(try await pullAll(RemoteTombstoneRow.self, from: harness.store).isEmpty)
    }
}
