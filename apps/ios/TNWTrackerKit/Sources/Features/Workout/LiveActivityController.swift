import ActivityKit
import Foundation

public final class LiveActivityController {
    private var currentActivity: Activity<ActiveWorkoutAttributes>?

    public init() {}

    public func start(workoutId: UUID, workoutName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = ActiveWorkoutAttributes(workoutId: workoutId, startedAt: Date())
        let contentState = ActiveWorkoutAttributes.ContentState(
            workoutName: workoutName,
            currentExerciseName: nil,
            restSecondsRemaining: nil,
            completedSets: 0,
            totalSets: 0
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil)
            )
        } catch {
            // Live Activity no disponible en este dispositivo
        }
    }

    public func update(
        exerciseName: String?,
        restSecondsRemaining: Int?,
        completedSets: Int,
        totalSets: Int
    ) async {
        let activity = currentActivity
        let state = ActiveWorkoutAttributes.ContentState(
            workoutName: activity?.attributes.workoutId.uuidString ?? "",
            currentExerciseName: exerciseName,
            restSecondsRemaining: restSecondsRemaining,
            completedSets: completedSets,
            totalSets: totalSets
        )
        await activity?.update(.init(state: state, staleDate: nil))
    }

    public func end() async {
        let activity = currentActivity
        await activity?.end(nil, dismissalPolicy: .immediate)
        currentActivity = nil
    }
}
