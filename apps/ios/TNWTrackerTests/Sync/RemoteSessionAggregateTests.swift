import Foundation
import Testing
@testable import TNWTrackerKit

@Suite("Remote session aggregate")
struct RemoteSessionAggregateTests {
    private let userId = UUID()

    @Test func consistentAggregateIsValid() throws {
        try TrainingRemoteStoreContract.finishedSession(for: userId).validate()
    }

    @Test func entryOfAnotherSessionIsInvalid() {
        var aggregate = TrainingRemoteStoreContract.finishedSession(for: userId)
        aggregate.entries[1].sessionId = UUID()

        #expect(throws: RemoteStoreError.invalidAggregate(
            "entry \(aggregate.entries[1].id) is not part of session \(aggregate.session.id)"
        )) {
            try aggregate.validate()
        }
    }

    @Test func setOfAnotherUserIsInvalid() {
        var aggregate = TrainingRemoteStoreContract.finishedSession(for: userId)
        aggregate.sets[0].userId = UUID()

        #expect(throws: RemoteStoreError.invalidAggregate(
            "set \(aggregate.sets[0].id) is not part of session \(aggregate.session.id)"
        )) {
            try aggregate.validate()
        }
    }

    @Test func rowBothStoredAndRemovedIsInvalid() {
        var aggregate = TrainingRemoteStoreContract.finishedSession(for: userId)
        aggregate.removedSetIds = [aggregate.sets[0].id]

        #expect(throws: RemoteStoreError.invalidAggregate("a row cannot be both stored and removed")) {
            try aggregate.validate()
        }
    }
}
