import Foundation
import SwiftData
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - CoordinatorSpy

/// Test double for DrainCoordinatorProtocol.
/// Records dispatched method names in call order.
@MainActor
final class CoordinatorSpy: DrainCoordinatorProtocol {
    private(set) var calls: [String] = []
    private let _workoutId: UUID

    init(workoutId: UUID) {
        _workoutId = workoutId
    }

    var activeWorkoutId: UUID? {
        _workoutId
    }

    func skipTimer() async {
        calls.append("skip")
    }

    func pause() async throws {
        calls.append("pause")
    }

    func resume() async throws {
        calls.append("resume")
    }

    func finish() async throws {
        calls.append("end")
    }
}

// MARK: - DrainPendingIntentsTests

@Suite("DrainPendingIntentsTests", .serialized)
@MainActor
struct DrainPendingIntentsTests {
    let container: ModelContainer
    let workoutId: UUID

    init() throws {
        container = try ModelContainerFactory.makeContainer(inMemory: true)
        workoutId = UUID()
    }

    // MARK: - Helper

    private func makeContext() -> ModelContext {
        ModelContext(container)
    }

    private func insertEvent(
        context: ModelContext,
        workoutId: UUID,
        kind: String,
        consumed: Bool = false
    ) throws -> WorkoutIntentEvent {
        let event = WorkoutIntentEvent(workoutId: workoutId, kind: kind)
        context.insert(event)
        if consumed { event.consumedAt = Date() }
        try context.save()
        return event
    }

    // MARK: - Tests

    @Test("drainsAllUnconsumedEvents — nil consumedAt events dispatched and then marked")
    func drainsAllUnconsumedEvents() async throws {
        let context = makeContext()
        let spy = CoordinatorSpy(workoutId: workoutId)

        _ = try insertEvent(context: context, workoutId: workoutId, kind: "skip")
        _ = try insertEvent(context: context, workoutId: workoutId, kind: "pause")

        try await AppEnvironment.drainPendingIntents(
            context: context,
            coordinator: spy,
            coordinatorWorkoutId: workoutId
        )

        #expect(spy.calls.count == 2)
        #expect(spy.calls[0] == "skip")
        #expect(spy.calls[1] == "pause")

        let descriptor = FetchDescriptor<WorkoutIntentEvent>(
            predicate: #Predicate { $0.workoutId == workoutId }
        )
        let events = try context.fetch(descriptor)
        #expect(events.allSatisfy { $0.consumedAt != nil })
    }

    @Test("eventsAreOrderedByCreatedAt — FIFO dispatch order preserved")
    func eventsAreOrderedByCreatedAt() async throws {
        let context = makeContext()
        let spy = CoordinatorSpy(workoutId: workoutId)

        _ = try insertEvent(context: context, workoutId: workoutId, kind: "skip")
        _ = try insertEvent(context: context, workoutId: workoutId, kind: "resume")
        _ = try insertEvent(context: context, workoutId: workoutId, kind: "pause")

        try await AppEnvironment.drainPendingIntents(
            context: context,
            coordinator: spy,
            coordinatorWorkoutId: workoutId
        )

        #expect(spy.calls.count == 3)
        #expect(spy.calls[0] == "skip")
        #expect(spy.calls[1] == "resume")
        #expect(spy.calls[2] == "pause")
    }

    @Test("eventsForOtherWorkoutsAreSkipped — mismatched workoutId not dispatched")
    func eventsForOtherWorkoutsAreSkipped() async throws {
        let context = makeContext()
        let spy = CoordinatorSpy(workoutId: workoutId)

        let otherId = UUID()
        _ = try insertEvent(context: context, workoutId: otherId, kind: "skip")
        _ = try insertEvent(context: context, workoutId: workoutId, kind: "pause")

        try await AppEnvironment.drainPendingIntents(
            context: context,
            coordinator: spy,
            coordinatorWorkoutId: workoutId
        )

        #expect(spy.calls.count == 1)
        #expect(spy.calls[0] == "pause")

        let descriptor = FetchDescriptor<WorkoutIntentEvent>(
            predicate: #Predicate { $0.workoutId == otherId }
        )
        let notConsumed = try context.fetch(descriptor)
        #expect(notConsumed.allSatisfy { $0.consumedAt == nil })
    }

    @Test("consumedEventsAreSkippedOnRedrain — already-consumed events not dispatched again")
    func consumedEventsAreSkippedOnRedrain() async throws {
        let context = makeContext()

        _ = try insertEvent(context: context, workoutId: workoutId, kind: "skip")

        let spy1 = CoordinatorSpy(workoutId: workoutId)
        try await AppEnvironment.drainPendingIntents(
            context: context,
            coordinator: spy1,
            coordinatorWorkoutId: workoutId
        )
        #expect(spy1.calls.count == 1)

        // Second drain — event is already consumed
        let spy2 = CoordinatorSpy(workoutId: workoutId)
        try await AppEnvironment.drainPendingIntents(
            context: context,
            coordinator: spy2,
            coordinatorWorkoutId: workoutId
        )
        #expect(spy2.calls.isEmpty)
    }
}
