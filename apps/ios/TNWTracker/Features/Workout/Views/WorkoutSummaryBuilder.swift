import Foundation
import TNWTrackerKit

// MARK: - WorkoutSummary

/// Immutable snapshot of a completed workout, built by `WorkoutSummaryBuilder`.
/// Sendable because it contains only value types.
public struct WorkoutSummary: Sendable {
    public let workoutName: String
    public let durationSeconds: Int
    public let totalVolumeKg: Double
    public let personalRecords: [PRRow]
    public let exerciseRows: [ExerciseRow]

    // MARK: - Nested value types

    public struct PRRow: Sendable {
        public let exerciseName: String
        public let newValue: Double
    }

    public struct ExerciseRow: Sendable, Identifiable {
        public let id: UUID
        public let exerciseName: String
        public let setCount: Int
        public let totalVolumeKg: Double
    }
}

// MARK: - Workou// MARK: - WorkoutSummaryBuilder

/// Pure value-type builder. No SwiftUI or persistence dependency.
///
/// Only counted sets are read: sets of `done` entries that are neither superseded nor warm-up sets.
/// PR detection: compares this session's max weight per exercise against the
/// best weight of the sessions completed before it (`previousBests`, in kg).
/// If no previous best exists, the session's max is itself a new PR.
public enum WorkoutSummaryBuilder {
    public static func build(
        from session: TrainingSession,
        exerciseNames: [UUID: String],
        previousBests: [UUID: Double],
        now: Date = Date()
    ) -> WorkoutSummary {
        var totalVolume: Double = 0
        var prRows: [WorkoutSummary.PRRow] = []
        var exerciseRows: [WorkoutSummary.ExerciseRow] = []

        for entry in session.entries where entry.status == .done {
            let exerciseName = exerciseNames[entry.exerciseId] ?? entry.exerciseId.uuidString
            let counted = entry.countedSets
            let exerciseVolume = entry.volumeKg
            totalVolume += exerciseVolume

            exerciseRows.append(WorkoutSummary.ExerciseRow(
                id: entry.id,
                exerciseName: exerciseName,
                setCount: counted.count,
                totalVolumeKg: exerciseVolume
            ))

            let maxWeight = counted.compactMap { $0.values.weight?.kilograms }.max() ?? 0
            guard maxWeight > 0 else { continue }
            if maxWeight > previousBests[entry.exerciseId] ?? 0 {
                prRows.append(WorkoutSummary.PRRow(exerciseName: exerciseName, newValue: maxWeight))
            }
        }

        // Duration: prefer the stored training time, fall back to wall-clock.
        let durationSeconds: Int = if let stored = session.durationSeconds, stored > 0 {
            stored
        } else if let startedAt = session.startedAt {
            Int((session.completedAt ?? now).timeIntervalSince(startedAt))
        } else {
            0
        }

        return WorkoutSummary(
            workoutName: session.name ?? "",
            durationSeconds: max(0, durationSeconds),
            totalVolumeKg: totalVolume,
            personalRecords: prRows,
            exerciseRows: exerciseRows
        )
    }
}
