import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - ActiveWorkoutCoordinatorTests

/// The coordinator drives a session through `SessionRepositoryProtocol`:
/// no SwiftData, no network.
@Suite("ActiveWorkoutCoordinator", .serialized)
@MainActor
struct ActiveWorkoutCoordinatorTests {
    let fx: TrainingFixtures

    init() throws {
        fx = try TrainingFixtures()
    }

    private func makeCoordinator(requestSync: @escaping @MainActor () -> Void = {}) -> ActiveWorkoutCoordinator {
        ActiveWorkoutCoordinator(
            sessions: fx.sessions,
            routines: fx.routines,
            exerciseSettings: fx.store.exerciseSettings,
            changeExerciseRest: { 120 },
            requestSync: requestSync,
            timerService: RestTimerService(),
            liveActivity: LiveActivitySpy(),
            now: { TrainingFixtures.t0 }
        )
    }

    @Test("start(routineId:) opens a session in progress with the routine's entries")
    func startFromRoutine() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)

        #expect(coordinator.phase == .active)
        #expect(coordinator.session?.routineId == routine.id)
        #expect(coordinator.session?.name == routine.name)
        #expect(coordinator.entries.map(\.exerciseId) == [fx.squat.id, fx.press.id])
        #expect(coordinator.currentEntry?.exerciseId == fx.squat.id)
        #expect(try fx.sessions.activeSession()?.id == coordinator.activeWorkoutId)
    }

    @Test("start(routineId:) throws for a routine that does not exist")
    func startUnknownRoutine() async {
        let coordinator = makeCoordinator()
        await #expect(throws: TrainingDataError.notFound) {
            try await coordinator.start(routineId: UUID())
        }
        #expect(coordinator.phase == .idle)
    }

    @Test("recordSet logs a manual set on the current entry and rests between sets")
    func recordSetLogsManualSet() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)

        try await coordinator.recordSet(reps: 8, weight: .kg(16), rir: 2)

        let entry = try #require(coordinator.currentEntry)
        #expect(entry.status == .done)
        #expect(entry.manualSets.count == 1)
        #expect(entry.manualSets.first?.values == SetValues(reps: 8, weight: .kg(16), rir: 2))
        #expect(coordinator.phase == .restingBetweenSets)
        await coordinator.skipTimer()
    }

    @Test("a warm-up set is stored as warm-up, with its RIR as chosen, and starts no rest")
    func recordWarmupSet() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)

        try await coordinator.recordSet(reps: 12, weight: .kg(8), rir: 0, warmup: true)

        let set = try #require(coordinator.currentEntry?.manualSets.first)
        #expect(set.warmup)
        #expect(set.values.rir == 0)
        #expect(coordinator.phase == .active)

        try coordinator.setWarmup(false, setId: set.id)
        #expect(coordinator.currentEntry?.manualSets.first?.warmup == false)
    }

    @Test("warm-up sets do not count toward the routine's target sets")
    func warmupDoesNotCountTowardTarget() async throws {
        let routine = try fx.makeRoutine()  // squat: 3 target sets
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)

        try await coordinator.recordSet(reps: 12, weight: .kg(20), rir: 5, warmup: true)
        try await coordinator.recordSet(reps: 8, weight: .kg(60), rir: 2)
        await coordinator.skipTimer()
        try await coordinator.recordSet(reps: 8, weight: .kg(60), rir: 1)
        #expect(coordinator.phase == .restingBetweenSets)
        #expect(coordinator.currentEntry?.workingManualSets.count == 2)
        await coordinator.skipTimer()

        try await coordinator.recordSet(reps: 8, weight: .kg(60), rir: 0)
        #expect(coordinator.phase == .restingBetweenExercises)
        await coordinator.skipTimer()
    }

    @Test("undoLastSet deletes the last set and returns to active")
    func undoLastSet() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        try await coordinator.recordSet(reps: 8, weight: nil, rir: nil)

        try await coordinator.undoLastSet()

        #expect(coordinator.currentEntry?.manualSets.isEmpty == true)
        #expect(coordinator.currentEntry?.status == .skipped)
        #expect(coordinator.phase == .active)
    }

    @Test("start(routineId:) resumes a session left in progress instead of creating another")
    func startResumesResidualSession() async throws {
        let routine = try fx.makeRoutine()
        let residual = try fx.sessions.startSession(
            routineId: nil,
            name: "Residual",
            at: TrainingFixtures.t0,
            timeZone: .gmt
        )

        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)

        #expect(coordinator.phase == .active)
        #expect(coordinator.activeWorkoutId == residual.id)
        let all = try fx.sessions.completedSessions(in: DateInterval(start: .distantPast, end: .distantFuture))
        #expect(all.isEmpty)
    }

    /// The real sync, signed in as a new user, against the in-memory server, and
    /// a routine of that user's own data (written after the sign-in, so it syncs).
    private struct SignedIn {
        let scheduler: SyncScheduler
        let server: InMemoryTrainingRemoteStore
        let routine: Routine
    }

    private func signedInSync() async throws -> SignedIn {
        let server = InMemoryTrainingRemoteStore()
        let scheduler = SyncScheduler(store: fx.store, remote: server, now: { TrainingFixtures.t0 })
        scheduler.signIn(userId: UUID())
        await scheduler.waitUntilIdle()
        let lunge = Exercise(name: "Walking Lunge", type: .strength, equipment: .freeWeights)
        try fx.exercises.save(lunge)
        let routine = Routine(name: "Legs", items: [RoutineItem(order: 1, exerciseId: lunge.id, targetSets: 3)])
        try fx.routines.save(routine)
        return SignedIn(scheduler: scheduler, server: server, routine: routine)
    }

    @Test("S12 finish() returns while the sync it started is still running", .timeLimit(.minutes(1)))
    func finishDoesNotWaitForTheSync() async throws {
        let world = try await signedInSync()
        let (scheduler, server, routine) = (world.scheduler, world.server, world.routine)
        let coordinator = makeCoordinator(requestSync: { scheduler.requestSync() })
        try await coordinator.start(routineId: routine.id)
        let id = try #require(coordinator.activeWorkoutId)
        try await coordinator.recordSet(reps: 8, weight: nil, rir: nil)
        let gate = AsyncGate()
        await server.duringNextPull { await gate.wait() }

        try await coordinator.finish()

        #expect(scheduler.status == .syncing)
        #expect(coordinator.phase == .idle)
        #expect(coordinator.completedWorkoutId == id)
        #expect(try fx.sessions.session(id: id)?.isCompleted == true)
        await gate.open()
        await scheduler.waitUntilIdle()
        #expect(scheduler.status == .idle)
        #expect(await server.calls.contains(.pushSession(id)))
        #expect(try fx.store.syncState.pendingSessions().isEmpty)
    }

    @Test("S4 finish() completes the session even when the sync fails, and the session stays pending")
    func finishIsAtomicEvenWhenSyncFails() async throws {
        let world = try await signedInSync()
        let (scheduler, server, routine) = (world.scheduler, world.server, world.routine)
        let coordinator = makeCoordinator(requestSync: { scheduler.requestSync() })
        try await coordinator.start(routineId: routine.id)
        let id = try #require(coordinator.activeWorkoutId)
        try await coordinator.recordSet(reps: 8, weight: nil, rir: nil)
        await server.failNext(.pushSession)

        try await coordinator.finish()
        await scheduler.waitUntilIdle()

        #expect(scheduler.status == .failed)
        #expect(coordinator.phase == .idle)
        #expect(coordinator.completedWorkoutId == id)
        #expect(try fx.sessions.session(id: id)?.isCompleted == true)
        #expect(try fx.sessions.activeSession() == nil)
        #expect(try fx.store.syncState.pendingSessions().map(\.id) == [id])
    }

    // MARK: - T6 (D7): a session with no working sets is never saved

    private func history() throws -> [TrainingSession] {
        try fx.sessions.completedSessions(in: DateInterval(start: .distantPast, end: .distantFuture))
    }

    @Test("AC6.1 AC6.2 a routine session with no sets has no working sets, and finishing discards it")
    func routineWithoutSetsIsDiscarded() async throws {
        let routine = try fx.makeRoutine()
        _ = try fx.makeRoutine(name: "Full Body B")
        let proposedBefore = try fx.routines.nextRoutine()?.id
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        let id = try #require(coordinator.activeWorkoutId)
        #expect(!coordinator.hasWorkingSets)

        try await coordinator.finish()

        #expect(coordinator.lastFinishOutcome == .discarded)
        #expect(coordinator.phase == .idle)
        #expect(coordinator.completedWorkoutId == nil, "no summary for a discarded session")
        #expect(try fx.sessions.session(id: id) == nil)
        #expect(try fx.sessions.activeSession() == nil)
        #expect(try history().isEmpty)
        #expect(try fx.routines.nextRoutine()?.id == proposedBefore, "no effect on Próxima sesión")
    }

    @Test("AC6.1 AC6.2 warm-up sets are not working sets: a warm-up-only session is discarded")
    func warmupOnlyIsDiscarded() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        let id = try #require(coordinator.activeWorkoutId)
        try await coordinator.recordSet(reps: 10, weight: .kg(10), rir: nil, warmup: true)
        await coordinator.skipTimer()
        #expect(!coordinator.hasWorkingSets)

        try await coordinator.finish()
        #expect(coordinator.lastFinishOutcome == .discarded)
        #expect(try fx.sessions.session(id: id) == nil)
        #expect(try history().isEmpty)
    }

    @Test("AC6.1 AC6.2 a free session with no entries is discarded by the same rule")
    func emptyFreeSessionIsDiscarded() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startAdHoc(name: "Free")
        let id = try #require(coordinator.activeWorkoutId)
        #expect(!coordinator.hasWorkingSets)

        try await coordinator.finish()
        #expect(coordinator.lastFinishOutcome == .discarded)
        #expect(coordinator.phase == .idle)
        #expect(try fx.sessions.session(id: id) == nil)
        #expect(try fx.sessions.activeSession() == nil)
    }

    @Test("AC6.3 checking for working sets changes nothing: the session stays in progress")
    func keepTrainingKeepsSession() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        let before = try #require(try fx.sessions.activeSession())
        #expect(!coordinator.hasWorkingSets)

        #expect(coordinator.phase == .active)
        #expect(try fx.sessions.activeSession() == before)
    }

    @Test("AC6.4 a session with a working set is saved as before; exercises not done stay skipped")
    func workingSetSaves() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        let id = try #require(coordinator.activeWorkoutId)
        try await coordinator.recordSet(reps: 10, weight: .kg(10), rir: nil, warmup: true)
        await coordinator.skipTimer()
        try await coordinator.recordSet(reps: 8, weight: .kg(20), rir: nil)
        await coordinator.skipTimer()
        #expect(coordinator.hasWorkingSets)

        try await coordinator.finish()
        #expect(coordinator.lastFinishOutcome == .saved(id))
        #expect(coordinator.completedWorkoutId == id)
        let saved = try #require(try fx.sessions.session(id: id))
        #expect(saved.isCompleted)
        #expect(saved.entries.map(\.status) == [.done, .skipped])
    }

    @Test("D-T6a a cardio-only session is saved without the prompt")
    func cardioOnlySaves() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startAdHoc(name: "Free")
        let id = try #require(coordinator.activeWorkoutId)
        try fx.sessions.logManualSet(
            SetValues(durationSeconds: 1200, distanceMeters: 4000), exerciseId: fx.rower.id, sessionId: id,
            at: TrainingFixtures.t0
        )
        #expect(coordinator.hasWorkingSets)

        try await coordinator.finish()
        #expect(coordinator.lastFinishOutcome == .saved(id))
        #expect(try fx.sessions.session(id: id)?.isCompleted == true)
    }

    @Test("D-T6a an imported set counts as a working set")
    func importedSetSaves() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        let id = try #require(coordinator.activeWorkoutId)
        try fx.sessions.importEntry(fx.importedSets("e-1", reps: [10], weight: 40), into: id)
        #expect(coordinator.hasWorkingSets)

        try await coordinator.finish()
        #expect(coordinator.lastFinishOutcome == .saved(id))
    }

    @Test("M14 a session whose only set is an imported warm-up has no working sets: finishing discards it")
    func importedWarmupOnlyDiscards() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        let id = try #require(coordinator.activeWorkoutId)
        try fx.sessions.importEntry(fx.importedSets("e-1", reps: [10], weight: 40), into: id)
        let imported = try #require(try fx.sessions.session(id: id)?.entries.flatMap(\.sets).first)
        try fx.sessions.setWarmup(true, setId: imported.id)
        #expect(!coordinator.hasWorkingSets)

        try await coordinator.finish()
        #expect(coordinator.lastFinishOutcome == .discarded)
        #expect(try fx.sessions.session(id: id) == nil)
    }

    @Test("M15 the sets of a removed entry are not working sets")
    func removedEntrySetsDoNotCount() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        let id = try #require(coordinator.activeWorkoutId)
        try fx.sessions.importEntry(fx.importedSets("e-1", reps: [10], weight: 40), into: id)
        let entry = try #require(try fx.sessions.session(id: id)?.entries.first { $0.exerciseId == fx.press.id })
        try fx.sessions.removeEntry(id: entry.id)
        #expect(!coordinator.hasWorkingSets)
    }

    @Test("pause and resume switch the phase")
    func pauseResume() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        try await coordinator.pause()
        #expect(coordinator.phase == .paused)
        try await coordinator.resume()
        #expect(coordinator.phase == .active)
    }
}
