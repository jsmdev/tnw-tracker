import Foundation
import Testing
@testable import TNWTrackerKit

/// A routine's items and an exercise's muscle groups travel only when the list
/// itself changed on the device since the last sync (S13, L12): a change of the
/// parent alone (a favourite, a rename) never drops children another device
/// added. Real stores and repositories, two devices on the in-memory server.
/// Invented data only.
@Suite("Sync engine child lists")
@MainActor
struct TrainingSyncEngineChildListTests {
    let phone: PushWorld
    let tablet: PushWorld

    init() throws {
        phone = try PushWorld()
        tablet = try PushWorld(sharing: phone)
    }

    private var server: InMemoryTrainingRemoteStore { phone.server }

    /// The routine with a third item, as the tablet adds it.
    private func withThirdItem(_ routine: Routine) -> Routine {
        var routine = routine
        routine.items.append(RoutineItem(order: 3, exerciseId: phone.squat.id, targetSets: 2, notes: "Pause"))
        return routine
    }

    /// The squat with a third muscle, as the tablet adds it.
    private var squatWithCore: Exercise {
        var squat = phone.squat
        squat.muscleGroups.append(MuscleGroup(muscle: .core, role: .secondary))
        return squat
    }

    /// The phone's routine on both devices and the server, nothing pending.
    private func sharedRoutine() async throws -> Routine {
        let routine = try phone.saveRoutine()
        try await phone.engine.sync()
        try await tablet.engine.sync()
        try phone.expectNothingPending()
        try tablet.expectNothingPending()
        return routine
    }

    private func serverItems(of routineId: UUID) async -> [RemoteRoutineItemRow] {
        await phone.stored(RemoteRoutineItemRow.self).filter { $0.routineId == routineId }
            .sorted { $0.position < $1.position }
    }

    private func serverMuscles(of exerciseId: UUID) async -> [MuscleGroup] {
        await phone.stored(RemoteMuscleGroupRow.self).filter { $0.exerciseId == exerciseId }
            .sorted { $0.position < $1.position }
            .map { MuscleGroup(muscle: $0.muscle, role: $0.role) }
    }

    private func childDeletes(_ table: RemoteTable) async -> Int {
        await server.calls.filter { call in
            if case let .deleteChildren(deleted, _, _) = call { deleted == table } else { false }
        }.count
    }

    // MARK: - The parent alone changed

    @Test("a favourite marked on the phone keeps the item the tablet added, on both devices and the server")
    func favouriteKeepsAnotherDevicesItem() async throws {
        let routine = try await sharedRoutine()
        try tablet.store.routines.save(withThirdItem(routine))
        try await tablet.engine.sync()
        // Before the phone pulls the third item, the user unmarks the favourite there.
        try phone.store.routines.setFavorite(false, routineId: routine.id)

        let report = try await phone.engine.sync()
        try await tablet.engine.sync()

        #expect(report.push.pushed == [SyncAggregateRef(.routine, id: routine.id)])
        var expected = withThirdItem(routine)
        expected.isFavorite = false
        #expect(try phone.store.routines.routine(id: routine.id) == expected)
        #expect(try tablet.store.routines.routine(id: routine.id) == expected)
        #expect(await serverItems(of: routine.id).map(\.position) == [1, 2, 3])
        #expect(await phone.stored(RemoteRoutineRow.self).first { $0.id == routine.id }?.isFavorite == false)
        #expect(await childDeletes(.routineItems) == 2)
        try phone.expectNothingPending()
        try tablet.expectNothingPending()
    }

    @Test("a rename on the phone keeps the muscle the tablet added, on both devices and the server")
    func renameKeepsAnotherDevicesMuscle() async throws {
        _ = try await sharedRoutine()
        try tablet.store.exercises.save(squatWithCore)
        try await tablet.engine.sync()
        var renamed = phone.squat
        renamed.name = "Front Squat"
        try phone.store.exercises.save(renamed)

        try await phone.engine.sync()
        try await tablet.engine.sync()

        var expected = squatWithCore
        expected.name = "Front Squat"
        #expect(try phone.store.exercises.exercise(id: phone.squat.id) == expected)
        #expect(try tablet.store.exercises.exercise(id: phone.squat.id) == expected)
        #expect(await serverMuscles(of: phone.squat.id) == expected.muscleGroups)
        #expect(await phone.stored(RemoteExerciseRow.self).first { $0.id == phone.squat.id }?.name == "Front Squat")
        try phone.expectNothingPending()
        try tablet.expectNothingPending()
    }

    @Test("saving the same items again, recreated on the device, is not a change of the list")
    func identicalItemsAreNoChange() async throws {
        let routine = try await sharedRoutine()
        let deletes = await childDeletes(.routineItems)
        try phone.store.routines.save(routine)

        let report = try await phone.engine.push()

        #expect(report.pushed == [SyncAggregateRef(.routine, id: routine.id)])
        #expect(await childDeletes(.routineItems) == deletes)
        #expect(await serverItems(of: routine.id) == phone.itemRows(routine))
    }

    // MARK: - The list changed on the device

