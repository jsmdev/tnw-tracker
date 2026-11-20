import Foundation
import Testing
@testable import TNWTrackerKit

/// S11 and S4 around the cursors: rows of a session the device deleted, late
/// imports under a removed entry, and failures reading the tombstones.
extension TrainingSyncEngineDeleteTests {
    // MARK: - Cursors (L8)

    @Test("rows of a session deleted on the device are passed over, not held, while its deletion waits")
    func deletedSessionRowsDoNotStall() async throws {
        let ids = try await world.importThenRegroup()
        let wednesday = await server.stored(RemoteEntryRow.self).filter { $0.sessionId == ids.wednesday }
        let entry = try #require(wednesday.first)
        let set = try #require(await server.stored(RemoteSetRow.self).first { $0.entryId == entry.id })

        let report = try await engine.pull()

        #expect(report.skipped.contains(.init(table: .entries, id: entry.id, reason: .deletedOnDevice)))
        #expect(report.skipped.contains(.init(table: .sets, id: set.id, reason: .deletedOnDevice)))
        #expect(!report.skipped.contains { $0.reason == .missingParent })
        let lastEntry = try #require(await server.stored(RemoteEntryRow.self).last)
        #expect(try store.pulled.cursor(.entries, userId: world.userId)?.id == lastEntry.id)
        let lastSet = try #require(await server.stored(RemoteSetRow.self).last)
        #expect(try store.pulled.cursor(.sets, userId: world.userId)?.id == lastSet.id)
    }

    // MARK: - Late imports (L5 item 2)

    @Test("a set imported on the server into an entry the device removed comes back with it, instead of being lost")
    func lateImportSurvivesEntryRemoval() async throws {
        let session = try world.finishedSession()
        try await engine.sync()
        let entry = try #require(session.entries.first)
        let late = world.importedSetRow(
            entryId: entry.id, ref: "late#1", reps: 10, at: world.t0.addingTimeInterval(900)
        )
        try await server.insertOnServer(late)
        for set in entry.sets {
            try store.sessions.deleteManualSet(id: set.id)
        }
        #expect(try world.session(session.id).entries.isEmpty)

        try await engine.sync()

        #expect(await server.stored(RemoteEntryRow.self).map(\.id) == [entry.id])
        #expect(await server.stored(RemoteSetRow.self).map(\.id) == [late.id])
        let back = try #require(try world.session(session.id).entries.first)
        #expect(back.id == entry.id)
        #expect(back.sets.map(\.id) == [late.id])
        #expect(back.sets.first?.source == .imported)
        try world.expectNothingPending()
    }

    // MARK: - S4 on the pull

    @Test("a failure reading the tombstones deletes nothing and keeps every cursor")
    func tombstoneReadFailure() async throws {
        let session = try world.finishedSession()
        try await engine.sync()
        let cursors = try RemoteTable.allCases.map { try store.pulled.cursor($0, userId: world.userId) }
        try await server.deleteOnServer(.sessions, ids: [session.id])
        await server.failNextPull(of: .tombstones)

        await #expect(throws: URLError.self) { try await engine.pull() }

        #expect(try store.sessions.session(id: session.id) != nil)
        #expect(try RemoteTable.allCases.map { try store.pulled.cursor($0, userId: world.userId) } == cursors)
        try await engine.pull()
        #expect(try store.sessions.session(id: session.id) == nil)
        #expect(try store.pulled.cursor(.tombstones, userId: world.userId) != nil)
        // Read again in the overlap, the tombstones change nothing.
        let again = try await engine.pull()
        #expect(again.deletions.isEmpty)
        try world.expectNothingPending()
    }
}
