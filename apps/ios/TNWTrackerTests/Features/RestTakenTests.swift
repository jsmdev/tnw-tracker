import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - Rest taken (T3, AC3.8)

/// A set's `restSeconds` (format `set.restSeconds`, "Rest taken after the set")
/// is the time the rest timer after it really ran, or, with no timer, the time
/// until the next set. The last set of the session gets none.
@Suite("Rest taken", .serialized)
@MainActor
struct RestTakenTests {
    /// A clock the test moves by hand, shared by the coordinator and the timer.
    @MainActor
    final class TestClock {
        var now = TrainingFixtures.t0
        func advance(_ seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }

    let fx: TrainingFixtures
    let clock = TestClock()
    let timer: RestTimerService
    let routine: Routine

    init() throws {
        fx = try TrainingFixtures()
        let clock = clock
        timer = RestTimerService(liveActivity: LiveActivityController(), now: { clock.now })
        routine = try fx.makeRoutine() // squat: 3 sets, 90 s; then press: 2 sets, 60 s
    }

    private func makeCoordinator(changeExerciseRest: Int? = 120) -> ActiveWorkoutCoordinator {
        let clock = clock
        return ActiveWorkoutCoordinator(
            sessions: fx.sessions,
            routines: fx.routines,
            exerciseSettings: fx.store.exerciseSettings,
            changeExerciseRest: { changeExerciseRest },
            syncEngine: NoopSyncEngine(),
            timerService: timer,
            liveActivity: LiveActivityController(),
            now: { clock.now }
        )
    }

    private func start(changeExerciseRest: Int? = 120) async throws -> ActiveWorkoutCoordinator {
        let coordinator = makeCoordinator(changeExerciseRest: changeExerciseRest)
        try await coordinator.start(routineId: routine.id)
        return coordinator
    }

    /// The stored `restSeconds` of every manual set of `exercise`, in order, read
    /// back from the repository snapshot (the values an export maps).
    private func rests(_ sessionId: UUID?, _ exercise: Exercise) throws -> [Int?] {
        let id = try #require(sessionId)
        let session = try #require(try fx.sessions.session(id: id))
        let entry = try #require(session.entries.first { $0.exerciseId == exercise.id })
        return entry.manualSets.sorted { $0.order < $1.order }.map(\.values.restSeconds)
    }

    private func logSet(_ coordinator: ActiveWorkoutCoordinator, warmup: Bool = false) async throws {
        try await coordinator.recordSet(reps: 8, weight: .kg(20), rir: 2, warmup: warmup)
    }

    @Test("AC3.8 a rest timer that finishes records the seconds it ran")
    func timerFinished() async throws {
        let coordinator = try await start()
        try await logSet(coordinator)

        clock.advance(90)
        await timer.expireIfDue()

        #expect(timer.state == nil)
        #expect(try rests(coordinator.activeWorkoutId, fx.squat) == [90])
    }

    @Test("AC3.8 a skipped rest records the seconds it ran until the skip")
    func timerSkipped() async throws {
        let coordinator = try await start()
        try await logSet(coordinator)

        clock.advance(40)
        await coordinator.skipTimer()

        #expect(try rests(coordinator.activeWorkoutId, fx.squat) == [40])
    }

    @Test("AC3.8 −15 s / +15 s count in the recorded rest")
    func timerAdjusted() async throws {
        let coordinator = try await start()
        try await logSet(coordinator)

        await coordinator.adjustTimer(by: 15)
        clock.advance(100)
        await timer.expireIfDue()
        #expect(timer.state != nil, "90 s + 15 s has not ended after 100 s")
        clock.advance(5)
        await timer.expireIfDue()

        #expect(try rests(coordinator.activeWorkoutId, fx.squat) == [105])
    }

    @Test("AC3.8 logging the next set while the rest runs ends it and records the time so far")
    func nextSetMidRest() async throws {
        let coordinator = try await start()
        try await logSet(coordinator)

        clock.advance(50)
        try await logSet(coordinator)

        #expect(try rests(coordinator.activeWorkoutId, fx.squat) == [50, nil])
        #expect(coordinator.phase == .restingBetweenSets, "the second set starts its own rest")
        await coordinator.skipTimer()
    }

    @Test("AC3.8 with no timer, the rest is the time until the next set (rest off, warm-up, change-exercise rest off)")
    func noTimer() async throws {
        let coordinator = try await start(changeExerciseRest: nil)
        try coordinator.saveRestSetting(ExerciseSetting(exerciseId: fx.squat.id, restEnabled: false, restSeconds: 90))

        try await logSet(coordinator, warmup: true)
        clock.advance(30)
        for gap in [70.0, 65] {
            try await logSet(coordinator)
            clock.advance(gap)
        }
        try await logSet(coordinator) // last squat set: no change-exercise rest
        #expect(coordinator.currentEntry?.exerciseId == fx.press.id)
        clock.advance(80)
        try await logSet(coordinator) // first press set

        #expect(try rests(coordinator.activeWorkoutId, fx.squat) == [30, 70, 65, 80])
        await coordinator.skipTimer()
    }

    @Test("AC3.8 the last set of the session gets no restSeconds")
    func lastSetHasNone() async throws {
        let coordinator = try await start()
        let sessionId = coordinator.activeWorkoutId
        coordinator.advanceToNextExercise() // press: last exercise, 2 sets, 60 s

        try await logSet(coordinator)
        clock.advance(60)
        await timer.expireIfDue()
        clock.advance(10)
        try await logSet(coordinator)
        #expect(coordinator.phase == .finishing)
        clock.advance(120)
        try await coordinator.finish()

        #expect(try rests(sessionId, fx.press) == [60, nil])
    }

    @Test("AC3.8 a set whose rest is still running when the session ends gets no restSeconds")
    func finishDuringRest() async throws {
        let coordinator = try await start()
        let sessionId = coordinator.activeWorkoutId
        try await logSet(coordinator)

        clock.advance(30)
        try await coordinator.finish()

        #expect(try rests(sessionId, fx.squat) == [nil])
    }

    @Test("AC3.8 the repository updates the values of a manual set only, with the set rules")
    func repositoryUpdatesManualSetsOnly() throws {
        let session = try fx.sessions.startSession(routineId: nil, name: "Free", at: TrainingFixtures.t0, timeZone: .gmt)
        let manual = try fx.sessions.logManualSet(SetValues(reps: 8), exerciseId: fx.press.id, sessionId: session.id, at: TrainingFixtures.t0)

        try fx.sessions.updateManualSet(SetValues(reps: 8, restSeconds: 75), setId: manual.id)
        let stored = try #require(try fx.sessions.session(id: session.id)?.entries.first?.manualSets.first)
        #expect(stored.values == SetValues(reps: 8, restSeconds: 75))

        #expect(throws: TrainingDataError.invalidSet("rest must not be negative")) {
            try fx.sessions.updateManualSet(SetValues(reps: 8, restSeconds: -1), setId: manual.id)
        }
        #expect(throws: TrainingDataError.notFound) {
            try fx.sessions.updateManualSet(SetValues(reps: 8), setId: UUID())
        }

        try fx.sessions.importEntry(fx.importedSets("e-1", reps: [10], weight: 40), into: session.id)
        let imported = try #require(try fx.sessions.session(id: session.id)?.entries.first?.sets.first { $0.source == .imported })
        #expect(throws: TrainingDataError.invalidSet("only manual sets can be updated")) {
            try fx.sessions.updateManualSet(SetValues(reps: 10, restSeconds: 30), setId: imported.id)
        }
    }
}