    @Test("a list edited on the phone still replaces the server's, the tablet's item included")
    func editedListReplacesTheServers() async throws {
        let routine = try await sharedRoutine()
        try tablet.store.routines.save(withThirdItem(routine))
        try await tablet.engine.sync()
        var shorter = routine
        shorter.items = [RoutineItem(order: 1, exerciseId: phone.bench.id, targetDurationSeconds: 60)]
        try phone.store.routines.save(shorter)

        try await phone.engine.sync()
        try await tablet.engine.sync()

        #expect(await serverItems(of: routine.id).map(\.exerciseId) == [phone.bench.id])
        #expect(try phone.store.routines.routine(id: routine.id)?.items == shorter.items)
        #expect(try tablet.store.routines.routine(id: routine.id)?.items == shorter.items)
        try phone.expectNothingPending()
        try tablet.expectNothingPending()
    }

    @Test("a muscle list edited on the phone still replaces the server's")
    func editedMusclesReplaceTheServers() async throws {
        _ = try await sharedRoutine()
        try tablet.store.exercises.save(squatWithCore)
        try await tablet.engine.sync()
        var edited = phone.squat
        edited.muscleGroups = [MuscleGroup(muscle: .glutes, role: .primary)]
        try phone.store.exercises.save(edited)

        try await phone.engine.sync()
        try await tablet.engine.sync()

        #expect(await serverMuscles(of: phone.squat.id) == edited.muscleGroups)
        #expect(try tablet.store.exercises.exercise(id: phone.squat.id)?.muscleGroups == edited.muscleGroups)
        #expect(try phone.store.exercises.exercise(id: phone.squat.id)?.muscleGroups == edited.muscleGroups)
    }

    @Test("a list edit the network dropped stays pending, survives a pull and goes up next time (S4)")
    func droppedListEditStaysPending() async throws {
        let routine = try await sharedRoutine()
        var edited = withThirdItem(routine)
        edited.items[0].notes = "Slow"
        try phone.store.routines.save(edited)
        await server.failNext(.deleteChildren)

        await #expect(throws: URLError.self) { try await phone.engine.push() }
        #expect(await serverItems(of: routine.id) == phone.itemRows(routine))
        #expect(try phone.store.syncState.pending(.routine).map(\.id) == [routine.id])
        // The server's items, read again, undo neither the device's note nor its third item.
        try await phone.engine.pull()
        #expect(try phone.store.routines.routine(id: routine.id)?.items == edited.items)

        try await phone.engine.push()

        #expect(await serverItems(of: routine.id).map(\.position) == [1, 2, 3])
        #expect(await serverItems(of: routine.id).first?.notes == "Slow")
        try phone.expectNothingPending()
    }

    // MARK: - Pull under a pending parent

    @Test("a pull applies the server's changed and added items while the favourite waits, and keeps the favourite")
    func pullAppliesItemsUnderPendingFavourite() async throws {
        let routine = try await sharedRoutine()
        // Two rows change: the first one applied must not make the list look edited here.
        var onTablet = withThirdItem(routine)
        onTablet.items[0].notes = "Slow"
        try tablet.store.routines.save(onTablet)
        try await tablet.engine.sync()
        try phone.store.routines.setFavorite(false, routineId: routine.id)

        let report = try await phone.engine.pull()

        let onPhone = try #require(try phone.store.routines.routine(id: routine.id))
        #expect(onPhone.items == onTablet.items)
        #expect(!onPhone.isFavorite)
        #expect(report.resolved.contains(.init(aggregate: .init(.routine, id: routine.id), rule: .localKept)))
        #expect(try phone.store.syncState.pending(.routine).map(\.id) == [routine.id])
        let deletes = await childDeletes(.routineItems)
        try await phone.engine.push()
        #expect(await childDeletes(.routineItems) == deletes)
        #expect(await serverItems(of: routine.id).map(\.position) == [1, 2, 3])
    }

    @Test("a pull applies the server's muscle deletion and item deletion while only the parents changed here")
    func pullAppliesChildDeletionsUnderPendingParents() async throws {
        let routine = try await sharedRoutine()
        let quadriceps = RemoteMuscleGroupRow(exerciseId: phone.squat.id, muscle: .quadriceps, role: .primary)
        let second = RemoteRoutineItemRow.id(routineId: routine.id, position: 2)
        try await server.deleteOnServer(.exerciseMuscleGroups, ids: [quadriceps.id])
        try await server.deleteOnServer(.routineItems, ids: [second])
        var renamed = phone.squat
        renamed.name = "Front Squat"
        try phone.store.exercises.save(renamed)
        try phone.store.routines.setFavorite(false, routineId: routine.id)

        let report = try await phone.engine.pull()

        #expect(Set(report.deletions.map(\.id)) == [quadriceps.id, second])
        #expect(report.deletions.allSatisfy { $0.rule == .serverApplied })
        let squat = try phone.store.exercises.exercise(id: phone.squat.id)
        #expect(squat?.muscleGroups == [MuscleGroup(muscle: .glutes, role: .secondary)])
        #expect(squat?.name == "Front Squat")
        #expect(try phone.store.routines.routine(id: routine.id)?.items == [routine.items[0]])
        try await phone.engine.push()
        #expect(await serverMuscles(of: phone.squat.id) == [MuscleGroup(muscle: .glutes, role: .secondary)])
        #expect(await serverItems(of: routine.id).map(\.position) == [1])
        try phone.expectNothingPending()
    }

