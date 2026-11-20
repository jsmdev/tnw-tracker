import Foundation
import SwiftData

/// One local training store per account (S10): whoever signs in on the device
/// sees only their own data, and the sync brings it to any device they sign in
/// on. Nothing here deletes data.
///
/// - Each store is `<root>/<user id>/training.store`, `root` being
///   `Application Support/Accounts` in the app's own container: not Documents,
///   not the app group the widget extension shares. The folder is named by the
///   user id's canonical text only (a `UUID`, never an email or a name), so it
///   is always exactly one folder inside `root`.
/// - Files are protected until the device is first unlocked after a restart
///   (`completeUntilFirstUserAuthentication`): the app writes to the store while
///   locked during a workout (the lock-screen buttons, the rest timer) and the
///   sync may run then; `complete` would close the files under them.
/// - The account's exercise media live beside its store, in `Media`
///   (`mediaStore(for:source:)`), with the same protection, out of backups.
/// - The store every account shared before is moved to the folder of the user
///   it is stamped with when that user first signs in. One stamped with nobody,
///   or that cannot be read, is left where it is and is no one's store.
public struct AccountStores: Sendable {
    static let storeFileName = "training.store"
    static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    /// The folder holding one folder per account.
    public let root: URL
    /// Where the store every account shared before may be.
    let legacyStores: [URL]
    /// Sets a file's protection class: a system service (the simulator keeps none).
    let protect: @Sendable (URL, FileProtectionType) throws -> Void

    public init(
        root: URL,
        legacyStores: [URL] = [],
        protect: @escaping @Sendable (URL, FileProtectionType) throws -> Void = Self.setProtection
    ) {
        self.root = root
        self.legacyStores = legacyStores
        self.protect = protect
    }

    public static func setProtection(of url: URL, to protection: FileProtectionType) throws {
        try FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
    }

    /// The device's account stores.
    public static func onDevice() throws -> AccountStores {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return AccountStores(
            root: support.appending(path: "Accounts", directoryHint: .isDirectory),
            legacyStores: ModelContainerFactory.legacyStoreURLs()
        )
    }

    /// The file of the account's store.
    public func storeURL(for userId: UUID) -> URL {
        folder(for: userId).appending(path: Self.storeFileName)
    }

    private func folder(for userId: UUID) -> URL {
        root.appending(path: userId.uuidString.lowercased(), directoryHint: .isDirectory)
    }

    /// The account's exercise media (#137 S2), in `<root>/<user id>/Media`:
    /// beside its store, with the store's protection class on the folder and on
    /// every file downloaded into it, and excluded from backups (the server
    /// keeps every object). Another account's folder is never read.
    public func mediaStore(for userId: UUID, source: any ExerciseMediaSource) throws -> ExerciseMediaStore {
        var media = folder(for: userId).appending(path: Self.mediaFolderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try protect(media, Self.protection)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try media.setResourceValues(values)
        let protect = protect
        return ExerciseMediaStore(folder: media, source: source) { try protect($0, Self.protection) }
    }

    static let mediaFolderName = "Media"

    /// Opens the account's store as it was left, or creates it (`isNew`).
    @MainActor
    public func open(for userId: UUID) throws -> (store: TrainingStore, isNew: Bool) {
        let fileManager = FileManager.default
        let folder = folder(for: userId)
        let url = storeURL(for: userId)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        // Before the store opens, so the files SQLite creates in the folder inherit it.
        try protect(folder, Self.protection)
        let isNew = try !fileManager.fileExists(atPath: url.path) && !adoptLegacyStore(of: userId, to: url)
        let store = try TrainingStore(url: url)
        for file in try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            try protect(file, Self.protection)
        }
        return (store, isNew)
    }

    /// Moves the legacy store to `url` when it is stamped with `userId`.
    @MainActor
    private func adoptLegacyStore(of userId: UUID, to url: URL) throws -> Bool {
        let fileManager = FileManager.default
        guard let legacy = legacyStores.first(where: {
            fileManager.fileExists(atPath: $0.path) && Self.owner(ofStoreAt: $0) == userId
        }) else { return false }
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: legacy.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(at: source, to: URL(fileURLWithPath: url.path + suffix))
        }
        return true
    }

    /// The owner stamp of the store at `url`, read through a read-only
    /// container closed before returning; nil when it has none or cannot be read.
    @MainActor
    private static func owner(ofStoreAt url: URL) -> UUID? {
        autoreleasepool {
            guard let container = try? ModelContainerFactory.makeContainer(url: url, allowsSave: false) else {
                return nil
            }
            return try? SwiftDataStoreOwnership(context: ModelContext(container)).owner()
        }
    }
}
