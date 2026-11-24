import Foundation
import Testing
@testable import TNWTrackerKit

/// Personal related links (S10, AC5): behaviour every `TrainingRemoteStore`
/// keeps, run against the fake and the local stack like the rest of
/// `TrainingRemoteStoreContract`. Invented data only.
extension TrainingRemoteStoreContract {
    /// Links of a catalogue and an own exercise read back as written, a rename
    /// updates the row in place, and every deleted link leaves its owner a
    /// tombstone, also one deleted with its exercise; writing it again clears it.
    static func linksReadBackAndLeaveTombstones(_ harness: RemoteStoreHarness) async throws {
        let own = RemoteExerciseRow(id: UUID(), userId: harness.userId, name: "Lunge", type: .strength)
        try await harness.store.upsert([own])
        var links = [(benchPress, "bench"), (own.id, "lunge"), (shoulderPress, "press")].map { exerciseId, slug in
            RemoteExerciseLinkRow(
                id: UUID(), userId: harness.userId, exerciseId: exerciseId, title: "About \(slug)",
                url: "https://blog.example.test/\(slug)", source: "blog.example.test", position: 1
            )
        }
        try await harness.store.upsert(links)
        links[0].title = "Bench, explained"
        links[0].position = 2
        try await harness.store.upsert([links[0]])

        let stored = try await pullAll(RemoteExerciseLinkRow.self, from: harness.store)
        #expect(stored.map(withoutServerFields).sorted(by: byId) == links.sorted(by: byId))
        #expect(stored.last?.id == links[0].id, "the row written last is read last")
        #expect(stored.allSatisfy { $0.updatedAt != nil })

        try await harness.store.delete(.exerciseLinks, ids: [links[2].id])
        try await harness.store.delete(.exercises, ids: [own.id])
        #expect(try await pullAll(RemoteExerciseLinkRow.self, from: harness.store).map(\.id) == [links[0].id])
        let tombstones = try await pullAll(RemoteTombstoneRow.self, from: harness.store)
        #expect(Set(tombstones.map { "\($0.tableName):\($0.rowId)" }) == [
            "exercise_links:\(links[2].id)", "exercise_links:\(links[1].id)", "exercises:\(own.id)"
        ])
        #expect(tombstones.allSatisfy { $0.userId == harness.userId })

        try await harness.store.upsert([links[2]])
        #expect(try await pullAll(RemoteTombstoneRow.self, from: harness.store)
            .allSatisfy { $0.rowId != links[2].id })
    }

    /// A link the server would not keep is refused as data: one on an exercise
    /// the user cannot see (`42501`), and one with an address that is not
    /// `https` or a blank title (`23514`). Nothing is stored.
    static func invalidLinksAreRejected(_ harness: RemoteStoreHarness) async throws {
        let valid = RemoteExerciseLinkRow(
            id: UUID(), userId: harness.userId, exerciseId: benchPress, title: "About bench",
            url: "https://blog.example.test/bench", source: "blog.example.test", position: 1
        )
        var unseen = valid
        unseen.exerciseId = UUID()
        var plain = valid
        plain.url = "http://blog.example.test/bench"
        var untitled = valid
        untitled.title = " "
        var unplaced = valid
        unplaced.position = 0

        for (link, code) in [(unseen, "42501"), (plain, "23514"), (untitled, "23514"), (unplaced, "23514")] {
            do {
                try await harness.store.upsert([link])
                Issue.record("the server stored a link it should refuse with \(code)")
            } catch let RemoteStoreError.rejected(refused, _) {
                #expect(refused == code)
            }
        }
        #expect(try await pullAll(RemoteExerciseLinkRow.self, from: harness.store).isEmpty)
    }
}
