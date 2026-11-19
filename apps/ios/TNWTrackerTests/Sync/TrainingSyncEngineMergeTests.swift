import Foundation
import Testing
@testable import TNWTrackerKit

/// How the pull merges server rows into data the device already holds (S8,
/// S13): the import rules, the conflict rule and local deletions. Real store
/// and repositories, in-memory server.
@Suite("Sync engine pull merge")
@MainActor
struct TrainingSyncEngineMergeTests {
    let world: PushWorld

    init() throws {
        world = try PushWorld()
    }

    private var store: TrainingStore { world.store }
    private var server: InMemoryTrainingRemoteStore { world.server }
    private var engine: TrainingSyncEngine { world.engine }

    /// A finished session pushed to the server, and the id of its squat entry.
    private func pushedSession() async throws -> (session: TrainingSession, entryId: UUID) {
        let session = try world.finishedSession()
        try await engine.push()
        let entryId = try #require(session.entries.first { $0.exerciseId == world.squat.id }?.id)
        return (session, entryId)
    }

    /// What an importer writing on the server does when its set belongs to the
    /// app's entry: the entry gains the import's ref, the set is added.
    private func importOnServer(into entryId: UUID, entryRef: String, set: RemoteSetRow) async throws {
        var entry = try await world.serverEntry(entryId)
        entry.externalRef = world.ref(entryRef)
        try await server.insertOnServer(entry)
        try await server.insertOnServer(set)
    }

    // MARK: - S8: the import rules

    @Test("an imported set pulled into an entry with manual sets ends as the in-app importer leaves it")
    func pullMergesLikeTheImporter() async throws {
        // The in-app importer, on another device with the same session.
        let inApp = try PushWorld()
        let local = try inApp.finishedSession()
        try inApp.store.sessions.importEntry(
            ImportedEntry(
                exerciseId: inApp.squat.id, externalRef: world.ref("e-9"),
                sets: [ImportedSet(
                    externalRef: world.ref("e-9#1"), order: 1, values: SetValues(reps: 10, weight: .kg(50)),
                    completedAt: world.t0.addingTimeInterval(900)
                )]
            ),
            into: local.id
        )
        // The pull: the same set, written on the server by an importer.
        let (session, entryId) = try await pushedSession()
        let set = world.importedSetRow(entryId: entryId, ref: "e-9#1", reps: 10, at: world.t0.addingTimeInterval(900))
        try await importOnServer(into: entryId, entryRef: "e-9", set: set)

        let report = try await engine.pull()

        let pulled = try world.session(session.id)
        #expect(SessionShape(pulled) == SessionShape(try inApp.session(local.id)))
        let entry = try #require(pulled.entries.first { $0.id == entryId })
        #expect(entry.reconciliation?.keep == .imported)
        #expect(entry.reconciliation?.decidedBy == .default)
        #expect(entry.sets.filter { $0.source == .manual }.allSatisfy { $0.superseded })
        #expect(entry.sets.first { $0.source == .imported }?.id == set.id)
        // The default decision is the device's: the session goes up again with it.
        #expect(report.changedLocally == [session.id])
        #expect(try world.isPending(session.id))
        try await engine.push()
        let serverEntry = try await world.serverEntry(entryId)
        #expect(serverEntry.reconciliationKeep == .imported)
        #expect(serverEntry.reconciliationDecidedBy == .default)
        let manual = await server.stored(RemoteSetRow.self).filter { $0.entryId == entryId && $0.source == .manual }
        #expect(manual.count == 2)
        #expect(manual.allSatisfy { $0.superseded })
        // Reading that push back changes nothing.
        try await engine.pull()
        try world.expectNothingPending()
    }

