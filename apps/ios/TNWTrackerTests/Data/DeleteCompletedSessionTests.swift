import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

/// #174 S7: deleting a finished workout from the history. Only a workout
/// without imported data can be deleted: an import would bring the other back.
@Suite("Deleting a completed session")
@MainActor
struct DeleteCompletedSessionTests {
    let fx: TrainingFixtures
    let t0 = TrainingFixtures.t0

    init() throws {
        fx = try TrainingFixtures()
        try fx.store.ownership.claim(userId: UUID(), at: t0)
    }

    private var sync: any SyncStateRepositoryProtocol { fx.store.syncState }

    /// A finished free session with manual sets only.
    private func finishedManual() throws -> TrainingSession {
        let open = try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: open.id, at: t0)
        try fx.sessions.logManualSet(
            SetValues(reps: 8, weight: .kg(30)), exerciseId: fx.press.id, sessionId: open.id, at: t0
        )
        return try fx.sessions.finishSession(id: open.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
    }

    private func send(_ id: UUID) throws {
        let pending = try #require(try sync.pendingSessions().first { $0.id == id })
        #expect(try sync.markSent(.session, id: id, ifRevision: pending.revision))
    }

    private func storedRows() throws -> (entries: Int, sets: Int) {
        let context = ModelContext(fx.store.container)
        return try (
            context.fetchCount(FetchDescriptor<SessionEntryModel>()),
            context.fetchCount(FetchDescriptor<ExerciseSetModel>())
        )
    }

    @Test("a finished manual workout is deleted with its entries and sets, and leaves the history")
    func deletesManualSession() throws {
        let session = try finishedManual()
        #expect(session.hasImportedData == false)

        try fx.sessions.deleteCompletedSession(id: session.id)

        #expect(try fx.sessions.session(id: session.id) == nil)
        #expect(try fx.sessions.completedSessions(in: DateInterval(start: .distantPast, end: .distantFuture)).isEmpty)
        let rows = try storedRows()
        #expect(rows.entries == 0)
        #expect(rows.sets == 0)
    }

    @Test("deleting a sent workout leaves one session tombstone; an unsent one leaves none")
    func tombstoneOnlyWhenSent() throws {
        let sent = try finishedManual()
        try send(sent.id)
        let unsent = try finishedManual()

        try fx.sessions.deleteCompletedSession(id: sent.id)
        try fx.sessions.deleteCompletedSession(id: unsent.id)

        let tombstones = try sync.tombstones()
        #expect(tombstones.map(\.id) == [sent.id])
        #expect(try sync.pendingSessions().contains { $0.id == sent.id || $0.id == unsent.id } == false)
    }

    @Test("a workout with imported sets is not deleted")
    func refusesMixedSession() throws {
        let open = try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: open.id, at: t0)
        try fx.sessions.importEntry(
            ImportedEntry(exerciseId: fx.press.id, externalRef: fx.ref("e-1"), sets: [
                ImportedSet(externalRef: fx.ref("e-1#1"), order: 1, values: SetValues(reps: 10, weight: .kg(40)))
            ]),
            into: open.id
        )
        let session = try fx.sessions.finishSession(id: open.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
        #expect(session.hasImportedData)

        #expect(throws: TrainingDataError.sessionHasImportedData) {
            try fx.sessions.deleteCompletedSession(id: session.id)
        }
        #expect(try fx.sessions.session(id: session.id) == session)
    }

    @Test("an imported workout is not deleted")
    func refusesImportedSession() throws {
        let press = Exercise(externalRef: fx.ref("ex-1"), name: "Chest Press Machine", type: .strength)
        let bundled = BundleSession(
            id: UUID(), externalRef: fx.ref("w-1"), completedAt: t0, timeZone: "UTC",
            entries: [ImportedEntry(exerciseId: press.id, externalRef: fx.ref("e-1"), sets: [
                ImportedSet(externalRef: fx.ref("e-1#1"), order: 1, values: SetValues(reps: 10, weight: .kg(40)))
            ])]
        )
        let result = try fx.store.importer.importBundle(TrainingBundle(exercises: [press], sessions: [bundled]))
        let id = try #require(result.sessionIds[bundled.id])
        #expect(try #require(try fx.sessions.session(id: id)).hasImportedData)

        #expect(throws: TrainingDataError.sessionHasImportedData) {
            try fx.sessions.deleteCompletedSession(id: id)
        }
        #expect(try fx.sessions.session(id: id) != nil)
    }

    @Test("a workout in progress is not deleted from the history: it is discarded")
    func refusesSessionInProgress() throws {
        let open = try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: TrainingFixtures.zone)
        #expect(throws: TrainingDataError.sessionInProgress) {
            try fx.sessions.deleteCompletedSession(id: open.id)
        }
        #expect(try fx.sessions.activeSession()?.id == open.id)
    }

    @Test("an unknown workout is not found")
    func unknownSession() {
        #expect(throws: TrainingDataError.notFound) {
            try fx.sessions.deleteCompletedSession(id: UUID())
        }
    }
}

/// Each way a session can hold imported data on its own, so no condition of
/// `hasImportedData` hides behind another (#174 S7, L4).
@Suite("TrainingSession.hasImportedData")
@MainActor
struct HasImportedDataTests {
    let ref = ExternalRef(provider: TrainingFixtures.provider, id: "x-1")
    let exerciseId = UUID()

    private func manualSet() -> ExerciseSet {
        ExerciseSet(order: 1, source: .manual, values: SetValues(reps: 5))
    }

    private func session(sessionRef: ExternalRef? = nil, entries: [SessionEntry]) -> TrainingSession {
        TrainingSession(externalRef: sessionRef, completedAt: TrainingFixtures.t0, timeZone: "UTC", entries: entries)
    }

    @Test("manual sets only: no imported data")
    func manualOnly() {
        let entry = SessionEntry(exerciseId: exerciseId, order: 1, status: .done, sets: [manualSet()])
        #expect(session(entries: [entry]).hasImportedData == false)
    }

    @Test("only the session has a ref")
    func sessionRefOnly() {
        let entry = SessionEntry(exerciseId: exerciseId, order: 1, status: .done, sets: [manualSet()])
        #expect(session(sessionRef: ref, entries: [entry]).hasImportedData)
    }

    @Test("only an entry has a ref, its imported sets moved elsewhere")
    func entryRefOnly() {
        let entry = SessionEntry(externalRef: ref, exerciseId: exerciseId, order: 1, status: .done, sets: [manualSet()])
        #expect(session(entries: [entry]).hasImportedData)
    }

    @Test("only a set is imported")
    func importedSetOnly() {
        let set = ExerciseSet(order: 1, source: .imported, values: SetValues(reps: 5))
        let entry = SessionEntry(exerciseId: exerciseId, order: 1, status: .done, sets: [set])
        #expect(session(entries: [entry]).hasImportedData)
    }

    @Test("a removed entry with an imported set still counts")
    func removedEntryCounts() {
        let set = ExerciseSet(order: 1, source: .imported, values: SetValues(reps: 5), superseded: true)
        let removed = SessionEntry(exerciseId: exerciseId, order: 1, status: .removed, sets: [set])
        let manual = SessionEntry(exerciseId: UUID(), order: 2, status: .done, sets: [manualSet()])
        #expect(session(entries: [removed, manual]).hasImportedData)
    }
}
