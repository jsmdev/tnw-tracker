import AppIntents
import Foundation

/// "Pausar" / "Reanudar" on the workout's Live Activity: pauses the workout, or
/// resumes it when `resumes` is set (the Live Activity shows it paused). A
/// `LiveActivityIntent`, so the system runs `perform()` in the app process (#136 S3).
public struct PauseWorkoutIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource {
        LocalizedStringResource("intent.pause-workout.title", defaultValue: "Pause Workout")
    }

    public static var description: IntentDescription {
        IntentDescription(LocalizedStringResource(
            "intent.pause-workout.description",
            defaultValue: "Pause the current workout"
        ))
    }

    /// Only the Live Activity runs it: it needs the id of the workout in progress.
    public static let isDiscoverable: Bool = false

    /// The workout in progress (`ActiveWorkoutAttributes.workoutId`).
    @Parameter(title: LocalizedStringResource("intent.workout-id.parameter", defaultValue: "Workout"))
    public var workoutId: String

    /// Resume instead of pause.
    @Parameter(
        title: LocalizedStringResource("intent.pause-workout.resumes-parameter", defaultValue: "Resume"),
        default: false
    )
    public var resumes: Bool

    /// Injected in tests; nil uses the device's intent mailbox.
    private let mailbox: (any IntentMailboxProtocol)?

    public init() {
        mailbox = nil
    }

    public init(workoutId: UUID, resumes: Bool = false) {
        mailbox = nil
        self.workoutId = workoutId.uuidString
        self.resumes = resumes
    }

    /// Test-injectable init.
    public init(workoutId: UUID, resumes: Bool = false, mailbox: any IntentMailboxProtocol) {
        self.mailbox = mailbox
        self.workoutId = workoutId.uuidString
        self.resumes = resumes
    }

    public func perform() async throws -> some IntentResult {
        try await resolveMailbox(mailbox).deliver(kind: resumes ? "resume" : "pause", workoutId: workoutId)
        return .result()
    }
}
