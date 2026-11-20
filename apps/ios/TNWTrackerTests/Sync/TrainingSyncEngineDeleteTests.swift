import Foundation
import Testing
@testable import TNWTrackerKit

/// S11: deletes propagate both ways, against the in-memory server (which
/// records tombstones as the server's triggers do), with the real store.
@Suite("Sync engine deletes")
@MainActor
struct TrainingSyncEngineDeleteTests {
    let world: PushWorld

    init() throws {
        world = try PushWorld()
    }

    var store: TrainingStore { world.store }
    var server: InMemoryTrainingRemoteStore { world.server }
    var engine: TrainingSyncEngine { world.engine }

    // MARK: - Push: deletions made on the device

    @Test("a session deleted on the device is deleted on the server with its rows, and its tombstone goes")
    func deletedSessionReachesServer() async throws {
        let ids = try await world.importThenRegroup()
        let wednesdayEntries = await server.stored(RemoteEntryRow.self).filter { $0.sessionId == ids.wednesday }
        #expect(wednesdayEntries.count == 1)

        let report = try await engine.push()

        #expect(report.deleted == [SyncAggregateRef(.session, id: ids.wednesday)])
        #expect(report.rejected.isEmpty)
        #expect(report.pushed.filter { $0.kind == .session } == [SyncAggregateRef(.session, id: ids.monday)])
        #expect(await server.stored(RemoteSessionRow.self).map(\.id) == [ids.monday])
        // Wednesday's set now lives in Monday's entry.
        let entries = await server.stored(RemoteEntryRow.self)
        #expect(entries.map(\.sessionId) == [ids.monday])
        #expect(await server.stored(RemoteSetRow.self).count == 2)
        #expect(try store.syncState.tombstones().isEmpty)
        #expect(try world.localTombstones().isEmpty)
        #expect(await world.serverTombstones().contains("sessions:\(ids.wednesday)"))
        try world.expectNothingPending()
    }

    @Test("a network failure keeps the tombstone and the server's rows, and the next push deletes them (S4)")
    func failedDeletionIsKept() async throws {
        let ids = try await world.importThenRegroup()
        await server.failNext(.delete)

        await #expect(throws: URLError.self) { try await engine.push() }

        #expect(try store.syncState.tombstones().map(\.id) == [ids.wednesday])
        #expect(await server.stored(RemoteSessionRow.self).contains { $0.id == ids.wednesday })
        let report = try await engine.push()
        #expect(report.deleted == [SyncAggregateRef(.session, id: ids.wednesday)])
        #expect(try store.syncState.tombstones().isEmpty)
    }

    @Test("a refused deletion keeps its tombstone, is reported, and the push carries on")
    func refusedDeletionIsKept() async throws {
        let ids = try await world.importThenRegroup()
        let refusal = RemoteStoreError.rejected(code: "23503", message: "still in use")
        await server.failNext(.delete, with: refusal)

        let report = try await engine.push()

        #expect(report.rejected == [.init(aggregate: .init(.session, id: ids.wednesday), error: refusal)])
        #expect(report.deleted.isEmpty)
        #expect(try store.syncState.tombstones().map(\.id) == [ids.wednesday])
        #expect(report.pushed.contains(SyncAggregateRef(.session, id: ids.monday)))
        #expect(await server.stored(RemoteSessionRow.self).contains { $0.id == ids.wednesday })
        let retry = try await engine.push()
        #expect(retry.deleted == [SyncAggregateRef(.session, id: ids.wednesday)])
        #expect(retry.rejected.isEmpty)
        #expect(try store.syncState.tombstones().isEmpty)
        try world.expectNothingPending()
    }

    @Test("removed sessions are deleted before sessions go up, so a re-import may reuse a removed session's ref")
    func sessionDeletionsBeforeUploads() async throws {
        let ids = try await world.importThenRegroup()
        let wednesday = BundleSession(
            id: UUID(), externalRef: world.ref("w-2"), completedAt: world.t0.addingTimeInterval(2 * 86_400),
            timeZone: "UTC", entries: [ImportedEntry(exerciseId: world.press.id, externalRef: world.ref("e-3"), sets: [
                ImportedSet(externalRef: world.ref("e-3#1"), order: 1, values: SetValues(reps: 8, weight: .kg(45)))
            ])]
        )
        let again = try store.importer.importBundle(TrainingBundle(exercises: [world.press], sessions: [wednesday]))
        let newId = try #require(again.sessionIds[wednesday.id])
        #expect(newId != ids.wednesday)

        let report = try await engine.push()

        #expect(report.rejected.isEmpty)
        #expect(report.deleted == [SyncAggregateRef(.session, id: ids.wednesday)])
        #expect(report.pushed.contains(SyncAggregateRef(.session, id: newId)))
        #expect(Set(await server.stored(RemoteSessionRow.self).map(\.id)) == [ids.monday, newId])
        try world.expectNothingPending()
    }

