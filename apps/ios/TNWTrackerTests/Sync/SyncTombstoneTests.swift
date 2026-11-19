import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

/// S11 (local half): deleting a row that may exist on the server leaves a
/// tombstone; deleting one that never reached it leaves none. Set and entry
/// tombstones travel with their session's push; session tombstones stand alone.
@Suite("Local tombstones (S11)")
@MainActor
struct SyncTombstoneTests {
    let fx: TrainingFixtures
    let t0 = TrainingFixtures.t0

    init() throws {
        fx = try TrainingFixtures()
        try fx.store.ownership.claim(userId: UUID(), at: t0)
    }

    private var sync: any SyncStateRepositoryProtocol { fx.store.syncState }

    private func pending(_ id: UUID) throws -> PendingSyncAggregate {
        try #require(try sync.pendingSessions().first { $0.id == id })
    }

    /// Marks the session as sent at its current revision, as the push does before uploading.
    private func send(_ id: UUID) throws {
        #expect(try sync.markSent(.session, id: id, ifRevision: pending(id).revision))
    }

    /// A finished free session with two squat sets and one press set.
    private func finished() throws -> TrainingSession {
        let open = try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: TrainingFixtures.zone)
        for reps in [5, 6] {
            try fx.sessions.logManualSet(SetValues(reps: reps), exerciseId: fx.squat.id, sessionId: open.id, at: t0)
        }
        try fx.sessions.logManualSet(
            SetValues(reps: 8, weight: .kg(30)), exerciseId: fx.press.id, sessionId: open.id, at: t0
        )
        return try fx.sessions.finishSession(id: open.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
    }

    private func entry(_ session: TrainingSession, _ exercise: Exercise) throws -> SessionEntry {
        try #require(session.entries.first { $0.exerciseId == exercise.id })
    }

    // MARK: - Sets and entries

    @Test("deleting a set of a sent session leaves a tombstone that its next push carries and clears")
    func setTombstoneTravelsWithSession() throws {
        let session = try finished()
        try send(session.id)
        let removed = try #require(try entry(session, fx.squat).sets.first)

        try fx.sessions.deleteManualSet(id: removed.id)

        let next = try pending(session.id)
        #expect(next.removedSetIds == [removed.id])
        #expect(next.removedEntryIds.isEmpty)
        #expect(try sync.markSynced(.session, id: session.id, ifRevision: next.revision))
        try fx.sessions.setWarmup(true, setId: try #require(try entry(session, fx.squat).sets.last).id)
        #expect(try pending(session.id).removedSetIds.isEmpty, "an acknowledged tombstone is forgotten")
        #expect(try sync.tombstones().isEmpty, "set tombstones are not propagated on their own")
    }

    @Test("a tombstone created during the upload survives the stale acknowledgement")
    func tombstoneSurvivesStaleAcknowledgement() throws {
        let session = try finished()
        let pushed = try pending(session.id).revision
        #expect(try sync.markSent(.session, id: session.id, ifRevision: pushed))
        let removed = try #require(try entry(session, fx.squat).sets.first)

        try fx.sessions.deleteManualSet(id: removed.id)

        #expect(try sync.markSynced(.session, id: session.id, ifRevision: pushed) == false)
        #expect(try pending(session.id).removedSetIds == [removed.id])
    }

    @Test("deleting the last set of an unplanned entry of a sent session also leaves the entry's tombstone")
    func entryTombstone() throws {
        let session = try finished()
        try send(session.id)
        let press = try entry(session, fx.press)

        try fx.sessions.deleteManualSet(id: try #require(press.sets.first).id)

        let next = try pending(session.id)
        #expect(next.removedSetIds == press.sets.map(\.id))
        #expect(next.removedEntryIds == [press.id])
    }

    @Test("deleting rows that never reached the server leaves no tombstone")
    func neverSentLeavesNone() throws {
        let open = try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: TrainingFixtures.zone)
        let set = try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: open.id, at: t0)
        try fx.sessions.logManualSet(
            SetValues(reps: 9, weight: .kg(30)), exerciseId: fx.press.id, sessionId: open.id, at: t0
        )
        try fx.sessions.deleteManualSet(id: set.id)
        try fx.sessions.finishSession(id: open.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)

        let next = try pending(open.id)
        #expect(next.removedSetIds.isEmpty)
        #expect(next.removedEntryIds.isEmpty)
    }

