import ActivityKit
import Foundation

public struct ActiveWorkoutAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var workoutName: String
        public var currentExerciseName: String?
        public var restSecondsRemaining: Int?
        public var completedSets: Int
        public var totalSets: Int
        /// Whether the workout is currently paused — drives pause/resume button toggle in Live Activity.
        public var isPaused: Bool

        public init(
            workoutName: String,
            currentExerciseName: String? = nil,
            restSecondsRemaining: Int? = nil,
            completedSets: Int,
            totalSets: Int,
            isPaused: Bool = false
        ) {
            self.workoutName = workoutName
            self.currentExerciseName = currentExerciseName
            self.restSecondsRemaining = restSecondsRemaining
            self.completedSets = completedSets
            self.totalSets = totalSets
            self.isPaused = isPaused
        }
    }

    public var workoutId: UUID
    public var startedAt: Date

    public init(workoutId: UUID, startedAt: Date) {
        self.workoutId = workoutId
        self.startedAt = startedAt
    }
}
