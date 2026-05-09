import Foundation

/// Internal protocol that abstracts the Live Activity rendering boundary.
/// Enables testing of ordering and isolation guarantees without ActivityKit
/// entitlements or hardware. Conforms to Sendable so callers from any
/// actor context — including future AppIntent handlers — can hold a reference.
protocol LiveActivityRendering: Sendable {
    func start(
        attributes: ActiveWorkoutAttributes,
        contentState: ActiveWorkoutAttributes.ContentState
    ) async throws

    func update(state: ActiveWorkoutAttributes.ContentState) async

    func end() async
}
