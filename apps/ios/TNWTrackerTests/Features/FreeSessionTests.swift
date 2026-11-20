import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// A free session (#137 S5): started without a routine, its exercises picked
/// from the list. A picked exercise is not saved until its first set.
@Suite("Free session", .serialized)
@MainActor
struct FreeSessionTests {
    let fx: TrainingFixtures

    init() throws {
        fx = try TrainingFixtures()
    }

    private func makeCoordinator() -> ActiveWorkoutCoordinator {
        ActiveWorkoutCoordinator(
            sessions: fx.sessions,
            routines: fx.routines,
            exerciseSettings: fx.store.exerciseSettings,
            changeExerciseRest: { 120 },
            requestSync: {},
            timerService: RestTimerService(),
            liveActivity: LiveActivitySpy(),
            now: { TrainingFixtures.t0 }
        )
    }

    private func savedExercises(_ coordinator: ActiveWorkoutCoordinator) throws -> [UUID] {
        let id = try #require(coordinator.activeWorkoutId)
        return try #require(try fx.sessions.session(id: id)).entries.map(\.exerciseId)
    }

    @Test("a picked exercise becomes the current one and is not saved before its first set")
    func pickIsCurrentAndUnsaved() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startAdHoc(name: "Free")

        coordinator.addExercise(fx.squat.id)

        #expect(coordinator.entries.map(\.exerciseId) == [fx.squat.id])
        #expect(coordinator.currentEntry?.exerciseId == fx.squat.id)
        #expect(coordinator.currentEntry?.sets.isEmpty == true)
        #expect(coordinator.phase == .active)
        #expect(try savedExercises(coordinator).isEmpty)
    }

    @Test("the first set of the picked exercise saves it with that set")
    func firstSetSavesPick() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startAdHoc(name: "Free")
        coordinator.addExercise(fx.squat.id)

        try await coordinator.recordSet(reps: 8, weight: .kg(40), rir: 2)
        await coordinator.skipTimer()

        #expect(try savedExercises(coordinator) == [fx.squat.id])
        #expect(coordinator.entries.map(\.exerciseId) == [fx.squat.id])
        #expect(coordinator.currentEntry?.status == .done)
        #expect(coordinator.currentEntry?.manualSets.count == 1)
    }

    @Test("picking again before any set replaces the unlogged pick")
    func secondPickReplacesUnloggedPick() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startAdHoc(name: "Free")
        coordinator.addExercise(fx.squat.id)

        coordinator.addExercise(fx.press.id)

        #expect(coordinator.entries.map(\.exerciseId) == [fx.press.id])
        #expect(coordinator.currentEntry?.exerciseId == fx.press.id)
    }

    @Test("a pick after a logged exercise goes after it and becomes current")
    func pickAfterLoggedExercise() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startAdHoc(name: "Free")
        coordinator.addExercise(fx.squat.id)
        try await coordinator.recordSet(reps: 8, weight: .kg(40), rir: 2)
        await coordinator.skipTimer()

        coordinator.addExercise(fx.press.id)
        #expect(coordinator.entries.map(\.exerciseId) == [fx.squat.id, fx.press.id])
        #expect(coordinator.currentExerciseIndex == 1)

        try await coordinator.recordSet(reps: 10, weight: .kg(20), rir: 1)
        await coordinator.skipTimer()
        #expect(try savedExercises(coordinator) == [fx.squat.id, fx.press.id])
        #expect(coordinator.currentEntry?.exerciseId == fx.press.id)
    }

    @Test("picking an exercise already in the session selects its entry")
    func pickExistingSelectsEntry() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)

        coordinator.addExercise(fx.press.id)

        #expect(coordinator.entries.map(\.exerciseId) == [fx.squat.id, fx.press.id])
        #expect(coordinator.currentEntry?.exerciseId == fx.press.id)
    }

    @Test("a routine session takes an extra exercise after its planned ones")
    func routineSessionTakesExtraExercise() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)

        coordinator.addExercise(fx.rower.id)

        #expect(coordinator.entries.map(\.exerciseId) == [fx.squat.id, fx.press.id, fx.rower.id])
        #expect(coordinator.currentEntry?.exerciseId == fx.rower.id)
    }

    @Test("undoing the only set of a picked exercise keeps it picked")
    func undoKeepsPick() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startAdHoc(name: "Free")
        coordinator.addExercise(fx.squat.id)
        try await coordinator.recordSet(reps: 8, weight: .kg(40), rir: 2)

        try await coordinator.undoLastSet()

        #expect(try savedExercises(coordinator).isEmpty)
        #expect(coordinator.entries.map(\.exerciseId) == [fx.squat.id])
        #expect(coordinator.currentEntry?.exerciseId == fx.squat.id)
        #expect(coordinator.phase == .active)
    }

    @Test("finishing with only an unlogged pick discards the session")
    func finishWithOnlyPickDiscards() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startAdHoc(name: "Free")
        let id = try #require(coordinator.activeWorkoutId)
        coordinator.addExercise(fx.squat.id)

        try await coordinator.finish()

        #expect(coordinator.lastFinishOutcome == .discarded)
        #expect(try fx.sessions.session(id: id) == nil)
        #expect(coordinator.entries.isEmpty)
    }

    @Test("a pick does not survive the end of the session")
    func pickClearedOnAbandon() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startAdHoc(name: "Free")
        coordinator.addExercise(fx.squat.id)

        await coordinator.abandon()
        try await coordinator.startAdHoc(name: "Free")

        #expect(coordinator.entries.isEmpty)
    }

    @Test("picking without a session in progress does nothing")
    func pickWithoutSession() {
        let coordinator = makeCoordinator()
        coordinator.addExercise(fx.squat.id)
        #expect(coordinator.entries.isEmpty)
        #expect(coordinator.phase == .idle)
    }
}
