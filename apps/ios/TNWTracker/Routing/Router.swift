import Foundation
import Observation
import SwiftUI

public struct ActiveWorkoutPresentation: Identifiable, Equatable {
    /// The routine to start from, or any id for a free session.
    public let id: UUID
    /// A free session: no routine, the user picks the exercises (#137 S5).
    public var isFree = false
    /// The exercise to add to the session once it has started or resumed
    /// («Entrenar este ejercicio» in the exercise sheet).
    public var startingExerciseId: UUID?

    /// A free session, started without a routine.
    public static func free(startingWith exerciseId: UUID? = nil) -> ActiveWorkoutPresentation {
        ActiveWorkoutPresentation(id: UUID(), isFree: true, startingExerciseId: exerciseId)
    }
}

/// The exercise whose sheet shows; `id` is the exercise's.
public struct ExercisePresentation: Identifiable, Equatable {
    public let id: UUID
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
    /// The exercise sheet, one for the whole app: the catalogue, a finished
    /// workout, a routine and the exercise deep link all open it.
    public var presentedExercise: ExercisePresentation?
    /// The exercise picked in its sheet to train, waiting for the sheet to close.
    public private(set) var exerciseToTrain: UUID?

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

    /// Shows `route`. An exercise opens its sheet instead of a screen.
    public func push(_ route: Route) {
        if case let .exerciseDetail(exerciseID) = route {
            presentExercise(exerciseID)
            return
        }
        path.append(route)
    }

    public func presentExercise(_ exerciseId: UUID) {
        exerciseToTrain = nil
        presentedExercise = ExercisePresentation(id: exerciseId)
    }

    /// «Entrenar este ejercicio»: closes the sheet; the workout opens once it
    /// has closed (`exerciseSheetDidClose`), as one cover cannot open while a
    /// sheet is still closing.
    public func train(_ exerciseId: UUID) {
        exerciseToTrain = exerciseId
        presentedExercise = nil
    }

    /// The exercise sheet has closed. With an exercise to train, reopens the
    /// workout in progress (`sessionInProgressId`) with it, or starts a free
    /// session with it when there is none.
    public func exerciseSheetDidClose(sessionInProgressId: UUID?) {
        guard let exerciseId = exerciseToTrain else { return }
        exerciseToTrain = nil
        if let sessionInProgressId {
            presentedActiveWorkout = ActiveWorkoutPresentation(id: sessionInProgressId, startingExerciseId: exerciseId)
        } else {
            presentedActiveWorkout = .free(startingWith: exerciseId)
        }
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
