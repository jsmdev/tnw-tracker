import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// A session left in progress (the app closed, or the user signed in again) is
/// resumed where the user was: on the exercise of its most recent set.
@Suite("Resume a workout in progress", .serialized)
@MainActor
struct ResumeWorkoutTests {
    let fx: TrainingFixtures

    init() throws {
        fx = try TrainingFixtures()
    }

    @MainActor
    private final class Clock {
        var now = TrainingFixtures.t0
    }

    private func makeCoordinator(clock: Clock) -> ActiveWorkoutCoordinator {
        ActiveWorkoutCoordinator(
            sessions: fx.sessions,
            routines: fx.routines,
            exerciseSettings: fx.store.exerciseSettings,
            changeExerciseRest: { 120 },
            requestSync: {},
            timerService: RestTimerService(),
            liveActivity: LiveActivitySpy(),
            now: { clock.now }
        )
    }

    @Test("resuming goes to the exercise of the latest set, past skipped planned ones")
    func resumesOnLatestSetExercise() async throws {
        let routine = try fx.makeRoutine()
        let clock = Clock()
        let first = makeCoordinator(clock: clock)
        try await first.start(routineId: routine.id)
        first.addExercise(fx.plank.id)
        clock.now = TrainingFixtures.t0.addingTimeInterval(300)
        try await first.recordSet(reps: 10, weight: nil, rir: nil)
        await first.skipTimer()

        // The app is opened again: a new coordinator finds the session.
        let resumed = makeCoordinator(clock: clock)
        try await resumed.start(routineId: routine.id)

        #expect(resumed.activeWorkoutId == first.activeWorkoutId)
        #expect(resumed.currentEntry?.exerciseId == fx.plank.id)
    }

    @Test("resuming goes to the later of two exercises with sets")
    func resumesOnMostRecentOfSeveral() async throws {
        let routine = try fx.makeRoutine()
        let clock = Clock()
        let first = makeCoordinator(clock: clock)
        try await first.start(routineId: routine.id)
        first.addExercise(fx.plank.id)
        clock.now = TrainingFixtures.t0.addingTimeInterval(60)
        try await first.recordSet(reps: 10, weight: nil, rir: nil)
        await first.skipTimer()
        first.addExercise(fx.press.id)
        clock.now = TrainingFixtures.t0.addingTimeInterval(120)
        try await first.recordSet(reps: 8, weight: .kg(20), rir: 2)
        await first.skipTimer()

        // "Entrenamiento libre" also resumes the session in progress.
        let resumed = makeCoordinator(clock: clock)
        try await resumed.startAdHoc(name: "Free")

        #expect(resumed.currentEntry?.exerciseId == fx.press.id)
    }

    @Test("a resumed session without sets starts on its first planned exercise")
    func resumesWithoutSetsOnFirstExercise() async throws {
        let routine = try fx.makeRoutine()
        let clock = Clock()
        let first = makeCoordinator(clock: clock)
        try await first.start(routineId: routine.id)

        let resumed = makeCoordinator(clock: clock)
        try await resumed.start(routineId: routine.id)

        #expect(resumed.currentEntry?.exerciseId == fx.squat.id)
    }
}
