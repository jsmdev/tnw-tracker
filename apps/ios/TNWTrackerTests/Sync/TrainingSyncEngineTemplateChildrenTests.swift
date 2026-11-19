import Foundation
import Testing
@testable import TNWTrackerKit

/// Muscle groups and routine items both ways (S1, S2, S11, S13): a push makes
/// the server hold exactly the device's list, in its order; a pull follows the
/// server's additions, order and deletions. Real stores and repositories,
/// in-memory server. Invented data only.
@Suite("Sync engine muscle groups and routine items")
@MainActor
struct TrainingSyncEngineTemplateChildrenTests {
    let phone: PushWorld

    init() throws {
        phone = try PushWorld()
    }

    private var server: InMemoryTrainingRemoteStore { phone.server }

    /// The squat as the phone edits it: quadriceps dropped, glutes moved first, core added.
    private var editedSquat: Exercise {
        var squat = phone.squat
        squat.muscleGroups = [
            MuscleGroup(muscle: .glutes, role: .secondary), MuscleGroup(muscle: .core, role: .primary)
        ]
        return squat
    }

    /// The routine with its first item removed: bench is now the only item.
    private func shortened(_ routine: Routine) -> Routine {
        var routine = routine
        routine.items = [RoutineItem(order: 1, exerciseId: phone.bench.id, targetDurationSeconds: 60)]
        return routine
    }

    private func serverMuscles(of exerciseId: UUID) async -> [RemoteMuscleGroupRow] {
        await phone.stored(RemoteMuscleGroupRow.self).filter { $0.exerciseId == exerciseId }
            .sorted { $0.position < $1.position }
    }

    private func serverItems(of routineId: UUID) async -> [RemoteRoutineItemRow] {
        await phone.stored(RemoteRoutineItemRow.self).filter { $0.routineId == routineId }
            .sorted { $0.position < $1.position }
    }

    // MARK: - Push

