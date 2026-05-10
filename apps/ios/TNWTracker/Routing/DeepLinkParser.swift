import Foundation

/// Resultado de un deep link. Distingue entre rutas de NavigationStack y
/// presentaciones modales (ActiveWorkout vive en `fullScreenCover`, no en Route).
public enum DeepLink: Hashable {
    case route(Route)
    case openActiveWorkout
}

public enum DeepLinkParser {
    /// Parser canónico. Maneja todos los hosts soportados por REQ-ROUTE-03.
    public static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme == "tnwtracker" else { return nil }
        let pathComponents = Array(url.pathComponents.dropFirst())
        switch url.host() {
        case "session":
            guard let uuidString = pathComponents.first,
                  let id = UUID(uuidString: uuidString) else { return nil }
            return .route(.sessionDetail(sessionID: id))
        case "exercise":
            guard let uuidString = pathComponents.first,
                  let id = UUID(uuidString: uuidString) else { return nil }
            return .route(.exerciseDetail(exerciseID: id))
        case "session-history":
            return .route(.sessionHistory)
        case "settings":
            return .route(.settings)
        case "workout":
            // REQ-ROUTE-03: tnwtracker://workout/active abre el workout activo.
            // ActiveWorkout vive en fullScreenCover (per ADR-2), no en Route enum,
            // así que se modela como caso aparte para que el handler decida.
            guard pathComponents.first == "active" else { return nil }
            return .openActiveWorkout
        default:
            return nil
        }
    }

    /// Compat: solo Routes de NavigationStack. Devuelve nil para presentaciones.
    public static func route(from url: URL) -> Route? {
        guard case let .route(route) = parse(url) else { return nil }
        return route
    }
}
