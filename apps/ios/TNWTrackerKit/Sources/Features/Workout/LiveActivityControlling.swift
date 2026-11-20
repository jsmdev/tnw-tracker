import Foundation

/// The workout's Live Activity as the coordinator drives it: started when the
/// session starts or is resumed, updated with the session's state, ended only
/// when the session is finished or abandoned. `LiveActivityController` is the
/// ActivityKit implementation; tests record the calls.
@MainActor
public protocol LiveActivityControlling: AnyObject {
    /// Shows the Live Activity of `workoutId` with its first state.
    func start(workoutId: UUID, state: ActiveWorkoutAttributes.ContentState)
    /// Replaces the state the Live Activity shows.
    func update(state: ActiveWorkoutAttributes.ContentState)
    /// Removes the Live Activity.
    func end()
}
