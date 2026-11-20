import AppIntents
import Foundation

/// "Terminar" on the workout's Live Activity. A `LiveActivityIntent`, so the
/// system runs `perform()` in the app process (#136 S3).
public struct EndWorkoutIntent: LiveActivityIntent {
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

    /// The workout in progress (`ActiveWorkoutAttributes.workoutId`).
    @Parameter(title: LocalizedStringResource("intent.workout-id.parameter", defaultValue: "Workout"))
    public var workoutId: String

    /// Injected in tests; nil uses the device's intent mailbox.
    private let mailbox: (any IntentMailboxProtocol)?

    public init() {
        mailbox = nil
    }

    public init(workoutId: UUID) {
        mailbox = nil
        self.workoutId = workoutId.uuidString
    }

    /// Test-injectable init.
    public init(workoutId: UUID, mailbox: any IntentMailboxProtocol) {
        self.mailbox = mailbox
        self.workoutId = workoutId.uuidString
    }

    public func perform() async throws -> some IntentResult {
        try await resolveMailbox(mailbox).deliver(kind: "end", workoutId: workoutId)
        return .result()
    }
}
