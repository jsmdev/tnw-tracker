import AppIntents
import Foundation
import os

public struct PauseWorkoutIntent: AppIntent {
    public static var title: LocalizedStringResource {
        LocalizedStringResource("intent.pause-workout.title", defaultValue: "Pause Workout")
    }

    public static var description: IntentDescription {
        IntentDescription(LocalizedStringResource(
            "intent.pause-workout.description",
            defaultValue: "Pause the current workout"
        ))
    }

    private let logger = Logger(subsystem: "com.tnwtracker", category: "PauseWorkoutIntent")

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
        logger.info("PauseWorkoutIntent.perform() workoutId: \(_workoutId, privacy: .private)")
        try await mailbox.enqueue(workoutId: _workoutId, kind: "pause")
        mailbox.postIntentNotification()
        return .result()
    }
}
