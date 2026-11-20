import Foundation
import os
import SwiftData

// MARK: - Protocol

/// Two-method protocol enabling test substitution without swizzling CFNotificationCenter.
public protocol IntentMailboxProtocol: Sendable {
    /// Persists a new WorkoutIntentEvent to the device's intent mailbox, shared with the app.
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

// MARK: - Delivery from the Live Activity intents

extension IntentMailboxProtocol {
    /// Writes a `kind` event for the workout `workoutId` and wakes the app,
    /// which drains it (`IntentInbox.drain`). An id that is not a workout id
    /// (an intent run without its parameter) writes nothing.
    func deliver(kind: String, workoutId: String) async throws {
        guard let id = UUID(uuidString: workoutId) else {
            intentLogger.error("\(kind, privacy: .public) intent without a workout id — ignored")
            return
        }
        intentLogger.info("\(kind, privacy: .public) intent for workout \(id, privacy: .private)")
        try await enqueue(workoutId: id, kind: kind)
        postIntentNotification()
    }
}

/// The mailbox an intent writes to: the injected one (tests), else the device's.
func resolveMailbox(_ injected: (any IntentMailboxProtocol)?) throws -> any IntentMailboxProtocol {
    if let injected { return injected }
    return try IntentMailbox(container: ModelContainerFactory.makeIntentMailboxContainer())
}

private let intentLogger = Logger(subsystem: "com.tnwtracker", category: "WorkoutIntent")
