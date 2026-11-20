import Foundation
import Supabase
import Testing
@testable import TNWTrackerKit

/// S1 and S2 for routines, exercises and their settings, end to end: what a
/// device changes reaches the local Supabase stack through the real adapter,
/// and what another device changed there comes back. Skipped when the stack is
/// not configured or not running (see `LocalSupabaseStack`).
@Suite(
    "Sync engine templates (local stack)",
    .enabled("needs the local Supabase stack") { await LocalSupabaseStack.isAvailable() }
)
struct TrainingSyncEngineTemplateContractTests {
    @Test("a routine shortened, a muscle dropped and settings saved in the app are what Supabase holds")
    func templatesGoUp() async throws {
        try await LocalSupabaseStack.withThrowawayUser { client, userId in
            try await Self.templatesGoUp(client: client, userId: userId)
        }
    }

    @MainActor
    private static func templatesGoUp(client: SupabaseClient, userId: UUID) async throws {
        let world = try PushWorld(userId: userId)
        let remote = SupabaseTrainingRemoteStore(client: client, userId: userId)
        let engine = TrainingSyncEngine(store: world.store, remote: remote, userId: userId)
        let routine = try world.saveRoutine()
        try world.store.exerciseSettings.save(ExerciseSetting(exerciseId: world.bench.id, restSeconds: 60))
        try await engine.push()

        var squat = world.squat
        squat.muscleGroups = [
            MuscleGroup(muscle: .glutes, role: .secondary), MuscleGroup(muscle: .core, role: .primary)
        ]
        try world.store.exercises.save(squat)
        var shorter = routine
        shorter.items = [RoutineItem(order: 1, exerciseId: world.bench.id, targetDurationSeconds: 60)]
        try world.store.routines.save(shorter)
        try world.store.exerciseSettings.save(
            ExerciseSetting(exerciseId: world.squat.id, restEnabled: false, restSeconds: 150)
        )
        let report = try await engine.push()

        #expect(report.rejected.isEmpty)
        #expect(report.skipped.isEmpty)
        let groups = try await TrainingRemoteStoreContract.pullAll(RemoteMuscleGroupRow.self, from: remote)
            .filter { $0.exerciseId == world.squat.id }
        #expect(groups.map(PushWorld.plain).sorted { $0.position < $1.position } == [
            RemoteMuscleGroupRow(exerciseId: world.squat.id, muscle: .glutes, role: .secondary, position: 1),
            RemoteMuscleGroupRow(exerciseId: world.squat.id, muscle: .core, role: .primary, position: 2)
        ])
        let items = try await TrainingRemoteStoreContract.pullAll(RemoteRoutineItemRow.self, from: remote)
        #expect(items.map(PushWorld.plain) == [
            RemoteRoutineItemRow(
                id: RemoteRoutineItemRow.id(routineId: routine.id, position: 1), userId: userId,
                routineId: routine.id, position: 1, exerciseId: world.bench.id, targetDurationSeconds: 60
            )
        ])
        let settings = try await TrainingRemoteStoreContract.pullAll(RemoteExerciseSettingRow.self, from: remote)
        #expect(PushWorld.byId(settings.map(PushWorld.plain)) == PushWorld.byId([
            RemoteExerciseSettingRow(exerciseId: world.bench.id, userId: userId, restEnabled: true, restSeconds: 60),
            RemoteExerciseSettingRow(exerciseId: world.squat.id, userId: userId, restEnabled: false, restSeconds: 150)
        ]))
        let tombstones = try await TrainingRemoteStoreContract.pullAll(RemoteTombstoneRow.self, from: remote)
        #expect(Set(tombstones.map(\.tableName)) == ["exercise_muscle_groups", "routine_items"])
        try world.expectNothingPending()
    }

    @Test("a routine, muscle order and settings another device changed in Supabase reach the app")
    func templatesComeDown() async throws {
        try await LocalSupabaseStack.withThrowawayUser { client, userId in
            try await Self.templatesComeDown(client: client, userId: userId)
        }
    }

    @MainActor
    private static func templatesComeDown(client: SupabaseClient, userId: UUID) async throws {
        let phone = try PushWorld(userId: userId)
        let tablet = try PushWorld(sharing: phone)
        let remote = SupabaseTrainingRemoteStore(client: client, userId: userId)
        let phoneEngine = TrainingSyncEngine(store: phone.store, remote: remote, userId: userId)
        let tabletEngine = TrainingSyncEngine(store: tablet.store, remote: remote, userId: userId)
        let routine = try phone.saveRoutine()
        try phone.store.exerciseSettings.save(ExerciseSetting(exerciseId: phone.bench.id, restSeconds: 60))
        try phone.store.exerciseSettings.save(ExerciseSetting(exerciseId: phone.squat.id, restSeconds: 45))
        try await phoneEngine.push()
        try await tabletEngine.sync()

        // The phone reorders and drops muscles, shortens the routine, changes one
        // setting; then another client deletes the other setting in Supabase.
        var squat = phone.squat
        squat.muscleGroups = [
            MuscleGroup(muscle: .glutes, role: .secondary), MuscleGroup(muscle: .core, role: .primary)
        ]
        try phone.store.exercises.save(squat)
        var shorter = routine
        shorter.items = [RoutineItem(order: 1, exerciseId: phone.bench.id, targetDurationSeconds: 60)]
        try phone.store.routines.save(shorter)
        try phone.store.exerciseSettings.save(
            ExerciseSetting(exerciseId: phone.bench.id, restEnabled: false, restSeconds: 30)
        )
        try await phoneEngine.push()
        try await remote.delete(.exerciseSettings, ids: [phone.squat.id])

        let report = try await tabletEngine.sync()

        #expect(report.push.pushed.isEmpty)
        #expect(report.pull.deletions.allSatisfy { $0.rule == .serverApplied })
        #expect(try tablet.store.exercises.exercise(id: phone.squat.id)?.muscleGroups == squat.muscleGroups)
        #expect(try tablet.store.routines.routine(id: routine.id) == phone.store.routines.routine(id: routine.id))
        #expect(try tablet.store.routines.routine(id: routine.id)?.items == shorter.items)
        #expect(try tablet.store.exerciseSettings.setting(exerciseId: phone.bench.id) == ExerciseSetting(
            exerciseId: phone.bench.id, restEnabled: false, restSeconds: 30
        ))
        #expect(try tablet.store.exerciseSettings.setting(exerciseId: phone.squat.id) == nil)
        try tablet.expectNothingPending()
        // Reading it all back again changes nothing.
        let again = try await tabletEngine.sync()
        #expect(again.push.pushed.isEmpty)
        try tablet.expectNothingPending()
    }

    @Test("a favourite marked on one device keeps the item another device added in Supabase")
    func favouriteKeepsAnotherDevicesItem() async throws {
        try await LocalSupabaseStack.withThrowawayUser { client, userId in
            try await Self.favouriteKeepsAnotherDevicesItem(client: client, userId: userId)
        }
    }

    @MainActor
    private static func favouriteKeepsAnotherDevicesItem(client: SupabaseClient, userId: UUID) async throws {
        let phone = try PushWorld(userId: userId)
        let tablet = try PushWorld(sharing: phone)
        let remote = SupabaseTrainingRemoteStore(client: client, userId: userId)
        let phoneEngine = TrainingSyncEngine(store: phone.store, remote: remote, userId: userId)
        let tabletEngine = TrainingSyncEngine(store: tablet.store, remote: remote, userId: userId)
        let routine = try phone.saveRoutine()
        try await phoneEngine.sync()
        try await tabletEngine.sync()

        var longer = routine
        longer.items.append(RoutineItem(order: 3, exerciseId: phone.squat.id, targetSets: 2, notes: "Pause"))
        try tablet.store.routines.save(longer)
        try await tabletEngine.sync()
        // The phone has not pulled the third item when the user unmarks the favourite there.
        try phone.store.routines.setFavorite(false, routineId: routine.id)
        try await phoneEngine.sync()
        try await tabletEngine.sync()

        var expected = longer
        expected.isFavorite = false
        #expect(try phone.store.routines.routine(id: routine.id) == expected)
        #expect(try tablet.store.routines.routine(id: routine.id) == expected)
        let items = try await TrainingRemoteStoreContract.pullAll(RemoteRoutineItemRow.self, from: remote)
        #expect(items.map(\.position).sorted() == [1, 2, 3])
        let routines = try await TrainingRemoteStoreContract.pullAll(RemoteRoutineRow.self, from: remote)
        #expect(routines.map(\.isFavorite) == [false])
        try phone.expectNothingPending()
        try tablet.expectNothingPending()
    }
}
