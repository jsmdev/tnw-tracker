import Foundation
import SwiftData
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// S10, T9: the "Sign out" button of Settings. It ends the session with the
/// auth service and closes the account even when that service cannot be
/// reached, so nobody is left signed in with no way out. The account's data
/// stays in its store for its next sign-in. Real accounts and on-disk stores
/// under a temporary root; the auth service is a double. Invented data only.
@Suite("Sign out from Settings (S10)")
@MainActor
final class SignOutTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "sign-out-\(UUID().uuidString)")
    let userA = UUID()
    let userB = UUID()
    let auth = AuthRepositoryMock()
    let mailbox: ModelContainer
    let accounts: AppAccounts

    init() throws {
        let stores = AccountStores(root: root)
        let mailbox = try ModelContainerFactory.makeIntentMailboxContainer(inMemory: true)
        self.mailbox = mailbox
        accounts = AppAccounts.makeForTesting(
            authRepository: auth,
            remote: { _ in InMemoryTrainingRemoteStore() },
            openStore: { try stores.open(for: $0) },
            intentInbox: IntentInbox(container: mailbox)
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func signIn(_ userId: UUID) async throws -> AppEnvironment {
        await accounts.handle(AuthStateChange(event: .signedIn, userId: userId))
        let env = try #require(accounts.current)
        await env.syncScheduler.waitUntilIdle()
        return env
    }

    /// A routine and a workout in progress with one set, in the account's store.
    private func startWorkout(in env: AppEnvironment) async throws -> ActiveWorkoutCoordinator {
        let bench = Exercise(
            id: TrainingRemoteStoreContract.benchPress, isCatalogue: true, name: "Bench Press", type: .strength
        )
        try env.exerciseRepository.save(bench)
        let routine = Routine(name: "Legs A", items: [RoutineItem(order: 1, exerciseId: bench.id, targetSets: 3)])
        try env.routineRepository.save(routine)
        let coordinator = env.makeActiveWorkoutCoordinator()
        env.activeCoordinator = coordinator
        try await coordinator.start(routineId: routine.id)
        try await coordinator.recordSet(reps: 5, weight: nil, rir: nil)
        return coordinator
    }

    private func pendingIntents() throws -> Int {
        try ModelContext(mailbox).fetchCount(FetchDescriptor<WorkoutIntentEvent>())
    }

    @Test("S10 signing out ends the session and closes the account; signing in again finds its data as left")
    func signOutClosesTheAccount() async throws {
        let a = try await signIn(userA)
        let coordinator = try await startWorkout(in: a)
        let workoutId = try #require(coordinator.activeWorkoutId)
        try await IntentMailbox(container: mailbox).enqueue(workoutId: workoutId, kind: "pause")

        await accounts.signOut()

        #expect(auth.signOutCount == 1, "the session ended with the auth service")
        #expect(accounts.current == nil, "signed out: the login shows")
        #expect(coordinator.phase == .idle, "the workout's timers stopped, nothing finished")
        #expect(coordinator.timerState == nil)
        #expect(a.syncScheduler.status == .signedOut, "its sync stopped")
        #expect(try pendingIntents() == 0, "the lock-screen intents are forgotten")

        let again = try await signIn(userA)
        #expect(try again.routineRepository.routines(RoutineQuery()).map(\.name) == ["Legs A"])
        let resumed = try #require(try again.sessionRepository.activeSession())
        #expect(resumed.id == workoutId)
        #expect(resumed.completedAt == nil)
        #expect(resumed.entries.flatMap(\.sets).count == 1)
    }

    @Test("S10 the auth service unreachable (offline): the account still closes")
    func signOutOfflineStillCloses() async throws {
        auth.signOutError = URLError(.notConnectedToInternet)
        let a = try await signIn(userA)
        let coordinator = try await startWorkout(in: a)

        await accounts.signOut()

        #expect(auth.signOutCount == 1)
        #expect(accounts.current == nil, "never left signed in with no way out")
        #expect(coordinator.phase == .idle)
        #expect(a.syncScheduler.status == .signedOut)
    }

    @Test(
        "S10 a logout request answering after another account signed in leaves that account open",
        .timeLimit(.minutes(1))
    )
    func lateLogoutAnswerKeepsTheNextAccount() async throws {
        let gate = AsyncGate()
        auth.signOutGate = gate
        _ = try await signIn(userA)

        let signingOut = Task { await accounts.signOut() }
        for _ in 0 ..< 1000 where auth.signOutCount == 0 {
            await Task.yield()
        }
        try #require(auth.signOutCount == 1, "the logout request is in flight")
        // Meanwhile the auth service reported the sign-out, and B signed in.
        await accounts.handle(AuthStateChange(event: .signedOut, userId: nil))
        let b = try await signIn(userB)
        await gate.open()
        await signingOut.value

        #expect(accounts.current === b, "the late answer closes nothing of B")
        #expect(b.syncScheduler.status != .signedOut)
    }

    @Test("S10 signing out with no account open only ends the session")
    func signOutWhileSignedOut() async {
        await accounts.signOut()

        #expect(auth.signOutCount == 1)
        #expect(accounts.current == nil)
    }
}
