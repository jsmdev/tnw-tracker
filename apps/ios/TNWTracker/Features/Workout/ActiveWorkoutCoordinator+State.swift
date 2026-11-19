import Foundation
import TNWTrackerKit

// Read-only views of the coordinator state.

extension ActiveWorkoutCoordinator {
    /// What `finish()` did with the session.
    public enum FinishOutcome: Equatable {
        /// Completed and saved; the summary shows it.
        case saved(UUID)
        /// Deleted: it had no working sets (T6, D7).
        case discarded
    }

    /// Whether the session in progress has a working set (T6, D-T6a). Without
    /// one, "Terminar" asks first and `finish()` discards the session.
    public var hasWorkingSets: Bool {
        guard let current = session else { return false }
        return ((try? sessions.session(id: current.id)) ?? current).hasWorkingSets
    }

    // MARK: - DrainCoordinatorProtocol conformance

    public var activeWorkoutId: UUID? {
        session?.id
    }

    /// Entries the user works through, in session order. Removed entries are hidden.
    public var entries: [SessionEntry] {
        (session?.entries ?? []).filter { $0.status != .removed }
    }

    public var currentEntry: SessionEntry? {
        let list = entries
        guard list.indices.contains(currentExerciseIndex) else { return nil }
        return list[currentExerciseIndex]
    }

    /// Expone el estado del timer de descanso para que las Views lo puedan leer directamente.
    public var timerState: RestTimerState? {
        timerService.state
    }

    /// The manual set `id` of the session in progress.
    func manualSet(_ id: UUID) -> ExerciseSet? {
        entries.lazy.flatMap(\.manualSets).first { $0.id == id }
    }
}
