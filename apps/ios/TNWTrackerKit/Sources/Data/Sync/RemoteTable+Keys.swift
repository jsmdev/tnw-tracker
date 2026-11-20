import Foundation

// How the sync addresses the rows of each server table.

public extension RemoteTable {
    /// The column that identifies a row of the signed-in user: the second half
    /// of the pull cursor, and the column deletes filter on. `exercise_settings`
    /// has no `id`; its rows are one per exercise for their owner.
    var keyColumn: String {
        self == .exerciseSettings ? "exercise_id" : "id"
    }

    /// The unique key an upsert matches existing rows on.
    var conflictTarget: String {
        self == .exerciseSettings ? "user_id,exercise_id" : "id"
    }

    /// The column naming the parent of a child row the device keeps no id for:
    /// muscle groups follow their exercise, routine items their routine.
    var parentColumn: String? {
        switch self {
        case .exerciseMuscleGroups: "exercise_id"
        case .routineItems: "routine_id"
        default: nil
        }
    }
}