    @Test("a muscle dropped on the device is deleted on the server, and the rest go up in the device's order")
    func droppedMuscleIsDeleted() async throws {
        try await phone.engine.push()
        try phone.store.exercises.save(editedSquat)

        let report = try await phone.engine.push()

        #expect(report.rejected.isEmpty)
        #expect(await serverMuscles(of: phone.squat.id) == [
            RemoteMuscleGroupRow(exerciseId: phone.squat.id, muscle: .glutes, role: .secondary, position: 1),
            RemoteMuscleGroupRow(exerciseId: phone.squat.id, muscle: .core, role: .primary, position: 2)
        ])
        let quadriceps = RemoteMuscleGroupRow(exerciseId: phone.squat.id, muscle: .quadriceps, role: .primary)
        #expect(await server.stored(RemoteTombstoneRow.self).map(\.rowId) == [quadriceps.id])
        try phone.expectNothingPending()
    }

    @Test("a routine shortened on the device loses the items it no longer lists on the server")
    func shortenedRoutineLosesItems() async throws {
        let routine = try phone.saveRoutine()
        try await phone.engine.push()
        try phone.store.routines.save(shortened(routine))

        let report = try await phone.engine.push()

        #expect(report.rejected.isEmpty)
        #expect(await serverItems(of: routine.id) == [
            RemoteRoutineItemRow(
                id: RemoteRoutineItemRow.id(routineId: routine.id, position: 1), userId: phone.userId,
                routineId: routine.id, position: 1, exerciseId: phone.bench.id, targetDurationSeconds: 60
            )
        ])
        let removed = RemoteRoutineItemRow.id(routineId: routine.id, position: 2)
        #expect(await server.stored(RemoteTombstoneRow.self).map(\.rowId) == [removed])
        try phone.expectNothingPending()
    }

    @Test("children another client wrote under its own ids give way to the device's list, without a collision")
    func foreignChildrenGiveWay() async throws {
        let routine = try phone.saveRoutine()
        try await phone.engine.push()
        // An importer adds a muscle and replaces the second item under ids of its own.
        let foreignMuscle = RemoteMuscleGroupRow(
            id: UUID(), exerciseId: phone.squat.id, muscle: .core, role: .primary, position: 3
        )
        try await server.insertOnServer(foreignMuscle)
        let second = RemoteRoutineItemRow.id(routineId: routine.id, position: 2)
        try await server.deleteOnServer(.routineItems, ids: [second])
        let foreignItem = RemoteRoutineItemRow(
            id: UUID(), userId: phone.userId, routineId: routine.id, position: 2, exerciseId: phone.squat.id
        )
        try await server.insertOnServer(foreignItem)
        // The device, which has not pulled them, edits both aggregates.
        try phone.store.exercises.save(editedSquat)
        try phone.store.routines.save(routine)

        let report = try await phone.engine.push()

        #expect(report.rejected.isEmpty)
        #expect(await serverMuscles(of: phone.squat.id).map(\.id) == [
            RemoteMuscleGroupRow(exerciseId: phone.squat.id, muscle: .glutes, role: .secondary).id,
            RemoteMuscleGroupRow(exerciseId: phone.squat.id, muscle: .core, role: .primary).id
        ])
        #expect(await serverItems(of: routine.id) == phone.itemRows(routine))
        try phone.expectNothingPending()
    }

    // MARK: - Pull

    @Test("another device's muscle order, dropped muscle and shorter routine reach the device as they are")
    func childrenReachAnotherDevice() async throws {
        let tablet = try PushWorld(sharing: phone)
        let routine = try phone.saveRoutine()
        try await phone.engine.push()
        try await tablet.engine.sync()
        try phone.store.exercises.save(editedSquat)
        try phone.store.routines.save(shortened(routine))
        try await phone.engine.push()

        let report = try await tablet.engine.sync()

        #expect(try tablet.store.exercises.exercise(id: phone.squat.id)?.muscleGroups == editedSquat.muscleGroups)
        let onPhone = try #require(try phone.store.routines.routine(id: routine.id))
        #expect(onPhone.items == shortened(routine).items)
        #expect(try tablet.store.routines.routine(id: routine.id) == onPhone)
        let squatOnPhone = try phone.store.exercises.exercise(id: phone.squat.id)
        #expect(try tablet.store.exercises.exercise(id: phone.squat.id) == squatOnPhone)
        #expect(report.pull.deletions.map(\.rule).allSatisfy { $0 == .serverApplied })
        #expect(Set(report.pull.deletions.map(\.table)) == [.exerciseMuscleGroups, .routineItems])
        try tablet.expectNothingPending()
        #expect(report.push.pushed.isEmpty)
    }

    @Test("a muscle and an item another client wrote under its own ids and then deleted go from the device")
    func foreignChildrenDeletedOnServerGo() async throws {
        let routine = try phone.saveRoutine()
        try await phone.engine.push()
        let foreignItem = RemoteRoutineItemRow(
            id: UUID(), userId: phone.userId, routineId: routine.id, position: 3, exerciseId: phone.squat.id,
            targetSets: 2
        )
        let foreignMuscle = RemoteMuscleGroupRow(
            id: UUID(), exerciseId: phone.squat.id, muscle: .core, role: .primary, position: 3
        )
        try await server.insertOnServer(foreignItem)
        try await server.insertOnServer(foreignMuscle)
        try await phone.engine.pull()
        #expect(try phone.store.routines.routine(id: routine.id)?.items.count == 3)
        #expect(try phone.store.exercises.exercise(id: phone.squat.id)?.muscleGroups.last
            == MuscleGroup(muscle: .core, role: .primary))

        try await server.deleteOnServer(.routineItems, ids: [foreignItem.id])
        try await server.deleteOnServer(.exerciseMuscleGroups, ids: [foreignMuscle.id])
        let report = try await phone.engine.pull()

        #expect(report.deletions == [
            .init(table: .routineItems, id: foreignItem.id, rule: .serverApplied),
            .init(table: .exerciseMuscleGroups, id: foreignMuscle.id, rule: .serverApplied)
        ])
        #expect(try phone.store.routines.routine(id: routine.id) == routine.withFavorite)
        #expect(try phone.store.exercises.exercise(id: phone.squat.id) == phone.squat)
        try phone.expectNothingPending()
    }

    @Test("a child the pull brought under another client's id goes up under that id when its parent is pushed")
    func pulledChildKeepsItsServerId() async throws {
        let routine = try phone.saveRoutine()
        try await phone.engine.push()
        let foreignItem = RemoteRoutineItemRow(
            id: UUID(), userId: phone.userId, routineId: routine.id, position: 3, exerciseId: phone.squat.id
        )
        try await server.insertOnServer(foreignItem)
        try await phone.engine.pull()
        // Pending without the items being written again.
        try phone.store.routines.setFavorite(false, routineId: routine.id)

        let report = try await phone.engine.push()

        #expect(report.pushed == [SyncAggregateRef(.routine, id: routine.id)])
        #expect(await serverItems(of: routine.id).map(\.id) == phone.itemRows(routine).map(\.id) + [foreignItem.id])
        #expect(await server.stored(RemoteTombstoneRow.self).isEmpty)
    }

    @Test("muscles the server holds at the same position keep the server's id order on the device")
    func tiedMusclesKeepIdOrder() async throws {
        let catalogue = RemoteExerciseRow(
            id: TrainingRemoteStoreContract.shoulderPress, userId: nil, name: "Shoulder Press", type: .strength
        )
        let low = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
        let high = try #require(UUID(uuidString: "ffffffff-0000-4000-8000-000000000001"))
        try await server.insertOnServer(catalogue)
        try await server.insertOnServer(RemoteMuscleGroupRow(
            id: high, exerciseId: catalogue.id, muscle: .triceps, role: .secondary, position: 1
        ))
        try await server.insertOnServer(RemoteMuscleGroupRow(
            id: low, exerciseId: catalogue.id, muscle: .shoulders, role: .primary, position: 1
        ))

        try await phone.engine.pull()

        #expect(try phone.store.exercises.exercise(id: catalogue.id)?.muscleGroups == [
            MuscleGroup(muscle: .shoulders, role: .primary), MuscleGroup(muscle: .triceps, role: .secondary)
        ])
    }

    @Test("a routine with an item that lost its exercise is not pushed, so the server keeps that item")
    func routineWithoutAnItemsExerciseWaits() async throws {
        let routine = try phone.saveRoutine()
        try await phone.engine.push()
        let model = try #require(try phone.store.context.fetchRoutine(id: routine.id))
        model.items.first { $0.order == 2 }?.exercise = nil
        model.markChanged()
        try phone.store.context.save()

        let report = try await phone.engine.push()

        #expect(report.skipped == [.init(aggregate: SyncAggregateRef(.routine, id: routine.id), reason: .incomplete)])
        #expect(await serverItems(of: routine.id) == phone.itemRows(routine))
    }

    @Test("a muscle or item deleted on the server stays while its aggregate has a local change, and goes back up")
    func localChangeKeepsDeletedChildren() async throws {
        let routine = try phone.saveRoutine()
        try await phone.engine.push()
        let quadriceps = RemoteMuscleGroupRow(exerciseId: phone.squat.id, muscle: .quadriceps, role: .primary)
        let second = RemoteRoutineItemRow.id(routineId: routine.id, position: 2)
        try await server.deleteOnServer(.exerciseMuscleGroups, ids: [quadriceps.id])
        try await server.deleteOnServer(.routineItems, ids: [second])
        var renamed = phone.squat
        renamed.name = "Front Squat"
        try phone.store.exercises.save(renamed)
        try phone.store.routines.setFavorite(false, routineId: routine.id)

        let pull = try await phone.engine.pull()

        #expect(Set(pull.deletions.map(\.id)) == [quadriceps.id, second])
        #expect(pull.deletions.allSatisfy { $0.rule == .localKept })
        #expect(try phone.store.exercises.exercise(id: phone.squat.id)?.muscleGroups == phone.squat.muscleGroups)
        #expect(try phone.store.routines.routine(id: routine.id)?.items == routine.items)

        try await phone.engine.sync()
        #expect(await serverMuscles(of: phone.squat.id).count == 2)
        #expect(await serverItems(of: routine.id).count == 2)
        #expect(await server.stored(RemoteTombstoneRow.self).isEmpty)
        try phone.expectNothingPending()
    }

    @Test("an exercise whose routine item and own row are deleted on the server in one pull goes from the device")
    func exerciseOnlyADeletedItemUsedGoes() async throws {
        let plank = Exercise(name: "Plank", type: .bodyweight)
        try phone.store.exercises.save(plank)
        let routine = Routine(name: "Core", items: [
            RoutineItem(order: 1, exerciseId: phone.bench.id, targetSets: 3),
            RoutineItem(order: 2, exerciseId: plank.id, targetDurationSeconds: 60)
        ])
        try phone.store.routines.save(routine)
        try await phone.engine.push()
        let second = RemoteRoutineItemRow.id(routineId: routine.id, position: 2)
        try await server.deleteOnServer(.routineItems, ids: [second])
        try await server.deleteOnServer(.exercises, ids: [plank.id])

        let report = try await phone.engine.pull()

        #expect(report.deletions.map(\.table) == [.routineItems, .exercises])
        #expect(try phone.store.exercises.exercise(id: plank.id) == nil)
        #expect(try phone.store.routines.routine(id: routine.id)?.items.map(\.exerciseId) == [phone.bench.id])
        try phone.expectNothingPending()
    }
}

private extension Routine {
    /// As `PushWorld.saveRoutine()` leaves it: marked favourite after saving.
    var withFavorite: Routine {
        var routine = self
        routine.isFavorite = true
        return routine
    }
}
