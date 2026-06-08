import Foundation

public enum Route: Hashable {
    case sessionDetail(sessionID: UUID)
    case exerciseDetail(exerciseID: UUID)
    case sessionHistory
    case workoutDetail(workoutID: UUID)
    case settings
}
