import Foundation
import Testing
@testable import TNWTrackerKit

/// What a test needs to run the contract against one `TrainingRemoteStore`.
struct RemoteStoreHarness: Sendable {
    let store: any TrainingRemoteStore
    let userId: UUID
    /// Writes an imported set as an importer would, outside the app.
    let insertImportedSet: @Sendable (RemoteSetRow) async throws -> Void
}

/// Behaviour every `TrainingRemoteStore` keeps. The same scenarios run against
/// the in-memory fake (`InMemoryTrainingRemoteStoreTests`) and the real adapter
/// on the local Supabase stack (`SupabaseTrainingRemoteStoreContractTests`), so
/// the fake cannot drift from the server.
enum TrainingRemoteStoreContract {
    /// Catalogue exercises of supabase/seed.sql: a strength one and another.
    static let benchPress = UUID(uuidString: "e1000001-0000-4000-8000-000000000001") ?? UUID()
    static let shoulderPress = UUID(uuidString: "e1000002-0000-4000-8000-000000000002") ?? UUID()

    // MARK: - Scenarios

    /// S1 at the boundary: a pushed session, its entries and sets read back unchanged.
    static func pushedSessionReadsBack(_ harness: RemoteStoreHarness) async throws {
        let aggregate = finishedSession(for: harness.userId)

        try await harness.store.pushSession(aggregate)

        let sessions = try await pullAll(RemoteSessionRow.self, from: harness.store)
        let entries = try await pullAll(RemoteEntryRow.self, from: harness.store)
        let sets = try await pullAll(RemoteSetRow.self, from: harness.store)
        #expect(sessions.map(withoutServerFields) == [aggregate.session])
        #expect(Set(entries.map(withoutServerFields).map(\.id)) == Set(aggregate.entries.map(\.id)))
        #expect(entries.map(withoutServerFields).sorted(by: byPosition) == aggregate.entries)
        #expect(sets.map(withoutServerFields).sorted(by: byPosition) == aggregate.sets)
        #expect((sessions.map(\.updatedAt) + entries.map(\.updatedAt) + sets.map(\.updatedAt)).allSatisfy { $0 != nil })
    }

    /// Pushing again overwrites every column, a value cleared on the device included.
    static func rePushClearsValues(_ harness: RemoteStoreHarness) async throws {
        var aggregate = finishedSession(for: harness.userId)
        try await harness.store.pushSession(aggregate)

        aggregate.session.notes = nil
        aggregate.session.name = "Renamed"
        aggregate.sets[0].rir = nil
        aggregate.sets[0].weight = nil
        try await harness.store.pushSession(aggregate)

        let sessions = try await pullAll(RemoteSessionRow.self, from: harness.store)
        let sets = try await pullAll(RemoteSetRow.self, from: harness.store)
        #expect(sessions.map(withoutServerFields) == [aggregate.session])
        #expect(sessions.first?.notes == nil)
        #expect(sets.map(withoutServerFields).sorted(by: byPosition) == aggregate.sets)
        #expect(sets.first { $0.id == aggregate.sets[0].id }?.rir == nil)
        #expect(sets.first { $0.id == aggregate.sets[0].id }?.weight == nil)
    }

    /// A done entry whose sets were all deleted on the device turns skipped: the
    /// removed sets go first, or the server refuses a skipped entry with sets.
    static func rePushRemovesSetsBeforeSkippingEntry(_ harness: RemoteStoreHarness) async throws {
        var aggregate = finishedSession(for: harness.userId)
        try await harness.store.pushSession(aggregate)

        aggregate.removedSetIds = aggregate.sets.map(\.id)
        aggregate.sets = []
        aggregate.entries[0].status = .skipped
        aggregate.entries[0].completedAt = nil
        try await harness.store.pushSession(aggregate)

        let entries = try await pullAll(RemoteEntryRow.self, from: harness.store)
        let sets = try await pullAll(RemoteSetRow.self, from: harness.store)
        #expect(entries.map(withoutServerFields).sorted(by: byPosition) == aggregate.entries)
        #expect(sets.isEmpty)
    }

    /// Removed ids only delete rows still in the pushed session on the server,
    /// never a row another session holds now.
    static func removedIdsNeverReachAnotherSession(_ harness: RemoteStoreHarness) async throws {
        let other = finishedSession(for: harness.userId)
        var aggregate = finishedSession(for: harness.userId)
        try await harness.store.pushSession(other)
        try await harness.store.pushSession(aggregate)

        aggregate.removedSetIds = [other.sets[0].id]
        aggregate.removedEntryIds = [other.entries[1].id]
        try await harness.store.pushSession(aggregate)

        let entries = try await pullAll(RemoteEntryRow.self, from: harness.store)
        let sets = try await pullAll(RemoteSetRow.self, from: harness.store)
        #expect(Set(entries.map(\.id)) == Set((other.entries + aggregate.entries).map(\.id)))
        #expect(Set(sets.map(\.id)) == Set((other.sets + aggregate.sets).map(\.id)))
    }

