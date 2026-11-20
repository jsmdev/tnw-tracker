import Foundation
import Testing
@testable import TNWTrackerKit

/// The sync settles after the server refused or failed part of a push (S4, S11,
/// S13): which failures still let the pull run, and how a pull resolves what
/// the push could not send. Real store and engine, in-memory server; the same
/// cases run against the local stack in `SyncVerifierProbeTests`. Invented data only.
@Suite("Sync engine, recovery")
@MainActor
struct TrainingSyncEngineRecoveryTests {
    let world: PushWorld

    init() throws {
        world = try PushWorld()
    }

    private var pulls: [RemoteTable] {
        get async {
            await world.server.calls.compactMap { call in
                if case let .pull(table, _, _) = call { return table }
                return nil
            }
        }
    }

    // MARK: - Which failures let the pull run

    @Test("S11 S4 a session using an exercise deleted on the server is refused, the pull runs, the next sends both")
    func inUseExerciseDeletedOnServer() async throws {
        try await world.engine.sync()
        let session = try world.finishedSession()
        try await world.server.deleteOnServer(.exercises, ids: [world.squat.id])

        let first = try await world.engine.sync()
        try await world.engine.sync()

        let refusal = InMemoryTrainingRemoteStore.rowLevelSecurity(.entries)
        #expect(first.push.rejected == [.init(aggregate: .init(.session, id: session.id), error: refusal)])
        #expect(await world.stored(RemoteExerciseRow.self).contains { $0.id == world.squat.id })
        let entries = await world.stored(RemoteEntryRow.self).filter { $0.sessionId == session.id }
        let expected: Set<UUID> = Set(session.entries.map(\.id))
        #expect(Set(entries.map(\.id)) == expected)
        try world.expectNothingPending()
    }

    @Test("S11 S4 a routine using an exercise deleted on the server is refused, then both go up again")
    func routineOfExerciseDeletedOnServer() async throws {
        try await world.engine.sync()
        let routine = try world.saveRoutine()
        try await world.server.deleteOnServer(.exercises, ids: [world.squat.id])

        let first = try await world.engine.sync()
        try await world.engine.sync()

        let refusal = InMemoryTrainingRemoteStore.rowLevelSecurity(.routineItems)
        #expect(first.push.rejected == [.init(aggregate: .init(.routine, id: routine.id), error: refusal)])
        #expect(await world.stored(RemoteExerciseRow.self).contains { $0.id == world.squat.id })
        let items = await world.stored(RemoteRoutineItemRow.self)
        #expect(PushWorld.byId(items) == PushWorld.byId(world.itemRows(routine)))
        try world.expectNothingPending()
    }

    @Test("S11 S4 a setting of an exercise deleted on the server is refused, then goes with its exercise")
    func settingOfExerciseDeletedOnServer() async throws {
        try await world.engine.sync()
        try world.store.exerciseSettings.save(
            ExerciseSetting(exerciseId: world.squat.id, restEnabled: false, restSeconds: 30)
        )
        try await world.server.deleteOnServer(.exercises, ids: [world.squat.id])

        let first = try await world.engine.sync()
        let second = try await world.engine.sync()

        let refusal = InMemoryTrainingRemoteStore.rowLevelSecurity(.exerciseSettings)
        #expect(first.push.rejected == [.init(aggregate: .init(.exerciseSetting, id: world.squat.id), error: refusal)])
        #expect(try world.store.exercises.exercises().contains { $0.id == world.squat.id } == false)
        #expect(second.push.pushed.isEmpty)
        #expect(await world.stored(RemoteExerciseSettingRow.self).isEmpty)
        try world.expectNothingPending()
    }

    @Test("S4 a server fault stops the push, the pull still runs, and the sync throws the fault")
    func serverFaultStillPulls() async throws {
        let routine = try world.saveRoutine()
        let fault = RemoteServerError(code: "XX000", message: "internal error")
        await world.server.failNext(.upsert, with: fault)
        let other = RemoteExerciseRow(id: UUID(), userId: world.userId, name: "Cable Row", type: .strength)
        try await world.server.insertOnServer(other)

        await #expect(throws: fault) { try await world.engine.sync() }

        #expect(try world.store.exercises.exercises().contains { $0.id == other.id && $0.name == "Cable Row" })
        #expect(try world.store.pulled.cursor(.exercises, userId: world.userId) != nil)
        #expect(try world.store.syncState.pending(.exercise).map(\.id) == [world.squat.id])
        #expect(try world.store.syncState.pending(.routine).map(\.id) == [routine.id])
        #expect(await world.stored(RemoteRoutineRow.self).isEmpty)
    }

