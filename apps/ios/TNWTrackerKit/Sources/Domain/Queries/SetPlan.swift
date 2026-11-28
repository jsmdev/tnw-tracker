import Foundation

/// The rows the set table of an exercise starts with, so a set is logged with
/// one tap (fast-add-exercise S5). In order of preference:
/// 1. the counted sets of the last time that have reps, one row each;
/// 2. the routine's target: its sets, the minimum of its rep range, its weight;
/// 3. 3 rows of 15 reps and 0 kg.
///
/// Only reps and weight are planned: effort and warm-up are the user's call
/// for each set. A missing weight is planned as 0 kg, so the row shows a value.
public enum SetPlan {
    public static let defaultSetCount = 3
    public static let defaultReps = 15

    public static func planned(last: LastPerformance?, target: RoutineItem?) -> [SetValues] {
        let lastRows = (last?.sets ?? []).filter { $0.reps != nil }.map(row)
        if !lastRows.isEmpty {
            return lastRows
        }
        let count = max(target?.targetSets ?? defaultSetCount, 1)
        let values = SetValues(
            reps: target?.targetReps?.min ?? defaultReps,
            weight: target?.targetWeight ?? .kg(0)
        )
        return Array(repeating: values, count: count)
    }

    /// The planned rows still to do once `loggedCount` working sets are logged today.
    public static func pending(planned: [SetValues], loggedCount: Int) -> [SetValues] {
        Array(planned.dropFirst(max(loggedCount, 0)))
    }

    /// A row added with «Añadir serie»: the reps and weight of the row above it.
    public static func added(after previous: SetValues?) -> SetValues {
        previous.map(row) ?? SetValues(reps: defaultReps, weight: .kg(0))
    }

    private static func row(_ values: SetValues) -> SetValues {
        SetValues(reps: values.reps, weight: values.weight ?? .kg(0))
    }
}
