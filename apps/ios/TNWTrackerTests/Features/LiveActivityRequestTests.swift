import ActivityKit
import Foundation
import Testing
@testable import TNWTrackerKit

/// T11: unit tests must not leave Live Activities behind. A Live Activity outlives
/// the test host, and the system relaunches the app in the background for it,
/// without `--uitesting`, which races the first launch of the next UI test run.
@Suite("Live Activity requests", .serialized)
@MainActor
struct LiveActivityRequestTests {
    @Test("T11 a controller made with requestsActivities: false never starts a Live Activity")
    func disabledControllerStartsNothing() async {
        await LiveActivityController.endAll()
        let controller = LiveActivityController(requestsActivities: false)

        controller.start(
            workoutId: UUID(),
            state: .init(workoutName: "Full Body A", completedSets: 0, totalSets: 5)
        )

        #expect(Activity<ActiveWorkoutAttributes>.activities.isEmpty)
        await LiveActivityController.endAll()
    }
}
