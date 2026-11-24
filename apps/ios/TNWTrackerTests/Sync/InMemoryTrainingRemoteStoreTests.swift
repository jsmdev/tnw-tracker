import Foundation
import Testing
@testable import TNWTrackerKit

/// The remote-store contract against the in-memory fake, plus the failure
/// controls the sync tests rely on.
@Suite("In-memory remote store")
struct InMemoryTrainingRemoteStoreTests {
    private let userId = UUID()
    private let fake = InMemoryTrainingRemoteStore()

    private var harness: RemoteStoreHarness {
        let fake = fake
        return RemoteStoreHarness(store: fake, userId: userId) { try await fake.insertOnServer($0) }
    }

    // MARK: - Contract

    @Test func pushedSessionReadsBack() async throws {
        try await TrainingRemoteStoreContract.pushedSessionReadsBack(harness)
    }

    @Test func rePushClearsValues() async throws {
        try await TrainingRemoteStoreContract.rePushClearsValues(harness)
    }

    @Test func rePushRemovesSetsBeforeSkippingEntry() async throws {
        try await TrainingRemoteStoreContract.rePushRemovesSetsBeforeSkippingEntry(harness)
    }

    @Test func removedIdsNeverReachAnotherSession() async throws {
        try await TrainingRemoteStoreContract.removedIdsNeverReachAnotherSession(harness)
    }

    @Test func importedSetArrivesAfterCursor() async throws {
        try await TrainingRemoteStoreContract.importedSetArrivesAfterCursor(harness)
    }

    @Test func serverRefusalIsRejected() async throws {
        try await TrainingRemoteStoreContract.serverRefusalIsRejected(harness)
    }

    @Test func exerciseAndRoutineReadBack() async throws {
        try await TrainingRemoteStoreContract.exerciseAndRoutineReadBack(harness)
    }

    @Test func childrenNoLongerListedAreDeleted() async throws {
        try await TrainingRemoteStoreContract.childrenNoLongerListedAreDeleted(harness)
    }

    @Test func settingsAreKeyedByExercise() async throws {
        try await TrainingRemoteStoreContract.settingsAreKeyedByExercise(harness)
    }

    @Test func linksReadBackAndLeaveTombstones() async throws {
        try await TrainingRemoteStoreContract.linksReadBackAndLeaveTombstones(harness)
    }

    @Test func invalidLinksAreRejected() async throws {
        try await TrainingRemoteStoreContract.invalidLinksAreRejected(harness)
    }

    @Test func rowsWrittenTogetherPageOneByOne() async throws {
        try await TrainingRemoteStoreContract.rowsWrittenTogetherPageOneByOne(harness)
    }

    @Test func inconsistentAggregateWritesNothing() async throws {
        try await TrainingRemoteStoreContract.inconsistentAggregateWritesNothing(harness)
    }

    @Test func unseenExerciseIsRejected() async throws {
        try await TrainingRemoteStoreContract.unseenExerciseIsRejected(harness)
    }

    @Test func secondDoneEntryIsRejected() async throws {
        try await TrainingRemoteStoreContract.secondDoneEntryIsRejected(harness)
    }

    @Test func duplicateExternalRefIsRejected() async throws {
        try await TrainingRemoteStoreContract.duplicateExternalRefIsRejected(harness)
    }

    @Test func rewoundCursorReadsAgain() async throws {
        try await TrainingRemoteStoreContract.rewoundCursorReadsAgain(harness)
    }

    @Test func deletedRowsLeaveTombstones() async throws {
        try await TrainingRemoteStoreContract.deletedRowsLeaveTombstones(harness)
    }

    @Test func rePushClearsTombstones() async throws {
        try await TrainingRemoteStoreContract.rePushClearsTombstones(harness)
    }

    @Test func removedEntryKeepsUnknownSets() async throws {
        try await TrainingRemoteStoreContract.removedEntryKeepsUnknownSets(harness)
    }

    @Test func exerciseInUseIsRefused() async throws {
        try await TrainingRemoteStoreContract.exerciseInUseIsRefused(harness)
    }

    // MARK: - Failure controls

    @Test func failedPushThrowsAndStoresNothing() async throws {
        let aggregate = TrainingRemoteStoreContract.finishedSession(for: userId)
        await fake.failNext(.pushSession)

        await #expect(throws: URLError.self) {
            try await fake.pushSession(aggregate)
        }
        #expect(await fake.stored(RemoteSessionRow.self).isEmpty)

        try await fake.pushSession(aggregate)
        #expect(await fake.stored(RemoteSessionRow.self).map(\.id) == [aggregate.session.id])
        #expect(await fake.calls == [.pushSession(aggregate.session.id), .pushSession(aggregate.session.id)])
    }

    @Test func pushFailingPartWayLeavesPrefixThatRetryCompletes() async throws {
        let aggregate = TrainingRemoteStoreContract.finishedSession(for: userId)
        await fake.failNextPush(at: .entries)

        await #expect(throws: URLError.self) {
            try await fake.pushSession(aggregate)
        }
        #expect(await fake.stored(RemoteSessionRow.self).map(\.id) == [aggregate.session.id])
        #expect(await fake.stored(RemoteEntryRow.self).isEmpty)
        #expect(await fake.stored(RemoteSetRow.self).isEmpty)

        try await fake.pushSession(aggregate)
        #expect(await fake.stored(RemoteEntryRow.self).count == aggregate.entries.count)
        #expect(await fake.stored(RemoteSetRow.self).count == aggregate.sets.count)
    }

    @Test func failedPullThrowsOnce() async throws {
        await fake.failNext(.pull)

        await #expect(throws: URLError.self) {
            _ = try await fake.pull(RemoteSetRow.self, after: nil, limit: 10)
        }
        let page = try await fake.pull(RemoteSetRow.self, after: nil, limit: 10)
        #expect(page.rows.isEmpty)
        #expect(await fake.calls == [.pull(.sets, after: nil, limit: 10), .pull(.sets, after: nil, limit: 10)])
    }

    /// The fake refuses what the server refuses, so a sync test cannot pass on
    /// an order the server would reject.
    @Test func skippingAnEntryThatStillHasSetsIsRejected() async throws {
        var aggregate = TrainingRemoteStoreContract.finishedSession(for: userId)
        try await fake.pushSession(aggregate)
        aggregate.entries[0].status = .skipped

        await #expect(throws: InMemoryTrainingRemoteStore.skippedEntryWithSets) {
            try await fake.upsert([aggregate.entries[0]])
        }
        #expect(await fake.stored(RemoteEntryRow.self).first { $0.id == aggregate.entries[0].id }?.status == .done)
    }
}
