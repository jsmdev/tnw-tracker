import Foundation
import Testing
@testable import TNWTrackerKit

/// The engine of one account never writes another's data into its store, nor
/// goes on once its account signed out (S10). Real store and engine, in-memory
/// server. Invented data only.
@Suite("Sync engine, one account")
@MainActor
struct TrainingSyncEngineAccountTests {
    let world: PushWorld

    init() throws {
        world = try PushWorld()
    }

    private func exerciseNames() throws -> [String] {
        try world.store.exercises.exercises().map(\.name)
    }

    @Test("S10 a pull that answers a row of another user applies nothing of it")
    func rowsOfAnotherUserAreNeverApplied() async throws {
        let mine = RemoteExerciseRow(id: UUID(), userId: world.userId, name: "Cable Row", type: .strength)
        let theirs = RemoteExerciseRow(id: UUID(), userId: UUID(), name: "Hip Thrust", type: .strength)
        try await world.server.insertOnServer(mine)
        try await world.server.insertOnServer(theirs)
        let before = try exerciseNames()

        await #expect(throws: TrainingSyncError.pulledRowsOfAnotherUser) { try await world.engine.pull() }

        #expect(try exerciseNames() == before, "not even the user's own row of that batch")
        #expect(try world.store.pulled.cursor(.exercises, userId: world.userId) == nil)
    }

    @Test("S10 the user's own rows and the catalogue are applied")
    func ownRowsAndCatalogueAreApplied() async throws {
        try await world.server.insertOnServer(
            RemoteExerciseRow(id: UUID(), userId: world.userId, name: "Cable Row", type: .strength)
        )
        try await world.server.insertOnServer(
            RemoteExerciseRow(id: UUID(), userId: nil, name: "Deadlift", type: .strength)
        )

        try await world.engine.pull()

        #expect(try Set(exerciseNames()).isSuperset(of: ["Cable Row", "Deadlift"]))
    }

    @Test("S10 a stopped engine sends nothing and writes nothing", .timeLimit(.minutes(1)))
    func stoppedEngineDoesNothing() async throws {
        _ = try world.saveRoutine()
        world.engine.stop()

        await #expect(throws: CancellationError.self) { try await world.engine.sync() }

        #expect(await world.server.calls.isEmpty)
        #expect(try world.store.syncState.pending(.routine).count == 1)
    }

    @Test("S10 stopping the engine during an upload keeps the aggregate pending and sends nothing more",
          .timeLimit(.minutes(1)))
    func stopDuringUploadKeepsItPending() async throws {
        let routine = try world.saveRoutine()
        let engine = world.engine
        await world.server.duringNextUpsert(of: .exercises) {
            await MainActor.run { engine.stop() }
        }

        await #expect(throws: CancellationError.self) { try await engine.push() }

        #expect(await world.server.calls == [.upsert(.exercises, count: 1)])
        #expect(try world.store.syncState.pending(.exercise).map(\.id) == [world.squat.id])
        #expect(try world.store.syncState.pending(.routine).map(\.id) == [routine.id])
    }

    @Test("S10 an upload the server answers after the engine stopped is not marked synced",
          .timeLimit(.minutes(1)))
    func answerAfterStopMarksNothing() async throws {
        try await world.uploadPrerequisites()
        let session = try world.finishedSession()
        let engine = world.engine
        await world.server.duringNextPush {
            await MainActor.run { engine.stop() }
        }

        await #expect(throws: CancellationError.self) { try await engine.push() }

        #expect(await world.server.stored(RemoteSessionRow.self).map(\.id) == [session.id], "the server answered")
        let pending = try world.store.syncState.pending(.session)
        #expect(pending.map(\.id) == [session.id])
        #expect(pending.first?.failureCount == 0)
    }

    @Test("S10 a muscle group is never applied under an exercise that is not the user's on the server")
    func muscleGroupNeedsTheUsersExercise() async throws {
        let device = try PushWorld(claimed: false)
        let local = Exercise(
            name: "Sample Row", type: .strength, muscleGroups: [MuscleGroup(muscle: .back, role: .primary)]
        )
        try device.store.exercises.save(local)
        try device.claim()
        var batch = PulledBatch()
        let row = RemoteMuscleGroupRow(id: UUID(), exerciseId: local.id, muscle: .biceps, role: .secondary)
        batch.muscleGroups = [row]

        let report = try device.store.pulled.apply(batch, userId: device.userId)

        let stored = try #require(try device.store.exercises.exercises().first { $0.id == local.id })
        #expect(stored.muscleGroups == [MuscleGroup(muscle: .back, role: .primary)])
        let notTheUsers = SyncPullSkipReason.invalid("its exercise is not the user's")
        #expect(report.skipped == [.init(table: .exerciseMuscleGroups, id: row.id, reason: notTheUsers)])
    }
}
