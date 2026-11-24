import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

/// Personal related links of an exercise (S10: AC2-AC4 data layer, AC5): the
/// real in-memory store and repositories. Invented data only.
@Suite("ExerciseLinkRepository")
@MainActor
struct ExerciseLinkRepositoryTests {
    let store: TrainingStore
    let own = Exercise(name: "Goblet Squat", type: .strength)
    let catalogue = Exercise(isCatalogue: true, name: "Bench Press", type: .strength)

    init() throws {
        store = try TrainingStore.inMemory()
        _ = try store.ownership.claim(userId: UUID(), at: TrainingFixtures.t0)
        try store.exercises.save(own)
        try store.exercises.save(catalogue)
    }

    private var links: any ExerciseLinkRepositoryProtocol {
        store.exerciseLinks
    }

    private func tombstones() throws -> [SyncTombstone] {
        try store.syncState.tombstones()
    }

    // MARK: - Add

    @Test("a link is added after the others with its title, address and source trimmed, on own and catalogue")
    func addAppends() throws {
        let first = try links.add(
            exerciseId: own.id, title: "  Squat depth ", url: " https://video.example.test/watch?v=aaa111\n",
            source: " video.example.test "
        )
        let second = try links.add(
            exerciseId: own.id, title: "Squat cues", url: "https://blog.example.test/squat", source: "blog.example.test"
        )
        let onCatalogue = try links.add(
            exerciseId: catalogue.id, title: "Press grip", url: "https://blog.example.test/press",
            source: "blog.example.test"
        )

        #expect(first == ExerciseLink(
            id: first.id, exerciseId: own.id, title: "Squat depth", url: "https://video.example.test/watch?v=aaa111",
            source: "video.example.test", position: 1
        ))
        #expect(second.position == 2)
        #expect(onCatalogue.position == 1)
        let fresh = SwiftDataExerciseLinkRepository(context: ModelContext(store.container))
        #expect(try fresh.links(exerciseId: own.id) == [first, second])
        #expect(try fresh.links(exerciseId: catalogue.id) == [onCatalogue])
        #expect(try Set(store.syncState.pending(.exerciseLink).map(\.id)) == [first.id, second.id, onCatalogue.id])
    }

    @Test("links come by position, ties by id, and only the exercise's")
    func linksInOrder() throws {
        let lowId = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
        let highId = try #require(UUID(uuidString: "F0000000-0000-4000-8000-000000000001"))
        // Two devices added at the same position: the pull brings both.
        for (id, position) in [(highId, 1), (lowId, 1)] {
            let model = ExerciseLinkModel(
                id: id, exerciseId: own.id, title: "Tie", url: "https://blog.example.test/\(id)",
                source: "blog.example.test", position: position
            )
            store.context.insert(model)
        }
        try store.context.save()
        let third = try links.add(
            exerciseId: own.id, title: "Third", url: "https://blog.example.test/third", source: "blog.example.test"
        )

        #expect(try links.links(exerciseId: own.id).map(\.id) == [lowId, highId, third.id])
        #expect(third.position == 2)
        #expect(try links.links(exerciseId: catalogue.id).isEmpty)
    }

    @Test("an address that is not https, has spaces or is empty is refused, and nothing is stored")
    func invalidAddressRefused() throws {
        let refused = [
            "http://blog.example.test/a", "https://", "https://blog.example.test/a b", "blog.example.test", "",
            "HTTPS://blog.example.test/a"
        ]
        for url in refused {
            #expect(throws: TrainingDataError.invalidLink("the address is not https")) {
                try links.add(exerciseId: own.id, title: "Bad", url: url, source: "blog.example.test")
            }
        }
        #expect(try links.links(exerciseId: own.id).isEmpty)
        #expect(try store.syncState.pending(.exerciseLink).isEmpty)
    }

    @Test("a blank title or source is refused")
    func blankTitleOrSourceRefused() throws {
        #expect(throws: TrainingDataError.invalidLink("a link needs a title and a source")) {
            try links.add(exerciseId: own.id, title: "  ", url: "https://blog.example.test/a", source: "blog")
        }
        #expect(throws: TrainingDataError.invalidLink("a link needs a title and a source")) {
            try links.add(exerciseId: own.id, title: "Title", url: "https://blog.example.test/a", source: "\n")
        }
        #expect(try links.links(exerciseId: own.id).isEmpty)
    }

    @Test("an address the exercise already has is refused; another exercise may have it")
    func duplicateRefused() throws {
        let url = "https://blog.example.test/same"
        try links.add(exerciseId: own.id, title: "First", url: url, source: "blog.example.test")

        #expect(throws: TrainingDataError.duplicateLink) {
            try links.add(exerciseId: own.id, title: "Again", url: " \(url) ", source: "blog.example.test")
        }
        try links.add(exerciseId: catalogue.id, title: "Elsewhere", url: url, source: "blog.example.test")

        #expect(try links.links(exerciseId: own.id).map(\.title) == ["First"])
        #expect(try links.links(exerciseId: catalogue.id).map(\.title) == ["Elsewhere"])
    }

    @Test("a link of an exercise that does not exist is refused")
    func unknownExerciseRefused() throws {
        #expect(throws: TrainingDataError.notFound) {
            try links.add(exerciseId: UUID(), title: "T", url: "https://blog.example.test/a", source: "blog")
        }
    }

    @Test("a link added before any sign-in stays on the device")
    func unownedLinkStaysLocal() throws {
        let unowned = try TrainingStore.inMemory()
        try unowned.exercises.save(own)

        let link = try unowned.exerciseLinks.add(
            exerciseId: own.id, title: "Local", url: "https://blog.example.test/a", source: "blog"
        )

        #expect(try unowned.exerciseLinks.links(exerciseId: own.id) == [link])
        #expect(try unowned.syncState.pending(.exerciseLink).isEmpty)
    }

    // MARK: - Rename

    @Test("renaming trims the title, keeps the rest and marks the link changed")
    func renameKeepsTheRest() throws {
        let link = try links.add(
            exerciseId: own.id, title: "Old", url: "https://blog.example.test/a", source: "blog.example.test"
        )
        let pending = try #require(try store.syncState.pending(.exerciseLink).first)
        try store.syncState.markSynced(.exerciseLink, id: link.id, ifRevision: pending.revision)

        try links.rename(id: link.id, title: "  New title ")

        var expected = link
        expected.title = "New title"
        #expect(try links.links(exerciseId: own.id) == [expected])
        #expect(try store.syncState.pending(.exerciseLink).map(\.id) == [link.id])
    }

    @Test("a blank title or an unknown link is refused on rename")
    func renameRefusals() throws {
        let link = try links.add(
            exerciseId: own.id, title: "Old", url: "https://blog.example.test/a", source: "blog.example.test"
        )

        #expect(throws: TrainingDataError.invalidLink("a link needs a title and a source")) {
            try links.rename(id: link.id, title: " ")
        }
        #expect(throws: TrainingDataError.notFound) { try links.rename(id: UUID(), title: "New") }
        #expect(try links.links(exerciseId: own.id).map(\.title) == ["Old"])
    }

    // MARK: - Delete

    @Test("deleting a link that never reached the server leaves no tombstone")
    func deleteUnsentLeavesNoTombstone() throws {
        let link = try links.add(
            exerciseId: own.id, title: "Gone", url: "https://blog.example.test/a", source: "blog.example.test"
        )

        try links.delete(id: link.id)

        #expect(try links.links(exerciseId: own.id).isEmpty)
        #expect(try tombstones().isEmpty)
        #expect(try store.syncState.pending(.exerciseLink).isEmpty)
    }

    @Test("deleting a link that may be on the server leaves its tombstone; an unknown link is refused")
    func deleteSentLeavesTombstone() throws {
        let link = try links.add(
            exerciseId: catalogue.id, title: "Gone", url: "https://blog.example.test/a", source: "blog.example.test"
        )
        let kept = try links.add(
            exerciseId: catalogue.id, title: "Kept", url: "https://blog.example.test/b", source: "blog.example.test"
        )
        let pending = try #require(try store.syncState.pending(.exerciseLink).first { $0.id == link.id })
        try store.syncState.markSent(.exerciseLink, id: link.id, ifRevision: pending.revision)

        try links.delete(id: link.id)

        #expect(try links.links(exerciseId: catalogue.id) == [kept])
        let tombstone = try #require(try tombstones().first)
        #expect(try tombstones().count == 1)
        #expect(tombstone.kind == .exerciseLink)
        #expect(tombstone.id == link.id)
        #expect(throws: TrainingDataError.notFound) { try links.delete(id: link.id) }
    }

    @Test("a local reset deletes every link")
    func resetDeletesLinks() throws {
        try links.add(exerciseId: catalogue.id, title: "T", url: "https://blog.example.test/a", source: "blog")

        try store.deleteAllTrainingData()

        #expect(try store.context.fetchCount(FetchDescriptor<ExerciseLinkModel>()) == 0)
    }
}