    @Test("S4 S10 no network or a refused session stops the push and the pull: nothing is read or applied")
    func transportAndSessionFailuresStopTheRun() async throws {
        let failures: [any Error] = [InMemoryTrainingRemoteStore.networkDown, RemoteSessionError.sessionRefused]
        try await world.server.insertOnServer(
            RemoteExerciseRow(id: UUID(), userId: world.userId, name: "Cable Row", type: .strength)
        )

        for failure in failures {
            await world.server.failNext(.upsert, with: failure)
            do {
                try await world.engine.sync()
                Issue.record("the sync did not fail")
            } catch {
                #expect(String(describing: error) == String(describing: failure))
            }
        }

        #expect(await pulls.isEmpty)
        #expect(try !world.store.exercises.exercises().contains { $0.name == "Cable Row" })
        #expect(try world.store.syncState.pending(.exercise).map(\.id) == [world.squat.id])
    }

    // MARK: - A second done entry of an exercise

    @Test("S13 a done entry an importer added for the same exercise takes in the device's own, and the sync settles")
    func concurrentDoneEntryMerges() async throws {
        let session = try world.finishedSession()
        try await world.engine.sync()
        let appRef = world.ref("app-e#1")
        try world.store.sessions.importEntry(
            ImportedEntry(
                exerciseId: world.bench.id, externalRef: world.ref("app-e"),
                sets: [ImportedSet(externalRef: appRef, order: 1, values: SetValues(reps: 5, weight: .kg(60)))]
            ),
            into: session.id
        )
        let entry = RemoteEntryRow(
            id: UUID(), userId: world.userId, sessionId: session.id, position: 3, exerciseId: world.bench.id,
            status: .done, completedAt: world.t0.addingTimeInterval(1_200), externalRef: world.ref("probe-e")
        )
        let imported = world.importedSetRow(
            entryId: entry.id, ref: "probe-e#1", reps: 10, at: world.t0.addingTimeInterval(1_100)
        )
        try await world.server.insertOnServer(entry)
        try await world.server.insertOnServer(imported)

        let first = try await world.engine.sync()
        try await world.engine.sync()
        let last = try await world.engine.sync()

        #expect(first.push.rejected.map(\.aggregate) == [.init(.session, id: session.id)])
        #expect(first.pull.adopted.map(\.serverId) == [entry.id])
        let benches = try world.session(session.id).entries.filter { $0.exerciseId == world.bench.id }
        #expect(benches.map(\.id) == [entry.id])
        #expect(Set(benches.flatMap(\.sets).compactMap(\.externalRef)) == [appRef, world.ref("probe-e#1")])
        let onServer = await world.stored(RemoteSetRow.self).filter { $0.entryId == entry.id }
        #expect(Set(onServer.compactMap(\.externalRef)) == [appRef, world.ref("probe-e#1")])
        let serverBenches = await world.stored(RemoteEntryRow.self).filter { $0.exerciseId == world.bench.id }
        #expect(serverBenches.map(\.id) == [entry.id])
        // The importer's ref goes up; the device's own still finds the entry on the device.
        #expect(serverBenches.first?.externalRef == world.ref("probe-e"))
        #expect(try world.store.context.fetchEntry(ref: world.ref("app-e"))?.id == entry.id)
        #expect(last.push.rejected.isEmpty)
        #expect(last.pull.skipped.isEmpty)
        try world.expectNothingPending()
    }

    @Test("S13 a done entry is held, not passed over, while the server also sends the device's own entry of it")
    func conflictingDoneEntryIsHeld() async throws {
        let session = try world.finishedSession()
        try await world.engine.sync()
        let mine = try #require(session.entries.first)
        // Another device turned the device's entry into a skipped one and added its own done entry.
        var skipped = PushWorld.rows(of: session, userId: world.userId).entries[0]
        skipped.status = .skipped
        skipped.completedAt = nil
        await world.server.advanceClock(seconds: 60)
        try await world.server.deleteOnServer(
            .sets, ids: session.entries.flatMap(\.sets).map(\.id)
        )
        try await world.server.insertOnServer(skipped)
        // Its row comes first in the pull, before the device learns its own entry was
        // skipped, and further behind than the pull's overlap re-reads.
        let theirs = RemoteEntryRow(
            id: UUID(), userId: world.userId, sessionId: session.id, position: 2, exerciseId: world.squat.id,
            status: .done, completedAt: world.t0.addingTimeInterval(1_200)
        )
        try await world.server.insertLateOnServer(theirs, secondsBehind: 30)

        let first = try await world.engine.pull()
        let second = try await world.engine.pull()

        #expect(first.skipped.contains { skip in
            if case .conflict = skip.reason { return skip.id == theirs.id && skip.table == .entries }
            return false
        })
        #expect(second.skipped.isEmpty)
        let entries = try world.session(session.id).entries
        #expect(entries.first { $0.id == mine.id }?.status == .skipped)
        #expect(entries.first { $0.id == theirs.id }?.status == .done)
    }
}
