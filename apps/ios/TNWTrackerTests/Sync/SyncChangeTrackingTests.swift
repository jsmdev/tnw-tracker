import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

/// S7, S3, S4: every command that changes user data marks its aggregate pending
/// in the same save. A session is ready to push only once completed, and it is
/// marked synced only at the revision the server acknowledged.
@Suite("Sync change tracking (S7)")
@MainActor
struct SyncChangeTrackingTests {
    let fx: TrainingFixtures
    let t0 = TrainingFixtures.t0

    init() throws {
        fx = try TrainingFixtures()
        try fx.store.ownership.claim(userId: UUID(), at: t0)
    }

    private var sync: any SyncStateRepositoryProtocol { fx.store.syncState }

    /// The session's sync state as saved, read through a context of its own.
    struct SavedState {
        var revision: Int
        var synced: Int
        var syncable: Bool
    }

    private func saved(_ id: UUID) throws -> SavedState {
        let context = ModelContext(fx.store.container)
        let descriptor = FetchDescriptor<SessionModel>(predicate: #Predicate { $0.id == id })
        let model = try #require(try context.fetch(descriptor).first)
        return SavedState(revision: model.syncRevision, synced: model.syncedRevision, syncable: model.isSyncable)
    }

    private func start(at offset: TimeInterval = 0) throws -> TrainingSession {
        try fx.sessions.startSession(
            routineId: nil, name: nil, at: t0.addingTimeInterval(offset), timeZone: TrainingFixtures.zone
        )
    }

    private func finished(at offset: TimeInterval = 0) throws -> TrainingSession {
        let session = try start(at: offset)
        try fx.sessions.logManualSet(
            SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: session.id, at: t0.addingTimeInterval(offset)
        )
        return try fx.sessions.finishSession(
            id: session.id, at: t0.addingTimeInterval(offset + 1800), durationSeconds: nil
        )
    }

    private func pendingRevision(_ id: UUID) throws -> Int? {
        try sync.pendingSessions().first { $0.id == id }?.revision
    }

    // MARK: - Sessions

    @Test("a session in progress is tracked in the same save but is not ready to push")
    func inProgressIsTrackedNotPending() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: session.id, at: t0)