    /// S2 at the boundary: a set an importer writes after the last pull comes
    /// back from the cursor, and only it.
    static func importedSetArrivesAfterCursor(_ harness: RemoteStoreHarness) async throws {
        let aggregate = finishedSession(for: harness.userId)
        try await harness.store.pushSession(aggregate)
        let first = try await harness.store.pull(RemoteSetRow.self, after: nil, limit: 100)
        let cursor = try #require(first.next)

        let imported = RemoteSetRow(
            id: UUID(),
            userId: harness.userId,
            entryId: aggregate.entries[0].id,
            position: 1,
            source: .imported,
            reps: 12,
            weight: .kg(40),
            completedAt: date(minute: 20),
            externalRef: ExternalRef(provider: "machines-atlas", id: "set-\(UUID().uuidString)")
        )
        try await harness.insertImportedSet(imported)

        let page = try await harness.store.pull(RemoteSetRow.self, after: cursor, limit: 100)
        #expect(page.rows.map(withoutServerFields) == [imported])
        #expect(page.mayHaveMore == false)
        let next = try #require(page.next)
        #expect(next.id == imported.id)
        let after = try await harness.store.pull(RemoteSetRow.self, after: next, limit: 100)
        #expect(after.rows.isEmpty)
        #expect(after.next == nil)
    }

    /// Rows written in one statement share `updated_at`; the id breaks the tie,
    /// so paging one row at a time returns each exactly once, in a stable order.
    static func rowsWrittenTogetherPageOneByOne(_ harness: RemoteStoreHarness) async throws {
        var aggregate = finishedSession(for: harness.userId)
        aggregate.sets.append(manualSet(position: 3, entry: aggregate.entries[0], reps: 6))
        try await harness.store.pushSession(aggregate)

        var cursor: RemoteCursor?
        var seen: [RemoteSetRow] = []
        for _ in 0 ..< 10 {
            let page = try await harness.store.pull(RemoteSetRow.self, after: cursor, limit: 1)
            guard let next = page.next else { break }
            #expect(page.rows.count == 1)
            #expect(page.mayHaveMore)
            seen += page.rows
            cursor = next
        }
        #expect(seen.count == 3)
        #expect(Set(seen.compactMap(\.updatedAt)).count == 1)
        let idOrder = aggregate.sets.map(\.id).sorted { $0.uuidString.lowercased() < $1.uuidString.lowercased() }
        #expect(seen.map(\.id) == idOrder)
    }

    /// An aggregate with a row of another session is refused before any write.
    static func inconsistentAggregateWritesNothing(_ harness: RemoteStoreHarness) async throws {
        var aggregate = finishedSession(for: harness.userId)
        aggregate.sets[0].entryId = UUID()

        await #expect(throws: RemoteStoreError.self) {
            try await harness.store.pushSession(aggregate)
        }

        let sessions = try await pullAll(RemoteSessionRow.self, from: harness.store)
        #expect(sessions.isEmpty)
    }

    // MARK: - Fixtures

    /// A finished session: a done strength entry with two manual sets, then a
    /// skipped entry. Whole-second dates, so they survive the round trip exactly.
    static func finishedSession(for userId: UUID) -> RemoteSessionAggregate {
        let session = RemoteSessionRow(
            id: UUID(),
            userId: userId,
            name: "Upper body",
            notes: "Felt strong",
            startedAt: date(minute: 0),
            completedAt: date(minute: 45),
            timeZone: "Europe/Madrid",
            durationSeconds: 2_400
        )
        let done = RemoteEntryRow(
            id: UUID(), userId: userId, sessionId: session.id, position: 1,
            exerciseId: benchPress, status: .done, completedAt: date(minute: 30), notes: "Smooth"
        )
        let skipped = RemoteEntryRow(
            id: UUID(), userId: userId, sessionId: session.id, position: 2,
            exerciseId: shoulderPress, status: .skipped
        )
        var heavy = manualSet(position: 1, entry: done, reps: 8)
        heavy.weight = Weight(value: 82.5, unit: .kg)
        heavy.rir = 2
        heavy.restSeconds = 90
        var warmup = manualSet(position: 2, entry: done, reps: 10)
        warmup.warmup = true
        return RemoteSessionAggregate(session: session, entries: [done, skipped], sets: [heavy, warmup])
    }

    static func manualSet(position: Int, entry: RemoteEntryRow, reps: Int) -> RemoteSetRow {
        RemoteSetRow(
            id: UUID(), userId: entry.userId, entryId: entry.id, position: position,
            source: .manual, reps: reps, completedAt: date(minute: 10 + position)
        )
    }

    static func date(minute: Int) -> Date {
        Date(timeIntervalSince1970: 1_795_000_000 + TimeInterval(minute * 60))
    }

    // MARK: - Helpers

    static func pullAll<Row: RemoteRow>(_ type: Row.Type, from store: any TrainingRemoteStore) async throws -> [Row] {
        var rows: [Row] = []
        var cursor: RemoteCursor?
        repeat {
            let page = try await store.pull(type, after: cursor, limit: 2)
            rows += page.rows
            cursor = page.mayHaveMore ? page.next : nil
        } while cursor != nil
        return rows
    }

    static func withoutServerFields<Row: RemoteRow>(_ row: Row) -> Row {
        var row = row
        row.updatedAt = nil
        return row
    }

    private static func byPosition(_ lhs: RemoteEntryRow, _ rhs: RemoteEntryRow) -> Bool {
        lhs.position < rhs.position
    }

    private static func byPosition(_ lhs: RemoteSetRow, _ rhs: RemoteSetRow) -> Bool {
        (lhs.source.rawValue, lhs.position) < (rhs.source.rawValue, rhs.position)
    }
}
