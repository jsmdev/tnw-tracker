import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// #137 S2 and S10: each account keeps the exercise media it downloaded in its
/// own folder beside its store, protected like it and out of backups; nothing
/// one account downloaded is readable by another, and its decoded images are
/// forgotten when it closes. Real accounts and on-disk folders under a
/// temporary root; the bucket is an in-memory double. Invented bytes only.
@Suite("Exercise media per account (#137, S10)")
@MainActor
final class ExerciseMediaAccountTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "exercise-media-\(UUID().uuidString)")
    let userA = UUID()
    let userB = UUID()
    let protections = MediaProtectionLog()
    let stores: AccountStores

    init() {
        let protections = protections
        stores = AccountStores(root: root, protect: { url, protection in
            protections.record(url, protection)
        })
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func folder(of userId: UUID) -> URL {
        stores.storeURL(for: userId).deletingLastPathComponent()
    }

    // MARK: - Folder

    @Test("S10 the media live in the account's folder, protected like its store and excluded from backups")
    func mediaFolderIsTheAccountsOwn() async throws {
        _ = try stores.open(for: userA)
        let path = InventedMedia.path(user: userA, file: "photo.png")
        let store = try stores.mediaStore(for: userA, source: RecordingMediaSource([path: InventedMedia.png()]))

        let file = try await store.file(for: path)

        let media = folder(of: userA).appending(path: "Media", directoryHint: .isDirectory)
        #expect(store.folder.standardizedFileURL == media.standardizedFileURL)
        #expect(file.deletingLastPathComponent().standardizedFileURL == media.standardizedFileURL)
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        #expect(
            try AccountStores.onDevice().storeURL(for: userA).deletingLastPathComponent()
                .appending(path: "Media").standardizedFileURL.path.hasPrefix(support.standardizedFileURL.path),
            "on the device, in Application Support: not Caches, which the system may purge"
        )
        let protected = protections.entries.filter { $0.url.standardizedFileURL.path.hasPrefix(media.path) }
        #expect(Set(protected.map(\.url.lastPathComponent)) == [media.lastPathComponent, file.lastPathComponent])
        #expect(protected.allSatisfy { $0.protection == .completeUntilFirstUserAuthentication })
        let values = try media.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("S10 the media folder leaves the account's store as it was: reopened, not new, same place")
    func mediaFolderKeepsTheStore() throws {
        let opened = try stores.open(for: userA)
        try opened.store.exercises.save(Exercise(isCatalogue: true, name: "Bench Press", type: .strength))
        _ = try stores.mediaStore(for: userA, source: RecordingMediaSource())

        let again = try stores.open(for: userA)

        #expect(!again.isNew)
        #expect(try again.store.exercises.exercises().map(\.name) == ["Bench Press"])
        #expect(stores.storeURL(for: userA).lastPathComponent == "training.store")
    }

    @Test("S10 account B cannot read what account A downloaded: B asks its own source, and A's file stays A's")
    func anotherAccountCannotReadTheMedia() async throws {
        let path = InventedMedia.path(user: userA, file: "photo.png")
        let sourceA = RecordingMediaSource([path: InventedMedia.png()])
        let mediaA = try stores.mediaStore(for: userA, source: sourceA)
        let fileA = try await mediaA.file(for: path)

        let sourceB = RecordingMediaSource()
        sourceB.fail(with: URLError(.userAuthenticationRequired))
        let mediaB = try stores.mediaStore(for: userB, source: sourceB)

        #expect(await mediaB.storedFile(for: path) == nil)
        await #expect(throws: URLError.self) { try await mediaB.file(for: path) }
        #expect(sourceB.requests == [path], "B asked its own session, which the bucket refuses")
        #expect(sourceA.requests == [path], "A's source never served B")
        #expect(!mediaB.folder.standardizedFileURL.path.hasPrefix(folder(of: userA).standardizedFileURL.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: mediaB.folder.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: fileA.path))
    }

    // MARK: - Closing the account

    private func accounts(sources: [UUID: RecordingMediaSource]) -> AppAccounts {
        let stores = stores
        return AppAccounts.makeForTesting(
            authRepository: AuthRepositoryMock(),
            remote: { _ in InMemoryTrainingRemoteStore() },
            openStore: { try stores.open(for: $0) },
            openMedia: { userId in
                try ExerciseMediaLibrary(store: stores.mediaStore(
                    for: userId, source: sources[userId] ?? RecordingMediaSource()
                ))
            }
        )
    }

    /// Signs `userId` in and waits for its first sync, so no sync is left
    /// running on the folder when the test removes it.
    private func signIn(_ userId: UUID, on accounts: AppAccounts) async throws -> AppEnvironment {
        await accounts.handle(AuthStateChange(event: .signedIn, userId: userId))
        let env = try #require(accounts.current)
        await env.syncScheduler.waitUntilIdle()
        return env
    }

    @Test("S10 signing out forgets the account's decoded images; its files stay for its next sign-in")
    func signOutClearsTheImageMemory() async throws {
        let path = InventedMedia.path(user: userA, file: "photo.png")
        let sourceA = RecordingMediaSource([path: InventedMedia.png()])
        let accounts = accounts(sources: [userA: sourceA])
        let library = try await signIn(userA, on: accounts).exerciseMedia
        _ = try await library.image(path: path)
        #expect(library.memoryCachedImage(path: path) != nil)

        await accounts.handle(AuthStateChange(event: .signedOut, userId: nil))

        #expect(accounts.current == nil)
        #expect(library.memoryCachedImage(path: path) == nil)
        #expect(await library.store.storedFile(for: path) != nil)

        sourceA.goOffline()
        let again = try await signIn(userA, on: accounts).exerciseMedia
        #expect(try await again.image(path: path).size.width > 0, "offline: from the file A kept")
        #expect(sourceA.requests == [path])
    }

    @Test("S10 another account signing in forgets the previous one's images and finds none of its files")
    func switchingAccountsClearsTheImageMemory() async throws {
        let path = InventedMedia.path(user: userA, file: "photo.png")
        let sourceB = RecordingMediaSource()
        sourceB.goOffline()
        let accounts = accounts(sources: [userA: RecordingMediaSource([path: InventedMedia.png()]), userB: sourceB])
        let libraryA = try await signIn(userA, on: accounts).exerciseMedia
        _ = try await libraryA.image(path: path)

        let libraryB = try await signIn(userB, on: accounts).exerciseMedia

        #expect(libraryA.memoryCachedImage(path: path) == nil)
        #expect(libraryB.memoryCachedImage(path: path) == nil)
        #expect(await libraryB.store.storedFile(for: path) == nil)
        await #expect(throws: (any Error).self) { try await libraryB.image(path: path) }
    }
}

/// The protection classes `AccountStores` set, in order.
final class MediaProtectionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(url: URL, protection: FileProtectionType)] = []

    var entries: [(url: URL, protection: FileProtectionType)] {
        lock.withLock { recorded }
    }

    func record(_ url: URL, _ protection: FileProtectionType) {
        lock.withLock { recorded.append((url, protection)) }
    }
}