    @Test("sessions are deleted before the exercises they used, so the server accepts both deletions")
    func sessionsBeforeExercises() async throws {
        let session = try world.finishedSession()
        try await engine.push()
        try world.deleteLocally(session: session.id, andExercise: world.squat.id)

        let report = try await engine.push()

        #expect(report.rejected.isEmpty)
        #expect(report.deleted == [.init(.session, id: session.id), .init(.exercise, id: world.squat.id)])
        #expect(await server.stored(RemoteSessionRow.self).isEmpty)
        #expect(await server.stored(RemoteExerciseRow.self).isEmpty)
        #expect(try store.syncState.tombstones().isEmpty)
    }

    // MARK: - Pull: deletions made elsewhere

    @Test("a session deleted on the server disappears from the device, leaving nothing pending or tombstoned")
    func serverDeletedSessionDisappears() async throws {
        let session = try world.finishedSession()
        try await engine.sync()
        try await server.deleteOnServer(.sessions, ids: [session.id])

        let report = try await engine.pull()

        #expect(try store.sessions.session(id: session.id) == nil)
        #expect(report.deletions.contains(.init(table: .sessions, id: session.id, rule: .serverApplied)))
        #expect(report.read[.tombstones] == 1 + session.entries.count + session.entries.flatMap(\.sets).count)
        #expect(try world.localTombstones().isEmpty)
        try world.expectNothingPending()
        let calls = await server.calls.count
        try await engine.push()
        #expect(await server.calls.count == calls, "the deletion is not echoed back")
    }

    @Test("a set deleted on the server goes, and its session stays clean even with another of its rows pulled")
    func serverDeletedSetIsAnEcho() async throws {
        let session = try world.finishedSession()
        try await engine.sync()
        let entry = try #require(session.entries.first)
        let warmup = try #require(entry.sets.first { $0.warmup })
        try await server.deleteOnServer(.sets, ids: [warmup.id])
        var row = try await world.serverEntry(entry.id)
        row.notes = "Edited on the other phone"
        try await server.insertOnServer(row)

        let report = try await engine.pull()

        let local = try #require(try world.session(session.id).entries.first)
        #expect(local.sets.map(\.id) == entry.sets.filter { !$0.warmup }.map(\.id))
        #expect(local.notes == "Edited on the other phone")
        #expect(report.deletions == [.init(table: .sets, id: warmup.id, rule: .serverApplied)])
        #expect(report.changedLocally.isEmpty)
        #expect(try world.localTombstones().isEmpty)
        try world.expectNothingPending()
    }

