import Foundation
import SwiftData

public enum ModelContainerFactory {
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
        let schema = Schema(versionedSchema: SchemaV1.self)
        let url: URL = if inMemory {
            URL(fileURLWithPath: "/dev/null")
        } else {
            (FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: "group.com.tnwtracker.shared")
                ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
                .appendingPathComponent("tnwtracker.sqlite")
        }
        let config = ModelConfiguration(
            nil,
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}

public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [
            Plan.self, Routine.self, Session.self,
            PlanRoutine.self, RoutineSession.self, SessionExercise.self,
            Exercise.self, ExerciseVideo.self, Workout.self,
            WorkoutExercise.self, ExerciseSet.self, RestTimer.self,
            PersonalRecord.self, User.self,
            SyncOperationRecord.self,
            WorkoutIntentEvent.self
        ]
    }
}
