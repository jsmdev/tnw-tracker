import Foundation

public enum Route: Hashable {
    case sessionDetail(sessionID: UUID)
    case exerciseDetail(exerciseID: UUID)
    /// A finished workout of the history (#174 S7).
    case workoutDetail(sessionID: UUID)
    case sessionHistory
    case settings
}
