import Foundation
import Observation
import SwiftUI

public struct ActiveWorkoutPresentation: Identifiable, Equatable {
    /// The routine to start from, or any id for a free session.
    public let id: UUID
    /// A free session: no routine, the user picks the exercises (#137 S5).
    public var isFree = false

    /// A free session, started without a routine.
    public static func free() -> ActiveWorkoutPresentation {
        ActiveWorkoutPresentation(id: UUID(), isFree: true)
    }
}

public struct WorkoutSummaryPresentation: Identifiable, Equatable {
    public let id: UUID
}

/// The app's tabs (#174), in tab bar order.
public enum AppTab: Hashable, CaseIterable, Sendable {
    case home, history, exercises
}

@Observable
@MainActor
public final class Router {
    public var selectedTab: AppTab = .home
    /// Each tab keeps its own stack, so switching tabs keeps where you were.
    public var homePath = NavigationPath()
    public var historyPath = NavigationPath()
    public var exercisesPath = NavigationPath()
    public var presentedActiveWorkout: ActiveWorkoutPresentation?
    public var presentedWorkoutSummary: WorkoutSummaryPresentation?

    public init() {}

    public func path(for tab: AppTab) -> NavigationPath {
        switch tab {
        case .home: homePath
        case .history: historyPath
        case .exercises: exercisesPath
        }
    }

    /// The selected tab's stack.
    public var path: NavigationPath {
        get { path(for: selectedTab) }
        set { setPath(newValue, for: selectedTab) }
    }

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
        guard let link = DeepLinkParser.parse(url) else { return }
        switch link {
        case let .route(route):
            selectedTab = route.tab
            push(route)
        case .openActiveWorkout:
            // ActiveWorkout requiere acceso al coordinator activo para conocer su
            // sessionID; el Router no lo tiene. RootView intercepta este caso vía
            // onOpenURL antes de delegar al router.
            break
        }
    }

    private func setPath(_ newValue: NavigationPath, for tab: AppTab) {
        switch tab {
        case .home: homePath = newValue
        case .history: historyPath = newValue
        case .exercises: exercisesPath = newValue
        }
    }
}

extension Route {
    /// The tab whose stack shows this screen.
    var tab: AppTab {
        switch self {
        case .exerciseDetail: .exercises
        case .workoutDetail: .history
        case .sessionDetail, .sessionHistory, .settings: .home
        }
    }
}
