import Foundation
import SwiftData

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

// MARK: - WorkoutSummaryBuilder

/// Pure value-type builder. No SwiftUI dependency.
/// Input: a `Workout` with its `workoutExercises` and `exerciseSets` wired via
/// explicit-append (per swiftdata-relationships-bug, engram id 92).
///
/// PR detection: compares this workout's max weight per exercise against
/// the previous `PersonalRecord` for that exercise in SwiftData.
/// If no previous record exists, the workout's max is itself a new PR.
public enum WorkoutSummaryBuilder {
    public static func build(from workout: Workout, context: ModelContext) -> WorkoutSummary {
        let exercises = workout.workoutExercises.sorted { $0.orderIndex < $1.orderIndex }

        // Resolve exercise names from SwiftData
        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let exerciseMap = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })

        // Resolve previous PRs
        let allPRs = (try? context.fetch(FetchDescriptor<PersonalRecord>())) ?? []
        let prevPRMap: [UUID: Double] = allPRs.reduce(into: [:]) { dict, pr in
            guard pr.recordType == .maxWeight else { return }
            dict[pr.exerciseId] = max(dict[pr.exerciseId] ?? 0, pr.value)
        }

        // Build exercise rows + detect PRs + compute volume
        var totalVolume: Double = 0
        var prRows: [WorkoutSummary.PRRow] = []
        var exerciseRows: [WorkoutSummary.ExerciseRow] = []

        for we in exercises {
            let exerciseName = exerciseMap[we.exerciseId]?.name ?? we.exerciseId.uuidString
            let workingSets = we.exerciseSets.filter { !$0.isWarmup }
            let setCount = we.exerciseSets.count

            let exerciseVolume = workingSets.reduce(0.0) { sum, s in
                sum + (s.weight ?? 0) * Double(s.reps ?? 0)
            }
            totalVolume += exerciseVolume

            exerciseRows.append(WorkoutSummary.ExerciseRow(
                id: we.id,
                exerciseName: exerciseName,
                setCount: setCount,
                totalVolumeKg: exerciseVolume
            ))

            // PR detection: max weight this workout for this exercise
            let maxWeight = workingSets.compactMap(\.weight).max() ?? 0
            guard maxWeight > 0 else { continue }

            let previousMax = prevPRMap[we.exerciseId] ?? 0
            if maxWeight > previousMax {
                prRows.append(WorkoutSummary.PRRow(
                    exerciseName: exerciseName,
                    newValue: maxWeight
                ))
            }
        }

        // Duration: prefer coordinator-stored durationSeconds, fall back to wall-clock
        let durationSeconds: Int = if let stored = workout.durationSeconds, stored > 0 {
            stored
        } else if let completedAt = workout.completedAt {
            Int(completedAt.timeIntervalSince(workout.startedAt))
        } else {
            Int(Date().timeIntervalSince(workout.startedAt))
        }

        return WorkoutSummary(
            workoutName: workout.name,
            durationSeconds: max(0, durationSeconds),
            totalVolumeKg: totalVolume,
            personalRecords: prRows,
            exerciseRows: exerciseRows
        )
    }
}
