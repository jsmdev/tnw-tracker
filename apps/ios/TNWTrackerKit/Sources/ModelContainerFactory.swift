import Foundation
import SwiftData

public enum ModelContainerFactory {
    /// File of the training store in the shared app group. It is not the file
    /// the previous model used (`tnwtracker.sqlite`): data in that file is not
    /// migrated and is left untouched.
    public static let storeFileName = "training-v1.store"

    /// In-memory container for SwiftUI #Preview blocks.
    /// Crashes with a descriptive message if schema initialization fails — fine for Xcode previews.
    public static func previewContainer() -> ModelContainer {
        do {
            return try makeContainer(inMemory: true)
        } catch {
            fatalError("ModelContainerFactory.previewContainer() failed: \(error)")
        }
    }

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TrainingSchemaV1.self)
        let url: URL = if inMemory {
            URL(fileURLWithPath: "/dev/null")
        } else {
            (FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: "group.com.tnwtracker.shared")
                ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
                .appendingPathComponent(storeFileName)
        }
        let config = ModelConfiguration(
            nil,
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TrainingMigrationPlan.self,
            configurations: [config]
        )
    }
}
