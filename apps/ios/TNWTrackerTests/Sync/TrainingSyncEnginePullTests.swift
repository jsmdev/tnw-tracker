import Foundation
import Testing
@testable import TNWTrackerKit

/// The pull half of the sync (S2, S4, S8, S10) against the in-memory server,
/// with the real SwiftData store and repositories.
@Suite("Sync engine pull")
@MainActor
struct TrainingSyncEnginePullTests {
    let world: PushWorld

    init() throws {
        world = try PushWorld()
    }

    var store: TrainingStore { world.store }
    var server: InMemoryTrainingRemoteStore { world.server }
    var engine: TrainingSyncEngine { world.engine }

    // MARK: - S2: what arrives

    @Test("a session an importer wrote on the server appears on the device with the server's ids, and stays clean")
    func importedSessionArrives() async throws {
        try await world.uploadPrerequisites()
        var rows = world.importedSessionRows()
        // The machine replaced the planned squat.
        rows.entries[0].replacedExerciseId = world.squat.id
        try await world.writeOnServer(rows)

        let report = try await engine.sync()

        #expect(report.pull.created == [SyncAggregateRef(.session, id: rows.session.id)])
        let local = try world.session(rows.session.id)
        let entry = try #require(local.entries.first)
        #expect(local.name == "Machine day")
        #expect(local.completedAt == rows.session.completedAt)
        #expect(local.durationSeconds == 3_000)
        #expect(local.externalRef == world.ref("2030-03-05/e-1"))
        #expect(entry.id == rows.entries[0].id)
        #expect(entry.exerciseId == world.bench.id)
        #expect(entry.replacedExerciseId == world.squat.id)
        #expect(entry.externalRef == world.ref("e-1"))
        #expect(entry.reconciliation == nil)
        #expect(entry.sets.map(\.id) == [rows.sets[0].id])
        #expect(entry.sets.first?.source == .imported)
        #expect(entry.sets.first?.values == SetValues(reps: 10, weight: .kg(50)))
        #expect(entry.sets.first?.externalRef == world.ref("e-1#1"))
        #expect(entry.sets.first?.superseded == false)
        try world.expectNothingPending()
        // Nothing goes back up: what came from the server is not a local change.
        let calls = await server.calls.count
        try await engine.push()
        #expect(await server.calls.count == calls)
    }

    @Test("an in-app re-import recognises the entry and set the pull brought, instead of duplicating them")
    func pulledRefsAreKnownToTheImporter() async throws {
        try await world.uploadPrerequisites()
        let rows = world.importedSessionRows()
        try await world.writeOnServer(rows)
        try await engine.pull()

        try store.sessions.importEntry(
            ImportedEntry(
                exerciseId: world.bench.id, externalRef: world.ref("e-1"),
                sets: [ImportedSet(externalRef: world.ref("e-1#1"), order: 1, values: SetValues(reps: 11))]
            ),
            into: rows.session.id
        )

        let entry = try #require(try world.session(rows.session.id).entries.first)
        #expect(try world.session(rows.session.id).entries.count == 1)
        #expect(entry.id == rows.entries[0].id)
        #expect(entry.sets.map(\.id) == [rows.sets[0].id])
        #expect(entry.sets.first?.values == SetValues(reps: 11))
    }

    @Test("a set another device logged in a session the device already holds arrives as it is")
    func manualSetFromAnotherDeviceArrives() async throws {
        let session = try world.finishedSession()
        try await engine.push()
        let entryId = try #require(session.entries.first { $0.exerciseId == world.squat.id }?.id)
        let logged = RemoteSetRow(
            id: UUID(), userId: world.userId, entryId: entryId, position: 3, source: .manual, reps: 6,
            weight: .kg(45), rir: 1, completedAt: world.t0.addingTimeInterval(900), warmup: false
        )
        try await server.insertOnServer(logged)

        let report = try await engine.pull()

        let set = try #require(try world.session(session.id).entries.first { $0.id == entryId }?.sets.last)
        #expect(set.id == logged.id)
        #expect(set.order == 3)
        #expect(set.source == .manual)
        #expect(set.values == SetValues(reps: 6, weight: .kg(45), rir: 1))
        #expect(set.completedAt == logged.completedAt)
        #expect(report.changedLocally.isEmpty)
        try world.expectNothingPending()
    }

