import CryptoKit
import Foundation

/// The exercise media one account downloaded, kept on the device (#137 S2):
/// each object is downloaded once, the first time it is shown, and read from
/// its file from then on, with or without a network.
///
/// - The folder is the account's own (`AccountStores.mediaStore(for:source:)`),
///   inside Application Support, not Caches, so the system never purges it; it
///   is excluded from backups, since the server keeps every object.
/// - The cache key is the object path. Object paths are immutable (a changed
///   file gets a new name), so a file once downloaded never goes stale.
/// - Each file is named by a hash of the whole object path plus its extension
///   (AVFoundation needs it to play a local file): the path is server data, so
///   it never becomes a file system path, and two objects with the same file
///   name in different folders never collide.
/// - Every file gets the folder's protection class as it is written.
public actor ExerciseMediaStore {
    /// The account's media folder.
    public nonisolated let folder: URL
    private let source: any ExerciseMediaSource
    private let protect: @Sendable (URL) throws -> Void
    /// Downloads on their way, so two views asking for one object download it once.
    private var downloads: [String: Task<URL, any Error>] = [:]

    public init(
        folder: URL,
        source: any ExerciseMediaSource,
        protect: @escaping @Sendable (URL) throws -> Void = { _ in }
    ) {
        self.folder = folder
        self.source = source
        self.protect = protect
    }

    /// The local file of the object at `path`, downloaded first if this account
    /// never downloaded it. Throws `ExerciseMediaError.invalidPath` for a path
    /// that is not an object path, and the source's error when the download fails.
    public func file(for path: String) async throws -> URL {
        guard let name = Self.fileName(for: path) else { throw ExerciseMediaError.invalidPath }
        let file = folder.appending(path: name)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        if let download = downloads[path] { return try await download.value }
        let source = source
        let protect = protect
        let download = Task {
            let data = try await source.download(path: path)
            try data.write(to: file, options: .atomic)
            try protect(file)
            return file
        }
        downloads[path] = download
        defer { downloads[path] = nil }
        return try await download.value
    }

    /// The object's bytes, downloaded first if needed (see `file(for:)`).
    public func data(for path: String) async throws -> Data {
        try await Data(contentsOf: file(for: path))
    }

    /// The local file of the object at `path` when this account already has
    /// it; nil otherwise. Never downloads.
    public func storedFile(for path: String) -> URL? {
        guard let name = Self.fileName(for: path) else { return nil }
        let file = folder.appending(path: name)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// The file name of an object path, or nil when `path` is not one: empty
    /// parts, `.` or `..`, a leading `/`, a scheme or a backslash.
    static func fileName(for path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.contains("\\"), !path.contains(":"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { return nil }
        let hash = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        let name = parts.last.map(String.init) ?? ""
        let fileExtension = name.contains(".") ? (name.split(separator: ".").last.map(String.init) ?? "") : ""
        let safe = fileExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return safe.isEmpty || safe.count > 8 ? hash : "\(hash).\(safe)"
    }
}

public enum ExerciseMediaError: Error, Equatable, Sendable {
    /// The value is not an object path of the media bucket.
    case invalidPath
}
