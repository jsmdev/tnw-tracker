import Foundation
import Observation
import Supabase
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// How the app starts the sync of the signed-in account (S3, S12) and claims its
/// store at sign-in (S10): the real accounts, store, scheduler and engine against
/// the in-memory server.
@Suite("App sync wiring")
@MainActor
struct AppSyncWiringTests {
    let server = InMemoryTrainingRemoteStore()
    let network = NetworkMonitor(monitorsPath: false)
    let accounts: AppAccounts
    let user = UUID()

    init() {
        accounts = AppAccounts.makeForTesting(
            authRepository: AuthRepositoryMock(), remote: { [server] _ in server }, networkMonitor: network
        )
    }

    private func syncRuns() async -> Int {
        await server.calls.filter {
            if case .pull(.tombstones, _, _) = $0 { return true }
            return false
        }.count
    }

    private func signIn(_ userId: UUID, event: AuthChangeEvent = .signedIn) async throws -> AppEnvironment {
        await accounts.handle(AuthStateChange(event: event, userId: userId))
        let env = try #require(accounts.current)
        await env.syncScheduler.waitUntilIdle()
        return env
    }

    @Test("S10 signing in opens the account claimed for the user, and syncs it", arguments: [
        AuthChangeEvent.signedIn, .initialSession
    ])
    func signInClaimsAndSyncs(event: AuthChangeEvent) async throws {
        let env = try await signIn(user, event: event)

        #expect(accounts.isAuthenticated)
        #expect(env.userId == user)
        #expect(env.storeOwner() == user)
        #expect(env.syncScheduler.status == .idle)
        #expect(await syncRuns() == 1)
    }

    @Test("S10 a session event without a user opens no account")
    func eventWithoutUserOpensNothing() async {
        await accounts.handle(AuthStateChange(event: .initialSession, userId: nil))

        #expect(accounts.current == nil)
        #expect(await server.calls.isEmpty)
    }

    @Test("S10 an account whose store cannot be opened stays signed out on the device, and nothing syncs")
    func storeThatCannotOpenOpensNothing() async {
        let broken = AppAccounts.makeForTesting(
            authRepository: AuthRepositoryMock(),
            remote: { [server] _ in server },
            openStore: { _ in throw CocoaError(.fileReadCorruptFile) }
        )

        await broken.handle(AuthStateChange(event: .signedIn, userId: user))

        #expect(broken.current == nil)
        #expect(await server.calls.isEmpty)
    }

    @Test("S10 other auth events, such as a token refresh, leave the account as it is")
    func otherEventsChangeNothing() async throws {
        let env = try await signIn(user)

        await accounts.handle(AuthStateChange(event: .tokenRefreshed, userId: user))

        #expect(accounts.current === env)
        #expect(await syncRuns() == 1)
    }

    @Test("S12 signing in again as the same account keeps it open and syncs")
    func sameAccountAgainSyncs() async throws {
        let env = try await signIn(user)

        let again = try await signIn(user)

        #expect(again === env)
        #expect(await syncRuns() == 2)
    }

    @Test("S12 signed out, foreground and reconnection do not sync")
    func signedOutDoesNotSync() async {
        network.apply(online: false)
        network.apply(online: true)

        #expect(accounts.current == nil)
        #expect(await server.calls.isEmpty)
    }

    @Test("S12 coming to the foreground syncs")
    func foregroundSyncs() async throws {
        let env = try await signIn(user)

        env.sceneDidBecomeActive()
        await env.syncScheduler.waitUntilIdle()

        #expect(await syncRuns() == 2)
    }

    @Test("S3 the network coming back syncs; staying online does not")
    func reconnectionSyncs() async throws {
        let env = try await signIn(user)

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

    @Test("S12 signing out stops the sync and closes the account")
    func signOutStopsSync() async throws {
        let env = try await signIn(user)

        await accounts.handle(AuthStateChange(event: .signedOut, userId: nil))
        network.apply(online: false)
        network.apply(online: true)
        env.syncScheduler.requestSync()
        await env.syncScheduler.waitUntilIdle()

        #expect(accounts.current == nil)
        #expect(env.syncScheduler.status == .signedOut)
        #expect(await syncRuns() == 1)
    }

    // MARK: - Debug sample data

    @Test("S9 S10 the reset to sample data claims the store again and never sends the sample data")
    func replaceWithSampleDataReclaims() async throws {
        let env = try await signIn(user)

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

    @Test("S10 the reset to sample data stops a running sync first: it reads nothing more into the reset store",
          .timeLimit(.minutes(1)))
    func replaceWithSampleDataStopsTheRunningSync() async throws {
        let env = try await signIn(user)
        let reached = AsyncGate()
        let release = AsyncGate()
        await server.duringNextPull {
            await reached.open()
            await release.wait()
        }
        let before = await server.calls.count
        env.sceneDidBecomeActive()
        await reached.wait()

        try env.replaceWithSampleData()
        await release.open()
        await env.syncScheduler.waitUntilIdle()

        let pulls = await server.calls.dropFirst(before).compactMap { call -> RemoteTable? in
            if case let .pull(table, _, _) = call { return table }
            return nil
        }
        #expect(pulls == [.tombstones] + SyncSchedulerTests.pullOrder)
        #expect(env.storeOwner() == user)
        #expect(env.syncScheduler.status == .idle)
    }
}
