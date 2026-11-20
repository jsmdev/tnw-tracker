import Foundation
import os.log
import TNWTrackerKit

private let logger = Logger(subsystem: "com.tnwtracker", category: "coordinator")

// Adding exercises to the session in progress (#137 S5, free session).

extension ActiveWorkoutCoordinator {
    /// An exercise picked from the list that has no set yet. It is not saved:
    /// its first set creates the entry. The session keeps one such pick at a time.
    struct PickedExercise: Equatable {
        let exerciseId: UUID
        /// Stable identity of the pick while it is shown.
        let entryId: UUID
    }

    /// Makes `exerciseId` the current exercise. An exercise already in the session
    /// selects its entry; any other one is picked and shown after the saved entries,
    /// replacing an earlier pick that has no set yet. Does nothing without a session.
    public func addExercise(_ exerciseId: UUID) {
        guard session != nil, phase != .idle else { return }
        if let index = savedEntries.firstIndex(where: { $0.exerciseId == exerciseId }) {
            picked = nil
            currentExerciseIndex = index
        } else {
            picked = PickedExercise(exerciseId: exerciseId, entryId: UUID())
            currentExerciseIndex = entries.count - 1
        }
        logger.info("Coordinator added exercise \(exerciseId) at index \(self.currentExerciseIndex)")
        publishLiveActivity()
    }

    /// Entries saved in the session, in session order. Removed entries are hidden.
    var savedEntries: [SessionEntry] {
        (session?.entries ?? []).filter { $0.status != .removed }
    }

    /// The pick as an entry without sets, unless the exercise already has a saved entry.
    var pickedEntry: SessionEntry? {
        guard let picked, !savedEntries.contains(where: { $0.exerciseId == picked.exerciseId }) else {
            return nil
        }
        return SessionEntry(
            id: picked.entryId,
            exerciseId: picked.exerciseId,
            order: (session?.entries.map(\.order).max() ?? 0) + 1,
            status: .skipped
        )
    }

    /// After an undo removed the entry of `exerciseId`, keep the exercise picked.
    func keepPickedIfUnsaved(_ exerciseId: UUID?) {
        guard let exerciseId, !savedEntries.contains(where: { $0.exerciseId == exerciseId }) else { return }
        picked = PickedExercise(exerciseId: exerciseId, entryId: UUID())
    }
}
