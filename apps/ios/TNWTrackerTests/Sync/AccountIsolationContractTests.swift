import Foundation
import Supabase
import Testing
@testable import TNWTrackerKit

/// S10 against the local Supabase stack: two accounts, each with its own store
/// and client, never receive nor write each other's rows. Skipped when the stack
/// is not configured or not running (see `LocalSupabaseStack`).
@Suite(
    "Two accounts on the local stack",
    .enabled("needs the local Supabase stack") { await LocalSupabaseStack.isAvailable() }
)
struct AccountIsolationContractTests {
    @Test("S10 account B's sync never receives nor writes account A's rows")
    func accountsNeverSeeEachOther() async throws {
        try await LocalSupabaseStack.withThrowawayUser { clientA, userA in
            try await LocalSupabaseStack.withThrowawayUser { clientB, userB in
                try await Self.accountsNeverSeeEachOther(
                    a: (clientA, userA),
                    b: (clientB, userB)
                )
            }
        }
    }

    @MainActor
    private static func accountsNeverSeeEachOther(
        a: (client: SupabaseClient, user: UUID),
        b: (client: SupabaseClient, user: UUID)
    ) async throws {
        let phoneA = try PushWorld(userId: a.user)
        let routine = try phoneA.saveRoutine()
        let session = try phoneA.finishedSession(routineId: routine.id)
        let remoteA = SupabaseTrainingRemoteStore(client: a.client, userId: a.user)
        try await TrainingSyncEngine(store: phoneA.store, remote: remoteA, userId: a.user).sync()
        let sessionsOfA = try await TrainingRemoteStoreContract.pullAll(RemoteSessionRow.self, from: remoteA)
        let routinesOfA = try await TrainingRemoteStoreContract.pullAll(RemoteRoutineRow.self, from: remoteA)
        #expect(sessionsOfA.map(\.id) == [session.id])

        let phoneB = try PushWorld(userId: b.user)
        let remoteB = SupabaseTrainingRemoteStore(client: b.client, userId: b.user)
        try await TrainingSyncEngine(store: phoneB.store, remote: remoteB, userId: b.user).sync()

        // B's store holds nothing of A.
        #expect(try phoneB.store.sessions.session(id: session.id) == nil)
        #expect(try phoneB.store.routines.routine(id: routine.id) == nil)
        #expect(try !phoneB.store.exercises.exercises().map(\.id).contains(phoneA.squat.id))
        #expect(try await TrainingRemoteStoreContract.pullAll(RemoteSessionRow.self, from: remoteB).isEmpty)
        // A row naming A, written with B's session, is refused by row-level security.
        await #expect(throws: (any Error).self) {
            try await remoteB.upsert([RemoteRoutineRow(id: UUID(), userId: a.user, name: "Not yours")])
        }
        // A's store through B's client: refused before any request.
        let aThroughB = SupabaseTrainingRemoteStore(client: b.client, userId: a.user)
        await #expect(throws: RemoteSessionError.notSignedInAsAccount) {
            try await TrainingSyncEngine(store: phoneA.store, remote: aThroughB, userId: a.user).sync()
        }
        // A's rows on the server are as A left them.
        #expect(try await TrainingRemoteStoreContract.pullAll(RemoteSessionRow.self, from: remoteA) == sessionsOfA)
        #expect(try await TrainingRemoteStoreContract.pullAll(RemoteRoutineRow.self, from: remoteA) == routinesOfA)
    }
}
