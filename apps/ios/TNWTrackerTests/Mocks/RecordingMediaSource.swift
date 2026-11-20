import Foundation
@testable import TNWTrackerKit

/// An in-memory media bucket for tests: invented objects by object path, the
/// paths it was asked for in order, and a switch for "no network".
final class RecordingMediaSource: ExerciseMediaSource, @unchecked Sendable {
    private let lock = NSLock()
    private var objects: [String: Data]
    private var requested: [String] = []
    private var online = true
    /// When set, every download throws it (a refusal, a missing object).
    private var failure: (any Error)?

    init(_ objects: [String: Data] = [:]) {
        self.objects = objects
    }

    var requests: [String] {
        lock.withLock { requested }
    }

    func goOffline() {
        lock.withLock { online = false }
    }

    func fail(with error: any Error) {
        lock.withLock { failure = error }
    }

    func download(path: String) throws -> Data {
        try lock.withLock {
            requested.append(path)
            if let failure { throw failure }
            guard online else { throw URLError(.notConnectedToInternet) }
            guard let data = objects[path] else { throw URLError(.fileDoesNotExist) }
            return data
        }
    }
}

/// Invented media bytes for tests.
enum InventedMedia {
    /// A PNG `side` pixels wide, in one flat colour.
    static func png(side: CGFloat = 4) -> Data {
        InventedExerciseMediaSource.inventedImage(side: side)
    }

    /// Bytes that start like an MP4 file. The store never decodes a video.
    static func mp4(_ marker: String = "clip") -> Data {
        Data([0, 0, 0, 0x18]) + Data("ftypmp42".utf8) + Data(marker.utf8)
    }

    /// An object path of the media bucket: `<user>/<exercise>/<file>`.
    static func path(user: UUID, exercise: UUID = UUID(), file: String) -> String {
        "\(user.uuidString.lowercased())/\(exercise.uuidString.lowercased())/\(file)"
    }

    /// A new empty folder under the temporary directory.
    static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "exercise-media-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