        let state = try saved(session.id)
        #expect(state.syncable)
        #expect(state.revision > state.synced)
        #expect(try sync.pendingSessions().isEmpty)
    }

    @Test("a finished session is ready to push with the revision that was saved")
    func finishedIsPending() throws {
        let session = try finished()
        let state = try saved(session.id)
        let expected = PendingSyncAggregate(kind: .session, id: session.id, revision: state.revision)
        #expect(try sync.pendingSessions() == [expected])
    }

    @Test("marking synced at the pushed revision clears the session")
    func markSyncedClears() throws {
        let session = try finished()
        let revision = try #require(try pendingRevision(session.id))

        #expect(try sync.markSynced(.session, id: session.id, ifRevision: revision))

        #expect(try sync.pendingSessions().isEmpty)
        #expect(try saved(session.id).synced == revision)
    }

    @Test("an edit during the upload keeps the session pending at its new revision")
    func editDuringUploadStaysPending() throws {
        let session = try finished()
        let pushed = try #require(try pendingRevision(session.id))
        let set = try #require(session.entries.first?.sets.first)

        try fx.sessions.setWarmup(true, setId: set.id)

        #expect(try sync.markSynced(.session, id: session.id, ifRevision: pushed) == false)
        let current = try #require(try pendingRevision(session.id))
        #expect(current > pushed)
        #expect(try saved(session.id).synced == 0)
        #expect(try sync.markSynced(.session, id: session.id, ifRevision: current))
        #expect(try sync.pendingSessions().isEmpty)
    }

    /// Commands that change a completed session.
    enum CompletedCommand: String, CaseIterable {
        case setWarmup, updateManualSet, deleteManualSet, replaceExercise, removeEntry, importEntry,
             chooseReconciliation
    }

    @Test("every command that changes a completed session marks it pending again", arguments: CompletedCommand.allCases)
    func completedCommandsMarkPending(_ command: CompletedCommand) throws {
        let routine = Routine(name: "Full Body A", items: [
            RoutineItem(order: 1, exerciseId: fx.squat.id),
            RoutineItem(order: 2, exerciseId: fx.press.id),
            RoutineItem(order: 3, exerciseId: fx.plank.id)
        ])
        try fx.routines.save(routine)
        let open = try fx.sessions.startSession(
            routineId: routine.id, name: nil, at: t0, timeZone: TrainingFixtures.zone
        )
        let squatSet = try fx.sessions.logManualSet(
            SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: open.id, at: t0
        )
        try fx.sessions.logManualSet(
            SetValues(reps: 8, weight: .kg(30)), exerciseId: fx.press.id, sessionId: open.id, at: t0
        )
        try fx.sessions.importEntry(fx.importedSets("e-1", reps: [10], weight: 40), into: open.id)
        let session = try fx.sessions.finishSession(id: open.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
        let synced = try #require(try pendingRevision(session.id))
        try sync.markSynced(.session, id: session.id, ifRevision: synced)
        let entries = Dictionary(uniqueKeysWithValues: session.entries.map { ($0.exerciseId, $0) })
        let press = try #require(entries[fx.press.id])

        switch command {
        case .setWarmup: try fx.sessions.setWarmup(true, setId: squatSet.id)
        case .updateManualSet: try fx.sessions.updateManualSet(SetValues(reps: 6), setId: squatSet.id)
        case .deleteManualSet: try fx.sessions.deleteManualSet(id: squatSet.id)
        case .replaceExercise:
            try fx.sessions.replaceExercise(entryId: try #require(entries[fx.plank.id]).id, with: fx.rower.id)
        case .removeEntry: try fx.sessions.removeEntry(id: press.id)
        case .importEntry:
            try fx.sessions.importEntry(fx.importedSets("e-1", reps: [10, 9], weight: 40), into: session.id)
        case .chooseReconciliation: try fx.sessions.chooseReconciliation(entryId: press.id, keep: .manual, at: t0)
        }

        let state = try saved(session.id)
        #expect(state.revision > synced, "the change is saved with its mark")
        #expect(try pendingRevision(session.id) == state.revision)
    }

    @Test("an import marks the session it joins and tracks the session it creates")
    func importMarksSessions() throws {
        let logged = try finished()
        try sync.markSynced(.session, id: logged.id, ifRevision: try #require(try pendingRevision(logged.id)))
        let press = Exercise(externalRef: fx.ref("ex-1"), name: "Chest Press Machine", type: .strength)
        func entry(_ ref: String) -> ImportedEntry {
            ImportedEntry(exerciseId: press.id, externalRef: fx.ref(ref), sets: [
                ImportedSet(externalRef: fx.ref("\(ref)#1"), order: 1, values: SetValues(reps: 10, weight: .kg(40)))
            ])
        }
        let sameDay = BundleSession(
            id: UUID(), externalRef: fx.ref("w-1"), completedAt: t0.addingTimeInterval(3600), timeZone: "UTC",
            entries: [entry("e-1")]
        )
        let nextDay = BundleSession(
            id: UUID(), externalRef: fx.ref("w-2"), completedAt: t0.addingTimeInterval(86400), timeZone: "UTC",
            entries: [entry("e-2")]
        )

        let bundle = TrainingBundle(exercises: [press], sessions: [sameDay, nextDay])
        let result = try fx.store.importer.importBundle(bundle)

        let created = try #require(result.sessionIds[nextDay.id])
        #expect(result.sessionIds[sameDay.id] == logged.id)
        #expect(try sync.pendingSessions().map(\.id) == [logged.id, created])
    }

    @Test("pending sessions come in completion order")
    func pendingInCompletionOrder() throws {
        let second = try finished(at: 7200)
        let first = try finished(at: 0)
        let third = try finished(at: 14400)
        #expect(try sync.pendingSessions().map(\.id) == [first.id, second.id, third.id])
    }

    // MARK: - Routines, exercises and settings

    @Test("routines, user exercises and exercise settings are tracked; catalogue and unowned exercises never")
    func otherAggregatesTracked() throws {
        #expect(try sync.pending(.exercise).isEmpty, "the fixtures' exercises were saved before the claim")
        let own = Exercise(name: "Cable Row", type: .strength)
        try fx.exercises.save(own)
        try fx.exercises.save(Exercise(isCatalogue: true, name: "Deadlift", type: .strength))
        let routine = try fx.makeRoutine()
        try fx.store.exerciseSettings.save(
            ExerciseSetting(exerciseId: fx.squat.id, restEnabled: false, restSeconds: 60)
        )

        let exercise = try #require(try sync.pending(.exercise).first)
        #expect(try sync.pending(.exercise).map(\.id) == [own.id])
        let saved = try #require(try sync.pending(.routine).first)
        #expect(saved.id == routine.id)
        let setting = try #require(try sync.pending(.exerciseSetting).first)
        #expect(setting.id == fx.squat.id)

        try fx.routines.setFavorite(true, routineId: routine.id)
        let favorite = try #require(try sync.pending(.routine).first)
        #expect(favorite.revision > saved.revision)
        #expect(try sync.markSynced(.routine, id: routine.id, ifRevision: saved.revision) == false)

        #expect(try sync.markSynced(.routine, id: routine.id, ifRevision: favorite.revision))
        #expect(try sync.markSynced(.exercise, id: own.id, ifRevision: exercise.revision))
        #expect(try sync.markSynced(.exerciseSetting, id: fx.squat.id, ifRevision: setting.revision))
        #expect(try SyncAggregateKind.allCases.allSatisfy { try sync.pending($0).isEmpty })
    }
}