    @Test("a stale markSent changes nothing, so a later delete leaves no tombstone")
    func staleMarkSentRefused() throws {
        let session = try finished()
        let stale = try pending(session.id).revision
        let squat = try entry(session, fx.squat)
        try fx.sessions.setWarmup(true, setId: try #require(squat.sets.last).id)

        #expect(try sync.markSent(.session, id: session.id, ifRevision: stale) == false)
        try fx.sessions.deleteManualSet(id: try #require(squat.sets.first).id)
        #expect(try pending(session.id).removedSetIds.isEmpty)
    }

    @Test("discarding a session in progress leaves no tombstone")
    func discardLeavesNone() throws {
        let open = try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: open.id, at: t0)

        try fx.sessions.discardSession(id: open.id)

        #expect(try sync.tombstones().isEmpty)
        #expect(try sync.pendingSessions().isEmpty)
    }

    // MARK: - Imports (D8)

    /// A completed session with one manual squat set and the imported press entry `e-7`.
    private func userSession() throws -> TrainingSession {
        let open = try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: open.id, at: t0)
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10, 9], weight: 40), into: open.id)
        return try fx.sessions.finishSession(id: open.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
    }

    @Test("a set moved by an import leaves a tombstone on the sent session it left, dropped when it comes back")
    func movedSetTombstone() throws {
        let first = try userSession()
        try send(first.id)
        let moved = try #require(try entry(first, fx.press).sets.first)
        let second = try fx.sessions.startSession(
            routineId: nil, name: nil, at: t0.addingTimeInterval(7200), timeZone: TrainingFixtures.zone
        )
        func regrouped(_ entryRef: String) -> ImportedEntry {
            ImportedEntry(exerciseId: fx.press.id, externalRef: fx.ref(entryRef), sets: [
                ImportedSet(externalRef: fx.ref("e-7#1"), order: 1, values: SetValues(reps: 10, weight: .kg(40)))
            ])
        }

        try fx.sessions.importEntry(regrouped("e-8"), into: second.id)
        #expect(try pending(first.id).removedSetIds == [moved.id])

        try fx.sessions.importEntry(regrouped("e-9"), into: first.id)
        #expect(try pending(first.id).removedSetIds.isEmpty, "the set is back in the session")
    }

    @Test("a set regrouped within the same sent session leaves no removed id")
    func sameSessionRegroupLeavesNone() throws {
        let first = try userSession()
        try send(first.id)
        let regrouped = ImportedEntry(exerciseId: fx.squat.id, externalRef: fx.ref("e-10"), sets: [
            ImportedSet(externalRef: fx.ref("e-7#1"), order: 1, values: SetValues(reps: 10, weight: .kg(40)))
        ])

        try fx.sessions.importEntry(regrouped, into: first.id)

        let next = try pending(first.id)
        #expect(next.removedSetIds.isEmpty, "the set is still in the session it was sent with")
        #expect(next.removedEntryIds.isEmpty)
    }

    @Test("an entry ref moved by an import marks the session it left as changed")
    func refOnlyMoveMarksVacatedSession() throws {
        let first = try userSession()
        let synced = try pending(first.id).revision
        #expect(try sync.markSynced(.session, id: first.id, ifRevision: synced))
        let second = try fx.sessions.startSession(
            routineId: nil, name: nil, at: t0.addingTimeInterval(7200), timeZone: TrainingFixtures.zone
        )
        let moved = ImportedEntry(exerciseId: fx.press.id, externalRef: fx.ref("e-7"), sets: [
            ImportedSet(externalRef: fx.ref("e-7#5"), order: 1, values: SetValues(reps: 10, weight: .kg(40)))
        ])

        try fx.sessions.importEntry(moved, into: second.id)

        let next = try pending(first.id)
        #expect(next.revision > synced, "the session lost its entry ref")
        #expect(next.removedSetIds.isEmpty)
        #expect(next.removedEntryIds.isEmpty)
    }

    /// Two import-only sessions on different days, then a re-import that regroups
    /// both entries under Monday, which removes Wednesday (D8).
    private func importThenRegroup(sendingWednesday: Bool) throws -> (monday: UUID, wednesday: UUID) {
        let press = Exercise(externalRef: fx.ref("ex-1"), name: "Chest Press Machine", type: .strength)
        func entry(_ ref: String) -> ImportedEntry {
            ImportedEntry(exerciseId: press.id, externalRef: fx.ref(ref), sets: [
                ImportedSet(externalRef: fx.ref("\(ref)#1"), order: 1, values: SetValues(reps: 10, weight: .kg(40)))
            ])
        }
        func session(_ ref: String, day: Double, _ entries: [ImportedEntry]) -> BundleSession {
            BundleSession(
                id: UUID(), externalRef: fx.ref(ref), completedAt: t0.addingTimeInterval(day * 86400),
                timeZone: "UTC", entries: entries
            )
        }
        let monday = session("w-1", day: 0, [entry("e-1")])
        let wednesday = session("w-2", day: 2, [entry("e-2")])
        let first = try fx.store.importer.importBundle(
            TrainingBundle(exercises: [press], sessions: [monday, wednesday])
        )
        let ids = try (#require(first.sessionIds[monday.id]), #require(first.sessionIds[wednesday.id]))
        if sendingWednesday { try send(ids.1) }
        try fx.store.importer.importBundle(
            TrainingBundle(exercises: [press], sessions: [session("w-1", day: 0, [entry("e-1"), entry("e-2")])])
        )
        #expect(try fx.sessions.session(id: ids.1) == nil)
        return ids
    }

    @Test("an import that removes a sent import-only session leaves its tombstone, cleared by compare")
    func removedImportedSessionTombstone() throws {
        let ids = try importThenRegroup(sendingWednesday: true)

        let tombstone = try #require(try sync.tombstones().first)
        #expect(try sync.tombstones().count == 1)
        #expect(tombstone.kind == .session)
        #expect(tombstone.id == ids.wednesday)
        #expect(try sync.pendingSessions().map(\.id) == [ids.monday])
        let saved = try ModelContext(fx.store.container).fetch(FetchDescriptor<SyncTombstoneModel>())
        #expect(saved.map(\.rowId) == [ids.wednesday], "the session's own entry and set tombstones went with it")

        var stale = tombstone
        stale.revision -= 1
        #expect(try sync.clearTombstone(stale) == false)
        #expect(try sync.clearTombstone(tombstone))
        #expect(try sync.tombstones().isEmpty)
    }

    @Test("an import that removes an import-only session that was never sent leaves no tombstone")
    func removedUnsentImportedSession() throws {
        _ = try importThenRegroup(sendingWednesday: false)
        #expect(try sync.tombstones().isEmpty)
    }
}
