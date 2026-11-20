import Foundation
@testable import TNWTrackerKit

/// Records the Live Activity calls the coordinator makes, in order.
@MainActor
final class LiveActivitySpy: LiveActivityControlling {
    enum Call: Equatable {
        case start(workoutId: UUID, state: ActiveWorkoutAttributes.ContentState)
        case update(ActiveWorkoutAttributes.ContentState)
        case end
    }

    private(set) var calls: [Call] = []

    /// The state the Live Activity shows now: the last one started or updated.
    var shownState: ActiveWorkoutAttributes.ContentState? {
        for call in calls.reversed() {
            switch call {
            case let .start(_, state), let .update(state): return state
            case .end: return nil
            }
        }
        return nil
    }

    var endCount: Int {
        calls.filter { $0 == .end }.count
    }

    func start(workoutId: UUID, state: ActiveWorkoutAttributes.ContentState) {
        calls.append(.start(workoutId: workoutId, state: state))
    }

    func update(state: ActiveWorkoutAttributes.ContentState) {
        calls.append(.update(state))
    }

    func end() {
        calls.append(.end)
    }
}
