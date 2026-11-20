import Foundation

// MARK: - DrainCoordinatorProtocol

/// Minimal protocol for drain dispatch — testable without the full coordinator.
/// Only the methods and properties called by drainIfActive / drainPendingIntents are declared here.
@MainActor
public protocol DrainCoordinatorProtocol: AnyObject {
    /// The ID of the currently active workout, or nil if no workout is running.
    var activeWorkoutId: UUID? { get }
    func skipTimer() async
    func pause() async throws
    func resume() async throws
    func finish() async throws
    /// Leaves the workout in progress, with its timers stopped (a sign-out).
    func abandon() async
}
