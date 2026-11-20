import Foundation
import Supabase
import Testing
@testable import TNWTrackerKit

/// Source whose downloads wait until released, counting starts.
private final class GatedMediaSource: ExerciseMediaSource, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var started = 0
    let bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    var starts: Int { lock.withLock { started } }
    func release() {
        let released = lock.withLock {
            let current = waiters
            waiters = []
            return current
        }
        released.forEach { $0.resume() }
    }
    func download(path: String) async throws -> Data {
        await withCheckedContinuation { continuation in
            lock.withLock {
                started += 1
                waiters.append(continuation)
            }
        }
        return bytes
    }
}

private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data("ok".utf8)
    nonisolated(unsafe) static var onRequest: (() -> Void)?
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.onRequest?()
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"]
              )
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UUID?
    init(_ initial: UUID?) { value = initial }
    func get() -> UUID? { lock.withLock { value } }
    func set(_ newValue: UUID?) { lock.withLock { value = newValue } }
}

/// Media store robustness (#137 S2): one download per object under concurrency,
/// an answer dropped when the account switches mid-request, files always inside
/// the account folder, and undecodable bytes downloaded again.
@Suite("Exercise media robustness", .serialized)
struct ExerciseMediaRobustnessTests {
    let user = UUID()

    @Test("two concurrent requests start one download")
    func concurrentRequestsShareOneDownload() async throws {
        let folder = try InventedMedia.folder()
        let source = GatedMediaSource(bytes: InventedMedia.mp4())
        let store = ExerciseMediaStore(folder: folder, source: source)
        let path = InventedMedia.path(user: user, file: "clip.mp4")
        async let a = store.file(for: path)
        async let b = store.file(for: path)
        while source.starts == 0 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(200))
        source.release()
        let files = try await [a, b]
        #expect(files[0] == files[1])
        #expect(source.starts == 1)
    }

    @Test("an answer arriving after an account switch is dropped")
    func answerDroppedWhenAccountSwitchesMidFlight() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let client = SupabaseClient(
            supabaseURL: try #require(URL(string: "http://127.0.0.1:9")), supabaseKey: "k",
            options: SupabaseClientOptions(auth: .init(storage: InMemoryAuthStorage(), autoRefreshToken: false),
                                           global: .init(session: URLSession(configuration: config)))
        )
        let flag = Flag(user)
        StubProtocol.onRequest = { flag.set(UUID()) }
        let source = SupabaseExerciseMediaSource(client: client, userId: user) { flag.get() }
        await #expect(throws: RemoteSessionError.notSignedInAsAccount) {
            _ = try await source.download(path: InventedMedia.path(user: user, file: "p.png"))
        }
        // Control: no switch, bytes come through.
        flag.set(user)
        StubProtocol.onRequest = nil
        let data = try await source.download(path: InventedMedia.path(user: user, file: "p.png"))
        #expect(data == StubProtocol.body)
    }

    @Test(
        "odd object paths never leave the account folder",
        arguments: ["a/%2e%2e/b.jpg", "a/b/..jpg", "a/ b /c.mp4", "u/e/x.mp4.", "u/e/\u{0000}.jpg", "u/e/é.JPG"]
    )
    func storedFileAlwaysInsideFolder(path: String) async throws {
        let folder = try InventedMedia.folder()
        let store = ExerciseMediaStore(folder: folder, source: RecordingMediaSource([path: Data("x".utf8)]))
        if let file = try? await store.file(for: path) {
            #expect(file.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        }
    }

    @Test("bytes that do not decode are downloaded again on the next view")
    func undecodableImageIsDownloadedAgain() async throws {
        let folder = try InventedMedia.folder()
        let path = InventedMedia.path(user: user, file: "photo.png")
        let bad = RecordingMediaSource([path: Data("not an image".utf8)])
        let library = ExerciseMediaLibrary(store: ExerciseMediaStore(folder: folder, source: bad))
        _ = try? await library.image(path: path)
        // Server now serves the good image; does a new library recover?
        let good = RecordingMediaSource([path: InventedMedia.png()])
        let again = ExerciseMediaLibrary(store: ExerciseMediaStore(folder: folder, source: good))
        let result = try? await again.image(path: path)
        #expect(result != nil)
        #expect(good.requests == [path])
    }
}
