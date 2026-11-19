import Foundation
import Testing
@testable import TNWTrackerKit

/// Deletes (S11): behaviour every `TrainingRemoteStore` keeps, run against the
/// fake and the local stack like the rest of `TrainingRemoteStoreContract`.
extension TrainingRemoteStoreContract {
    /// Deleting a session deletes its entries and sets, and leaves a tombstone
    /// of each, owned by the user, read with the same keyset cursor as rows.
    /// Deleting it again is harmless.
    static func deletedRowsLeaveTombstones(_ harness: RemoteStoreHarness) async throws {
        let aggregate = finishedSession(for: harness.userId)
        try await harness.store.pushSession(aggregate)

        try await harness.store.delete(.sessions, ids: [aggregate.session.id])
        try await harness.store.delete(.sessions, ids: [aggregate.session.id])

        #expect(try await pullAll(RemoteSessionRow.self, from: harness.store).isEmpty)
        #expect(try await pullAll(RemoteEntryRow.self, from: harness.store).isEmpty)
        #expect(try await pullAll(RemoteSetRow.self, from: harness.store).isEmpty)
        let tombstones = try await pullAll(RemoteTombstoneRow.self, from: harness.store)
        let expected = [("sessions", aggregate.session.id)] + aggregate.entries.map { ("entries", $0.id) }
            + aggregate.sets.map { ("sets", $0.id) }
        #expect(Set(tombstones.map { "\($0.tableName):\($0.rowId)" }) == Set(expected.map { "\($0.0):\($0.1)" }))
        #expect(tombstones.count == expected.count)
        #expect(tombstones.allSatisfy { $0.userId == harness.userId && $0.updatedAt != nil })
        let last = try #require(tombstones.last)
        let after = RemoteCursor(updatedAt: try #require(last.updatedAt), id: last.id)
        #expect(try await harness.store.pull(RemoteTombstoneRow.self, after: after, limit: 10).rows.isEmpty)
    }

    /// Pushing a deleted session again brings its rows back and clears their
    /// tombstones, so no pull reads a tombstone of a row that exists.
    static func rePushClearsTombstones(_ harness: RemoteStoreHarness) async throws {
        let aggregate = finishedSession(for: harness.userId)
        try await harness.store.pushSession(aggregate)
        try await harness.store.delete(.sessions, ids: [aggregate.session.id])

        try await harness.store.pushSession(aggregate)

        #expect(try await pullAll(RemoteSessionRow.self, from: harness.store).map(\.id) == [aggregate.session.id])
        #expect(try await pullAll(RemoteSetRow.self, from: harness.store).count == aggregate.sets.count)
        #expect(try await pullAll(RemoteTombstoneRow.self, from: harness.store).isEmpty)
    }

    /// A removed entry that holds a set the device never listed (an importer
    /// added it after the device's last pull) is kept with that set, and both
    /// are read again after the cursors; a removed entry without one is deleted.
    static func removedEntryKeepsUnknownSets(_ harness: RemoteStoreHarness) async throws {
        var aggregate = finishedSession(for: harness.userId)
        try await harness.store.pushSession(aggregate)
        let firstEntries = try await harness.store.pull(RemoteEntryRow.self, after: nil, limit: 10)
        let entriesCursor = try #require(firstEntries.next)
        let late = RemoteSetRow(
            id: UUID(), userId: harness.userId, entryId: aggregate.entries[0].id, position: 1, source: .imported,
            reps: 12, weight: .kg(40), completedAt: date(minute: 20),
            externalRef: ExternalRef(provider: "machines-atlas", id: "set-\(UUID().uuidString)")
        )
        try await harness.insertImportedSet(late)
        let lastSet = try #require(try await pullAll(RemoteSetRow.self, from: harness.store).last)
        let setsCursor = RemoteCursor(updatedAt: try #require(lastSet.updatedAt), id: lastSet.id)

        // The device deleted both manual sets, so both entries.
        aggregate.removedSetIds = aggregate.sets.map(\.id)
        aggregate.removedEntryIds = aggregate.entries.map(\.id)
        aggregate.entries = []
        aggregate.sets = []
        try await harness.store.pushSession(aggregate)

        let entries = try await pullAll(RemoteEntryRow.self, from: harness.store)
        #expect(entries.map(\.id) == [late.entryId])
        #expect(try await pullAll(RemoteSetRow.self, from: harness.store).map(withoutServerFields) == [late])
        let reread = try await harness.store.pull(RemoteEntryRow.self, after: entriesCursor, limit: 10)
        #expect(reread.rows.map(\.id).contains(late.entryId))
        let rereadSets = try await harness.store.pull(RemoteSetRow.self, after: setsCursor, limit: 10)
        #expect(rereadSets.rows.map(\.id) == [late.id])
        let tombstones = try await pullAll(RemoteTombstoneRow.self, from: harness.store)
        #expect(Set(tombstones.map(\.rowId)) == Set(aggregate.removedSetIds + [aggregate.removedEntryIds[1]]))
    }

    /// An exercise a session still uses cannot be deleted; once the session is
    /// gone it can, so sessions are deleted before the exercises they use.
    static func exerciseInUseIsRefused(_ harness: RemoteStoreHarness) async throws {
        let exercise = RemoteExerciseRow(id: UUID(), userId: harness.userId, name: "Cable row", type: .strength)
        try await harness.store.upsert([exercise])
        var aggregate = finishedSession(for: harness.userId)
        aggregate.entries[0].exerciseId = exercise.id
        try await harness.store.pushSession(aggregate)

        do {
            try await harness.store.delete(.exercises, ids: [exercise.id])
            Issue.record("an exercise a session uses was deleted")
        } catch let RemoteStoreError.rejected(code, _) {
            #expect(code == "23503")
        }
        #expect(try await pullAll(RemoteExerciseRow.self, from: harness.store).contains { $0.id == exercise.id })

        try await harness.store.delete(.sessions, ids: [aggregate.session.id])
        try await harness.store.delete(.exercises, ids: [exercise.id])
        let exercises = try await pullAll(RemoteExerciseRow.self, from: harness.store)
        #expect(exercises.contains { $0.id == exercise.id } == false)
        #expect(try await pullAll(RemoteTombstoneRow.self, from: harness.store).contains {
            $0.deletedTable == .exercises && $0.rowId == exercise.id
        })
    }
}
