import Foundation
import Supabase
import SwiftData
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// S10: "Si alguien entra en la app, en mi propio móvil, con su cuenta, verá
/// solo lo suyo, no lo mío." Two accounts on one device, through the auth
/// changes the app receives: real accounts, on-disk stores under a temporary
/// root, scheduler and engine; each account has its own in-memory server, as
/// row-level security gives it. Invented data only.
@Suite("Accounts on one device (S10)")
@MainActor
final class AccountSwitchTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "account-switch-\(UUID().uuidString)")
    let userA = UUID()
    let userB = UUID()
    let serverA = InMemoryTrainingRemoteStore()
    let serverB = InMemoryTrainingRemoteStore()
    let defaultsName = "account-switch-\(UUID().uuidString)"
    let widget: NextRoutineSnapshot
    let stores: AccountStores
    let accounts: AppAccounts
    /// Which account was open when a held request of A ended, in `switchDuringASync`.
    var openWhileInFlight: UUID??

    init() throws {
        stores = AccountStores(root: root)
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        widget = NextRoutineSnapshot(defaults: defaults)
        accounts = Self.accounts(stores: stores, servers: [userA: serverA, userB: serverB], widget: widget)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        UserDefaults().removePersistentDomain(forName: defaultsName)
    }

    private static func accounts(
        stores: AccountStores,
        servers: [UUID: InMemoryTrainingRemoteStore],
        widget: NextRoutineSnapshot? = nil,
        loadsSampleData: Bool = false
    ) -> AppAccounts {
        AppAccounts.makeForTesting(
            authRepository: AuthRepositoryMock(),
            remote: { servers[$0] ?? InMemoryTrainingRemoteStore() },
            openStore: { try stores.open(for: $0) },
            widget: widget,
            loadsSampleData: loadsSampleData
        )
    }

    /// A catalogue exercise every server holds (supabase/seed.sql).
    static let bench = Exercise(
        id: TrainingRemoteStoreContract.benchPress, isCatalogue: true, name: "Bench Press", type: .strength
    )

    private func signIn(_ userId: UUID) async throws -> AppEnvironment {
        await accounts.handle(AuthStateChange(event: .signedIn, userId: userId))
        let env = try #require(accounts.current)
        await env.syncScheduler.waitUntilIdle()
        return env
    }

    private func signOut() async {
        await accounts.handle(AuthStateChange(event: .signedOut, userId: nil))
    }

    @discardableResult
    private func saveRoutine(_ name: String, in env: AppEnvironment) throws -> Routine {
        try env.exerciseRepository.save(Self.bench)
        let routine = Routine(name: name, items: [RoutineItem(order: 1, exerciseId: Self.bench.id, targetSets: 3)])
        try env.routineRepository.save(routine)
        return routine
    }

    private func routineNames(_ env: AppEnvironment) throws -> [String] {
        try env.routineRepository.routines(RoutineQuery()).map(\.name)
    }

    // MARK: - Each account sees only its own data

    @Test("S10 another account signing in on the device sees only its own data, and the first one finds its own again")
    func eachAccountSeesOnlyItsOwn() async throws {
        let a = try await signIn(userA)
        try saveRoutine("Legs A", in: a)
        await signOut()
        #expect(accounts.current == nil, "signed out, no account's store is open")

        let b = try await signIn(userB)
        #expect(try routineNames(b).isEmpty)
        #expect(b.storeOwner() == userB)
        try saveRoutine("Push B", in: b)
        await signOut()

        // Returning to A reopens its store as it was left, with no download needed.
        await serverA.failNext(.pull)
        let again = try await signIn(userA)
        #expect(try routineNames(again) == ["Legs A"])
        #expect(again.syncScheduler.status == .failed, "the pull failed, and the data was there anyway")
        #expect(await !serverB.stored(RemoteRoutineRow.self).map(\.name).contains("Legs A"))
        #expect(await serverA.stored(RemoteRoutineRow.self).map(\.name) == ["Legs A"])
    }

    @Test("S10 a new account's empty store fills from its server on the first sync")
    func newStoreFillsFromTheServer() async throws {
        let row = RemoteExerciseRow(id: UUID(), userId: userB, name: "Cable Row", type: .strength)
        try await serverB.insertOnServer(row)

        let b = try await signIn(userB)

        #expect(try b.exerciseRepository.exercises().map(\.name) == ["Cable Row"])
    }

    @Test("S10 another account signing in without a sign-out between also gets only its own store")
    func switchWithoutSignOut() async throws {
        let a = try await signIn(userA)
        try saveRoutine("Legs A", in: a)

        let b = try await signIn(userB)

        #expect(try routineNames(b).isEmpty)
        #expect(accounts.current?.userId == userB)
    }

    // MARK: - A workout in progress

    @Test("S10 a workout in progress at sign-out stays in its own account's store and never moves to the next")
    func workoutInProgressStaysWithItsAccount() async throws {
        let a = try await signIn(userA)
        let routine = try saveRoutine("Legs A", in: a)
        let coordinator = a.makeActiveWorkoutCoordinator()
        a.activeCoordinator = coordinator
        try await coordinator.start(routineId: routine.id)
        try await coordinator.recordSet(reps: 5, weight: nil, rir: nil)
        let workoutId = try #require(coordinator.activeWorkoutId)

        #expect(coordinator.timerState != nil, "the set started a rest")

        await signOut()
        #expect(coordinator.phase == .idle, "left where it is, nothing finished")
        #expect(coordinator.activeWorkoutId == nil)
        #expect(coordinator.timerState == nil, "its rest timer stopped, so it records nothing later")

        let b = try await signIn(userB)
        #expect(try b.sessionRepository.activeSession() == nil)
        #expect(try b.sessionRepository.session(id: workoutId) == nil)
        await signOut()

        let again = try await signIn(userA)
        let resumed = try #require(try again.sessionRepository.activeSession())
        #expect(resumed.id == workoutId)
        #expect(resumed.completedAt == nil)
        #expect(resumed.entries.flatMap(\.sets).count == 1)
        #expect(await !serverA.calls.contains(.pushSession(workoutId)), "a workout in progress is never sent (S9)")
    }

    @Test("S10 once signed out, nothing keeps the account's store, its screens' state or its workout")
    func signOutReleasesTheAccount() async throws {
        weak var weakEnv: AppEnvironment?
        weak var weakStore: TrainingStore?
        weak var weakCoordinator: ActiveWorkoutCoordinator?
        do {
            let a = try await signIn(userA)
            let routine = try saveRoutine("Legs A", in: a)
            let coordinator = a.makeActiveWorkoutCoordinator()
            a.activeCoordinator = coordinator
            try await coordinator.start(routineId: routine.id)
            try await coordinator.recordSet(reps: 5, weight: nil, rir: nil)
            a.router.push(.settings)
            weakEnv = a
            weakStore = a.store
            weakCoordinator = coordinator
        }

        await signOut()

        #expect(weakCoordinator == nil)
        #expect(weakEnv == nil)
        #expect(weakStore == nil)
    }

    // MARK: - A sync in flight

    @Test(
        "S10 another account signing in during a sync: it stops before applying, and the next store opens after it",
        .timeLimit(.minutes(1))
    )
    func switchDuringASync() async throws {
        let rowOfA = RemoteExerciseRow(id: UUID(), userId: userA, name: "Cable Row", type: .strength)
        try await serverA.insertOnServer(rowOfA)
        _ = try await signIn(userA)
        let reached = AsyncGate()
        // A's next sync is held at its last table, like a request in flight.
        await serverA.duringNextPull(of: .exercises) { [self] in
            await reached.open()
            await AsyncGate().waitUnlessCancelled()
            await MainActor.run { openWhileInFlight = .some(accounts.current?.userId) }
        }
        try await serverA.insertOnServer(
            RemoteExerciseRow(id: UUID(), userId: userA, name: "Hip Thrust", type: .strength)
        )
        accounts.current?.sceneDidBecomeActive()
        await reached.wait()
        let callsOfA = await serverA.calls.count

        let b = try await signIn(userB)

        #expect(openWhileInFlight == .some(nil), "B opened only once A's request had ended")
        #expect(await serverA.calls.count == callsOfA, "A's sync sent nothing more")
        #expect(try b.exerciseRepository.exercises().isEmpty)
        #expect(await serverB.calls.allSatisfy { call in
            if case .pull = call { return true }
            return false
        })
        await signOut()
        await serverA.failNext(.pull)
        let a = try await signIn(userA)
        #expect(try a.exerciseRepository.exercises().map(\.name) == ["Cable Row"], "the stopped pull applied nothing")
    }

    // MARK: - Other state of the account

    @Test("S10 signing out forgets the lock-screen intents sent for the account's workout")
    func signOutForgetsPendingIntents() async throws {
        let mailbox = try ModelContainerFactory.makeIntentMailboxContainer(inMemory: true)
        let accounts = AppAccounts.makeForTesting(
            authRepository: AuthRepositoryMock(),
            remote: { [serverA] _ in serverA },
            intentInbox: IntentInbox(container: mailbox)
        )
        await accounts.handle(AuthStateChange(event: .signedIn, userId: userA))
        try await IntentMailbox(container: mailbox).enqueue(workoutId: UUID(), kind: "pause")

        await accounts.handle(AuthStateChange(event: .signedOut, userId: nil))

        #expect(try ModelContext(mailbox).fetchCount(FetchDescriptor<WorkoutIntentEvent>()) == 0)
    }

    @Test("S10 a launch with no session clears what an account left on the device", arguments: [
        AuthChangeEvent.initialSession, .signedOut
    ])
    func launchWithoutSessionClearsLeftovers(event: AuthChangeEvent) async throws {
        let cache = URLCache(memoryCapacity: 1 << 20, diskCapacity: 0)
        let mailbox = try ModelContainerFactory.makeIntentMailboxContainer(inMemory: true)
        let accounts = AppAccounts.makeForTesting(
            authRepository: AuthRepositoryMock(),
            remote: { [serverA] _ in serverA },
            intentInbox: IntentInbox(container: mailbox),
            widget: widget,
            urlCache: cache
        )
        widget.publish("Legs A")
        try await IntentMailbox(container: mailbox).enqueue(workoutId: UUID(), kind: "pause")
        let url = try #require(URL(string: "https://cache.example.test/rest/v1/routines"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        cache.storeCachedResponse(
            CachedURLResponse(response: response, data: Data("[]".utf8)), for: URLRequest(url: url)
        )

        await accounts.handle(AuthStateChange(event: event, userId: nil))

        #expect(accounts.current == nil)
        #expect(widget.routineName == nil)
        #expect(try ModelContext(mailbox).fetchCount(FetchDescriptor<WorkoutIntentEvent>()) == 0)
        #expect(cache.cachedResponse(for: URLRequest(url: url)) == nil)
    }

    @Test("S10 signing out empties the URL cache")
    func signOutEmptiesTheURLCache() async throws {
        let cache = URLCache(memoryCapacity: 1 << 20, diskCapacity: 0)
        let accounts = AppAccounts.makeForTesting(
            authRepository: AuthRepositoryMock(), remote: { [serverA] _ in serverA }, urlCache: cache
        )
        let url = try #require(URL(string: "https://cache.example.test/rest/v1/sessions"))
        let request = URLRequest(url: url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        await accounts.handle(AuthStateChange(event: .signedIn, userId: userA))
        cache.storeCachedResponse(CachedURLResponse(response: response, data: Data("[]".utf8)), for: request)
        #expect(cache.cachedResponse(for: request) != nil)

        await accounts.handle(AuthStateChange(event: .signedOut, userId: nil))

        #expect(cache.cachedResponse(for: request) == nil)
    }

    // MARK: - Widget

    @Test("S10 the widget shows the signed-in account's next routine, nothing while signed out, never another's")
    func widgetFollowsTheAccount() async throws {
        let a = try await signIn(userA)
        try saveRoutine("Legs A", in: a)
        accounts.sceneDidEnterBackground()
        #expect(widget.routineName == "Legs A")

        await signOut()
        #expect(widget.routineName == nil)

        _ = try await signIn(userB)
        #expect(widget.routineName == nil)
    }

    // MARK: - Owner stamp

    @Test("S10 an account's store stamped with another user never syncs, and nothing is deleted")
    func storeStampedWithAnotherUserNeverSyncs() async throws {
        do {
            let store = try stores.open(for: userA).store
            _ = try store.ownership.claim(userId: userB, at: TrainingFixtures.t0)
            try store.exercises.save(Self.bench)
        }

        let a = try await signIn(userA)

        #expect(a.syncScheduler.status == .storeNotOwned(owner: userB))
        #expect(await serverA.calls.isEmpty)
        #expect(try a.exerciseRepository.exercises().map(\.name) == ["Bench Press"])
    }

    // MARK: - Debug sample data

    @Test("S9 S10 the sample data goes only into a new store, before it is claimed, and is never sent")
    func sampleDataOnlyInANewStore() async throws {
        let accounts = Self.accounts(stores: stores, servers: [userA: serverA], loadsSampleData: true)
        await accounts.handle(AuthStateChange(event: .signedIn, userId: userA))
        let a = try #require(accounts.current)
        await a.syncScheduler.waitUntilIdle()
        let sample = try routineNames(a)
        #expect(!sample.isEmpty)
        #expect(a.storeOwner() == userA)
        #expect(try SyncAggregateKind.allCases.allSatisfy { try a.store.syncState.pending($0).isEmpty })
        await accounts.handle(AuthStateChange(event: .signedOut, userId: nil))

        await accounts.handle(AuthStateChange(event: .signedIn, userId: userA))
        let again = try #require(accounts.current)
        await again.syncScheduler.waitUntilIdle()

        #expect(try routineNames(again) == sample, "an existing store gets no sample data again")
        #expect(await !serverA.calls.contains { call in
            if case .upsert = call { return true }
            if case .pushSession = call { return true }
            return false
        })
    }
}
