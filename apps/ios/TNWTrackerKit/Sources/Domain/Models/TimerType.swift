import Foundation

public enum TimerType: String, Codable, CaseIterable, Sendable {
    case betweenSets = "between_sets"
    case betweenExercises = "between_exercises"
    case custom
}
