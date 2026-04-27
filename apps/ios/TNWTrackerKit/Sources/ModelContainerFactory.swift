import Foundation
import SwiftData

public enum ModelContainerFactory {
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
            schema: schema,
            url: url,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}

public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [
            Plan.self, Routine.self, Session.self,
            PlanRoutine.self, RoutineSession.self, SessionExercise.self,
            Exercise.self, ExerciseVideo.self, Workout.self,
            WorkoutExercise.self, ExerciseSet.self, RestTimer.self,
            PersonalRecord.self, User.self,
            SyncOperationRecord.self
        ]
    }
}
