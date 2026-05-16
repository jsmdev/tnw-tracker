import AppIntents
import Foundation
import os

public struct SkipRestIntent: AppIntent {
    public static var title: LocalizedStringResource {
        LocalizedStringResource("intent.skip-rest.title", defaultValue: "Skip Rest")
    }

    public static var description: IntentDescription {
        IntentDescription(LocalizedStringResource(
            "intent.skip-rest.description",
            defaultValue: "Skip the rest timer and proceed to the next set"
        ))
    }

    private let logger = Logger(subsystem: "com.tnwtracker", category: "SkipRestIntent")

    // Injected mailbox — allows test substitution without swizzling.
    private let mailbox: any IntentMailboxProtocol
    private let _workoutId: UUID

    /// Default init for widget process invocation.
    public init() {
        _workoutId = UUID()
        do {
            let container = try ModelContainerFactory.makeContainer()
            mailbox = IntentMailbox(container: container)
        } catch {
            fatalError("SkipRestIntent.init failed to build ModelContainer: \(error)")
        }
    }

    /// Test-injectable init.
    public init(workoutId: UUID, mailbox: any IntentMailboxProtocol) {
        _workoutId = workoutId
        self.mailbox = mailbox
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        logger.info("SkipRestIntent.perform() workoutId: \(_workoutId, privacy: .private)")
        try await mailbox.enqueue(workoutId: _workoutId, kind: "skip")
        mailbox.postIntentNotification()
        return .result()
    }
}
