import Foundation
import SwiftData

// MARK: - Protocol

/// Two-method protocol enabling test substitution without swizzling CFNotificationCenter.
public protocol IntentMailboxProtocol: Sendable {
    /// Persists a new WorkoutIntentEvent to the shared SwiftData container.
    func enqueue(workoutId: UUID, kind: String) async throws
    /// Posts a Darwin notification to wake the app process.
    func postIntentNotification()
}

// MARK: - Default implementation

/// Concrete actor that owns SwiftData container access and Darwin notification posting.
/// Swift 6 safe: actor serializes all enqueue calls; ModelContainer is Sendable.
public actor IntentMailbox: IntentMailboxProtocol {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public func enqueue(workoutId: UUID, kind: String) async throws {
        let context = ModelContext(container)
        let event = WorkoutIntentEvent(workoutId: workoutId, kind: kind)
        context.insert(event)
        try context.save()
    }

    public nonisolated func postIntentNotification() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName("com.tnwtracker.workout.intent" as CFString),
            nil,
            nil,
            true
        )
    }
}
