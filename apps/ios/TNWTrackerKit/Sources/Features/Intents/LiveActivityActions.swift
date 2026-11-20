import Foundation

// The Live Activity's buttons, built from its attributes so every one carries
// the id of the workout it shows (#136 S3). The widget builds its buttons here.

extension ActiveWorkoutAttributes {
    public var skipRestIntent: SkipRestIntent {
        SkipRestIntent(workoutId: workoutId)
    }

    /// Pause, or resume when the Live Activity shows the workout paused.
    public func pauseIntent(isPaused: Bool) -> PauseWorkoutIntent {
        PauseWorkoutIntent(workoutId: workoutId, resumes: isPaused)
    }

    public var endWorkoutIntent: EndWorkoutIntent {
        EndWorkoutIntent(workoutId: workoutId)
    }
}
