import Foundation
import Testing
@testable import TNWTrackerKit

/// How the server refuses rows that name what it does not hold (S4, S11, S13),
/// run against the fake and the local stack like the rest of
/// `TrainingRemoteStoreContract`, so the fake answers what the server answers.
extension TrainingRemoteStoreContract {
    /// A row naming an exercise the user cannot see (deleted on the server) is
    /// refused by row-level security, `42501`, as a refusal of the data: the
    /// session row written before it stays, its entries and sets do not.
    static func unseenExerciseIsRejected(_ harness: RemoteStoreHarness) async throws {
        var aggregate = finishedSession(for: harness.userId)
        aggregate.entries[0].exerciseId = UUID()

        try await expectRefused("42501") { try await harness.store.pushSession(aggregate) }
        try await expectRefused("42501") {
            try await harness.store.upsert([
                RemoteExerciseSettingRow(exerciseId: UUID(), userId: harness.userId, restEnabled: true, restSeconds: 60)
            ])
        }
        try await expectRefused("42501") {
            try await harness.store.upsert([
                RemoteMuscleGroupRow(id: UUID(), exerciseId: UUID(), muscle: .back, role: .primary)
            ])
        }
        let routine = RemoteRoutineRow(id: UUID(), userId: harness.userId, name: "Legs")
        try await harness.store.upsert([routine])
        try await expectRefused("42501") {
            try await harness.store.upsert([
                RemoteRoutineItemRow(
                    id: UUID(), userId: harness.userId, routineId: routine.id, position: 1, exerciseId: UUID()
                )
            ])
        }

        #expect(try await pullAll(RemoteSessionRow.self, from: harness.store).map(\.id) == [aggregate.session.id])
        #expect(try await pullAll(RemoteEntryRow.self, from: harness.store).isEmpty)
        #expect(try await pullAll(RemoteExerciseSettingRow.self, from: harness.store).isEmpty)
        #expect(try await pullAll(RemoteRoutineItemRow.self, from: harness.store).isEmpty)
    }

    /// A session holds one done entry per exercise: a second one, under another
    /// id, is refused with `23505`.
    static func secondDoneEntryIsRejected(_ harness: RemoteStoreHarness) async throws {
        var aggregate = finishedSession(for: harness.userId)
        try await harness.store.pushSession(aggregate)
        var second = aggregate.entries[0]
        second.id = UUID()
        second.position = 3
        aggregate.entries.append(second)
        aggregate.sets = []

        try await expectRefused("23505") { try await harness.store.pushSession(aggregate) }

        let entries = try await pullAll(RemoteEntryRow.self, from: harness.store)
        #expect(!entries.contains { $0.id == second.id })
    }

    private static func expectRefused(_ code: String, _ write: () async throws -> Void) async throws {
        do {
            try await write()
            Issue.record("the server stored rows it should refuse with \(code)")
        } catch let RemoteStoreError.rejected(refused, _) {
            #expect(refused == code)
        }
    }
}
