import Foundation
import Supabase
import SwiftData
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - RestTimerServiceTests

//
// Strict TDD — RED → GREEN for Task 11.1 (REQ-WIDGET-01: workoutName real in ContentState).
//
// Strategy:
// - RestTimerService depends on SupabaseClient (concrete type from SDK).
//   We create a dummy client pointing to a nonexistent URL.
//   All Supabase calls inside start() use `try?` — failures are silently swallowed.
// - LiveActivityController cannot run Live Activities in Simulator (ActivityKit gated),
//   so liveActivity.start() / update() are no-ops in the test environment.
// - We test only the observable surface: workoutName property + state.workoutId after start().

private func makeDummySupabase() -> SupabaseClient {
    guard let url = URL(string: "https://test.invalid") else {
        preconditionFailure("Invalid dummy Supabase URL")
    }
    return SupabaseClient(
        supabaseURL: url,
        supabaseKey: "test-key"
    )
}

@Suite("RestTimerService workoutName", .serialized)
@MainActor
struct RestTimerServiceTests {
    // MARK: - Tests

    /// REQ-WIDGET-01: start() must accept a workoutName parameter.
    /// Verifies the new workoutName param compiles + state.workoutId is set correctly.
    @Test("start() accepts workoutName and state carries correct workoutId")
    func startAcceptsWorkoutName() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let service = RestTimerService(
            supabase: makeDummySupabase(),
            modelContext: context,
            liveActivity: LiveActivityController()
        )

        let workoutId = UUID()
        let workoutName = "Push Day — Test"

        await service.start(
            workoutId: workoutId,
            workoutName: workoutName,
            type: .betweenSets,
            durationSeconds: 90
        )

        // State must be set and carry the correct workoutId
        let timerState = service.state
        #expect(timerState != nil)
        #expect(timerState?.workoutId == workoutId)

        // Cleanup: cancel tick via skip()
        await service.skip()
    }

    /// After start(), the exposed workoutName property matches what was passed.
    @Test("workoutName property reflects the value passed to start()")
    func workoutNameIsStored() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let service = RestTimerService(
            supabase: makeDummySupabase(),
            modelContext: context,
            liveActivity: LiveActivityController()
        )

        let name = "Legs Day"
        await service.start(
            workoutId: UUID(),
            workoutName: name,
            type: .betweenSets,
            durationSeconds: 60
        )

        #expect(service.workoutName == name)

        await service.skip()
    }

    /// After skip(), workoutName persists (stored on service, not cleared on skip).
    @Test("workoutName persists after skip()")
    func workoutNamePersistsAfterSkip() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let service = RestTimerService(
            supabase: makeDummySupabase(),
            modelContext: context,
            liveActivity: LiveActivityController()
        )

        let name = "Pull Day"
        await service.start(workoutId: UUID(), workoutName: name, type: .betweenSets, durationSeconds: 30)
        await service.skip()

        // workoutName reflects last started workout name
        #expect(service.workoutName == name)
        // state is cleared after skip
        #expect(service.state == nil)
    }
}
