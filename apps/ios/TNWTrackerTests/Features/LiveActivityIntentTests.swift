import Foundation
import SwiftData
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - Live Activity buttons (#136 S3)

/// Writes to a real intent mailbox but does not post the Darwin notification:
/// the test host observes it and would drain on another thread.
final class SilentMailbox: IntentMailboxProtocol, @unchecked Sendable {
    private let mailbox: IntentMailbox
    private(set) var postCount = 0

    init(container: ModelContainer) {
        mailbox = IntentMailbox(container: container)
    }

    func enqueue(workoutId: UUID, kind: String) async throws {
        try await mailbox.enqueue(workoutId: workoutId, kind: kind)
    }

    func postIntentNotification() {
        postCount += 1
    }
}

/// The Live Activity's buttons carry the id of the workout it shows, so the app
/// drains their events into the session in progress: skip, pause / resume and end.
@Suite("Live Activity buttons", .serialized)
@MainActor
struct LiveActivityIntentTests {
    let fx: TrainingFixtures
    let mailboxContainer: ModelContainer
    let spy = LiveActivitySpy()

    init() throws {
        fx = try TrainingFixtures()
        mailboxContainer = try ModelContainerFactory.makeIntentMailboxContainer(inMemory: true)
    }

    private func start() async throws -> (ActiveWorkoutCoordinator, ActiveWorkoutAttributes) {
        let coordinator = ActiveWorkoutCoordinator(
            sessions: fx.sessions,
            routines: fx.routines,
            exerciseSettings: fx.store.exerciseSettings,
            changeExerciseRest: { 120 },
            requestSync: {},
            timerService: RestTimerService(now: { TrainingFixtures.t0 }),
            liveActivity: spy,
            now: { TrainingFixtures.t0 }
        )
        try await coordinator.start(routineId: try fx.makeRoutine().id)
        let workoutId = try #require(coordinator.activeWorkoutId)
        return (coordinator, ActiveWorkoutAttributes(workoutId: workoutId, startedAt: TrainingFixtures.t0))
    }

    /// The button's intent as the system runs it: its parameters, on the mailbox.
    private func tap(_ intent: some WorkoutIntentRunnable, mailbox: SilentMailbox) async throws {
        try await intent.run(on: mailbox)
    }

    private func drain(into coordinator: ActiveWorkoutCoordinator) async throws {
        try await AppEnvironment.drainPendingIntents(
            inbox: IntentInbox(container: mailboxContainer),
            coordinator: coordinator,
            coordinatorWorkoutId: try #require(coordinator.activeWorkoutId)
        )
    }

    @Test("S3 every button of the Live Activity carries the id of the workout it shows")
    func buttonsCarryWorkoutId() {
        let workoutId = UUID()
        let attributes = ActiveWorkoutAttributes(workoutId: workoutId, startedAt: TrainingFixtures.t0)

        #expect(attributes.skipRestIntent.workoutId == workoutId.uuidString)
        #expect(attributes.pauseIntent(isPaused: false).workoutId == workoutId.uuidString)
        #expect(attributes.pauseIntent(isPaused: true).workoutId == workoutId.uuidString)
        #expect(attributes.endWorkoutIntent.workoutId == workoutId.uuidString)
    }

    @Test("S3 the pause button pauses an active workout and resumes a paused one")
    func pauseToggles() {
        let attributes = ActiveWorkoutAttributes(workoutId: UUID(), startedAt: TrainingFixtures.t0)

        #expect(attributes.pauseIntent(isPaused: false).resumes == false)
        #expect(attributes.pauseIntent(isPaused: true).resumes == true)
    }

    @Test("S3 skip on the Live Activity ends the rest of the session in progress")
    func skipReachesSession() async throws {
        let (coordinator, attributes) = try await start()
        let mailbox = SilentMailbox(container: mailboxContainer)
        try await coordinator.recordSet(reps: 8, weight: .kg(20), rir: 2)
        #expect(coordinator.phase == .restingBetweenSets)

        try await tap(attributes.skipRestIntent, mailbox: mailbox)
        try await drain(into: coordinator)

        #expect(mailbox.postCount == 1)
        #expect(coordinator.phase == .active)
        #expect(coordinator.timerState == nil)
        #expect(spy.shownState?.restSecondsRemaining == nil)
        #expect(spy.endCount == 0)
    }

    @Test("S3 pause then resume on the Live Activity reach the session, and the Live Activity follows")
    func pauseResumeReachSession() async throws {
        let (coordinator, attributes) = try await start()
        let mailbox = SilentMailbox(container: mailboxContainer)

        try await tap(attributes.pauseIntent(isPaused: false), mailbox: mailbox)
        try await drain(into: coordinator)
        #expect(coordinator.phase == .paused)
        #expect(spy.shownState?.isPaused == true)

        try await tap(attributes.pauseIntent(isPaused: spy.shownState?.isPaused ?? false), mailbox: mailbox)
        try await drain(into: coordinator)
        #expect(coordinator.phase == .active)
        #expect(spy.shownState?.isPaused == false)
        #expect(mailbox.postCount == 2)
    }

    @Test("S3 end on the Live Activity finishes the session and ends the Live Activity")
    func endReachesSession() async throws {
        let (coordinator, attributes) = try await start()
        let mailbox = SilentMailbox(container: mailboxContainer)
        try await coordinator.recordSet(reps: 8, weight: .kg(20), rir: 2)

        try await tap(attributes.endWorkoutIntent, mailbox: mailbox)
        try await drain(into: coordinator)

        #expect(coordinator.phase == .idle)
        #expect(coordinator.lastFinishOutcome == .saved(attributes.workoutId))
        #expect(spy.calls.last == .end)
    }

    @Test("S3 a button of another workout does nothing to the session in progress")
    func otherWorkoutIgnored() async throws {
        let (coordinator, _) = try await start()
        let mailbox = SilentMailbox(container: mailboxContainer)
        let stale = ActiveWorkoutAttributes(workoutId: UUID(), startedAt: TrainingFixtures.t0)

        try await tap(stale.pauseIntent(isPaused: false), mailbox: mailbox)
        try await drain(into: coordinator)

        #expect(coordinator.phase == .active)
    }
}

// MARK: - Running an intent on a test mailbox

/// The intents' `perform()` with the mailbox the test chooses, through the
/// intents' own test init: same parameters, same event.
protocol WorkoutIntentRunnable: Sendable {
    func run(on mailbox: any IntentMailboxProtocol) async throws
}

extension SkipRestIntent: WorkoutIntentRunnable {
    func run(on mailbox: any IntentMailboxProtocol) async throws {
        let id = try #require(UUID(uuidString: workoutId))
        _ = try await SkipRestIntent(workoutId: id, mailbox: mailbox).perform()
    }
}

extension PauseWorkoutIntent: WorkoutIntentRunnable {
    func run(on mailbox: any IntentMailboxProtocol) async throws {
        let id = try #require(UUID(uuidString: workoutId))
        _ = try await PauseWorkoutIntent(workoutId: id, resumes: resumes, mailbox: mailbox).perform()
    }
}

extension EndWorkoutIntent: WorkoutIntentRunnable {
    func run(on mailbox: any IntentMailboxProtocol) async throws {
        let id = try #require(UUID(uuidString: workoutId))
        _ = try await EndWorkoutIntent(workoutId: id, mailbox: mailbox).perform()
    }
}
