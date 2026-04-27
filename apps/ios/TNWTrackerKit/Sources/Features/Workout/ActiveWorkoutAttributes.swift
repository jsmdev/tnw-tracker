import ActivityKit
import Foundation

public struct ActiveWorkoutAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var workoutName: String
        public var currentExerciseName: String?
        public var restSecondsRemaining: Int?
        public var completedSets: Int
        public var totalSets: Int

        public init(
            workoutName: String,
            currentExerciseName: String? = nil,
            restSecondsRemaining: Int? = nil,
            completedSets: Int,
            totalSets: Int
        ) {
            self.workoutName = workoutName
            self.currentExerciseName = currentExerciseName
            self.restSecondsRemaining = restSecondsRemaining
            self.completedSets = completedSets
            self.totalSets = totalSets
        }
    }

    public var workoutId: UUID
    public var startedAt: Date

    public init(workoutId: UUID, startedAt: Date) {
        self.workoutId = workoutId
        self.startedAt = startedAt
    }
}
