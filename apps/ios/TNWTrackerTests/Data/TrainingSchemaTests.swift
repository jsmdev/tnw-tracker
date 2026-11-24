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
            "ExerciseSettingModel", "ExerciseLinkModel", "WorkoutIntentEvent", "StoreOwnerModel", "SyncTombstoneModel",
            "SyncCursorModel"
        ])
    }

    @Test("account stores and the shared store from before never use the old model's file")
    func storesUseNewFileNames() {
        #expect(ModelContainerFactory.legacyStoreFileName == "training-v1.store")
        #expect(AccountStores.storeFileName == "training.store")
        #expect(ModelContainerFactory.legacyStoreURLs().allSatisfy { $0.lastPathComponent == "training-v1.store" })
    }

    @Test("an in-memory store opens empty")
    func inMemoryStoreOpensEmpty() throws {
        let store = try TrainingStore.inMemory()
        #expect(try store.isEmpty())
        #expect(try store.sessions.activeSession() == nil)
    }
}
