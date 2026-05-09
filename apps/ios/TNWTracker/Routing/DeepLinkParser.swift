import Foundation

public enum DeepLinkParser {
    public static func route(from url: URL) -> Route? {
        guard url.scheme == "tnwtracker" else { return nil }
        switch url.host() {
        case "session":
            guard let uuidString = url.pathComponents.dropFirst().first,
                  let id = UUID(uuidString: uuidString) else { return nil }
            return .sessionDetail(sessionID: id)
        case "exercise":
            guard let uuidString = url.pathComponents.dropFirst().first,
                  let id = UUID(uuidString: uuidString) else { return nil }
            return .exerciseDetail(exerciseID: id)
        case "session-history":
            return .sessionHistory
        case "settings":
            return .settings
        default:
            return nil
        }
    }
}
