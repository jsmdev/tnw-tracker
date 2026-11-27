import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// The workout offers "La última vez" and starts each new set from it
/// (fast-add-exercise S3 AC1–AC4), through the real coordinator and store.
@Suite("Workout prefill", .serialized)
@MainActor
struct WorkoutPrefillTests {
    let fx: TrainingFixtures
    let t0 = TrainingFixtures.t0

    init() throws {
        fx = try TrainingFixtures()
    }

    private func makeCoordinator() -> ActiveWorkoutCoordinator {
        ActiveWorkoutCoordinator(
            sessions: fx.sessions,
            routines: fx.routines,
            exerciseSettings: fx.store.exerciseSettings,
            changeExerciseRest: { nil },
            requestSync: {},
            timerService: RestTimerService(),
            liveActivity: LiveActivitySpy(),
            now: { TrainingFixtures.t0 }
        )
    }

    /// A completed squat session a day before `t0`: 20 × 9, 15 × 10.1.
    private func squatYesterday() throws {
        let start = t0.addingTimeInterval(-86400)
        let session = try fx.sessions.startSession(
            routineId: nil, name: nil, at: start, timeZone: TrainingFixtures.zone
        )
        for (reps, kg) in [(20, 9.0), (15, 10.1)] {
            try fx.sessions.logManualSet(
                SetValues(reps: reps, weight: .kg(kg)), warmup: false,
                exerciseId: fx.squat.id, sessionId: session.id, at: start.addingTimeInterval(60)
            )
        }
        try fx.sessions.finishSession(id: session.id, at: start.addingTimeInterval(600), durationSeconds: nil)
    }

    @Test("each new set starts from the same set last time, then from today's previous set (AC1, AC2, AC4)")
    func setsFollowLastTime() async throws {
        try squatYesterday()
        let coordinator = makeCoordinator()
        try await coordinator.startAdHoc(name: "Free")
        coordinator.addExercise(fx.squat.id)

        let last = try #require(coordinator.lastPerformance(for: fx.squat.id))
        #expect(last.sets.map(\.reps) == [20, 15])
        #expect(last.completedAt == t0.addingTimeInterval(-86400 + 600))
        var entry = try #require(coordinator.currentEntry)
        #expect(coordinator.prefill(for: entry) == SetValues(reps: 20, weight: .kg(9)))

        try await coordinator.recordSet(reps: 18, weight: .kg(12), rir: nil, warmup: true)
        entry = try #require(coordinator.currentEntry)
        #expect(
            coordinator.prefill(for: entry) == SetValues(reps: 20, weight: .kg(9)), "a warm-up is not a working set"
        )

        try await coordinator.recordSet(reps: 21, weight: .kg(9.5), rir: nil)
        entry = try #require(coordinator.currentEntry)
        #expect(coordinator.prefill(for: entry) == SetValues(reps: 15, weight: .kg(10.1)))

        try await coordinator.recordSet(reps: 14, weight: .kg(11), rir: 1)
        entry = try #require(coordinator.currentEntry)
        #expect(coordinator.prefill(for: entry) == SetValues(reps: 14, weight: .kg(11)), "past last time's sets")
    }

    @Test("never done: the routine target, then nothing (AC3)")
    func routineTargetThenNothing() async throws {
        let routine = Routine(name: "Targets", items: [
            RoutineItem(
                order: 1, exerciseId: fx.squat.id, targetSets: 3,
                targetReps: RepRange(min: 8, max: 12), targetWeight: .kg(40)
            ),
            RoutineItem(order: 2, exerciseId: fx.press.id)
        ])
        try fx.routines.save(routine)
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)

        let squat = try #require(coordinator.entries.first { $0.exerciseId == fx.squat.id })
        #expect(coordinator.lastPerformance(for: fx.squat.id) == nil)
        #expect(coordinator.prefill(for: squat) == SetValues(reps: 8, weight: .kg(40)))
        let press = try #require(coordinator.entries.first { $0.exerciseId == fx.press.id })
        #expect(coordinator.prefill(for: press) == SetValues())
    }

    @Test("the next session reads the session just finished as last time")
    func nextSessionSeesTheFinishedOne() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startAdHoc(name: "First")
        coordinator.addExercise(fx.squat.id)
        #expect(coordinator.lastPerformance(for: fx.squat.id) == nil)
        try await coordinator.recordSet(reps: 6, weight: .kg(70), rir: nil)
        try await coordinator.finish()

        try await coordinator.startAdHoc(name: "Second")
        let last = try #require(coordinator.lastPerformance(for: fx.squat.id))
        #expect(last.sets.map(\.reps) == [6])
        #expect(last.sets.map(\.weight) == [.kg(70)])
    }
}
