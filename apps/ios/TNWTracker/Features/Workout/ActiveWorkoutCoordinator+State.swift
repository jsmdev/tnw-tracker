import Foundation
import TNWTrackerKit

// Read-only views of the coordinator state.

public extension ActiveWorkoutCoordinator {
    /// What `finish()` did with the session.
    enum FinishOutcome: Equatable {
        /// Completed and saved; the summary shows it.
        case saved(UUID)
        /// Deleted: it had no working sets (T6, D7).
        case discarded
    }

    /// Whether the session in progress has a working set (T6, D-T6a). Without
    /// one, "Terminar" asks first and `finish()` discards the session.
    var hasWorkingSets: Bool {
        guard let current = session else { return false }
        return ((try? sessions.session(id: current.id)) ?? current).hasWorkingSets
    }

    // MARK: - DrainCoordinatorProtocol conformance

    var activeWorkoutId: UUID? {
        session?.id
    }

    /// Entries the user works through, in session order. Removed entries are hidden.
    var entries: [SessionEntry] {
        savedEntries
    }

    var currentEntry: SessionEntry? {
        let list = entries
        guard list.indices.contains(currentExerciseIndex) else { return nil }
        return list[currentExerciseIndex]
    }

    /// Expone el estado del timer de descanso para que las Views lo puedan leer directamente.
    var timerState: RestTimerState? {
        timerService.state
    }

    /// Primer ejercicio cuyas series de trabajo (sin calentamiento) no alcanzan su objetivo; si todos
    /// están completos (o no hay objetivo), el último ejercicio.
    internal func firstIncompleteExerciseIndex() -> Int {
        for (idx, entry) in entries.enumerated() {
            guard let target = target(for: entry)?.targetSets else { continue }
            if entry.workingManualSets.count < target {
                return idx
            }
        }
        return max(0, entries.count - 1)
    }

    /// Where a session left in progress is resumed: an exercise the user added
    /// after the exercise of the most recent manual set and has not started yet
    /// (the last one), as it was the one on screen (fast-add-exercise S4); else
    /// the exercise of the most recent manual set, so planned exercises the user
    /// skipped are not shown again; without any set, the first exercise still
    /// short of its target.
    internal func resumeExerciseIndex() -> Int {
        let latest = entries.enumerated()
            .compactMap { index, entry in
                entry.manualSets.compactMap(\.completedAt).max().map { (index, $0) }
            }
            .max { $0.1 < $1.1 }
        let after = latest?.0 ?? -1
        // Added exercises go at the end, after the routine's, and are not in its targets.
        let added = entries.indices.last { index in
            index > after && entries[index].sets.isEmpty && target(for: entries[index]) == nil
        }
        return added ?? latest?.0 ?? firstIncompleteExerciseIndex()
    }

    internal func target(for entry: SessionEntry) -> RoutineItem? {
        targets[entry.exerciseId] ?? entry.replacedExerciseId.flatMap { targets[$0] }
    }

    /// The manual set `id` of the session in progress.
    internal func manualSet(_ id: UUID) -> ExerciseSet? {
        entries.lazy.flatMap(\.manualSets).first { $0.id == id }
    }
}