    @Test("a re-import on the server updates the set's values, never the device's reconciliation, superseded or warmup")
    func reimportKeepsTheDevicesChoices() async throws {
        let (session, entryId) = try await pushedSession()
        var set = world.importedSetRow(entryId: entryId, ref: "e-9#1", reps: 10, at: world.t0)
        try await importOnServer(into: entryId, entryRef: "e-9", set: set)
        try await engine.sync()
        try store.sessions.chooseReconciliation(entryId: entryId, keep: .manual, at: world.t0)
        try store.sessions.setWarmup(true, setId: set.id)
        try await engine.push()
        try world.expectNothingPending()
        // The importer writes raw values again: no decision, nothing superseded, no warm-up.
        var entry = try await world.serverEntry(entryId)
        entry.reconciliationKeep = nil
        entry.reconciliationDecidedBy = nil
        entry.reconciliationDecidedAt = nil
        try await server.insertOnServer(entry)
        set.reps = 12
        try await server.insertOnServer(set)

        let report = try await engine.pull()

        let local = try #require(try world.session(session.id).entries.first { $0.id == entryId })
        #expect(local.reconciliation?.keep == .manual)
        #expect(local.reconciliation?.decidedBy == .user)
        let imported = try #require(local.sets.first { $0.id == set.id })
        #expect(imported.values.reps == 12)
        #expect(imported.superseded)
        #expect(imported.warmup)
        #expect(local.sets.filter { $0.source == .manual }.allSatisfy { !$0.superseded })
        #expect(report.changedLocally == [session.id])
        try await engine.push()
        let pushed = try await world.serverSet(set.id)
        #expect(pushed.reps == 12)
        #expect(pushed.superseded)
        #expect(pushed.warmup)
        #expect(try await world.serverEntry(entryId).reconciliationKeep == .manual)
    }

    // MARK: - S13: the conflict rule