    @Test("a pull keeps the device's edited list and leaves the server's new item out")
    func pullKeepsALocallyEditedList() async throws {
        let routine = try await sharedRoutine()
        try tablet.store.routines.save(withThirdItem(routine))
        try await tablet.engine.sync()
        var edited = routine
        edited.items[0].notes = "Slow"
        try phone.store.routines.save(edited)

        try await phone.engine.pull()

        #expect(try phone.store.routines.routine(id: routine.id)?.items == edited.items)
        #expect(try phone.store.syncState.pending(.routine).map(\.id) == [routine.id])
    }

    @Test("a muscle the server added reaches the device while a rename waits to be pushed")
    func pullAppliesMusclesUnderPendingRename() async throws {
        _ = try await sharedRoutine()
        try tablet.store.exercises.save(squatWithCore)
        try await tablet.engine.sync()
        var renamed = phone.squat
        renamed.name = "Front Squat"
        try phone.store.exercises.save(renamed)

        try await phone.engine.pull()

        let squat = try phone.store.exercises.exercise(id: phone.squat.id)
        #expect(squat?.muscleGroups == squatWithCore.muscleGroups)
        #expect(squat?.name == "Front Squat")
        #expect(try phone.store.syncState.pending(.exercise).map(\.id) == [phone.squat.id])
    }

    // MARK: - When the list counts as synced

    @Test("the list a push sent counts as the server's at once, without a pull in between")
    func pushedListIsSyncedWithoutAPull() async throws {
        let routine = try phone.saveRoutine()
        try await phone.engine.push()
        try await tablet.engine.sync()
        try tablet.store.routines.save(withThirdItem(routine))
        try await tablet.engine.sync()
        try phone.store.routines.setFavorite(false, routineId: routine.id)

        try await phone.engine.push()

        #expect(await serverItems(of: routine.id).map(\.position) == [1, 2, 3])
    }

    @Test("the list a push sent counts as the server's even when the parent changed during the upload")
    func listSentDuringAParentEditIsSynced() async throws {
        let routine = try await sharedRoutine()
        let edited = withThirdItem(routine)
        try phone.store.routines.save(edited)
        let store = phone.store
        await server.duringNextUpsert(of: .routineItems) { @MainActor in
            try? store.routines.setFavorite(false, routineId: routine.id)
        }
        try await phone.engine.push()
        #expect(try phone.store.syncState.pending(.routine).map(\.id) == [routine.id])
        // Another device adds a fourth item before the favourite goes up.
        try await tablet.engine.sync()
        var longer = edited
        longer.items.append(RoutineItem(order: 4, exerciseId: phone.bench.id, targetSets: 1))
        try tablet.store.routines.save(longer)
        try await tablet.engine.sync()

        try await phone.engine.push()

        #expect(await serverItems(of: routine.id).map(\.position) == [1, 2, 3, 4])
        #expect(await phone.stored(RemoteRoutineRow.self).first { $0.id == routine.id }?.isFavorite == false)
    }

    @Test("an exercise pulled without muscles keeps the muscles added elsewhere when renamed here")
    func pulledEmptyListIsSynced() async throws {
        let plank = Exercise(name: "Plank", type: .bodyweight)
        try phone.store.exercises.save(plank)
        try await phone.engine.sync()
        try await tablet.engine.sync()
        var withCore = plank
        withCore.muscleGroups = [MuscleGroup(muscle: .core, role: .primary)]
        try phone.store.exercises.save(withCore)
        try await phone.engine.sync()
        var renamed = plank
        renamed.name = "Side Plank"
        try tablet.store.exercises.save(renamed)

        try await tablet.engine.push()

        #expect(await serverMuscles(of: plank.id) == withCore.muscleGroups)
    }

    @Test("a muscle whose role alone changed on the device goes up")
    func changedRoleGoesUp() async throws {
        _ = try await sharedRoutine()
        var squat = phone.squat
        squat.muscleGroups[1].role = .primary
        try phone.store.exercises.save(squat)

        try await phone.engine.push()

        #expect(await serverMuscles(of: phone.squat.id) == squat.muscleGroups)
    }

    @Test("a routine with no recorded list and no change waiting takes the server's items")
    func unrecordedListWithoutAChangeTakesTheServers() async throws {
        let routine = try await sharedRoutine()
        let model = try #require(try phone.store.context.fetchRoutine(id: routine.id))
        model.syncedChildrenFingerprint = nil
        try phone.store.context.save()
        try tablet.store.routines.save(withThirdItem(routine))
        try await tablet.engine.sync()

        try await phone.engine.pull()

        #expect(try phone.store.routines.routine(id: routine.id)?.items == withThirdItem(routine).items)
        try phone.expectNothingPending()
    }
}
