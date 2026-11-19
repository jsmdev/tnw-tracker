import Foundation
import Supabase
import Testing
@testable import TNWTrackerKit

/// The remote-store contract against the real adapter and the local Supabase
/// stack: schema, triggers and row-level security included. Skipped when the
/// stack is not configured or not running (see `LocalSupabaseStack`).
@Suite(
    "Supabase remote store contract (local stack)",
    .enabled("needs the local Supabase stack") { await LocalSupabaseStack.isAvailable() }
)
struct SupabaseTrainingRemoteStoreContractTests {
    @Test func pushedSessionReadsBack() async throws {
        try await run(TrainingRemoteStoreContract.pushedSessionReadsBack)
    }

    @Test func rePushClearsValues() async throws {
        try await run(TrainingRemoteStoreContract.rePushClearsValues)
    }

    @Test func rePushRemovesSetsBeforeSkippingEntry() async throws {
        try await run(TrainingRemoteStoreContract.rePushRemovesSetsBeforeSkippingEntry)
    }

    @Test func removedIdsNeverReachAnotherSession() async throws {
        try await run(TrainingRemoteStoreContract.removedIdsNeverReachAnotherSession)
    }

    @Test func importedSetArrivesAfterCursor() async throws {
        try await run(TrainingRemoteStoreContract.importedSetArrivesAfterCursor)
    }

    @Test func rowsWrittenTogetherPageOneByOne() async throws {
        try await run(TrainingRemoteStoreContract.rowsWrittenTogetherPageOneByOne)
    }

    @Test func inconsistentAggregateWritesNothing() async throws {
        try await run(TrainingRemoteStoreContract.inconsistentAggregateWritesNothing)
    }

    @Test func serverRefusalIsRejected() async throws {
        try await run(TrainingRemoteStoreContract.serverRefusalIsRejected)
    }

    @Test func exerciseAndRoutineReadBack() async throws {
        try await run(TrainingRemoteStoreContract.exerciseAndRoutineReadBack)
    }

    @Test func duplicateExternalRefIsRejected() async throws {
        try await run(TrainingRemoteStoreContract.duplicateExternalRefIsRejected)
    }

    @Test func rewoundCursorReadsAgain() async throws {
        try await run(TrainingRemoteStoreContract.rewoundCursorReadsAgain)
    }

    @Test func deletedRowsLeaveTombstones() async throws {
        try await run(TrainingRemoteStoreContract.deletedRowsLeaveTombstones)
    }

    @Test func rePushClearsTombstones() async throws {
        try await run(TrainingRemoteStoreContract.rePushClearsTombstones)
    }

    @Test func removedEntryKeepsUnknownSets() async throws {
        try await run(TrainingRemoteStoreContract.removedEntryKeepsUnknownSets)
    }

    @Test func exerciseInUseIsRefused() async throws {
        try await run(TrainingRemoteStoreContract.exerciseInUseIsRefused)
    }

    private func run(_ scenario: (RemoteStoreHarness) async throws -> Void) async throws {
        try await LocalSupabaseStack.withThrowawayUser { client, userId in
            let store = SupabaseTrainingRemoteStore(client: client)
            let harness = RemoteStoreHarness(store: store, userId: userId) { row in
                // The importer writes as the same user, outside the adapter.
                try await client.from("sets").insert(row, returning: .minimal).execute()
            }
            try await scenario(harness)
        }
    }
}
