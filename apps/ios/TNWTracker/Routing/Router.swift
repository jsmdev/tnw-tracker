import Foundation
import Observation
import SwiftUI

public struct ActiveWorkoutPresentation: Identifiable {
    public let id: UUID
}

public struct WorkoutSummaryPresentation: Identifiable {
    public let id: UUID
}

@Observable
@MainActor
public final class Router {
    public var path = NavigationPath()
    public var presentedActiveWorkout: ActiveWorkoutPresentation?
    public var presentedWorkoutSummary: WorkoutSummaryPresentation?

    public init() {}

    public func push(_ route: Route) {
        path.append(route)
    }

    public func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    public func popToRoot() {
        path = NavigationPath()
    }

    public func handle(deepLink url: URL) {
        guard let route = DeepLinkParser.route(from: url) else { return }
        push(route)
    }
}
