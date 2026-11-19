import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

/// S10: one local store per account, on disk under a temporary root, with the
/// store every account shared before. Invented data only.
@Suite("Account stores (S10)")
@MainActor
final class AccountStoresTests {
    let root: URL
    let legacy: URL
    let stores: AccountStores
    let userA = UUID()
    let userB = UUID()

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "account-stores-\(UUID().uuidString)")
        legacy = root.appending(path: "shared").appending(path: "training-v1.store")
        try FileManager.default.createDirectory(
            at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        stores = AccountStores(root: root.appending(path: "Accounts"), legacyStores: [legacy])
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func routine(_ name: String) -> Routine {
        let bench = Exercise(isCatalogue: true, name: "Bench Press", type: .strength)
        return Routine(name: name, items: [RoutineItem(order: 1, exerciseId: bench.id, targetSets: 3)])
    }

    /// Opens `userId`'s store, saves a routine and closes it again.
    private func saveRoutine(_ name: String, for userId: UUID) throws {
        let store = try stores.open(for: userId).store
        let routine = routine(name)
        try store.exercises.save(Exercise(
            id: try #require(routine.items.first).exerciseId, isCatalogue: true, name: "Bench Press", type: .strength
        ))
        try store.routines.save(routine)
    }

    private func routineNames(of userId: UUID) throws -> (names: [String], isNew: Bool) {
        let opened = try stores.open(for: userId)
        return try (opened.store.routines.routines(RoutineQuery()).map(\.name), opened.isNew)
    }

    /// Writes the store every account shared before, stamped with `owner` (or nobody).
    private func writeLegacyStore(owner: UUID?) throws {
        let store = try TrainingStore(url: legacy)
        if let owner { _ = try store.ownership.claim(userId: owner, at: TrainingFixtures.t0) }
        let routine = routine("Legacy")
        try store.exercises.save(Exercise(
            id: try #require(routine.items.first).exerciseId, isCatalogue: true, name: "Bench Press", type: .strength
        ))
        try store.routines.save(routine)
    }

    private func legacyBytes() throws -> Data {
        try Data(contentsOf: legacy)
    }

    /// The files next to the store from before: a read that wrote nothing leaves the same ones.
    private func legacyFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: legacy.deletingLastPathComponent().path).sorted()
    }

    // MARK: - Location and name

    @Test("S10 the stores live in Application Support, outside Documents and the shared app group")
    func storesLiveInApplicationSupport() throws {
        let device = try AccountStores.onDevice()
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        let documents = try #require(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let path = device.storeURL(for: userA).standardizedFileURL.path

        #expect(path.hasPrefix(support.standardizedFileURL.path + "/"))
        #expect(!path.hasPrefix(documents.standardizedFileURL.path + "/"))
        let fileManager = FileManager.default
        if let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tnwtracker.shared") {
            #expect(!path.hasPrefix(group.standardizedFileURL.path + "/"))
        }
    }

    @Test("S10 each store is one folder inside the root, named by the user id only", arguments: [
        "00000000-0000-0000-0000-000000000000",
        "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
        "8D1C2A6B-31F4-4E5A-9B0D-2C7E5F1A9B3E"
    ])
    func folderIsTheUserId(_ text: String) throws {
        let userId = try #require(UUID(uuidString: text))
        let url = stores.storeURL(for: userId).standardizedFileURL
        let folder = url.deletingLastPathComponent()

        #expect(folder.lastPathComponent == text.lowercased())
        #expect(folder.deletingLastPathComponent().path == stores.root.standardizedFileURL.path)
        #expect(url.lastPathComponent == "training.store")
    }

    // MARK: - One store per account

    @Test("S10 a new account gets an empty store of its own; another account's data is not in it")
    func accountsDoNotShareAStore() throws {
        try saveRoutine("Legs A", for: userA)

        let b = try routineNames(of: userB)

        #expect(b.names.isEmpty)
        #expect(b.isNew)
        #expect(stores.storeURL(for: userA) != stores.storeURL(for: userB))
    }

    @Test("S10 returning to an account reopens its store as it was left")
    func storeReopensAsLeft() throws {
        try saveRoutine("Legs A", for: userA)
        try saveRoutine("Push B", for: userB)

        let a = try routineNames(of: userA)

        #expect(a.names == ["Legs A"])
        #expect(!a.isNew)
    }

    @Test("S10 the folder and every store file are protected until the device is first unlocked")
    func filesAreProtected() throws {
        let protections = ProtectionLog()
        let protected = AccountStores(root: stores.root, protect: { url, protection in
            protections.record(url.lastPathComponent, protection)
            try AccountStores.setProtection(of: url, to: protection)
        })
        do {
            let store = try protected.open(for: userA).store
            try store.exercises.save(Self.bench)
        }
        protections.removeAll()

        _ = try protected.open(for: userA)

        let folder = protected.storeURL(for: userA).deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.contains("training.store"))
        #expect(protections.entries.first?.name == folder.lastPathComponent, "the folder first, before the store opens")
        #expect(Set(protections.entries.map(\.name)) == Set([folder.lastPathComponent] + files))
        #expect(protections.entries.allSatisfy { $0.protection == .completeUntilFirstUserAuthentication })
    }

    static let bench = Exercise(isCatalogue: true, name: "Bench Press", type: .strength)

    // MARK: - The store from before

    @Test("S10 the store from before becomes the store of the user it is stamped with")
    func legacyStoreMovesToItsOwner() throws {
        try writeLegacyStore(owner: userA)

        let a = try routineNames(of: userA)

        #expect(a.names == ["Legacy"])
        #expect(!a.isNew)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(try stores.open(for: userA).store.ownership.owner() == userA)
    }

    @Test("S10 the store from before stays where it is, untouched, for another user")
    func legacyStoreStaysForItsOwner() throws {
        try writeLegacyStore(owner: userA)
        let before = try legacyBytes()

        let b = try routineNames(of: userB)

        #expect(b.names.isEmpty)
        #expect(b.isNew)
        #expect(try legacyBytes() == before)
        #expect(try routineNames(of: userA).names == ["Legacy"], "its owner still gets it")
    }

    @Test("S10 a store from before stamped with nobody is left untouched and is no one's store")
    func unownedLegacyStoreIsLeftAlone() throws {
        try writeLegacyStore(owner: nil)
        let before = try legacyBytes()
        let files = try legacyFiles()

        let a = try routineNames(of: userA)
        let b = try routineNames(of: userB)

        #expect(a.names.isEmpty && a.isNew)
        #expect(b.names.isEmpty && b.isNew)
        #expect(try legacyBytes() == before)
        #expect(try legacyFiles() == files)
    }

    @Test("S10 a file from before that is not a readable store is left untouched and is no one's store")
    func unreadableLegacyFileIsLeftAlone() throws {
        let garbage = Data("not a store".utf8)
        try garbage.write(to: legacy)

        let a = try routineNames(of: userA)

        #expect(a.names.isEmpty && a.isNew)
        #expect(try legacyBytes() == garbage)
    }
}

/// The protection classes `AccountStores` set, in order.
private final class ProtectionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(name: String, protection: FileProtectionType)] = []

    var entries: [(name: String, protection: FileProtectionType)] {
        lock.withLock { recorded }
    }

    func record(_ name: String, _ protection: FileProtectionType) {
        lock.withLock { recorded.append((name, protection)) }
    }

    func removeAll() {
        lock.withLock { recorded = [] }
    }
}
