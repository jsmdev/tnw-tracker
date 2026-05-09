import Foundation
import Testing
@testable import TNWTrackerKit

@Suite("LiveActivityController boundaries")
struct LiveActivityControllerTests {
    // MARK: - Ordering test (REQ-LIVEACTIVITY-03)

    @Test("10 updates rápidos respetan orden FIFO")
    func updatesAreOrdered() async {
        let mock = LiveActivityRenderingMock()

        // Disparar 10 updates en orden desde un context estructurado
        for i in 0 ..< 10 {
            let state = makeState(completedSets: i)
            await mock.update(state: state)
        }

        let received = await mock.receivedCompletedSets
        #expect(received.count == 10)
        #expect(received == Array(0 ..< 10))
    }

    // MARK: - Caller nonisolated test (REQ-LIVEACTIVITY-02, REQ-LIVEACTIVITY-04)

    @Test("update(state:) es invocable desde contexto nonisolated sin warnings")
    func nonisolatedCallerCompiles() async {
        let mock = LiveActivityRenderingMock()
        await callFromNonisolated(rendering: mock)
        let count = await mock.receivedCompletedSets.count
        #expect(count == 1)
    }

    // MARK: - Helpers

    private nonisolated func callFromNonisolated(rendering: any LiveActivityRendering) async {
        await rendering.update(state: makeState(completedSets: 99))
    }

    private nonisolated func makeState(completedSets: Int) -> ActiveWorkoutAttributes.ContentState {
        ActiveWorkoutAttributes.ContentState(
            workoutName: "Test Workout",
            currentExerciseName: nil,
            restSecondsRemaining: nil,
            completedSets: completedSets,
            totalSets: 10
        )
    }
}
