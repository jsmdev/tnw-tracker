import Foundation
import Observation
import Supabase
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// How the app starts the sync (S3, S12) and guards the store at sign-in (S10):
/// the real environment, store, scheduler and engine against the in-memory server.
@Suite("App sync wiring")
@MainActor
struct AppSyncWiringTests {
    let server = InMemoryTrainingRemoteStore()
    let network = NetworkMonitor(monitorsPath: false)
    let env: AppEnvironment
    let user = UUID()

    init() {
        env = AppEnvironment.makeForTesting(
            authRepository: AuthRepositoryMock(), remote: server, networkMonitor: network
        )
        try? env.exerciseRepository.save(Self.bench)
    }

    /// A catalogue exercise the server already holds (supabase/seed.sql).
    static let bench = Exercise(
        id: TrainingRemoteStoreContract.benchPress, isCatalogue: true, name: "Bench Press", type: .strength
    )

    private func routine(_ name: String) -> Routine {
        Routine(name: name, items: [RoutineItem(order: 1, exerciseId: Self.bench.id, targetSets: 3)])
    }

    private func syncRuns() async -> Int {
        await server.calls.filter {
            if case .pull(.tombstones, _, _) = $0 { return true }
            return false
        }.count
    }

    private func signIn(_ userId: UUID, event: AuthChangeEvent = .signedIn) async {
        await env.handle(AuthStateChange(event: event, userId: userId))
        await env.syncScheduler.waitUntilIdle()
    }

    @Test("S10 the store is claimed before the training screens can write", arguments: [
        AuthChangeEvent.signedIn, .initialSession
    ])
    func claimsBeforeTheUIShows(event: AuthChangeEvent) async throws {
        var ownerWhenShown: UUID??
        withObservationTracking {
            _ = env.isAuthenticated
        } onChange: { [env] in
            MainActor.assumeIsolated {
                ownerWhenShown = env.storeOwner()
            }
        }

        await signIn(user, event: event)

        #expect(env.isAuthenticated)
        #expect(ownerWhenShown == .some(user))
        #expect(env.syncScheduler.status == .idle)
        #expect(await syncRuns() == 1)
    }

    @Test("S12 signed out, foreground and reconnection do not sync")
    func signedOutDoesNotSync() async {
        env.sceneDidBecomeActive()
        network.apply(online: false)
        network.apply(online: true)
        await env.syncScheduler.waitUntilIdle()

        #expect(await server.calls.isEmpty)
    }

    @Test("S12 coming to the foreground syncs")
    func foregroundSyncs() async {
        await signIn(user)

        env.sceneDidBecomeActive()
        await env.syncScheduler.waitUntilIdle()

        #expect(await syncRuns() == 2)
    }

    @Test("S3 the network coming back syncs; staying online does not")
    func reconnectionSyncs() async {
        await signIn(user)

        network.apply(online: true)
        await env.syncScheduler.waitUntilIdle()
        #expect(await syncRuns() == 1)

        network.apply(online: false)
        await env.syncScheduler.waitUntilIdle()
        #expect(await syncRuns() == 1)

        network.apply(online: true)
        await env.syncScheduler.waitUntilIdle()
        #expect(await syncRuns() == 2)
    }

    @Test("S12 signing out stops the sync")
    func signOutStopsSync() async {
        await signIn(user)

        await env.handle(AuthStateChange(event: .signedOut, userId: nil))
        env.sceneDidBecomeActive()
        await env.syncScheduler.waitUntilIdle()

        #expect(env.syncScheduler.status == .signedOut)
        #expect(await syncRuns() == 1)
    }

    @Test("S10 another user on this store: no sync, the status says so, writes refused, nothing deleted")
    func anotherUserGetsStoreNotOwned() async throws {
        let owner = UUID()
        await signIn(owner)
        let legs = routine("Legs")
        try env.routineRepository.save(legs)
        await env.handle(AuthStateChange(event: .signedOut, userId: nil))
        let callsBefore = await server.calls.count

        await signIn(user)
        env.sceneDidBecomeActive()
        await env.syncScheduler.waitUntilIdle()

        #expect(env.isAuthenticated)
        #expect(env.syncScheduler.status == .storeNotOwned(owner: owner))
        #expect(await server.calls.count == callsBefore)
        #expect(throws: TrainingDataError.storeNotOwned) {
            try env.routineRepository.save(routine("Pull"))
        }
        #expect(throws: TrainingDataError.storeNotOwned) { try env.replaceWithSampleData() }
        #expect(try env.routineRepository.routines(RoutineQuery()).map(\.id) == [legs.id])
        #expect(env.storeOwner() == owner)
    }

    // MARK: - Debug sample data

    @Test("S9 S10 the sample data loads only into a store nobody owns")
    func sampleDataOnlyWhenUnowned() async throws {
        let owned = AppEnvironment.makeForTesting(authRepository: AuthRepositoryMock(), remote: server)
        await owned.handle(AuthStateChange(event: .initialSession, userId: user))
        await owned.syncScheduler.waitUntilIdle()

        owned.loadSampleDataIfUnowned()
        #expect(try owned.exerciseRepository.exercises().isEmpty)

        let fresh = AppEnvironment.makeForTesting(authRepository: AuthRepositoryMock(), remote: server)
        fresh.loadSampleDataIfUnowned()
        #expect(try !fresh.exerciseRepository.exercises().isEmpty)
        #expect(fresh.storeOwner() == nil)
    }

    @Test("S9 S10 the reset to sample data claims the store again and never sends the sample data")
    func replaceWithSampleDataReclaims() async throws {
        await signIn(user)

        try env.replaceWithSampleData()
        await env.syncScheduler.waitUntilIdle()

        #expect(env.storeOwner() == user)
        #expect(env.syncScheduler.status == .idle)
        #expect(try !env.routineRepository.routines(RoutineQuery()).isEmpty)
        #expect(await !server.calls.contains { call in
            if case .upsert = call { return true }
            if case .pushSession = call { return true }
            return false
        })
    }
}
