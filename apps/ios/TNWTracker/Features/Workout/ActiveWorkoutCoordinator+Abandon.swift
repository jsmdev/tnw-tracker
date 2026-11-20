import Foundation

extension ActiveWorkoutCoordinator {
    /// Leaves the workout where it is, as quitting the app does (the account
    /// signed out, S10): its timers and Live Activity end, nothing is finished,
    /// discarded or written, and the session stays in progress in its account's
    /// store. Starting a workout on that account again resumes it.
    public func abandon() async {
        elapsedTask?.cancel()
        undoTask?.cancel()
        await timerService.stop()
        liveActivity.end()
        clearWorkout()
    }
}
