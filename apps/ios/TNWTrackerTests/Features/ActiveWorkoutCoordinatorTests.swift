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

    /// Sync that always fails, to prove `finish()` closes the session anyway.
    final class FailingSync: SyncEngine {
        struct Offline: Error {}
        private(set) var calls = 0
        func fullSync() async throws {
            calls += 1
            throw Offline()
        }
    }

    private func makeCoordinator(sync: any SyncEngine = NoopSyncEngine()) -> ActiveWorkoutCoordinator {
        let liveActivity = LiveActivityController()
        return ActiveWorkoutCoordinator(
            sessions: fx.sessions,
            routines: fx.routines,
            exerciseSettings: fx.store.exerciseSettings,
            changeExerciseRest: { 120 },
            syncEngine: sync,
            timerService: RestTimerService(liveActivity: liveActivity),
            liveActivity: liveActivity,
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
        let residual = try fx.sessions.startSession(routineId: nil, name: "Residual", at: TrainingFixtures.t0, timeZone: .gmt)

        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)

        #expect(coordinator.phase == .active)
        #expect(coordinator.activeWorkoutId == residual.id)
        let all = try fx.sessions.completedSessions(in: DateInterval(start: .distantPast, end: .distantFuture))
        #expect(all.isEmpty)
    }

    @Test("finish() completes the session and returns to idle even when the sync fails")
    func finishIsAtomicEvenWhenSyncFails() async throws {
        let routine = try fx.makeRoutine()
        let sync = FailingSync()
        let coordinator = makeCoordinator(sync: sync)
        try await coordinator.start(routineId: routine.id)
        let id = try #require(coordinator.activeWorkoutId)

        try await coordinator.finish()

        #expect(sync.calls == 1)
        #expect(coordinator.phase == .idle)
        #expect(coordinator.completedWorkoutId == id)
        #expect(try fx.sessions.session(id: id)?.isCompleted == true)
        #expect(try fx.sessions.activeSession() == nil)
    }

    @Test("finish() discards a free session that has no entries (format: at least one entry)")
    func finishDiscardsEmptyFreeSession() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startAdHoc(name: "Free")
        let id = try #require(coordinator.activeWorkoutId)

        try await coordinator.finish()

        #expect(coordinator.phase == .idle)
        #expect(try fx.sessions.session(id: id) == nil)
        #expect(try fx.sessions.activeSession() == nil)
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

// MARK: - SetLogFormState Tests

@Suite("SetLogFormState")
struct SetLogFormStateTests {
    @Test("default state has reps 0, weight 0, no RIR, not a warm-up")
    func defaultState() {
        let state = SetLogFormState()
        #expect(state.reps == 0)
        #expect(state.weight == 0.0)
        #expect(state.rir == nil)
        #expect(!state.warmup)
    }

    @Test("isValid requires reps > 0")
    func isValidRequiresPositiveReps() {
        var state = SetLogFormState()
        #expect(!state.isValid)

        state.reps = 5
        #expect(state.isValid)
    }

    @Test("isValid allows weight 0 (bodyweight exercises)")
    func isValidAllowsZeroWeight() {
        var state = SetLogFormState()
        state.reps = 10
        state.weight = 0.0
        #expect(state.isValid)
    }

    @Test("RIR is chosen directly in 0–10; nothing else is valid", arguments: [
        (nil, true), (0, true), (3, true), (10, true), (-1, false), (11, false)
    ] as [(Int?, Bool)])
    func rirValidRange(rir: Int?, valid: Bool) {
        var state = SetLogFormState()
        state.reps = 5
        state.rir = rir
        #expect(state.isValid == valid)
        #expect(state.rir == rir, "stored as chosen, no RPE conversion")
    }
}

// MARK: - RIRScale Tests

@Suite("RIRScale")
struct RIRScaleTests {
    @Test("with the default maximum 4 the options are 0, 1, 2, 3 and 4+")
    func defaultOptions() {
        let scale = RIRScale(maximum: RIRScale.defaultMaximum)
        #expect(RIRScale.defaultMaximum == 4)
        #expect(scale.options == [.value(0), .value(1), .value(2), .value(3), .atLeast(4)])
        #expect(scale.options.map(\.label) == ["0", "1", "2", "3", "4+"])
    }

    @Test("choosing N+ stores rir = N, any other option stores its value")
    func choosingStoresRIR() {
        let scale = RIRScale(maximum: 4)
        #expect(scale.rir(for: .atLeast(4)) == 4)
        #expect(scale.rir(for: .value(2)) == 2)
    }

    @Test("changing the maximum to 6 gives 0…5 and 6+")
    func maximumSix() {
        let scale = RIRScale(maximum: 6)
        #expect(scale.options == (0 ... 5).map(RIRScale.Option.value) + [.atLeast(6)])
    }

    @Test("the maximum stays in 1–10", arguments: [(0, 1), (1, 1), (10, 10), (11, 10)])
    func maximumClamped(input: Int, maximum: Int) {
        #expect(RIRScale(maximum: input).maximum == maximum)
    }

    @Test("a stored 7 with maximum 4 is shown as 4+ and is never rewritten")
    func storedAboveMaximum() {
        let scale = RIRScale(maximum: 4)
        var state = SetLogFormState()
        state.reps = 5
        state.rir = 7
        #expect(scale.option(for: state.rir) == .atLeast(4))
        #expect(scale.option(for: 3) == .value(3))
        #expect(scale.option(for: nil) == nil)
        #expect(state.rir == 7)
        #expect(state.isValid)
    }
}
