import Foundation
import Testing
@testable import TNWTrackerKit

/// When the sync runs (S3, S4, S12) and for whom (S10): the real store and
/// engine against the in-memory server. Invented data only.
@Suite("SyncScheduler")
@MainActor
struct SyncSchedulerTests {
    let store: TrainingStore
    let server = InMemoryTrainingRemoteStore()
    let scheduler: SyncScheduler
    let user = UUID()
    let t0 = TrainingFixtures.t0

    init() throws {
        store = try TrainingStore(inMemory: true)
        scheduler = SyncScheduler(store: store, remote: server, now: { TrainingFixtures.t0 })
        try store.exercises.save(Self.bench)
    }

    /// A catalogue exercise the server already holds (supabase/seed.sql).
    static let bench = Exercise(
        id: TrainingRemoteStoreContract.benchPress, isCatalogue: true, name: "Bench Press", type: .strength
    )

    /// Syncs run so far: every sync starts its pull with the tombstones.
    private func syncRuns() async -> Int {
        await server.calls.filter {
            if case .pull(.tombstones, _, _) = $0 { return true }
            return false
        }.count
    }

    private func routine(_ name: String) -> Routine {
        Routine(name: name, items: [RoutineItem(order: 1, exerciseId: Self.bench.id, targetSets: 3)])
    }

    /// Stops the next sync at its pull until `release` opens; `reached` opens once it got there.
    private func holdNextPull() async -> (reached: AsyncGate, release: AsyncGate) {
        let reached = AsyncGate()
        let release = AsyncGate()
        await server.duringNextPull {
            await reached.open()
            await release.wait()
        }
        return (reached, release)
    }

    // MARK: - Signed out

    @Test("S12 signed out, a request does nothing")
    func signedOutDoesNothing() async {
        scheduler.requestSync()
        await scheduler.waitUntilIdle()

        #expect(scheduler.status == .signedOut)
        #expect(await server.calls.isEmpty)
    }

    @Test("S12 after a sign-out, requests do nothing and the store keeps its data and owner")
    func signOutStopsTheSync() async throws {
        scheduler.signIn(userId: user)
        await scheduler.waitUntilIdle()
        try store.routines.save(routine("Push"))

        scheduler.signOut()
        scheduler.requestSync()
        await scheduler.waitUntilIdle()

        #expect(scheduler.status == .signedOut)
        #expect(await syncRuns() == 1)
        #expect(try store.ownership.owner() == user)
        #expect(try store.routines.routines(RoutineQuery()).map(\.name) == ["Push"])
    }

    @Test("S12 a request made before a sign-out runs no further sync after it")
    func signOutDropsTheQueuedRun() async throws {
        let hold = await holdNextPull()
        scheduler.signIn(userId: user)
        await hold.reached.wait()
        scheduler.requestSync()

        scheduler.signOut()
        await hold.release.open()
        await scheduler.waitUntilIdle()

        #expect(await syncRuns() == 1)
        #expect(scheduler.status == .signedOut)
    }

    // MARK: - Sign-in

    @Test("S10 S12 signing in claims the store for the user and syncs")
    func signInClaimsAndSyncs() async throws {
        scheduler.signIn(userId: user)

        #expect(try store.ownership.owner() == user)
        #expect(scheduler.status == .syncing)
        await scheduler.waitUntilIdle()
        #expect(scheduler.status == .idle)
        #expect(await syncRuns() == 1)
    }

    @Test("S10 data written right after the sign-in is the user's and is pushed")
    func writesAfterSignInSync() async throws {
        scheduler.signIn(userId: user)
        await scheduler.waitUntilIdle()
        let push = routine("Push")
        try store.routines.save(push)

        scheduler.requestSync()
        await scheduler.waitUntilIdle()

        #expect(await server.calls.contains(.upsert(.routines, count: 1)))
        #expect(try store.syncState.pending(.routine).isEmpty)
    }

    // MARK: - Coalescing

    @Test("S12 requests during a sync make exactly one more run, which sends the changes made meanwhile")
    func requestsDuringASyncCoalesce() async throws {
        let hold = await holdNextPull()
        scheduler.signIn(userId: user)
        await hold.reached.wait()
        // The first sync already pushed: only another run sends this.
        try store.routines.save(routine("Push"))

        scheduler.requestSync()
        scheduler.requestSync()
        scheduler.requestSync()
        #expect(scheduler.status == .syncing)
        await hold.release.open()
        await scheduler.waitUntilIdle()

        #expect(await syncRuns() == 2)
        #expect(await server.calls.filter { $0 == .upsert(.routines, count: 1) }.count == 1)
        #expect(try store.syncState.pending(.routine).isEmpty)
        #expect(scheduler.status == .idle)
    }

