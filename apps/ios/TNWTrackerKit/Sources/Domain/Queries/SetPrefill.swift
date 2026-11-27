import Foundation

/// What the user did the last time they trained an exercise: the counted sets
/// of the most recent completed session that has any for it.
public struct LastPerformance: Hashable, Sendable {
    public var completedAt: Date
    /// The counted sets (no warm-ups, no superseded sets), in the order they were done.
    public var sets: [SetValues]

    public init(completedAt: Date, sets: [SetValues]) {
        self.completedAt = completedAt
        self.sets = sets
    }
}

/// The values a new set starts with, so logging it can be a single tap.
/// In order of preference:
/// 1. the same working set of the last time;
/// 2. the previous working set of this session;
/// 3. the routine's target, with the minimum of its rep range;
/// 4. nothing.
///
/// Only reps and weight are prefilled: effort and warm-up are the user's call
/// for each set.
public enum SetPrefill {
    /// - Parameters:
    ///   - number: the working set number, starting at 1 (warm-ups are not counted).
    ///   - loggedToday: this session's working sets of the exercise, in order.
    public static func values(
        forSet number: Int,
        last: LastPerformance?,
        loggedToday: [SetValues],
        target: RoutineItem?
    ) -> SetValues {
        if let sets = last?.sets, sets.indices.contains(number - 1) {
            return repsAndWeight(of: sets[number - 1])
        }
        if let previous = loggedToday.last {
            return repsAndWeight(of: previous)
        }
        if let target {
            return SetValues(reps: target.targetReps?.min, weight: target.targetWeight)
        }
        return SetValues()
    }

    private static func repsAndWeight(of values: SetValues) -> SetValues {
        SetValues(reps: values.reps, weight: values.weight)
    }
}
