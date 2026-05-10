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

    @Test("Multiple intents call enqueue in invocation order")
    func multipleIntentsCallEnqueueInOrder() async throws {
        // Verifica el orden de invocación, NO el orden de persistencia del mailbox real.
        // Razón: el mailbox real llama a postIntentNotification() que postea la
        // Darwin notification global "com.tnwtracker.workout.intent". El host app
        // de tests tiene el observer activo (TnwTrackerApp.startIntentObserver),
        // que dispara drainIfActive en otro hilo y crashea el host bundle.
        // El ordering por createdAt es responsabilidad de IntentMailbox y se
        // testea por separado si hace falta — fuera del path de los Intents.
        let spy = IntentMailboxSpy()
        let intent1 = SkipRestIntent(workoutId: workoutId, mailbox: spy)
        let intent2 = PauseWorkoutIntent(workoutId: workoutId, mailbox: spy)

        _ = try await intent1.perform()
        _ = try await intent2.perform()

        #expect(spy.enqueueCalls.count == 2)
        #expect(spy.enqueueCalls[0].kind == "skip")
        #expect(spy.enqueueCalls[1].kind == "pause")
        #expect(spy.postNotificationCount == 2)
    }
}