    @Test("catalogue exercises arrive, never to be pushed; another device's exercise and routine arrive clean")
    func templatesArrive() async throws {
        let catalogue = RemoteExerciseRow(
            id: TrainingRemoteStoreContract.shoulderPress, userId: nil, name: "Shoulder Press", type: .strength,
            equipment: .freeWeights, executionSteps: ["Press up"]
        )
        let plank = RemoteExerciseRow(id: UUID(), userId: world.userId, name: "Plank", type: .bodyweight)
        let routine = RemoteRoutineRow(id: UUID(), userId: world.userId, name: "Core", isFavorite: true)
        let item = RemoteRoutineItemRow(
            id: RemoteRoutineItemRow.id(routineId: routine.id, position: 1), userId: world.userId,
            routineId: routine.id, position: 1, exerciseId: plank.id, targetSets: 3, targetDurationSeconds: 60
        )
        try await server.insertOnServer(catalogue)
        try await server.insertOnServer(plank)
        try await server.insertOnServer(
            RemoteMuscleGroupRow(exerciseId: catalogue.id, muscle: .shoulders, role: .primary)
        )
        try await server.insertOnServer(routine)
        try await server.insertOnServer(item)

        let report = try await engine.sync()

        #expect(Set(report.pull.created) == [
            SyncAggregateRef(.exercise, id: plank.id), SyncAggregateRef(.routine, id: routine.id)
        ])
        let shoulder = try #require(try store.exercises.exercise(id: catalogue.id))
        #expect(shoulder.isCatalogue)
        #expect(shoulder.equipment == .freeWeights)
        #expect(shoulder.instructions?.execution == ["Press up"])
        #expect(shoulder.muscleGroups == [MuscleGroup(muscle: .shoulders, role: .primary)])
        #expect(try store.exercises.exercise(id: plank.id)?.name == "Plank")
        let local = try #require(try store.routines.routine(id: routine.id))
        #expect(local.isFavorite)
        #expect(local.items == [RoutineItem(order: 1, exerciseId: plank.id, targetSets: 3, targetDurationSeconds: 60)])
        try world.expectNothingPending()

        // A session logged with them goes up at once: the server already holds both.
        let session = try world.finishedSession(routineId: routine.id, exerciseId: plank.id, at: 7_200)
        let push = try await engine.push()
        #expect(push.pushed == [SyncAggregateRef(.session, id: session.id)])
        #expect(push.skipped.isEmpty)
    }

    @Test("an exercise whose muscles changed here keeps them; a muscle of an exercise the device lacks waits")
    func pendingExerciseKeepsItsMuscles() async throws {
        try await world.uploadPrerequisites()
        var edited = world.squat
        edited.muscleGroups = [MuscleGroup(muscle: .glutes, role: .primary)]
        try store.exercises.save(edited)
        var hamstrings = RemoteMuscleGroupRow(exerciseId: world.squat.id, muscle: .hamstrings, role: .secondary)
        hamstrings.updatedAt = "2026-01-01T00:00:01.000000+00:00"
        var unknown = RemoteMuscleGroupRow(exerciseId: UUID(), muscle: .core, role: .primary)
        unknown.updatedAt = "2026-01-01T00:00:02.000000+00:00"

        let report = try store.pulled.apply(PulledBatch(muscleGroups: [hamstrings, unknown]), userId: world.userId)

        #expect(try store.exercises.exercise(id: world.squat.id)?.muscleGroups == edited.muscleGroups)
        // The list is decided apart from its parent row, which this batch does not hold.
        #expect(report.resolved.isEmpty)
        #expect(report.skipped == [.init(table: .exerciseMuscleGroups, id: unknown.id, reason: .missingParent)])
        #expect(try store.pulled.cursor(.exerciseMuscleGroups, userId: world.userId)?.id == hamstrings.id)
    }

    // MARK: - Echo

    @Test("pulling back what the device pushed leaves every aggregate unchanged and clean")
    func echoIsNotAChange() async throws {
        let routine = try world.saveRoutine()
        let session = try world.finishedSession(routineId: routine.id)
        try await engine.push()
        let before = try world.session(session.id)
        let routineBefore = try store.routines.routine(id: routine.id)
        let squatBefore = try store.exercises.exercise(id: world.squat.id)

        let report = try await engine.pull()

        #expect(report.created.isEmpty)
        #expect(report.changedLocally.isEmpty)
        #expect(report.resolved.contains(.init(aggregate: .init(.session, id: session.id), rule: .serverApplied)))
        #expect(try world.session(session.id) == before)
        #expect(try store.routines.routine(id: routine.id) == routineBefore)
        #expect(try store.exercises.exercise(id: world.squat.id) == squatBefore)
        try world.expectNothingPending()
    }

    // MARK: - Cursor

    @Test("the cursor advances page by page and the next pull reads only rows after it, less the overlap")
    func cursorAdvancesAndPages() async throws {
        let engine = world.engine(pageSize: 2)
        try await world.uploadPrerequisites()
        let rows = world.importedSessionRows()
        let entryId = rows.entries[0].id
        try await world.writeOnServer(rows)
        for position in 2 ... 4 {
            try await server.insertOnServer(
                world.importedSetRow(
                    entryId: entryId, ref: "e-1#\(position)", reps: position, position: position, at: world.t0
                )
            )
        }

        let first = try await engine.pull()

        #expect(first.read[.sets] == 4)
        #expect(await setPulls().count == 3) // 2 + 2 + an empty page
        let last = try #require(await server.stored(RemoteSetRow.self).last)
        let cursor = try #require(try store.pulled.cursor(.sets, userId: world.userId))
        #expect(cursor == RemoteCursor(updatedAt: try #require(last.updatedAt), id: last.id))

        // A minute later: the overlap re-reads the first four, then the new one.
        await server.advanceClock(seconds: 60)
        let fifth = world.importedSetRow(entryId: entryId, ref: "e-1#5", reps: 5, position: 5, at: world.t0)
        try await server.insertOnServer(fifth)
        #expect(try await engine.pull().read[.sets] == 5)
        let moved = try #require(try store.pulled.cursor(.sets, userId: world.userId))
        #expect(moved.id == fifth.id)

        // Another minute: only the fifth (inside the overlap) and the sixth are read.
        await server.advanceClock(seconds: 60)
        let sixth = world.importedSetRow(entryId: entryId, ref: "e-1#6", reps: 6, position: 6, at: world.t0)
        try await server.insertOnServer(sixth)
        let callsBefore = await setPulls().count

        let third = try await engine.pull()

        #expect(third.read[.sets] == 2)
        #expect(await setPulls().dropFirst(callsBefore).first == .pull(.sets, after: moved.rewound(by: 5), limit: 2))
        #expect(try world.session(rows.session.id).entries.first?.sets.map(\.values.reps) == [10, 2, 3, 4, 5, 6])
        try world.expectNothingPending()
    }

    private func setPulls() async -> [InMemoryTrainingRemoteStore.Call] {
        await server.calls.filter { call in
            if case .pull(.sets, _, _) = call { true } else { false }
        }
    }

    @Test("a row committed late behind the cursor is read again within the overlap, and re-reads change nothing")
    func overlapCatchesLateCommits() async throws {
        try await world.uploadPrerequisites()
        let rows = world.importedSessionRows()
        try await world.writeOnServer(rows)
        try await engine.pull()
        await server.advanceClock(seconds: 2)
        let before = try world.session(rows.session.id)
        let late = world.importedSetRow(entryId: rows.entries[0].id, ref: "e-1#2", reps: 9, position: 2, at: world.t0)
        // Its transaction started before the last pull and committed after it.
        try await server.insertLateOnServer(late, secondsBehind: 3)

        let report = try await engine.pull()

        let sets = try #require(try world.session(rows.session.id).entries.first?.sets)
        #expect(sets.map(\.id) == [rows.sets[0].id, late.id])
        #expect(sets.first == before.entries.first?.sets.first)
        #expect(report.read[.sets] == 2)
        try world.expectNothingPending()
        // Reading the same rows again is harmless.
        let again = try world.session(rows.session.id)
        try await engine.pull()
        #expect(try world.session(rows.session.id) == again)
        try world.expectNothingPending()
    }

    @Test("a store reset forgets the cursors, so the next pull reads from the start")
    func resetForgetsCursors() async throws {
        try await server.insertOnServer(
            RemoteExerciseRow(id: world.bench.id, userId: nil, name: "Bench Press", type: .strength)
        )
        try await world.uploadPrerequisites()
        try await world.writeOnServer(world.importedSessionRows())
        try await engine.pull()

        try store.deleteAllTrainingData()
        try world.claim()
        let callsBefore = await server.calls.count
        try await engine.pull()

        #expect(try store.pulled.cursor(.sets, userId: world.userId) != nil)
        let pulls = await server.calls.dropFirst(callsBefore)
        #expect(pulls.contains(.pull(.sets, after: nil, limit: 500)))
        #expect(try world.completedSessions().count == 1)
    }

    @Test("claiming the store for another user forgets the previous user's cursors")
    func claimForgetsOtherCursors() async throws {
        let fresh = try PushWorld(claimed: false)
        try fresh.claim()
        try await fresh.server.insertOnServer(
            RemoteExerciseRow(id: fresh.bench.id, userId: nil, name: "Bench Press", type: .strength)
        )
        // Only the catalogue comes down: the store holds no data of its owner.
        try await fresh.engine.pull()
        #expect(try fresh.store.pulled.cursor(.exercises, userId: fresh.userId) != nil)

        #expect(try fresh.store.ownership.claim(userId: UUID(), at: fresh.t0) == .claimed)

        #expect(try fresh.store.pulled.cursor(.exercises, userId: fresh.userId) == nil)
    }

    // MARK: - S4: failures

    @Test("a network failure part way through a pull applies nothing and keeps every cursor")
    func failureAppliesNothing() async throws {
        let session = try world.finishedSession()
        try await engine.push()
        let entryId = try #require(session.entries.first { $0.exerciseId == world.squat.id }?.id)
        // A set for an entry the device holds, and a whole new session.
        let imported = world.importedSetRow(entryId: entryId, ref: "e-9#1", reps: 10, at: world.t0)
        try await server.insertOnServer(imported)
        let rows = world.importedSessionRows()
        try await world.writeOnServer(rows)
        // Sets, entries and sessions are read; the exercises page fails.
        await server.failNextPull(of: .exercises)

        await #expect(throws: URLError.self) { try await engine.pull() }

        #expect(try world.session(session.id) == session)
        #expect(try store.sessions.session(id: rows.session.id) == nil)
        for table in RemoteTable.allCases {
            #expect(try store.pulled.cursor(table, userId: world.userId) == nil, "\(table)")
        }
        try world.expectNothingPending()
        try await engine.pull()
        #expect(try store.sessions.session(id: rows.session.id) != nil)
        #expect(try world.session(session.id).entries.flatMap(\.sets).contains { $0.id == imported.id })
    }

    @Test("a failure on a later page drops the pages already read and keeps the cursor where it was")
    func failureOnLaterPage() async throws {
        let engine = world.engine(pageSize: 1)
        try await world.uploadPrerequisites()
        try await world.writeOnServer(world.importedSessionRows())
        try await engine.pull()
        let cursors = try RemoteTable.allCases.map { try store.pulled.cursor($0, userId: world.userId) }
        await server.advanceClock(seconds: 60)
        let second = world.importedSessionRows(entryRef: "e-2")
        try await world.writeOnServer(second)
        // The first sets page (the overlap) arrives; the second fails.
        await server.failNextPull(of: .sets, afterPages: 1)

        await #expect(throws: URLError.self) { try await engine.pull() }

        #expect(try RemoteTable.allCases.map { try store.pulled.cursor($0, userId: world.userId) } == cursors)
        #expect(try store.sessions.session(id: second.session.id) == nil)
        try await engine.pull()
        #expect(try world.session(second.session.id).entries.first?.sets.map(\.id) == second.sets.map(\.id))
    }
}