    @Test("an entry deleted on the server goes with its sets, and the rest of the session stays as it was")
    func serverDeletedEntryDisappears() async throws {
        let open = try world.startSession()
        for exercise in [world.squat.id, world.bench.id] {
            try store.sessions.logManualSet(SetValues(reps: 8), exerciseId: exercise, sessionId: open.id, at: world.t0)
        }
        let session = try store.sessions.finishSession(
            id: open.id, at: world.t0.addingTimeInterval(1_800), durationSeconds: nil
        )
        try await engine.sync()
        let bench = try #require(session.entries.first { $0.exerciseId == world.bench.id })
        try await server.deleteOnServer(.entries, ids: [bench.id])

        let report = try await engine.pull()

        let local = try world.session(session.id)
        #expect(local.entries.map(\.exerciseId) == [world.squat.id])
        #expect(local.entries.first?.sets.count == 1)
        #expect(report.deletions == bench.sets.map { .init(table: .sets, id: $0.id, rule: .serverApplied) }
            + [.init(table: .entries, id: bench.id, rule: .serverApplied)])
        #expect(try world.localTombstones().isEmpty)
        try world.expectNothingPending()
    }

    @Test("a session deleted on the server while it has a local change is kept and pushed back (S13)")
    func localChangeOutlivesServerDelete() async throws {
        let session = try world.finishedSession()
        try await engine.sync()
        let heavy = try #require(session.entries.first?.sets.first { !$0.warmup })
        try store.sessions.setWarmup(true, setId: heavy.id)
        try await server.deleteOnServer(.sessions, ids: [session.id])

        let report = try await engine.pull()

        #expect(report.deletions.contains(.init(table: .sessions, id: session.id, rule: .localKept)))
        #expect(report.deletions.contains(.init(table: .sets, id: heavy.id, rule: .localKept)))
        #expect(report.deletions.allSatisfy { $0.rule == .localKept })
        let kept = try world.session(session.id)
        #expect(kept.entries.flatMap(\.sets).first { $0.id == heavy.id }?.warmup == true)
        #expect(try world.isPending(session.id))
        #expect(try world.localTombstones().isEmpty)

        try await engine.push()

        #expect(await server.stored(RemoteSessionRow.self).map(\.id) == [session.id])
        #expect(try await world.serverSet(heavy.id).warmup)
        #expect(await world.serverTombstones().isEmpty, "the rows written again are no longer deleted")
        // Another device of the user, pulling from scratch, gets the session back.
        let other = try PushWorld(sharing: world)
        try await other.engine.pull()
        #expect(try other.session(session.id).entries.flatMap(\.sets).count == kept.entries.flatMap(\.sets).count)
    }

    @Test("a session written again after the pull read its tombstone is kept: the rows read later win")
    func rowWrittenAgainAfterItsTombstone() async throws {
        let session = try world.finishedSession()
        try await engine.sync()
        let rows = try await RemoteSessionAggregate(
            session: #require(server.stored(RemoteSessionRow.self).first),
            entries: server.stored(RemoteEntryRow.self),
            sets: server.stored(RemoteSetRow.self)
        )
        try await server.deleteOnServer(.sessions, ids: [session.id])
        // Another device pushes it back once the tombstones are read, before the rows are.
        await server.duringNextPull(of: .sets) { [server] in
            try? await server.pushSession(rows)
        }

        let report = try await engine.pull()

        #expect(report.deletions.contains(.init(table: .sessions, id: session.id, rule: .serverApplied)))
        #expect(report.created.contains(SyncAggregateRef(.session, id: session.id)))
        #expect(try Set(world.session(session.id).entries.flatMap(\.sets).map(\.id)) == Set(rows.sets.map(\.id)))
        #expect(await world.serverTombstones().isEmpty)
        try world.expectNothingPending()
    }

    @Test("a routine deleted on the server goes, and its sessions keep their rows without it")
    func serverDeletedRoutineDisappears() async throws {
        let routine = try world.saveRoutine()
        let session = try world.finishedSession(routineId: routine.id)
        try await engine.sync()
        try await server.deleteOnServer(.routines, ids: [routine.id])

        let report = try await engine.pull()

        #expect(try store.routines.routine(id: routine.id) == nil)
        #expect(try world.session(session.id).routineId == nil)
        #expect(report.deletions == [.init(table: .routines, id: routine.id, rule: .serverApplied)])
        try world.expectNothingPending()
    }

    @Test("a user exercise deleted on the server goes when unused, and is kept and sent again while the device uses it")
    func serverDeletedExercise() async throws {
        let row = Exercise(name: "Cable row", type: .strength)
        try store.exercises.save(row)
        try store.exerciseSettings.save(ExerciseSetting(exerciseId: row.id, restSeconds: 60))
        try await engine.push()
        // One the device never held: its tombstone is passed over.
        let elsewhere = RemoteExerciseRow(id: UUID(), userId: world.userId, name: "Sled push", type: .strength)
        try await server.insertOnServer(elsewhere)
        // A workout in progress uses the squat: it never left the device.
        let open = try world.startSession()
        try store.sessions.logManualSet(
            SetValues(reps: 8), exerciseId: world.squat.id, sessionId: open.id, at: world.t0
        )
        try await server.deleteOnServer(.exercises, ids: [row.id, world.squat.id, elsewhere.id])

        let report = try await engine.pull()

        #expect(try store.exercises.exercise(id: row.id) == nil)
        // The server deletes the exercise's settings with it.
        #expect(try store.exerciseSettings.setting(exerciseId: row.id) == nil)
        #expect(try store.exercises.exercise(id: elsewhere.id) == nil)
        #expect(try store.exercises.exercise(id: world.squat.id) != nil)
        #expect(report.deletions == [.init(table: .exercises, id: row.id, rule: .serverApplied)])
        #expect(report.skipped.contains { $0.table == .exercises && $0.id == world.squat.id })
        #expect(try store.syncState.pending(.exercise).map(\.id) == [world.squat.id])
        try await engine.push()
        #expect(await server.stored(RemoteExerciseRow.self).map(\.id) == [world.squat.id])
    }

    @Test("a session and the exercise only it used, deleted on one device, both go from another")
    func sessionAndExerciseDeletedTogether() async throws {
        let session = try world.finishedSession()
        try await engine.sync()
        let other = try PushWorld(sharing: world)
        try await other.engine.sync()
        #expect(try other.store.sessions.session(id: session.id) != nil)
        try other.expectNothingPending()
        try world.deleteLocally(session: session.id, andExercise: world.squat.id)
        try await engine.push()

        let report = try await other.engine.pull()

        #expect(try other.store.sessions.session(id: session.id) == nil)
        #expect(try other.store.exercises.exercise(id: world.squat.id) == nil)
        #expect(report.deletions.contains(.init(table: .exercises, id: world.squat.id, rule: .serverApplied)))
        #expect(report.skipped.isEmpty)
        try other.expectNothingPending()
        let calls = await server.calls.count
        try await other.engine.push()
        #expect(await server.calls.count == calls, "nothing is written back")
    }

    @Test("a routine and a user exercise only it used, deleted on the server together, both go")
    func routineAndExerciseDeletedTogether() async throws {
        let routine = try world.saveRoutine()
        try await engine.sync()
        try await server.deleteOnServer(.routines, ids: [routine.id])
        try await server.deleteOnServer(.exercises, ids: [world.squat.id])

        let report = try await engine.pull()

        #expect(try store.routines.routine(id: routine.id) == nil)
        #expect(try store.exercises.exercise(id: world.squat.id) == nil)
        #expect(report.deletions == [
            .init(table: .routines, id: routine.id, rule: .serverApplied),
            .init(table: .exercises, id: world.squat.id, rule: .serverApplied)
        ])
        try world.expectNothingPending()
    }
}
