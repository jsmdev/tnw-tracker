import Foundation
import Supabase
import Testing
@testable import TNWTrackerKit

/// S10 against the local Supabase stack: the remote store of one account names
/// its user in every delete and pull, and uses an answer only while the client
/// is still that account's. The signed-in user the store reads stands in for a
/// sign-in that changed during a request. Skipped without the stack.
@Suite(
    "Remote store bound to one account (local stack)",
    .enabled("needs the local Supabase stack") { await LocalSupabaseStack.isAvailable() }
)
struct SupabaseRemoteBindingContractTests {
    @Test("S10 a request sent with another account's token reaches none of its rows")
    func anotherAccountsTokenReachesNothing() async throws {
        try await LocalSupabaseStack.withThrowawayUser { client, owner in
            let mine = SupabaseTrainingRemoteStore(client: client, userId: owner)
            let exercise = RemoteExerciseRow(id: UUID(), userId: owner, name: "Cable row", type: .strength)
            try await mine.upsert([exercise])
            let routine = RemoteRoutineRow(id: UUID(), userId: owner, name: "Legs")
            try await mine.upsert([routine])
            let item = RemoteRoutineItemRow(
                id: UUID(), userId: owner, routineId: routine.id, position: 1, exerciseId: exercise.id
            )
            try await mine.upsert([item])
            let session = TrainingRemoteStoreContract.finishedSession(for: owner)
            try await mine.pushSession(session)
            // Another account's store whose check of the signed-in user was fooled.
            let other = UUID()
            let fooled = SupabaseTrainingRemoteStore(client: client, userId: other) { other }

            let routines = try await fooled.pull(RemoteRoutineRow.self, after: nil, limit: 10)
            let exercises = try await TrainingRemoteStoreContract.pullAll(RemoteExerciseRow.self, from: fooled)
            try await fooled.delete(.routines, ids: [routine.id])
            try await fooled.deleteChildren(.routineItems, of: routine.id, keeping: [])
            var removing = TrainingRemoteStoreContract.finishedSession(for: other)
            removing.session.id = session.session.id
            removing.entries = []
            removing.sets = []
            removing.removedEntryIds = session.entries.map(\.id)
            removing.removedSetIds = session.sets.map(\.id)
            // Nothing of the owner's is deleted, and the session row naming another user is refused.
            await #expect(throws: RemoteStoreError.self) { try await fooled.pushSession(removing) }

            #expect(routines.rows.isEmpty)
            #expect(exercises.allSatisfy { $0.userId == nil }, "the catalogue only")
            #expect(Set(exercises.map(\.id)).isSuperset(of: TrainingRemoteStoreContract.catalogue))
            #expect(try await TrainingRemoteStoreContract.pullAll(RemoteRoutineRow.self, from: mine).map(\.id) == [
                routine.id
            ])
            #expect(try await TrainingRemoteStoreContract.pullAll(RemoteRoutineItemRow.self, from: mine).map(\.id) == [
                item.id
            ])
            let entries = try await TrainingRemoteStoreContract.pullAll(RemoteEntryRow.self, from: mine)
            let sets = try await TrainingRemoteStoreContract.pullAll(RemoteSetRow.self, from: mine)
            #expect(Set(entries.map(\.id)) == Set(session.entries.map(\.id)))
            #expect(Set(sets.map(\.id)) == Set(session.sets.map(\.id)))
        }
    }

    @Test("S10 a delete answered after another account signed in is thrown away, so no tombstone is cleared")
    func deleteAnsweredUnderAnotherAccountThrows() async throws {
        try await LocalSupabaseStack.withThrowawayUser { client, owner in
            let mine = SupabaseTrainingRemoteStore(client: client, userId: owner)
            let routine = RemoteRoutineRow(id: UUID(), userId: owner, name: "Legs")
            try await mine.upsert([routine])
            let reads = Counter()
            let switching = SupabaseTrainingRemoteStore(client: client, userId: owner) {
                reads.next() == 1 ? owner : UUID()
            }

            await #expect(throws: RemoteSessionError.notSignedInAsAccount) {
                try await switching.delete(.routines, ids: [routine.id])
            }
        }
    }

    @Test("S10 the user's own pulls still read the catalogue and their own exercises")
    func exercisesPullReadsCatalogueAndOwn() async throws {
        try await LocalSupabaseStack.withThrowawayUser { client, owner in
            let mine = SupabaseTrainingRemoteStore(client: client, userId: owner)
            let exercise = RemoteExerciseRow(id: UUID(), userId: owner, name: "Cable row", type: .strength)
            try await mine.upsert([exercise])

            let exercises = try await TrainingRemoteStoreContract.pullAll(RemoteExerciseRow.self, from: mine)

            #expect(exercises.contains { $0.id == exercise.id })
            #expect(Set(exercises.map(\.id)).isSuperset(of: TrainingRemoteStoreContract.catalogue))
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}