// MARK: - S10

extension TrainingSyncEnginePullTests {
    @Test("a store that changes hands while the pages are read applies nothing")
    func ownerChangeDuringPullAppliesNothing() async throws {
        try await world.uploadPrerequisites()
        let rows = world.importedSessionRows()
        try await world.writeOnServer(rows)
        let store = store
        await server.duringNextPull {
            await MainActor.run {
                // Signed out, the store reset, and claimed by someone else.
                _ = try? store.deleteAllTrainingData()
                _ = try? store.ownership.claim(userId: UUID(), at: .now)
            }
        }

        await #expect(throws: TrainingSyncError.self) { try await engine.pull() }

        #expect(try store.sessions.session(id: rows.session.id) == nil)
        #expect(try store.pulled.cursor(.sets, userId: world.userId) == nil)
    }

    @Test("a store owned by another user pulls nothing and changes nothing")
    func ownerMismatchPullsNothing() async throws {
        let other = try PushWorld(claimed: false)
        _ = try other.store.ownership.claim(userId: UUID(), at: other.t0)
        try await other.writeOnServer(other.importedSessionRows())
        let callsBefore = await other.server.calls.count

        await #expect(throws: TrainingSyncError.self) { try await other.engine.pull() }

        #expect(await other.server.calls.count == callsBefore)
        #expect(try other.completedSessions().isEmpty)
    }
}
