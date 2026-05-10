import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

// MARK: - IntentMailboxSpy

// Test double conforming to IntentMailboxProtocol.
// Records enqueue calls + postIntentNotification call count.

final class IntentMailboxSpy: IntentMailboxProtocol, @unchecked Sendable {
    struct EnqueueCall: Equatable {
        let workoutId: UUID
        let kind: String
    }

    private(set) var enqueueCalls: [EnqueueCall] = []
    private(set) var postNotificationCount: Int = 0

    func enqueue(workoutId: UUID, kind: String) async throws {
        enqueueCalls.append(EnqueueCall(workoutId: workoutId, kind: kind))
    }

    func postIntentNotification() {
        postNotificationCount += 1
    }
}

// MARK: - WorkoutIntentTests

@Suite("WorkoutIntentTests", .serialized)
struct WorkoutIntentTests {
    let container: ModelContainer
    let workoutId: UUID

    init() throws {
        container = try ModelContainerFactory.makeContainer(inMemory: true)
        workoutId = UUID()
    }

    // MARK: - SkipRestIntent

    @Test("SkipRestIntent.perform() enqueues skip event and posts notification")
    func skipRestIntentEnqueuesSkipEvent() async throws {
        let spy = IntentMailboxSpy()
        let intent = SkipRestIntent(workoutId: workoutId, mailbox: spy)

        _ = try await intent.perform()

        #expect(spy.enqueueCalls.count == 1)
        let call = try #require(spy.enqueueCalls.first)
        #expect(call.workoutId == workoutId)
        #expect(call.kind == "skip")
        #expect(spy.postNotificationCount == 1)
    }

    // MARK: - PauseWorkoutIntent

    @Test("PauseWorkoutIntent.perform() enqueues pause event and posts notification")
    func pauseWorkoutIntentEnqueuesPauseEvent() async throws {
        let spy = IntentMailboxSpy()
        let intent = PauseWorkoutIntent(workoutId: workoutId, mailbox: spy)

        _ = try await intent.perform()

        #expect(spy.enqueueCalls.count == 1)
        let call = try #require(spy.enqueueCalls.first)
        #expect(call.workoutId == workoutId)
        #expect(call.kind == "pause")
        #expect(spy.postNotificationCount == 1)
    }

    // MARK: - EndWorkoutIntent

    @Test("EndWorkoutIntent.perform() enqueues end event and posts notification")
    func endWorkoutIntentEnqueuesEndEvent() async throws {
        let spy = IntentMailboxSpy()
        let intent = EndWorkoutIntent(workoutId: workoutId, mailbox: spy)

        _ = try await intent.perform()

        #expect(spy.enqueueCalls.count == 1)
        let call = try #require(spy.enqueueCalls.first)
        #expect(call.workoutId == workoutId)
        #expect(call.kind == "end")
        #expect(spy.postNotificationCount == 1)
    }

    // MARK: - Ordering

    @Test("Multiple intents enqueue in correct createdAt order")
    func multipleIntentsEnqueueOrderedByCreatedAt() async throws {
        // Use real mailbox with in-memory container to verify createdAt ordering
        let mailbox = IntentMailbox(container: container)

        let intent1 = SkipRestIntent(workoutId: workoutId, mailbox: mailbox)
        let intent2 = PauseWorkoutIntent(workoutId: workoutId, mailbox: mailbox)

        _ = try await intent1.perform()
        _ = try await intent2.perform()

        let context = ModelContext(container)
        var descriptor = FetchDescriptor<WorkoutIntentEvent>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.predicate = #Predicate { $0.workoutId == workoutId }
        let events = try context.fetch(descriptor)

        #expect(events.count == 2)
        #expect(events[0].kind == "skip")
        #expect(events[1].kind == "pause")
        #expect(events[0].createdAt <= events[1].createdAt)
    }
}
