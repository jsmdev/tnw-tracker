import AppIntents
import Foundation
import os

public struct EndWorkoutIntent: AppIntent {
    public static var title: LocalizedStringResource {
        LocalizedStringResource("intent.end-workout.title", defaultValue: "End Workout")
    }

    public static var description: IntentDescription {
        IntentDescription(LocalizedStringResource(
            "intent.end-workout.description",
            defaultValue: "End the current workout"
        ))
    }

    /// Destructive intent: must open the app before completing the action.
    /// Apple force-unlocks device before running destructive AppIntents.
    public static let openAppWhenRun: Bool = true

    /// Not discoverable via Siri suggestions — user must tap explicitly.
    public static let isDiscoverable: Bool = false

    private let logger = Logger(subsystem: "com.tnwtracker", category: "EndWorkoutIntent")

    private let mailbox: any IntentMailboxProtocol
    private let _workoutId: UUID

    public init() {
        _workoutId = UUID()
        mailbox = IntentMailbox(container: try! ModelContainerFactory.makeContainer())
    }

    public init(workoutId: UUID, mailbox: any IntentMailboxProtocol) {
        _workoutId = workoutId
        self.mailbox = mailbox
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        logger.info("EndWorkoutIntent.perform() workoutId: \(_workoutId, privacy: .private)")
        try await mailbox.enqueue(workoutId: _workoutId, kind: "end")
        mailbox.postIntentNotification()
        return .result()
    }
}
