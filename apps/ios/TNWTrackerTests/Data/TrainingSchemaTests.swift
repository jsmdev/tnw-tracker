import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

@Suite("Training schema")
@MainActor
struct TrainingSchemaTests {
    @Test("the migration plan starts at TrainingSchemaV1 1.0.0 with no stages yet")
    func migrationPlanIsReadyForFutureVersions() {
        #expect(TrainingMigrationPlan.schemas.count == 1)
        #expect(TrainingMigrationPlan.schemas.first == TrainingSchemaV1.self)
        #expect(TrainingMigrationPlan.stages.isEmpty)
        #expect(TrainingSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    @Test("the schema holds every training model, the intent mailbox event and the sync state")
    func schemaHoldsEveryModel() {
        let names = Set(TrainingSchemaV1.models.map { String(describing: $0) })
        #expect(names == [
            "ExerciseModel", "MuscleGroupModel", "RoutineModel", "RoutineItemModel",
            "SessionModel", "SessionEntryModel", "EntryExternalRefModel", "ExerciseSetModel",
            "ExerciseSettingModel", "WorkoutIntentEvent", "StoreOwnerModel", "SyncTombstoneModel",
            "SyncCursorModel"
        ])
    }

    @Test("the store uses a new file name, so the old model's store is never opened")
    func storeUsesNewFileName() {
        #expect(ModelContainerFactory.storeFileName == "training-v1.store")
    }

    @Test("an in-memory store opens empty")
    func inMemoryStoreOpensEmpty() throws {
        let store = try TrainingStore(inMemory: true)
        #expect(try store.isEmpty())
        #expect(try store.sessions.activeSession() == nil)
    }
}
