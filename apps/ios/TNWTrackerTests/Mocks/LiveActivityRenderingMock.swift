import Foundation
@testable import TNWTrackerKit

actor LiveActivityRenderingMock: LiveActivityRendering {
    private(set) var receivedCompletedSets: [Int] = []
    private(set) var startCalled = false
    private(set) var endCalled = false

    func start(
        attributes: ActiveWorkoutAttributes,
        contentState: ActiveWorkoutAttributes.ContentState
    ) async throws {
        startCalled = true
    }

    func update(state: ActiveWorkoutAttributes.ContentState) async {
        receivedCompletedSets.append(state.completedSets)
    }

    func end() async {
        endCalled = true
    }
}
