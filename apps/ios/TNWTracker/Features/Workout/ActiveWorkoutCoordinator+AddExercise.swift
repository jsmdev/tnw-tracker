import Foundation
import os.log
import TNWTrackerKit

private let logger = Logger(subsystem: "com.tnwtracker", category: "coordinator")

// Adding exercises to the session in progress (#137 S5, free session).

extension ActiveWorkoutCoordinator {
    /// Makes `exerciseId` the current exercise. An exercise already in the session
    /// selects its entry; any other one is saved at once at the end, without sets,
    /// so leaving the workout keeps it (fast-add-exercise S4). Does nothing
    /// without a session.
    public func addExercise(_ exerciseId: UUID) {
        guard let current = session, phase != .idle else { return }
        do {
            let entry = try sessions.addEntry(exerciseId: exerciseId, sessionId: current.id)
            try refreshSession()
            currentExerciseIndex = entries.firstIndex { $0.id == entry.id } ?? currentExerciseIndex
        } catch {
            logger.error("addExercise failed: \(error)")
            return
        }
        logger.info("Coordinator added exercise \(exerciseId) at index \(self.currentExerciseIndex)")
        publishLiveActivity()
    }

    /// Entries saved in the session, in session order. Removed entries are hidden.
    var savedEntries: [SessionEntry] {
        (session?.entries ?? []).filter { $0.status != .removed }
    }

    /// After deleting the only set of an exercise the user added, the store drops
    /// its entry; add it back, so the exercise stays in the session.
    func keepAddedExercise(_ exerciseId: UUID?) throws {
        guard let exerciseId, let current = session,
              !savedEntries.contains(where: { $0.exerciseId == exerciseId }) else { return }
        try sessions.addEntry(exerciseId: exerciseId, sessionId: current.id)
        try refreshSession()
    }
}
