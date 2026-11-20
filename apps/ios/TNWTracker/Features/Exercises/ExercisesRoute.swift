import Foundation

/// The exercises screen in the navigation stack (#137 T2b). Kept beside the
/// feature: `Route` lists the destinations deep links reach.
enum ExercisesRoute: Hashable {
    case list
}

extension Router {
    /// Pushes the exercises screen, as Home pushes its other sections.
    func showExercises() {
        path.append(ExercisesRoute.list)
    }
}
