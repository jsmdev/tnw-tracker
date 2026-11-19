import Foundation
import Testing
@testable import TNWTrackerKit

/// The push half of the sync (S1, S3, S4, S7, S9, S10) against the in-memory
/// server, with the real SwiftData store and repositories.
@Suite("Sync engine push")
@MainActor
struct TrainingSyncEnginePushTests {
    let world: PushWorld

    init() throws {
        world = try PushWorld()
    }

    private var store: TrainingStore { world.store }
    private var server: InMemoryTrainingRemoteStore { world.server }
    private var engine: TrainingSyncEngine { world.engine }

    // MARK: - S1: what is sent

    @Test("a finished session goes up with its exercise and routine, every row equal to the local values")
    func finishedSessionUploads() async throws {
        let routine = try world.saveRoutine()
        let session = try world.finishedSession(routineId: routine.id)

        let report = try await engine.push()

        #expect(report.pushed == [
            SyncAggregateRef(.exercise, id: world.squat.id),
            SyncAggregateRef(.routine, id: routine.id),
            SyncAggregateRef(.session, id: session.id)
        ])
        #expect(report.skipped.isEmpty)
        #expect(report.rejected.isEmpty)
        let local = try #require(try store.sessions.session(id: session.id))
        let expected = PushWorld.rows(of: local, userId: world.userId)
        #expect(await server.stored(RemoteSessionRow.self).map(PushWorld.plain) == [expected.session])
        #expect(await world.stored(RemoteEntryRow.self) == PushWorld.byId(expected.entries))
        #expect(await world.stored(RemoteSetRow.self) == PushWorld.byId(expected.sets))
        #expect(await server.stored(RemoteExerciseRow.self).map(PushWorld.plain) == [world.squatRow])
        let muscles = [
            RemoteMuscleGroupRow(exerciseId: world.squat.id, muscle: .quadriceps, role: .primary, position: 1),
            RemoteMuscleGroupRow(exerciseId: world.squat.id, muscle: .glutes, role: .secondary, position: 2)
        ]
        #expect(await world.stored(RemoteMuscleGroupRow.self) == PushWorld.byId(muscles))
        #expect(await server.stored(RemoteRoutineRow.self).map(PushWorld.plain) == [
            RemoteRoutineRow(
                id: routine.id, userId: world.userId, name: "Legs", description: "Heavy", isFavorite: true
            )
        ])
        #expect(await world.stored(RemoteRoutineItemRow.self) == PushWorld.byId(world.itemRows(routine)))
        try world.expectNothingPending()
    }

    @Test("sets deleted after a push are deleted on the server by the next push")
    func removedSetsReachServer() async throws {
        let session = try world.finishedSession()
        try await engine.push()
        let removed = try #require(try store.sessions.session(id: session.id)?.entries.first?.sets.last)

        try store.sessions.deleteManualSet(id: removed.id)
        try await engine.push()

        let local = try #require(try store.sessions.session(id: session.id))
        #expect(await world.stored(RemoteSetRow.self)
            == PushWorld.byId(PushWorld.rows(of: local, userId: world.userId).sets))
        #expect(await server.stored(RemoteSetRow.self).contains { $0.id == removed.id } == false)
        try world.expectNothingPending()
    }

    // MARK: - S7, S9: what is never sent

    @Test("a session in progress is not uploaded")
    func inProgressIsNotUploaded() async throws {
        let session = try world.startSession()
        try store.sessions.logManualSet(
            SetValues(reps: 5), exerciseId: world.bench.id, sessionId: session.id, at: world.t0
        )

        let report = try await engine.push()

        // Only the user exercise, which is not part of the session.
        #expect(report.pushed == [SyncAggregateRef(.exercise, id: world.squat.id)])
        #expect(await server.stored(RemoteSessionRow.self).isEmpty)
        #expect(await server.calls.contains(.pushSession(session.id)) == false)
    }

    @Test("data written before the sign-in and catalogue exercises stay on the device")
    func localOnlyDataIsNotUploaded() async throws {
        let unowned = try PushWorld(claimed: false)
        let sampleRoutine = try unowned.saveRoutine()
        let sampleSession = try unowned.finishedSession(routineId: sampleRoutine.id)
        try unowned.claim()
        // A session of the signed-in user that uses the sample exercise and routine.
        let mixed = try unowned.finishedSession(routineId: sampleRoutine.id, at: 7_200)

        let report = try await unowned.engine.push()

        #expect(report.pushed.isEmpty)
        #expect(report.skipped == [
            .init(
                aggregate: .init(.session, id: mixed.id),
                reason: .usesLocalOnlyData(.init(.routine, id: sampleRoutine.id))
            )
        ])
        #expect(await unowned.server.calls.isEmpty)
        #expect(try unowned.store.syncState.pendingSessions().map(\.id) == [mixed.id])
        #expect(try unowned.store.sessions.session(id: sampleSession.id) != nil)
    }

    @Test("a session that only uses the catalogue goes up without uploading the catalogue")
    func catalogueIsNeverUploaded() async throws {
        let session = try world.finishedSession(exerciseId: world.bench.id)

        let report = try await engine.push()

        #expect(report.pushed == [
            SyncAggregateRef(.exercise, id: world.squat.id),
            SyncAggregateRef(.session, id: session.id)
        ])
        #expect(await server.stored(RemoteExerciseRow.self).map(\.id) == [world.squat.id])
        #expect(await server.stored(RemoteSessionRow.self).map(\.id) == [session.id])
    }

    // MARK: - S3, S4: failures

    @Test("offline, the session stays pending; back online it is sent exactly once and marked clean")
    func offlineThenOnline() async throws {
        try await world.uploadPrerequisites()
        let session = try world.finishedSession()
        await server.failNext(.pushSession)

        await #expect(throws: URLError.self) { try await engine.push() }
        #expect(await server.stored(RemoteSessionRow.self).isEmpty)
        #expect(try store.syncState.pendingSessions().map(\.id) == [session.id])
        #expect(try store.syncState.pendingSessions().first?.failureCount == 0)

        try await engine.push()
        try await engine.push()

        #expect(await server.stored(RemoteSessionRow.self).map(\.id) == [session.id])
        #expect(await server.calls.filter { $0 == .pushSession(session.id) }.count == 2)
        try world.expectNothingPending()
    }

    @Test("a network failure part way keeps every session pending and intact; the next push completes them")
    func failureMidwayKeepsPending() async throws {
        try await world.uploadPrerequisites()
        let first = try world.finishedSession()
        let second = try world.finishedSession(at: 7_200)
        let before = try [first.id, second.id].map { try store.sessions.session(id: $0) }
        await server.failNextPush(at: .sets)

        await #expect(throws: URLError.self) { try await engine.push() }

        #expect(await server.stored(RemoteSessionRow.self).map(\.id) == [first.id])
        #expect(await server.stored(RemoteSetRow.self).isEmpty)
        #expect(try store.syncState.pendingSessions().map(\.id) == [first.id, second.id])
        #expect(try [first.id, second.id].map { try store.sessions.session(id: $0) } == before)

        let report = try await engine.push()

        #expect(report.pushed == [SyncAggregateRef(.session, id: first.id), SyncAggregateRef(.session, id: second.id)])
        let expectedSets = try [first.id, second.id].flatMap { id in
            try PushWorld.rows(of: #require(try store.sessions.session(id: id)), userId: world.userId).sets
        }
        #expect(await world.stored(RemoteSetRow.self) == PushWorld.byId(expectedSets))
        try world.expectNothingPending()
    }

    @Test("an edit made while the session uploads keeps it pending, and the next push sends the edit")
    func editDuringUploadStaysPending() async throws {
        try await world.uploadPrerequisites()
        let session = try world.finishedSession()
        let setId = try #require(session.entries.first?.sets.first?.id)
        let store = store
        await server.duringNextPush {
            await MainActor.run { _ = try? store.sessions.setWarmup(true, setId: setId) }
        }

        let report = try await engine.push()

        #expect(report.pushed == [SyncAggregateRef(.session, id: session.id)])
        #expect(await server.stored(RemoteSetRow.self).first { $0.id == setId }?.warmup == false)
        #expect(try store.syncState.pendingSessions().map(\.id) == [session.id])

        try await engine.push()

        #expect(await server.stored(RemoteSetRow.self).first { $0.id == setId }?.warmup == true)
        try world.expectNothingPending()
    }

    @Test("a session the server refuses is recorded and does not block the next one")
    func rejectedSessionDoesNotBlockOthers() async throws {
        try await world.uploadPrerequisites()
        let refused = try world.finishedSession()
        let next = try world.finishedSession(at: 7_200)
        let rejection = RemoteStoreError.rejected(code: "23505", message: "sessions_external_ref_key")
        await server.failNext(.pushSession, with: rejection)

        let report = try await engine.push()

        #expect(report.rejected == [.init(aggregate: .init(.session, id: refused.id), error: rejection)])
        #expect(report.pushed == [SyncAggregateRef(.session, id: next.id)])
        #expect(await server.stored(RemoteSessionRow.self).map(\.id) == [next.id])
        let pending = try #require(try store.syncState.pendingSessions().first)
        #expect(pending.id == refused.id)
        #expect(pending.failureCount == 1)
        #expect(pending.lastError == String(describing: rejection))
        #expect(try store.sessions.session(id: refused.id) == refused)

        let retry = try await engine.push()

        #expect(retry.pushed == [SyncAggregateRef(.session, id: refused.id)])
        #expect(Set(await server.stored(RemoteSessionRow.self).map(\.id)) == [refused.id, next.id])
        try world.expectNothingPending()
    }

    @Test("a refused exercise holds back the routine and sessions that use it, and nothing else")
    func rejectedExerciseHoldsBackDependents() async throws {
        let routine = try world.saveRoutine()
        let dependent = try world.finishedSession(routineId: routine.id)
        let independent = try world.finishedSession(exerciseId: world.bench.id, at: 7_200)
        let rejection = RemoteStoreError.rejected(code: "23505", message: "exercises_external_ref_key")
        await server.failNext(.upsert, with: rejection)

        let report = try await engine.push()

        let squat = SyncAggregateRef(.exercise, id: world.squat.id)
        #expect(report.rejected == [.init(aggregate: squat, error: rejection)])
        #expect(report.skipped == [
            .init(aggregate: .init(.routine, id: routine.id), reason: .waitsFor(squat)),
            .init(aggregate: .init(.session, id: dependent.id), reason: .waitsFor(.init(.routine, id: routine.id)))
        ])
        #expect(report.pushed == [SyncAggregateRef(.session, id: independent.id)])
        #expect(await server.stored(RemoteSessionRow.self).map(\.id) == [independent.id])
        #expect(try store.syncState.pending(.exercise).first?.failureCount == 1)

        try await engine.push()

        #expect(Set(await server.stored(RemoteSessionRow.self).map(\.id)) == [dependent.id, independent.id])
        try world.expectNothingPending()
    }

    // MARK: - S10, concurrency

    @Test("a store owned by another user, or by nobody, pushes nothing", arguments: [true, false])
    func ownerMismatchPushesNothing(otherOwner: Bool) async throws {
        let unowned = try PushWorld(claimed: false)
        let owner = UUID()
        if otherOwner { _ = try unowned.store.ownership.claim(userId: owner, at: unowned.t0) }
        _ = try unowned.finishedSession()
        let pendingBefore = try unowned.store.syncState.pendingSessions()

        let refusal = TrainingSyncError.storeNotOwned(userId: unowned.userId, owner: otherOwner ? owner : nil)
        await #expect(throws: refusal) {
            try await unowned.engine.fullSync()
        }

        #expect(await unowned.server.calls.isEmpty)
        #expect(try unowned.store.syncState.pendingSessions() == pendingBefore)
    }

    @Test("two syncs started together send each session once")
    func concurrentSyncsDoNotDoublePush() async throws {
        let session = try world.finishedSession()

        async let first: Void = engine.fullSync()
        async let second: Void = engine.fullSync()
        _ = try await (first, second)

        #expect(await server.calls.filter { $0 == .pushSession(session.id) }.count == 1)
        #expect(await server.calls.filter { $0 == .upsert(.exercises, count: 1) }.count == 1)
        try world.expectNothingPending()
    }
}
