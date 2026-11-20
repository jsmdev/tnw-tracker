import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - Rest expiry (#136 S1, S5)

/// A rest that runs out on its own moves the session on: back to `.active`
/// after a rest between sets, and to the next exercise after a rest between
/// exercises, as skipping it does.
@Suite("Rest expiry", .serialized)
@MainActor
struct RestExpiryTests {
    let fx: TrainingFixtures
    let clock = RestTakenTests.TestClock()
    let timer: RestTimerService
    let routine: Routine

    init() throws {
        fx = try TrainingFixtures()
        let clock = clock
        timer = RestTimerService(now: { clock.now })
        routine = try fx.makeRoutine() // squat: 3 sets, 90 s; then press: 2 sets, 60 s
    }

    private func start() async throws -> ActiveWorkoutCoordinator {
        let clock = clock
        let coordinator = ActiveWorkoutCoordinator(
            sessions: fx.sessions,
            routines: fx.routines,
            exerciseSettings: fx.store.exerciseSettings,
            changeExerciseRest: { 120 },
            requestSync: {},
            timerService: timer,
            liveActivity: LiveActivitySpy(),
            now: { clock.now }
        )
        try await coordinator.start(routineId: routine.id)
        return coordinator
    }

    private func logSet(_ coordinator: ActiveWorkoutCoordinator) async throws {
        try await coordinator.recordSet(reps: 8, weight: .kg(20), rir: 2)
    }

    @Test("S1 a rest between sets that runs out returns the session to active on the same exercise")
    func restBetweenSetsExpires() async throws {
        let coordinator = try await start()
        try await logSet(coordinator)
        #expect(coordinator.phase == .restingBetweenSets)

        clock.advance(90)
        await timer.expireIfDue()

        #expect(coordinator.phase == .active)
        #expect(timer.state == nil)
        #expect(coordinator.currentEntry?.exerciseId == fx.squat.id)
    }

    @Test("S1 a rest between exercises that runs out moves to the next exercise, as skipping it does")
    func restBetweenExercisesExpires() async throws {
        let coordinator = try await start()
        for _ in 0 ..< 2 {
            try await logSet(coordinator)
            await coordinator.skipTimer()
        }
        try await logSet(coordinator)
        #expect(coordinator.phase == .restingBetweenExercises)

        clock.advance(120)
        await timer.expireIfDue()

        #expect(coordinator.phase == .active)
        #expect(timer.state == nil)
        #expect(coordinator.currentEntry?.exerciseId == fx.press.id)
    }

    @Test("S1 a rest that has not run out leaves the session resting")
    func restNotDueStaysResting() async throws {
        let coordinator = try await start()
        try await logSet(coordinator)

        clock.advance(89)
        await timer.expireIfDue()

        #expect(coordinator.phase == .restingBetweenSets)
        #expect(timer.state != nil)
        await coordinator.skipTimer()
    }

    @Test("S1 logging a set during a rest between exercises does not advance the exercise")
    func setDuringRestBetweenExercises() async throws {
        let coordinator = try await start()
        for _ in 0 ..< 2 {
            try await logSet(coordinator)
            await coordinator.skipTimer()
        }
        try await logSet(coordinator)
        #expect(coordinator.phase == .restingBetweenExercises)

        try await logSet(coordinator) // a fourth squat set cuts the rest short

        #expect(coordinator.currentEntry?.exerciseId == fx.squat.id)
        await coordinator.skipTimer()
    }

    @Test("S1 S2 the running timer ends the rest by itself: active again, Live Activity kept", .timeLimit(.minutes(1)))
    func timerRunsOutByItself() async throws {
        let spy = LiveActivitySpy()
        let realTimer = RestTimerService()
        let coordinator = ActiveWorkoutCoordinator(
            sessions: fx.sessions,
            routines: fx.routines,
            exerciseSettings: fx.store.exerciseSettings,
            changeExerciseRest: { 120 },
            requestSync: {},
            timerService: realTimer,
            liveActivity: spy
        )
        try await coordinator.start(routineId: routine.id)
        try await logSet(coordinator)
        await coordinator.adjustTimer(by: -90) // the rest ends now; the 1 Hz tick notices it

        for _ in 0 ..< 50 where coordinator.phase != .active {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(coordinator.phase == .active)
        #expect(realTimer.state == nil)
        #expect(spy.endCount == 0)
        #expect(spy.shownState?.restSecondsRemaining == nil)
        await coordinator.abandon()
    }
}
