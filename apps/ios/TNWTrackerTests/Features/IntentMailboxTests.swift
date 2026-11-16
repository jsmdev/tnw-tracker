import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

// MARK: - IntentMailboxTests

//
// Tests del actor IntentMailbox contra un ModelContainer in-memory real.
// Cubre el contrato de enqueue (persistencia, fields correctos, no deduplicación).
// postIntentNotification no se testea — es una Darwin notification cross-process
// no observable desde el bundle de tests.

@Suite("IntentMailbox actor", .serialized)
struct IntentMailboxTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerFactory.makeContainer(inMemory: true)
    }

    @Test("enqueue persists event with workoutId, kind, and unconsumed marker")
    func enqueuePersistsEvent() async throws {
        let mailbox = IntentMailbox(container: container)
        let workoutId = UUID()

        try await mailbox.enqueue(workoutId: workoutId, kind: "skip")

        let context = ModelContext(container)
        let events = try context.fetch(FetchDescriptor<WorkoutIntentEvent>())
        let event = try #require(events.first)

        #expect(events.count == 1)
        #expect(event.workoutId == workoutId)
        #expect(event.kind == "skip")
        #expect(event.consumedAt == nil)
    }

    @Test("multiple enqueues with same payload create distinct events")
    func multipleEnqueuesAreDistinct() async throws {
        let mailbox = IntentMailbox(container: container)
        let workoutId = UUID()

        try await mailbox.enqueue(workoutId: workoutId, kind: "skip")
        try await mailbox.enqueue(workoutId: workoutId, kind: "skip")

        let context = ModelContext(container)
        let events = try context.fetch(FetchDescriptor<WorkoutIntentEvent>())

        #expect(events.count == 2)
        #expect(events[0].id != events[1].id)
    }
}