    @Test("a session with no local change takes the server's values")
    func cleanSessionTakesServerValues() async throws {
        let (session, entryId) = try await pushedSession()
        var row = try #require(await server.stored(RemoteSessionRow.self).first)
        row.notes = "Edited on the other phone"
        try await server.insertOnServer(row)
        let manualId = try #require(session.entries.first { $0.id == entryId }?.sets.first?.id)
        var manual = try await world.serverSet(manualId)
        manual.reps = 7
        try await server.insertOnServer(manual)

        let report = try await engine.pull()

        #expect(report.resolved == [
            .init(aggregate: .init(.exercise, id: world.squat.id), rule: .serverApplied),
            .init(aggregate: .init(.session, id: session.id), rule: .serverApplied)
        ])
        let local = try world.session(session.id)
        #expect(local.notes == "Edited on the other phone")
        #expect(local.entries.first { $0.id == entryId }?.sets.first { $0.id == manualId }?.values.reps == 7)
        try world.expectNothingPending()
    }

    @Test("a session with a local change keeps its edited fields, still merges imported sets, and pushes its version")
    func pendingSessionKeepsLocalValues() async throws {
        let (session, entryId) = try await pushedSession()
        let manualId = try #require(session.entries.first { $0.id == entryId }?.sets.first?.id)
        try store.sessions.updateManualSet(SetValues(reps: 9, weight: .kg(45)), setId: manualId)
        var row = try #require(await server.stored(RemoteSessionRow.self).first)
        row.notes = "Edited on the other phone"
        try await server.insertOnServer(row)
        var manual = try await world.serverSet(manualId)
        manual.reps = 7
        try await server.insertOnServer(manual)
        let imported = world.importedSetRow(entryId: entryId, ref: "e-9#1", reps: 10, at: world.t0)
        try await importOnServer(into: entryId, entryRef: "e-9", set: imported)

        let report = try await engine.pull()

        #expect(report.resolved.contains(.init(aggregate: .init(.session, id: session.id), rule: .localKept)))
        let local = try world.session(session.id)
        #expect(local.notes == nil)
        let entry = try #require(local.entries.first { $0.id == entryId })
        #expect(entry.sets.first { $0.id == manualId }?.values == SetValues(reps: 9, weight: .kg(45)))
        #expect(entry.sets.first { $0.id == imported.id }?.values.reps == 10)
        #expect(entry.externalRef == world.ref("e-9"))
        #expect(try world.isPending(session.id))
        try await engine.push()
        #expect(try await world.serverSet(manualId).reps == 9)
        #expect(await server.stored(RemoteSessionRow.self).first?.notes == nil)
        #expect(try await world.serverSet(imported.id).source == .imported)
        try world.expectNothingPending()
    }

    // MARK: - Local deletions and missing parents

    @Test("a set deleted on the device is not brought back by a pull before its deletion is pushed")
    func deletedSetIsNotResurrected() async throws {
        let (session, entryId) = try await pushedSession()
        let deleted = try #require(session.entries.first { $0.id == entryId }?.sets.last?.id)
        try store.sessions.deleteManualSet(id: deleted)

        let report = try await engine.pull()

        #expect(report.skipped.contains(.init(table: .sets, id: deleted, reason: .deletedOnDevice)))
        #expect(try world.session(session.id).entries.flatMap(\.sets).contains { $0.id == deleted } == false)
        try await engine.push()
        #expect(await server.stored(RemoteSetRow.self).contains { $0.id == deleted } == false)
        try world.expectNothingPending()
    }

    @Test("a row whose parent the device does not hold is skipped and keeps its table's cursor before it")
    func missingParentHoldsTheCursor() async throws {
        let (session, entryId) = try await pushedSession()
        let held = RemoteSetRow(
            id: UUID(), userId: world.userId, entryId: UUID(), position: 1, source: .imported, reps: 5,
            externalRef: world.ref("x#1"), updatedAt: "2026-01-01T00:00:02.000000+00:00"
        )
        var first = world.importedSetRow(entryId: entryId, ref: "e-9#1", reps: 10, at: world.t0)
        first.updatedAt = "2026-01-01T00:00:01.000000+00:00"
        var after = world.importedSetRow(entryId: entryId, ref: "e-9#2", reps: 11, position: 2, at: world.t0)
        after.updatedAt = "2026-01-01T00:00:03.000000+00:00"

        let report = try store.pulled.apply(PulledBatch(sets: [first, held, after]), userId: world.userId)

        #expect(report.skipped == [.init(table: .sets, id: held.id, reason: .missingParent)])
        #expect(try store.pulled.cursor(.sets, userId: world.userId) == RemoteCursor(
            updatedAt: "2026-01-01T00:00:01.000000+00:00", id: first.id
        ))
        let sets = try #require(try world.session(session.id).entries.first { $0.id == entryId }?.sets)
        #expect(Set(sets.map(\.id)).isSuperset(of: [first.id, after.id]))
        // Held again as the first row read: the cursor does not move.
        _ = try store.pulled.apply(PulledBatch(sets: [held]), userId: world.userId)
        #expect(try store.pulled.cursor(.sets, userId: world.userId)?.id == first.id)
    }

    @Test("a set that breaks a rule of the format, or an imported set without a ref, is passed over")
    func invalidRowsArePassedOver() async throws {
        let (session, entryId) = try await pushedSession()
        let noValues = RemoteSetRow(
            id: UUID(), userId: world.userId, entryId: entryId, position: 3, source: .manual,
            updatedAt: "2026-01-01T00:00:01.000000+00:00"
        )
        let noRef = RemoteSetRow(
            id: UUID(), userId: world.userId, entryId: entryId, position: 1, source: .imported, reps: 5,
            updatedAt: "2026-01-01T00:00:02.000000+00:00"
        )

        let report = try store.pulled.apply(PulledBatch(sets: [noValues, noRef]), userId: world.userId)

        #expect(report.skipped == [
            .init(table: .sets, id: noRef.id, reason: .invalid("an imported set needs an external ref")),
            .init(table: .sets, id: noValues.id, reason: .invalid(String(
                describing: TrainingDataError.invalidSet("a set needs reps or a duration")
            )))
        ])
        #expect(try store.pulled.cursor(.sets, userId: world.userId)?.id == noRef.id)
        #expect(try world.session(session.id) == session)
    }
}
