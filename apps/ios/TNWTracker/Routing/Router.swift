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
        guard let link = DeepLinkParser.parse(url) else { return }
        switch link {
        case let .route(route):
            push(route)
        case .openActiveWorkout:
            // ActiveWorkout requiere acceso al coordinator activo para conocer su
            // sessionID; el Router no lo tiene. RootView intercepta este caso vía
            // onOpenURL antes de delegar al router.
            break
        }
    }
}
