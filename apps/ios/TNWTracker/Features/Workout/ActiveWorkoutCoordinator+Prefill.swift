import Foundation
import TNWTrackerKit

// "La última vez" and the values a new set starts with (fast-add-exercise S3).

public extension ActiveWorkoutCoordinator {
    /// What the user did the last time they trained the exercise, or nil.
    func lastPerformance(for exerciseId: UUID) -> LastPerformance? {
        guard let sessionId = session?.id else { return nil }
        if let cache = lastPerformances, cache.sessionId == sessionId, let cached = cache.byExercise[exerciseId] {
            return cached
        }
        let found = (try? sessions.lastPerformance(exerciseId: exerciseId)) ?? nil
        var byExercise = lastPerformances?.sessionId == sessionId ? lastPerformances?.byExercise ?? [:] : [:]
        byExercise[exerciseId] = .some(found)
        lastPerformances = (sessionId, byExercise)
        return found
    }

    /// The reps and weight the next working set of `entry` starts with (`SetPrefill`).
    func prefill(for entry: SessionEntry) -> SetValues {
        let today = entry.workingManualSets.map(\.values)
        return SetPrefill.values(
            forSet: today.count + 1,
            last: lastPerformance(for: entry.exerciseId),
            loggedToday: today,
            target: target(for: entry)
        )
    }
}
