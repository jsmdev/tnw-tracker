import Foundation
import TNWTrackerKit

// The set table of the current exercise (fast-add-exercise S5): the rows still
// to do are ready from the last time, and a check logs one.

public extension ActiveWorkoutCoordinator {
    /// The rows still to do for `entry`, in order: the user's rows once changed,
    /// else the planned sets (`SetPlan`) after the working sets logged today.
    func pendingSets(for entry: SessionEntry) -> [SetValues] {
        if let rows = pendingRows[entry.exerciseId] {
            return rows
        }
        let fresh = entries.first { $0.exerciseId == entry.exerciseId } ?? entry
        let planned = SetPlan.planned(last: lastPerformance(for: entry.exerciseId), target: target(for: fresh))
        return SetPlan.pending(planned: planned, loggedCount: fresh.workingManualSets.count)
    }

    /// Changes the reps and weight of row `index`.
    func updatePendingSet(_ values: SetValues, at index: Int, of entry: SessionEntry) {
        var rows = pendingSets(for: entry)
        guard rows.indices.contains(index) else { return }
        rows[index] = values
        pendingRows[entry.exerciseId] = rows
    }

    /// «Añadir serie»: one more row, with the values of the row above it, or of
    /// the last working set logged when no row is left.
    func addPendingSet(to entry: SessionEntry) {
        var rows = pendingSets(for: entry)
        let fresh = entries.first { $0.exerciseId == entry.exerciseId } ?? entry
        rows.append(SetPlan.added(after: rows.last ?? fresh.workingManualSets.last?.values))
        pendingRows[entry.exerciseId] = rows
    }

    /// Takes row `index` out without logging it.
    func removePendingSet(at index: Int, of entry: SessionEntry) {
        var rows = pendingSets(for: entry)
        guard rows.indices.contains(index) else { return }
        rows.remove(at: index)
        pendingRows[entry.exerciseId] = rows
    }

    /// Logs row `index` of `entry` as a set, as `recordSet` does, and takes the
    /// row out once the set is saved: a set that fails to save keeps its row.
    /// `values` (from the full set sheet) replace the row's values; a warm-up
    /// keeps the row, as it is not one of the planned working sets. A row
    /// without reps logs nothing.
    /// 0 kg logs no weight.
    func logPendingSet(
        at index: Int,
        of entry: SessionEntry,
        values: SetValues? = nil,
        rir: Int? = nil,
        warmup: Bool = false
    ) async throws {
        var rows = pendingSets(for: entry)
        guard rows.indices.contains(index) else { return }
        let logged = values ?? rows[index]
        guard let reps = logged.reps, reps > 0 else { return }
        // Kept as they are while saving: once the set counts, the plan would
        // drop its first row instead of this one.
        pendingRows[entry.exerciseId] = rows
        if let current = entries.firstIndex(where: { $0.exerciseId == entry.exerciseId }) {
            currentExerciseIndex = current
        }
        let weight = logged.weight.flatMap { $0.kilograms > 0 ? $0 : nil }
        try await recordSet(reps: reps, weight: weight, rir: rir, warmup: warmup)
        // A set that fails to save throws above, and its row stays.
        guard !warmup else { return }
        rows.remove(at: index)
        pendingRows[entry.exerciseId] = rows
    }

    /// A working set taken back (undone or deleted) comes back as the first row.
    internal func putBackPendingSet(_ set: ExerciseSet, exerciseId: UUID) {
        guard !set.warmup, var rows = pendingRows[exerciseId] else { return }
        rows.insert(SetPlan.added(after: set.values), at: 0)
        pendingRows[exerciseId] = rows
    }
}
