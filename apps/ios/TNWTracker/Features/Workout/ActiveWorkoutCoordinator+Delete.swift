import Foundation
import os.log
import TNWTrackerKit

private let logger = Logger(subsystem: "com.tnwtracker", category: "coordinator")

// Undoing the last set, deleting any logged set and removing an exercise from the
// session in progress.

public extension ActiveWorkoutCoordinator {
    /// Deshace la última serie si todavía está en la ventana de undo.
    func undoLastSet() async throws {
        guard let setId = undoLastSetId else { return }
        undoTask?.cancel()
        undoLastSetId = nil
        let restore = undoRestore
        undoRestore = nil
        if restingSet?.setId == setId {
            restingSet = nil
        }
        if setWithoutTimer?.setId == setId {
            setWithoutTimer = nil
        }
        let exerciseId = entries.first { $0.sets.contains { $0.id == setId } }?.exerciseId
        let undone = manualSet(setId)
        try sessions.deleteManualSet(id: setId)
        if let undone, let exerciseId {
            putBackPendingSet(undone, exerciseId: exerciseId)
        }
        try refreshSession()
        // An exercise the user added stays in the session when its only set is undone.
        try keepAddedExercise(exerciseId)
        // The undone set's own rest stops; a rest it cut short is not resumed (D-T3k).
        await timerService.skip()
        if let restore {
            // As if the undone set was never logged: the previous set's rest is
            // measured again until the next real set.
            recordRest(nil, setId: restore.setId)
            restingSet = nil
            setWithoutTimer = restore
        }
        // Back to the exercise of the undone set, for example after an auto-advance (D-T3d).
        let previousIndex = currentExerciseIndex
        if let exerciseId, let index = entries.firstIndex(where: { $0.exerciseId == exerciseId }) {
            currentExerciseIndex = index
        }
        if phase == .restingBetweenSets || phase == .restingBetweenExercises || currentExerciseIndex != previousIndex {
            phase = .active
            logger.info("Coordinator phase → .active (undoLastSet)")
        }
        publishLiveActivity()
    }

    /// Deletes a manual set of the session in progress. The last set, while its
    /// undo window is open, is undone exactly as `undoLastSet()`. A rest running
    /// after the deleted set stops.
    func deleteSet(id setId: UUID) async throws {
        if setId == undoLastSetId {
            return try await undoLastSet()
        }
        // Only a set of the session in progress.
        guard let exerciseId = entries.first(where: { $0.sets.contains { $0.id == setId } })?.exerciseId else {
            throw TrainingDataError.notFound
        }
        let wasResting = restingSet?.setId == setId
        if wasResting {
            restingSet = nil
        }
        if setWithoutTimer?.setId == setId {
            setWithoutTimer = nil
        }
        if undoRestore?.setId == setId {
            undoRestore = nil
        }

        let deleted = manualSet(setId)
        try sessions.deleteManualSet(id: setId)
        if let deleted {
            putBackPendingSet(deleted, exerciseId: exerciseId)
        }
        try refreshSession()
        // An exercise the user added stays in the session when its only set goes.
        try keepAddedExercise(exerciseId)
        if let index = entries.firstIndex(where: { $0.exerciseId == exerciseId }) {
            currentExerciseIndex = index
        }
        if wasResting {
            await stopRest()
        }
        logger.info("Coordinator deleted set \(setId)")
        publishLiveActivity()
    }

    /// Takes an exercise out of the session in progress. A saved entry is marked
    /// `removed` (its sets stay stored and stop counting). The current exercise stays selected when
    /// another one is removed.
    func removeExercise(entryId: UUID) async throws {
        let list = entries
        guard let removedIndex = list.firstIndex(where: { $0.id == entryId }) else {
            throw TrainingDataError.notFound
        }
        let setIds = Set(list[removedIndex].sets.map(\.id))
        let wasResting = restingSet.map { setIds.contains($0.setId) } ?? false
        if wasResting {
            restingSet = nil
        }
        if let pending = setWithoutTimer, setIds.contains(pending.setId) {
            setWithoutTimer = nil
        }
        if let undo = undoLastSetId, setIds.contains(undo) {
            undoTask?.cancel()
            undoLastSetId = nil
            undoRestore = nil
        }
        try sessions.removeEntry(id: entryId)
        pendingRows[list[removedIndex].exerciseId] = nil
        try refreshSession()
        if wasResting {
            await stopRest()
        }
        if removedIndex < currentExerciseIndex {
            currentExerciseIndex -= 1
        }
        currentExerciseIndex = min(currentExerciseIndex, max(entries.count - 1, 0))
        logger.info("Coordinator removed entry \(entryId)")
        publishLiveActivity()
    }

    /// Stops the rest of a set that is gone, without moving to another exercise.
    private func stopRest() async {
        await timerService.skip()
        if phase == .restingBetweenSets || phase == .restingBetweenExercises {
            phase = .active
        }
    }
}
