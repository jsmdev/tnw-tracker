import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - DeleteInWorkoutTests

/// Deleting any logged set and removing an exercise from the session in progress.
@Suite("Delete in workout", .serialized)
@MainActor
struct DeleteInWorkoutTests {
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

    /// A routine session with two sets logged on the first exercise (squat).
    private func sessionWithTwoSets() async throws -> ActiveWorkoutCoordinator {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        try await coordinator.recordSet(reps: 8, weight: .kg(40), rir: nil)
        await coordinator.skipTimer()
        try await coordinator.recordSet(reps: 6, weight: .kg(45), rir: nil)
        await coordinator.skipTimer()
        return coordinator
    }

    // MARK: Delete a set

    @Test("deleteSet removes an earlier set and keeps the others")
    func deleteEarlierSet() async throws {
        let coordinator = try await sessionWithTwoSets()
        let sets = try #require(coordinator.currentEntry?.manualSets)
        #expect(sets.count == 2)

        try await coordinator.deleteSet(id: sets[0].id)

        let left = try #require(coordinator.currentEntry?.manualSets)
        #expect(left.map(\.id) == [sets[1].id])
        let stored = try fx.sessions.session(id: #require(coordinator.activeWorkoutId))
        #expect(stored?.entries.first { $0.exerciseId == fx.squat.id }?.manualSets.count == 1)
        #expect(coordinator.phase == .active)
    }

    @Test("deleting the only set of a planned exercise keeps the exercise, not done")
    func deleteOnlySetOfPlannedExercise() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        try await coordinator.recordSet(reps: 8, weight: nil, rir: nil)
        await coordinator.skipTimer()
        let setId = try #require(coordinator.currentEntry?.manualSets.first?.id)

        try await coordinator.deleteSet(id: setId)

        #expect(coordinator.entries.count == 2)
        #expect(coordinator.currentEntry?.exerciseId == fx.squat.id)
        #expect(coordinator.currentEntry?.status == .skipped)
        #expect(!coordinator.hasWorkingSets)
    }

    @Test("deleting the set whose rest is running stops the rest")
    func deleteRestingSet() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        try await coordinator.recordSet(reps: 8, weight: nil, rir: nil)
        #expect(coordinator.phase == .restingBetweenSets)
        let setId = try #require(coordinator.currentEntry?.manualSets.first?.id)

        try await coordinator.deleteSet(id: setId)

        #expect(coordinator.phase == .active)
        #expect(coordinator.timerService.state == nil)
        #expect(coordinator.currentEntry?.manualSets.isEmpty == true)
    }

    // MARK: Remove an exercise

    @Test("removeExercise takes the exercise out: hidden, stored as removed, its sets do not count")
    func removeExerciseWithSets() async throws {
        let coordinator = try await sessionWithTwoSets()
        let entryId = try #require(coordinator.currentEntry?.id)

        try await coordinator.removeExercise(entryId: entryId)

        #expect(coordinator.entries.map(\.exerciseId) == [fx.press.id])
        #expect(coordinator.currentEntry?.exerciseId == fx.press.id)
        let stored = try fx.sessions.session(id: #require(coordinator.activeWorkoutId))
        let removed = stored?.entries.first { $0.id == entryId }
        #expect(removed?.status == .removed)
        #expect(removed?.manualSets.count == 2, "its sets stay stored")
        #expect(!coordinator.hasWorkingSets)
    }

    @Test("removing the exercise whose rest is running stops the rest")
    func removeRestingExercise() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        try await coordinator.recordSet(reps: 8, weight: nil, rir: nil)
        #expect(coordinator.phase == .restingBetweenSets)
        let entryId = try #require(coordinator.currentEntry?.id)

        try await coordinator.removeExercise(entryId: entryId)

        #expect(coordinator.phase == .active)
        #expect(coordinator.timerService.state == nil)
    }

    @Test("removing an earlier exercise keeps the current one selected")
    func removeEarlierExercise() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        let first = try #require(coordinator.entries.first?.id)
        coordinator.advanceToNextExercise()
        #expect(coordinator.currentEntry?.exerciseId == fx.press.id)

        try await coordinator.removeExercise(entryId: first)

        #expect(coordinator.currentExerciseIndex == 0)
        #expect(coordinator.currentEntry?.exerciseId == fx.press.id)
    }

    @Test("removing the last exercise in the list selects the one before it")
    func removeLastExercise() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        coordinator.advanceToNextExercise()
        let last = try #require(coordinator.currentEntry?.id)

        try await coordinator.removeExercise(entryId: last)

        #expect(coordinator.currentExerciseIndex == 0)
        #expect(coordinator.currentEntry?.exerciseId == fx.squat.id)
    }

    @Test("removing an exercise picked without sets just drops the pick")
    func removePickedExercise() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startAdHoc(name: "Free")
        coordinator.addExercise(fx.squat.id)
        let pickId = try #require(coordinator.currentEntry?.id)

        try await coordinator.removeExercise(entryId: pickId)

        #expect(coordinator.entries.isEmpty)
        #expect(coordinator.currentEntry == nil)
    }
}
