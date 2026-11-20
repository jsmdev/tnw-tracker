import Foundation
import Testing
@testable import TNWTrackerKit

/// #137 S2: images and videos are downloaded on demand, kept on the device by
/// object path, and shown offline after the first view; each account keeps
/// its own. On-disk folders under a temporary root; the bucket is an
/// in-memory double. Invented bytes only.
@Suite("Exercise media store (#137 S2)")
final class ExerciseMediaStoreTests {
    let root: URL
    let user = UUID()

    init() throws {
        root = try InventedMedia.folder()
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func store(_ source: RecordingMediaSource, folder: String = "media") throws -> ExerciseMediaStore {
        let url = root.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return ExerciseMediaStore(folder: url, source: source)
    }

    // MARK: - Cache key

    @Test("S2 the cache key is the whole object path: same file name in two folders, two objects, one download each")
    func cacheKeyIsTheObjectPath() async throws {
        let first = InventedMedia.path(user: user, file: "image.jpg")
        let second = InventedMedia.path(user: user, file: "image.jpg")
        let source = RecordingMediaSource([first: Data("first".utf8), second: Data("second".utf8)])
        let store = try store(source)

        let firstFile = try await store.file(for: first)
        let secondFile = try await store.file(for: second)
        let again = try await store.data(for: first)

        #expect(source.requests == [first, second], "each exact path downloaded once, never again")
        #expect(firstFile != secondFile)
        #expect(try Data(contentsOf: firstFile) == Data("first".utf8))
        #expect(try Data(contentsOf: secondFile) == Data("second".utf8))
        #expect(again == Data("first".utf8))
        #expect(await store.storedFile(for: first) == firstFile)
        #expect(await store.storedFile(for: InventedMedia.path(user: user, file: "image.jpg")) == nil)
    }

    @Test("S2 two views asking at once download the object once")
    func concurrentRequestsDownloadOnce() async throws {
        let path = InventedMedia.path(user: user, file: "clip.mp4")
        let source = RecordingMediaSource([path: InventedMedia.mp4()])
        let store = try store(source)

        async let first = store.file(for: path)
        async let second = store.file(for: path)
        let files = try await [first, second]

        #expect(files[0] == files[1])
        #expect(source.requests == [path])
    }

    @Test("S2 a value that is not an object path is refused and never requested", arguments: [
        "", "/absolute/image.jpg", "a//image.jpg", "a/../image.jpg", "./image.jpg",
        "https://media.example.test/a/b/image.jpg", "a\\b\\image.jpg"
    ])
    func invalidPathsAreRefused(path: String) async throws {
        let source = RecordingMediaSource([path: Data("x".utf8)])
        let store = try store(source)

        await #expect(throws: ExerciseMediaError.invalidPath) { try await store.file(for: path) }
        #expect(source.requests.isEmpty)
        #expect(await store.storedFile(for: path) == nil)
    }

    // MARK: - Video

    @Test("S2 a video is saved once to a local MP4 file in the account's folder and read from it")
    func videoIsSavedToALocalFile() async throws {
        let path = InventedMedia.path(user: user, file: "demo.mp4")
        let bytes = InventedMedia.mp4("demo")
        let source = RecordingMediaSource([path: bytes])
        let store = try store(source)
        let library = ExerciseMediaLibrary(store: store)

        let file = try await library.videoFile(path: path)

        #expect(file.isFileURL)
        #expect(file.pathExtension == "mp4", "AVFoundation plays a local file by its extension")
        #expect(file.deletingLastPathComponent().standardizedFileURL == store.folder.standardizedFileURL)
        #expect(try Data(contentsOf: file) == bytes)
        #expect(try await library.videoFile(path: path) == file)
        #expect(source.requests == [path])
    }

    // MARK: - Offline

    @Test("S2 after the first view, the image and the video show with no network, after a relaunch too")
    func offlineAfterTheFirstView() async throws {
        let image = InventedMedia.path(user: user, file: "photo.png")
        let video = InventedMedia.path(user: user, file: "clip.mp4")
        let online = RecordingMediaSource([image: InventedMedia.png(side: 6), video: InventedMedia.mp4()])
        let first = try ExerciseMediaLibrary(store: store(online))
        let shown = try await first.image(path: image)
        let played = try await first.videoFile(path: video)

        // A relaunch: a new store and a new pipeline on the same folder, with no network.
        let offline = RecordingMediaSource()
        offline.goOffline()
        let relaunched = try ExerciseMediaLibrary(store: store(offline))
        #expect(relaunched.memoryCachedImage(path: image) == nil, "nothing in memory: it comes from the file")

        let again = try await relaunched.image(path: image)
        let replayed = try await relaunched.videoFile(path: video)

        #expect(again.size == shown.size)
        #expect(again.size.width * again.scale == 6)
        #expect(replayed == played)
        #expect(try Data(contentsOf: replayed) == InventedMedia.mp4())
        #expect(offline.requests.isEmpty, "nothing was requested")
    }

    @Test("S2 never downloaded and offline: the media are unavailable offline, and nothing is kept")
    func neverDownloadedOffline() async throws {
        let image = InventedMedia.path(user: user, file: "photo.png")
        let source = RecordingMediaSource([image: InventedMedia.png()])
        source.goOffline()
        let store = try store(source)
        let library = ExerciseMediaLibrary(store: store)

        let error = await #expect(throws: (any Error).self) { try await library.image(path: image) }
        #expect(try ExerciseMediaLibrary.Unavailable(#require(error)) == .offline)
        let videoError = await #expect(throws: (any Error).self) { try await library.videoFile(path: image) }
        #expect(try ExerciseMediaLibrary.Unavailable(#require(videoError)) == .offline)
        #expect(await store.storedFile(for: image) == nil)
    }

    @Test("S2 a refused or missing object is a failed download, not an offline one")
    func refusedDownloadFails() async throws {
        let image = InventedMedia.path(user: user, file: "photo.png")
        let source = RecordingMediaSource()
        source.fail(with: RemoteSessionError.notSignedInAsAccount)
        let library = try ExerciseMediaLibrary(store: store(source))

        let error = await #expect(throws: (any Error).self) { try await library.image(path: image) }
        #expect(try ExerciseMediaLibrary.Unavailable(#require(error)) == .failed)
    }

    @Test("S2 bytes that are not an image are a failed download")
    func damagedImageFails() async throws {
        let image = InventedMedia.path(user: user, file: "photo.png")
        let library = try ExerciseMediaLibrary(store: store(RecordingMediaSource([image: Data("not an image".utf8)])))

        let error = await #expect(throws: (any Error).self) { try await library.image(path: image) }
        #expect(try ExerciseMediaLibrary.Unavailable(#require(error)) == .failed)
    }

    // MARK: - Memory

    @Test("S10 clearing the memory forgets the decoded images; their files stay")
    func clearMemoryForgetsDecodedImages() async throws {
        let image = InventedMedia.path(user: user, file: "photo.png")
        let source = RecordingMediaSource([image: InventedMedia.png()])
        let library = try ExerciseMediaLibrary(store: store(source))
        _ = try await library.image(path: image)
        #expect(library.memoryCachedImage(path: image) != nil)

        library.clearMemory()

        #expect(library.memoryCachedImage(path: image) == nil)
        #expect(await library.store.storedFile(for: image) != nil)
    }
}