    @Test("S12 a change made while a sync is pushing is sent by the run that follows it")
    func changeDuringThePushIsSentNext() async throws {
        scheduler.signIn(userId: user)
        await scheduler.waitUntilIdle()
        let session = try store.sessions.startSession(routineId: nil, name: "Free", at: t0, timeZone: .gmt)
        _ = try store.sessions.logManualSet(
            SetValues(reps: 8), exerciseId: Self.bench.id, sessionId: session.id, at: t0.addingTimeInterval(60)
        )
        _ = try store.sessions.finishSession(id: session.id, at: t0.addingTimeInterval(600), durationSeconds: 600)
        let reached = AsyncGate()
        let release = AsyncGate()
        await server.duringNextPush {
            await reached.open()
            await release.wait()
        }
        scheduler.requestSync()
        await reached.wait()

        // Routines were already pushed: this one waits for the next run.
        try store.routines.save(routine("Push"))
        scheduler.requestSync()
        await release.open()
        await scheduler.waitUntilIdle()

        #expect(await server.calls.filter { $0 == .upsert(.routines, count: 1) }.count == 1)
        #expect(try store.syncState.pending(.routine).isEmpty)
        #expect(try store.syncState.pendingSessions().isEmpty)
    }

    @Test("S12 a request after a sync finished runs a new one")
    func requestAfterASyncRunsAgain() async {
        scheduler.signIn(userId: user)
        await scheduler.waitUntilIdle()

        scheduler.requestSync()
        await scheduler.waitUntilIdle()

        #expect(await syncRuns() == 2)
    }

    // MARK: - Failures

    @Test("S4 a failed sync is reported, keeps the change pending and the next request retries it")
    func failureIsKeptForRetry() async throws {
        scheduler.signIn(userId: user)
        await scheduler.waitUntilIdle()
        let push = routine("Push")
        try store.routines.save(push)
        await server.failNext(.upsert)

        scheduler.requestSync()
        await scheduler.waitUntilIdle()
        #expect(scheduler.status == .failed)
        #expect(try store.syncState.pending(.routine).map(\.id) == [push.id])

        scheduler.requestSync()
        await scheduler.waitUntilIdle()
        #expect(scheduler.status == .idle)
        #expect(try store.syncState.pending(.routine).isEmpty)
    }

    // MARK: - Another user's store

    /// The store as `owner` left it: claimed, with a routine of theirs.
    private func ownedByAnotherUser() throws -> (owner: UUID, routine: Routine) {
        let owner = UUID()
        _ = try store.ownership.claim(userId: owner, at: t0)
        let legs = routine("Legs")
        try store.routines.save(legs)
        return (owner, legs)
    }

    @Test("S10 another user signing in never syncs, is told whose store it is, and nothing is deleted")
    func anotherUserNeverSyncs() async throws {
        let (owner, legs) = try ownedByAnotherUser()

        scheduler.signIn(userId: user)
        scheduler.requestSync()
        await scheduler.waitUntilIdle()

        #expect(scheduler.status == .storeNotOwned(owner: owner))
        #expect(await server.calls.isEmpty)
        #expect(try store.ownership.owner() == owner)
        #expect(try store.routines.routine(id: legs.id) == legs)
        #expect(store.userWritesBlocked)
    }

    @Test("S10 another user's writes are refused and never reach the owner's account")
    func anotherUsersWritesAreRefused() async throws {
        let (owner, legs) = try ownedByAnotherUser()
        scheduler.signIn(userId: user)

        #expect(throws: TrainingDataError.storeNotOwned) { try store.routines.save(routine("Pull")) }
        #expect(throws: TrainingDataError.storeNotOwned) { try store.routines.setFavorite(true, routineId: legs.id) }
        #expect(throws: TrainingDataError.storeNotOwned) { try store.deleteAllTrainingData() }

        scheduler.signOut()
        scheduler.signIn(userId: owner)
        await scheduler.waitUntilIdle()
        #expect(scheduler.status == .idle)
        #expect(!store.userWritesBlocked)
        #expect(try store.routines.routines(RoutineQuery()).map(\.name) == ["Legs"])
        #expect(try store.routines.routine(id: legs.id)?.isFavorite == false)
        #expect(await server.calls.filter { $0 == .upsert(.routines, count: 1) }.count == 1)
    }

    @Test("S10 signing out lifts the refusal of writes")
    func signOutLiftsTheRefusal() throws {
        _ = try ownedByAnotherUser()
        scheduler.signIn(userId: user)

        scheduler.signOut()

        #expect(!store.userWritesBlocked)
    }
}
