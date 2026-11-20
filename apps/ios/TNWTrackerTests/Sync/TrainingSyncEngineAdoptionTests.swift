import Foundation
import Testing
@testable import TNWTrackerKit

/// External refs the server holds under other ids (L5 item 1): an importer on
/// the server and the in-app importer brought the same provider data, so the
/// push is refused with 23505 until the pull gives the local rows the server's
/// ids. Real store and repositories, in-memory server.
@Suite("Sync engine pull adoption")
@MainActor
struct TrainingSyncEngineAdoptionTests {
    let world: PushWorld

    init() throws {
        world = try PushWorld()
    }

    private var store: TrainingStore { world.store }
    private var server: InMemoryTrainingRemoteStore { world.server }
    private var engine: TrainingSyncEngine { world.engine }

    @Test("rows the server holds under other ids for the same refs are adopted, so the next push succeeds")
    func serverIdsAreAdoptedForTheSameRefs() async throws {
        try await world.uploadPrerequisites()
        // An importer on the server and the in-app importer both brought the same provider data.
        let exercise = RemoteExerciseRow(
            id: UUID(), userId: world.userId, name: "Chest Press Machine", type: .strength,
            equipment: .connectedMachine, externalRef: world.ref("ex-1")
        )
        let routine = RemoteRoutineRow(
            id: UUID(), userId: world.userId, name: "Machines", externalRef: world.ref("r-1")
        )
        try await server.insertOnServer(exercise)
        try await server.insertOnServer(routine)
        try await server.insertOnServer(RemoteRoutineItemRow(
            id: RemoteRoutineItemRow.id(routineId: routine.id, position: 1), userId: world.userId,
            routineId: routine.id, position: 1, exerciseId: exercise.id
        ))
        var rows = world.importedSessionRows()
        rows.session.externalRef = world.ref("s-1")
        rows.session.routineId = routine.id
        rows.entries[0].exerciseId = exercise.id
        try await world.writeOnServer(rows)
        let machine = Exercise(
            externalRef: world.ref("ex-1"), name: "Chest Press Machine", type: .strength, equipment: .connectedMachine
        )
        let plan = Routine(externalRef: world.ref("r-1"), name: "Machines", items: [
            RoutineItem(order: 1, exerciseId: machine.id)
        ])
        let result = try store.importer.importBundle(try bundle(matching: rows, exercise: machine, routine: plan))
        let localSession = try #require(result.sessionIds.values.first)
        let localExercise = try #require(result.exerciseIds.values.first)

        let first = try await engine.sync()

        #expect(first.push.rejected.map(\.aggregate) == [SyncAggregateRef(.exercise, id: localExercise)])
        #expect(first.push.rejected.first?.error == InMemoryTrainingRemoteStore.duplicateExternalRef(.exercises))
        #expect(first.pull.adopted.map(\.table) == [.exercises, .routines, .sessions, .entries, .sets])
        #expect(first.pull.adopted.map(\.serverId) == [
            exercise.id, routine.id, rows.session.id, rows.entries[0].id, rows.sets[0].id
        ])
        #expect(first.pull.adopted.first { $0.table == .sessions }?.localId == localSession)
        #expect(try store.sessions.session(id: localSession) == nil)
        let adopted = try world.session(rows.session.id)
        #expect(adopted.routineId == routine.id)
        #expect(adopted.entries.map(\.id) == [rows.entries[0].id])
        #expect(adopted.entries.first?.exerciseId == exercise.id)
        #expect(adopted.entries.first?.sets.map(\.id) == [rows.sets[0].id])

        let second = try await engine.push()

        #expect(second.rejected.isEmpty)
        #expect(second.pushed == [
            SyncAggregateRef(.exercise, id: exercise.id), SyncAggregateRef(.routine, id: routine.id),
            SyncAggregateRef(.session, id: rows.session.id)
        ])
        #expect(await server.stored(RemoteRoutineRow.self).map(\.id) == [routine.id])
        #expect(await server.stored(RemoteSessionRow.self).map(\.id) == [rows.session.id])
        #expect(await server.stored(RemoteSetRow.self).map(\.id) == [rows.sets[0].id])
        try world.expectNothingPending()
    }

    @Test("a session the server refused for a ref it holds under another id is adopted, and its next push succeeds")
    func refusedSessionIsAdoptedAndPushes() async throws {
        try await world.uploadPrerequisites()
        let rows = world.importedSessionRows()
        try await world.writeOnServer(rows)
        // Without a ref, the bundle's exercise is the catalogue's bench press.
        let bench = Exercise(name: "Bench Press", type: .strength)
        let result = try store.importer.importBundle(try bundle(matching: rows, exercise: bench))
        let localSession = try #require(result.sessionIds.values.first)

        let first = try await engine.sync()

        #expect(first.push.rejected.map(\.aggregate) == [SyncAggregateRef(.session, id: localSession)])
        #expect(first.push.rejected.first?.error == InMemoryTrainingRemoteStore.duplicateExternalRef(.sessions))
        #expect(first.pull.adopted.map(\.table) == [.sessions, .entries, .sets])

        let second = try await engine.push()

        #expect(second.rejected.isEmpty)
        #expect(second.pushed == [SyncAggregateRef(.session, id: rows.session.id)])
        #expect(await server.stored(RemoteSessionRow.self).map(\.id) == [rows.session.id])
        #expect(await server.stored(RemoteEntryRow.self).map(\.id) == [rows.entries[0].id])
        #expect(await server.stored(RemoteSetRow.self).map(\.id) == [rows.sets[0].id])
        try world.expectNothingPending()
    }

    @Test("an imported set the server regrouped into another session moves there, and the emptied session goes (D8)")
    func regroupedSetMovesToTheServersSession() async throws {
        try await world.uploadPrerequisites()
        let rows = world.importedSessionRows(entryRef: "e-2")
        var earlier = world.importedSessionRows(entryRef: "e-1")
        earlier.session.completedAt = world.t0.addingTimeInterval(3_600)
        earlier.session.startedAt = world.t0
        // The device imported the set inside the earlier session; the importer on
        // the server put the same set in the later one.
        let bench = Exercise(name: "Bench Press", type: .strength)
        let result = try store.importer.importBundle(try bundle(matching: earlier, exercise: bench))
        let localSession = try #require(result.sessionIds.values.first)
        var regrouped = rows
        regrouped.sets[0].externalRef = earlier.sets[0].externalRef
        try await world.writeOnServer(regrouped)

        let report = try await engine.pull()

        #expect(report.adopted.map(\.table) == [.sets])
        #expect(try store.sessions.session(id: localSession) == nil)
        let entry = try #require(try world.session(rows.session.id).entries.first)
        #expect(entry.sets.map(\.id) == [regrouped.sets[0].id])
        #expect(entry.sets.first?.externalRef == earlier.sets[0].externalRef)
    }

    /// The bundle an importer on the device builds for the same provider data as `rows`.
    private func bundle(
        matching rows: RemoteSessionAggregate,
        exercise: Exercise,
        routine: Routine? = nil
    ) throws -> TrainingBundle {
        let set = rows.sets[0]
        return TrainingBundle(
            exercises: [exercise],
            routines: routine.map { [$0] } ?? [],
            sessions: [BundleSession(
                id: UUID(), externalRef: try #require(rows.session.externalRef), name: rows.session.name,
                startedAt: rows.session.startedAt, completedAt: rows.session.completedAt,
                timeZone: rows.session.timeZone, durationSeconds: rows.session.durationSeconds,
                routineId: routine?.id,
                entries: [ImportedEntry(
                    exerciseId: exercise.id, externalRef: try #require(rows.entries[0].externalRef),
                    completedAt: rows.entries[0].completedAt,
                    sets: [ImportedSet(
                        externalRef: try #require(set.externalRef), order: 1,
                        values: SetValues(reps: set.reps, weight: set.weight), completedAt: set.completedAt
                    )]
                )]
            )]
        )
    }

    @Test("a done entry the device added and never sent takes the id of the server's entry of that exercise")
    func unsentEntryTakesTheServersId() async throws {
        let session = try world.finishedSession()
        try await engine.push()
        // The in-app import adds a bench entry to the finished session; it is not sent yet.
        try store.sessions.importEntry(
            ImportedEntry(
                exerciseId: world.bench.id, externalRef: world.ref("e-7"),
                sets: [ImportedSet(externalRef: world.ref("e-7#1"), order: 1, values: SetValues(reps: 8))]
            ),
            into: session.id
        )
        let localEntry = try #require(try world.session(session.id).entries.first { $0.exerciseId == world.bench.id })
        // Another device logged bench in the same session meanwhile.
        let entry = RemoteEntryRow(
            id: UUID(), userId: world.userId, sessionId: session.id, position: 2, exerciseId: world.bench.id,
            status: .done
        )
        let logged = RemoteSetRow(
            id: UUID(), userId: world.userId, entryId: entry.id, position: 1, source: .manual, reps: 6
        )
        try await server.insertOnServer(entry)
        try await server.insertOnServer(logged)

        let report = try await engine.pull()

        #expect(report.adopted == [.init(table: .entries, localId: localEntry.id, serverId: entry.id)])
        let bench = try #require(try world.session(session.id).entries.first { $0.exerciseId == world.bench.id })
        #expect(bench.id == entry.id)
        #expect(Set(bench.sets.map(\.source)) == [.imported, .manual])
        let push = try await engine.push()
        #expect(push.rejected.isEmpty)
        let benchRows = await server.stored(RemoteEntryRow.self).filter { $0.exerciseId == world.bench.id }
        #expect(benchRows.map(\.id) == [entry.id])
        try world.expectNothingPending()
    }
}
