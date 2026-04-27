import Foundation

public enum WorkoutStatus: String, Codable, CaseIterable, Sendable {
    case active, paused, completed, cancelled
}
