import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

/// Schema V1 as it was before `ExerciseLinkModel` (S10): the shape of the
/// stores already on devices.
private enum SchemaV1WithoutLinks: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ExerciseModel.self, MuscleGroupModel.self, RoutineModel.self, RoutineItemModel.self,
            SessionModel.self, SessionEntryModel.self, EntryExternalRefModel.self, ExerciseSetModel.self,
            ExerciseSettingModel.self, WorkoutIntentEvent.self, StoreOwnerModel.self,
            SyncTombstoneModel.self, SyncCursorModel.self
        ]
    }
}

private enum PlanWithoutLinks: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1WithoutLinks.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// Models added to schema V1 in place must open the stores the previous V1
/// wrote. A real store on disk. Invented data only.
@Suite("Training schema compatibility")
@MainActor
struct TrainingSchemaCompatibilityTests {
    @Test("a store written by the previous V1 without ExerciseLinkModel opens and keeps its data")
    func previousStoreOpens() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "schema-compat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "training.store")
        let exerciseId = UUID()
        do {
            let schema = Schema(versionedSchema: SchemaV1WithoutLinks.self)
            #expect(!schema.entities.contains { $0.name == "ExerciseLinkModel" })
            let configuration = ModelConfiguration(nil, schema: schema, url: url, cloudKitDatabase: .none)
            let previous = try ModelContainer(
                for: schema, migrationPlan: PlanWithoutLinks.self, configurations: [configuration]
            )
            let context = ModelContext(previous)
            context.insert(ExerciseModel(id: exerciseId, name: "Old Squat", typeRaw: "strength"))
            try context.save()
        }

        let store = try TrainingStore(url: url)

        #expect(try store.exercises.exercises().map(\.id) == [exerciseId])
        #expect(try store.exercises.exercise(id: exerciseId)?.name == "Old Squat")
        let link = try store.exerciseLinks.add(
            exerciseId: exerciseId, title: "Squat depth", url: "https://blog.example.test/squat",
            source: "blog.example.test"
        )
        #expect(try store.exerciseLinks.links(exerciseId: exerciseId) == [link])
    }
}
