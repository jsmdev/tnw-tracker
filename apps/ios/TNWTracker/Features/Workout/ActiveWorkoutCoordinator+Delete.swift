import Foundation
import os.log
import TNWTrackerKit

private let logger = Logger(subsystem: "com.tnwtracker", category: "coordinator")

// Deleting any logged set and removing an exercise from the session in progress.

extension ActiveWorkoutCoordinator {
    /// Deletes a manual set of the session in progress. The last set, while its
    /// undo window is open, is undone exactly as `undoLastSet()`. A rest running
    /// after the deleted set stops.
    public func deleteSet(id setId: UUID) async throws {
        if setId == undoLastSetId {
            return try await undoLastSet()
        }
        let exerciseId = entries.first { $0.sets.contains { $0.id == setId } }?.exerciseId
        let wasResting = restingSet?.setId == setId
        if wasResting { restingSet = nil }
        if setWithoutTimer?.setId == setId { setWithoutTimer = nil }
        if undoRestore?.setId == setId { undoRestore = nil }

        try sessions.deleteManualSet(id: setId)
        try refreshSession()
        // An exercise the user picked stays in the session when its only set goes.
        keepPickedIfUnsaved(exerciseId)
        if let exerciseId, let index = entries.firstIndex(where: { $0.exerciseId == exerciseId }) {
            currentExerciseIndex = index
        }
        if wasResting { await stopRest() }
        logger.info("Coordinator deleted set \(setId)")
        publishLiveActivity()
    }

    /// Takes an exercise out of the session in progress. A saved entry is marked
    /// `removed` (its sets stay stored and stop counting); an exercise picked
    /// without sets is simply dropped. The current exercise stays selected when
    /// another one is removed.
    public func removeExercise(entryId: UUID) async throws {
        let list = entries
        guard let removedIndex = list.firstIndex(where: { $0.id == entryId }) else {
            throw TrainingDataError.notFound
        }
        if picked?.entryId == entryId {
            picked = nil
        } else {
            let setIds = Set(list[removedIndex].sets.map(\.id))
            let wasResting = restingSet.map { setIds.contains($0.setId) } ?? false
            if wasResting { restingSet = nil }
            if let pending = setWithoutTimer, setIds.contains(pending.setId) { setWithoutTimer = nil }
            if let undo = undoLastSetId, setIds.contains(undo) {
                undoTask?.cancel()
                undoLastSetId = nil
                undoRestore = nil
            }
            try sessions.removeEntry(id: entryId)
            try refreshSession()
            if wasResting { await stopRest() }
        }
        if removedIndex < currentExerciseIndex { currentExerciseIndex -= 1 }
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
