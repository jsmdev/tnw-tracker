import AppIntents
import Foundation

/// "Saltar" on the workout's Live Activity. A `LiveActivityIntent`, so the
/// system runs `perform()` in the app process (#136 S3).
public struct SkipRestIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource {
        LocalizedStringResource("intent.skip-rest.title", defaultValue: "Skip Rest")
    }

    public static var description: IntentDescription {
        IntentDescription(LocalizedStringResource(
            "intent.skip-rest.description",
            defaultValue: "Skip the rest timer and proceed to the next set"
        ))
    }

    /// Only the Live Activity runs it: it needs the id of the workout in progress.
    public static let isDiscoverable: Bool = false

    /// The workout in progress (`ActiveWorkoutAttributes.workoutId`). A parameter,
    /// so it survives the system re-creating the intent for the button.
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
        try await resolveMailbox(mailbox).deliver(kind: "skip", workoutId: workoutId)
        return .result()
    }
}
