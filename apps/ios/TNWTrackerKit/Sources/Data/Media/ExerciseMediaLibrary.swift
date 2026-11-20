import Foundation
import Nuke
import UIKit

/// An account's exercise images and videos (#137 S2), on its `ExerciseMediaStore`.
///
/// - Images go through a Nuke pipeline of the account's own: decoded images
///   stay in an in-memory cache keyed by object path, and their bytes come
///   from the store (`ImageRequest(id:data:)`), which downloads them once with
///   the account's session and keeps them on disk. The pipeline has no disk
///   cache of its own and never uses Nuke's shared caches or its URL loader.
/// - Videos are the store's local MP4 files, played by AVKit from the file.
/// - `clearMemory()` empties the image cache when the account closes.
public final class ExerciseMediaLibrary: Sendable {
    public let store: ExerciseMediaStore
    private let imageCache: ImageCache
    private let pipeline: ImagePipeline

    public init(store: ExerciseMediaStore) {
        self.store = store
        let imageCache = ImageCache()
        self.imageCache = imageCache
        // Never used: every request brings its own bytes. Ephemeral, so even
        // a URL request would leave nothing on disk.
        var configuration = ImagePipeline.Configuration(dataLoader: DataLoader(configuration: .ephemeral))
        configuration.dataCache = nil
        configuration.imageCache = imageCache
        pipeline = ImagePipeline(configuration: configuration)
    }

    /// The image at the object path, from memory, the account's files or a
    /// download, in that order.
    /// Bytes that do not decode are discarded, so the next view downloads
    /// them again instead of failing forever.
    public func image(path: String) async throws -> UIImage {
        do {
            return try await pipeline.image(for: request(path))
        } catch let error as ImagePipeline.Error {
            if case .decodingFailed = error { await store.discard(path: path) }
            throw error
        }
    }

    /// The image at the object path if it is decoded in memory now.
    public func memoryCachedImage(path: String) -> UIImage? {
        pipeline.cache[request(path)]?.image
    }

    /// The local file of the video at the object path, downloaded first if needed.
    public func videoFile(path: String) async throws -> URL {
        try await store.file(for: path)
    }

    /// Forgets every decoded image. The files stay in the account's folder.
    public func clearMemory() {
        imageCache.removeAll()
    }

    private func request(_ path: String) -> ImageRequest {
        let store = store
        return ImageRequest(id: path, data: { try await store.data(for: path) })
    }
}

extension ExerciseMediaLibrary {
    /// Why the media of an exercise are not shown.
    public enum Unavailable: Equatable, Sendable {
        /// The exercise has no image or video.
        case none
        /// Never downloaded on this device, and there is no network now.
        case offline
        /// The download failed for another reason (refused, missing, damaged).
        case failed

        /// Classifies the error of a failed load.
        public init(_ error: any Error) {
            let underlying = (error as? ImagePipeline.Error)?.dataLoadingError ?? error
            let offline: Set<URLError.Code> = [
                .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff
            ]
            if let urlError = underlying as? URLError, offline.contains(urlError.code) {
                self = .offline
            } else {
                self = .failed
            }
        }
    }
}
