import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - Workout Live Activity (#136 S2, S4)

/// The Live Activity lasts the whole session and shows its real state: the
/// workout, the current exercise, the working sets done of the session's sets,
/// the rest left and whether the workout is paused. Only finishing or leaving
/// the workout ends it.
@Suite("Workout Live Activity", .serialized)
@MainActor
struct WorkoutLiveActivityTests {
    typealias State = ActiveWorkoutAttributes.ContentState

    let fx: TrainingFixtures
    let clock = RestTakenTests.TestClock()
    let timer: RestTimerService
    let spy = LiveActivitySpy()
    let routine: Routine

    init() throws {
        fx = try TrainingFixtures()
        let clock = clock
        timer = RestTimerService(now: { clock.now })
        routine = try fx.makeRoutine() // squat: 3 sets, 90 s; then press: 2 sets, 60 s
    }

    private func makeCoordinator() -> ActiveWorkoutCoordinator {
        let clock = clock
        let exercises = fx.exercises
        return ActiveWorkoutCoordinator(
            sessions: fx.sessions,
            routines: fx.routines,
            exerciseSettings: fx.store.exerciseSettings,
            changeExerciseRest: { 120 },
            requestSync: {},
            timerService: timer,
            liveActivity: spy,
            exerciseName: { try? exercises.exercise(id: $0)?.name },
            now: { clock.now }
        )
    }

    private func start(_ routine: Routine? = nil) async throws -> ActiveWorkoutCoordinator {
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: (routine ?? self.routine).id)
        return coordinator
    }

    private func logSet(_ coordinator: ActiveWorkoutCoordinator, warmup: Bool = false) async throws {
        try await coordinator.recordSet(reps: 8, weight: .kg(20), rir: 2, warmup: warmup)
    }

    private func state(
        exercise: String? = "Goblet Squat",
        rest: Int? = nil,
        done: Int = 0,
        total: Int = 5,
        paused: Bool = false
    ) -> State {
        State(
            workoutName: "Full Body A",
            currentExerciseName: exercise,
            restSecondsRemaining: rest,
            completedSets: done,
            totalSets: total,
            isPaused: paused
        )
    }

    // MARK: S2 — one Live Activity for the whole session

    @Test("S2 starting a workout starts its Live Activity with the session's first state")
    func startShowsFirstState() async throws {
        let coordinator = try await start()

        let workoutId = try #require(coordinator.activeWorkoutId)
        #expect(spy.calls == [.start(workoutId: workoutId, state: state())])
    }

    @Test("S2 a rest that runs out keeps the Live Activity, without the rest")
    func expiryKeepsLiveActivity() async throws {
        let coordinator = try await start()
        try await logSet(coordinator)
        #expect(spy.shownState == state(rest: 90, done: 1))

        clock.advance(90)
        await timer.expireIfDue()

        #expect(spy.endCount == 0)
        #expect(spy.shownState == state(done: 1))
        #expect(coordinator.phase == .active)
    }

    @Test("S2 a skipped rest keeps the Live Activity, and the next rest shows on it")
    func skipKeepsLiveActivity() async throws {
        let coordinator = try await start()
        try await logSet(coordinator)
        await coordinator.skipTimer()
        #expect(spy.shownState == state(done: 1))

        try await logSet(coordinator)

        #expect(spy.endCount == 0)
        #expect(spy.shownState == state(rest: 90, done: 2))
        await coordinator.skipTimer()
    }

    @Test("S2 finishing the workout ends the Live Activity once")
    func finishEnds() async throws {
        let coordinator = try await start()
        try await logSet(coordinator)
        clock.advance(90)
        await timer.expireIfDue()

        try await coordinator.finish()

        #expect(spy.endCount == 1)
        #expect(spy.calls.last == .end)
    }

    @Test("S2 leaving the workout (sign-out) ends the Live Activity once")
    func abandonEnds() async throws {
        let coordinator = try await start()
        try await logSet(coordinator)

        await coordinator.abandon()

        #expect(spy.endCount == 1)
        #expect(spy.calls.last == .end)
    }

    @Test("S2 resuming a session left in progress starts its Live Activity with its progress")
    func adoptShowsProgress() async throws {
        let first = try await start()
        let workoutId = try #require(first.activeWorkoutId)
        try await logSet(first)
        await first.skipTimer()
        await first.abandon()

        let resumed = try await start()

        #expect(spy.calls.last == .start(workoutId: workoutId, state: state(done: 1)))
        #expect(resumed.activeWorkoutId == workoutId)
    }

    // MARK: S4 — real progress and state

    @Test("S4 each rest tick shows the seconds left")
    func tickShowsRestLeft() async throws {
        let coordinator = try await start()
        try await logSet(coordinator)

        clock.advance(30)
        await timer.tick()

        #expect(spy.shownState == state(rest: 60, done: 1))
        await coordinator.skipTimer()
    }

    @Test("S4 −15 s / +15 s show on the Live Activity")
    func adjustShowsRestLeft() async throws {
        let coordinator = try await start()
        try await logSet(coordinator)

        await coordinator.adjustTimer(by: 15)

        #expect(spy.shownState == state(rest: 105, done: 1))
        await coordinator.skipTimer()
    }

    @Test("S4 the sets done count across exercises, and the exercise name follows the session")
    func progressAcrossExercises() async throws {
        let coordinator = try await start()
        for _ in 0 ..< 3 {
            try await logSet(coordinator)
            await coordinator.skipTimer()
        }
        #expect(spy.shownState == state(exercise: "Chest Press Machine", done: 3))

        try await logSet(coordinator)

        #expect(spy.shownState == state(exercise: "Chest Press Machine", rest: 60, done: 4))
        await coordinator.skipTimer()
    }

    @Test("S4 changing exercise by hand shows the new exercise")
    func manualAdvanceShowsExercise() async throws {
        let coordinator = try await start()

        coordinator.advanceToNextExercise()

        #expect(spy.shownState == state(exercise: "Chest Press Machine"))
    }

    @Test("S4 warm-up sets do not count, and marking a set as warm-up updates the count")
    func warmupsDoNotCount() async throws {
        let coordinator = try await start()
        try await logSet(coordinator, warmup: true)
        #expect(spy.shownState == state())

        try await logSet(coordinator)
        let setId = try #require(coordinator.currentEntry?.workingManualSets.first?.id)
        await coordinator.skipTimer()
        #expect(spy.shownState == state(done: 1))

        try coordinator.setWarmup(true, setId: setId)

        #expect(spy.shownState == state())
    }

    @Test("S4 undoing a set takes it off the count")
    func undoUpdatesCount() async throws {
        let coordinator = try await start()
        try await logSet(coordinator)

        try await coordinator.undoLastSet()

        #expect(spy.shownState == state())
    }

    @Test("S4 an exercise with no target counts the sets logged, never fewer than done")
    func noTargetCountsLogged() async throws {
        let free = Routine(name: "Full Body A", items: [RoutineItem(order: 1, exerciseId: fx.plank.id)])
        try fx.routines.save(free)
        let coordinator = try await start(free)

        for _ in 0 ..< 2 {
            try await logSet(coordinator)
            await coordinator.skipTimer()
        }

        #expect(spy.shownState == state(exercise: "Plank", done: 2, total: 2))
    }

    @Test("S4 pause and resume show on the Live Activity")
    func pauseResumeShows() async throws {
        let coordinator = try await start()

        try await coordinator.pause()
        #expect(spy.shownState == state(paused: true))

        try await coordinator.resume()
        #expect(spy.shownState == state())
        #expect(coordinator.phase == .active)
    }

    @Test("S1 pausing during a rest does nothing, so the screen hides the button there")
    func pauseDuringRestIsIgnored() async throws {
        let coordinator = try await start()
        try await logSet(coordinator)

        try await coordinator.pause()

        #expect(coordinator.phase == .restingBetweenSets)
        #expect(spy.shownState == state(rest: 90, done: 1))
        await coordinator.skipTimer()
    }
}
