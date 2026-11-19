import Foundation
import SwiftData

public enum ModelContainerFactory {
    /// The app group the app shares with its widget extension.
    static let appGroup = "group.com.tnwtracker.shared"

    /// File of the one training store every account shared before each account
    /// had its own (S10). `AccountStores` moves it to its owner's folder and never
    /// opens it as anyone else's. It is not the file the previous model used
    /// (`tnwtracker.sqlite`): data in that file is not migrated and is left untouched.
    static let legacyStoreFileName = "training-v1.store"

    /// File of the intent mailbox: the widget process writes the Live Activity
    /// buttons' intents there for the app to drain. It belongs to no account and
    /// holds only workout ids and intent kinds, never training data.
    static let intentMailboxFileName = "intent-mailbox.store"

    /// In-memory container for SwiftUI #Preview blocks.
    /// Crashes with a descriptive message if schema initialization fails — fine for Xcode previews.
    public static func previewContainer() -> ModelContainer {
        do {
            return try makeContainer(url: nil)
        } catch {
            fatalError("ModelContainerFactory.previewContainer() failed: \(error)")
        }
    }

    /// The training store at `url`, or in memory when `url` is nil.
    /// `allowsSave: false` opens it read-only.
    public static func makeContainer(url: URL?, allowsSave: Bool = true) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TrainingSchemaV1.self)
        let config = ModelConfiguration(
            nil,
            schema: schema,
            url: url ?? URL(fileURLWithPath: "/dev/null"),
            allowsSave: allowsSave,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TrainingMigrationPlan.self,
            configurations: [config]
        )
    }

    /// The intent mailbox, in the app group so the widget process reaches it.
    /// `inMemory` for tests, previews and UI testing.
    public static func makeIntentMailboxContainer(inMemory: Bool = false) throws -> ModelContainer {
        let url = inMemory
            ? URL(fileURLWithPath: "/dev/null")
            : sharedDirectory().appending(path: intentMailboxFileName)
        let config = ModelConfiguration(url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: WorkoutIntentEvent.self, configurations: config)
    }

    /// Where the legacy store may be: the app group, or Documents when the group is missing.
    static func legacyStoreURLs() -> [URL] {
        var urls: [URL] = []
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            urls.append(group.appending(path: legacyStoreFileName))
        }
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(documents.appending(path: legacyStoreFileName))
        }
        return urls
    }

    private static func sharedDirectory() -> URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
