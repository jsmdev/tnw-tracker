@preconcurrency import ActivityKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.tnwtracker", category: "liveactivity")

/// Actor boundary for Live Activity updates.
///
/// Lives on the MainActor so `currentActivity` is always mutated on the
/// main thread (required by ActivityKit). Cross-actor callers — timer ticks,
/// future AppIntent handlers — use the `nonisolated` overloads that hop to
/// the MainActor internally via Task, serialising writes through the actor's
/// FIFO job queue.
@MainActor
public final class LiveActivityController {
    private var currentActivity: Activity<ActiveWorkoutAttributes>?

    /// `nonisolated` so the init is callable from any context without
    /// requiring `await`. The instance itself is @MainActor-isolated once
    /// constructed; its properties are never accessed before the first method
    /// call reaches the main actor.
    public nonisolated init() {}

    // MARK: - MainActor face (callers already on MainActor)

    /// Requests a new Live Activity for the given workout.
    /// Only callable from @MainActor context (e.g. ActiveWorkoutCoordinator).
    public func start(workoutId: UUID, workoutName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities disabled on this device — skipping start")
            return
        }

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
            logger.info("Live Activity started for workout \(workoutId, privacy: .public)")
        } catch {
            logger.error("Live Activity request failed: \(error, privacy: .public)")
        }
    }

    // MARK: - nonisolated face (cross-actor callers — timer ticks, AppIntent)

    /// Updates the Live Activity with a pre-built ContentState.
    ///
    /// `nonisolated` so it can be called from any actor context, including
    /// `nonisolated` functions, timer ticks, and future AppIntent handlers.
    /// Hops to the MainActor internally; the hop is FIFO through the actor's
    /// job queue, preserving update order when called sequentially.
    public nonisolated func update(state: ActiveWorkoutAttributes.ContentState) {
        Task { @MainActor [self] in
            await _update(state)
        }
    }

    /// Ends the Live Activity.
    ///
    /// Same nonisolated + hop pattern as `update(state:)`.
    public nonisolated func end() {
        Task { @MainActor [self] in
            await _end()
        }
    }

    // MARK: - Private MainActor implementation

    private func _update(_ state: ActiveWorkoutAttributes.ContentState) async {
        guard currentActivity != nil else {
            logger.debug("update(state:) called but no active Live Activity — ignoring")
            return
        }
        await currentActivity?.update(.init(state: state, staleDate: nil))
        logger.debug("Live Activity updated: sets \(state.completedSets)/\(state.totalSets)")
    }

    private func _end() async {
        guard currentActivity != nil else {
            logger.debug("end() called but no active Live Activity — ignoring")
            return
        }
        await currentActivity?.end(nil, dismissalPolicy: .immediate)
        currentActivity = nil
        logger.info("Live Activity ended")
    }
}

// MARK: - LiveActivityRendering conformance

extension LiveActivityController: LiveActivityRendering {
    func start(
        attributes: ActiveWorkoutAttributes,
        contentState: ActiveWorkoutAttributes.ContentState
    ) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        currentActivity = try Activity.request(
            attributes: attributes,
            content: .init(state: contentState, staleDate: nil)
        )
        logger.info("Live Activity started via protocol: \(attributes.workoutId, privacy: .public)")
    }
}
