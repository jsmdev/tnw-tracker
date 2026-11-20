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

    /// Entries the user works through, in session order, then the exercise picked
    /// from the list that has no set yet. Removed entries are hidden.
    public var entries: [SessionEntry] {
        savedEntries + (pickedEntry.map { [$0] } ?? [])
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

    /// Primer ejercicio cuyas series de trabajo (sin calentamiento) no alcanzan su objetivo; si todos
    /// están completos (o no hay objetivo), el último ejercicio.
    func firstIncompleteExerciseIndex() -> Int {
        for (idx, entry) in entries.enumerated() {
            guard let target = target(for: entry)?.targetSets else { continue }
            if entry.workingManualSets.count < target { return idx }
        }
        return max(0, entries.count - 1)
    }

    /// Where a session left in progress is resumed: the exercise of its most
    /// recent manual set, so planned exercises the user skipped are not shown
    /// again. Without any set, the first exercise still short of its target.
    func resumeExerciseIndex() -> Int {
        let latest = entries.enumerated()
            .compactMap { index, entry in
                entry.manualSets.compactMap(\.completedAt).max().map { (index, $0) }
            }
            .max { $0.1 < $1.1 }
        return latest?.0 ?? firstIncompleteExerciseIndex()
    }

    func target(for entry: SessionEntry) -> RoutineItem? {
        targets[entry.exerciseId] ?? entry.replacedExerciseId.flatMap { targets[$0] }
    }

    /// The manual set `id` of the session in progress.
    func manualSet(_ id: UUID) -> ExerciseSet? {
        entries.lazy.flatMap(\.manualSets).first { $0.id == id }
    }
}
