import Foundation
import Testing
@testable import TNWTrackerKit

/// Personal related links both ways (S10, AC5): a link added, renamed or
/// deleted on one device shows the same on the other after a sync. Pushed after
/// their exercise, pulled and deleted like the other aggregates. Real store and
/// repositories, in-memory server. Invented data only.
@Suite("Sync engine personal links")
@MainActor
struct TrainingSyncEngineLinksTests {
    let world: PushWorld

    init() throws {
        world = try PushWorld()
    }

    private var store: TrainingStore {
        world.store
    }

    private var server: InMemoryTrainingRemoteStore {
        world.server
    }

    @discardableResult
    private func add(_ exerciseId: UUID, _ slug: String, on device: PushWorld? = nil) throws -> ExerciseLink {
        try (device ?? world).store.exerciseLinks.add(
            exerciseId: exerciseId, title: "About \(slug)", url: "https://blog.example.test/\(slug)",
            source: "blog.example.test"
        )
    }

    private func row(_ link: ExerciseLink) -> RemoteExerciseLinkRow {
        RemoteExerciseLinkRow(
            id: link.id, userId: world.userId, exerciseId: link.exerciseId, title: link.title, url: link.url,
            source: link.source, position: link.position
        )
    }

    // MARK: - Push

    @Test("links of a catalogue and an own exercise go up after the exercise, every column included")
    func linksGoUp() async throws {
        let onOwn = try add(world.squat.id, "squat")
        let onCatalogue = try add(world.bench.id, "bench")

        let report = try await world.engine.push()

        let squat = SyncAggregateRef(.exercise, id: world.squat.id)
        let ownLink = SyncAggregateRef(.exerciseLink, id: onOwn.id)
        #expect(report.rejected.isEmpty)
        #expect(report.skipped.isEmpty)
        #expect(Set(report.pushed) == [squat, ownLink, SyncAggregateRef(.exerciseLink, id: onCatalogue.id)])
        #expect(try #require(report.pushed.firstIndex(of: squat)) < #require(report.pushed.firstIndex(of: ownLink)))
        #expect(await world.stored(RemoteExerciseLinkRow.self) == PushWorld.byId([row(onOwn), row(onCatalogue)]))
        try world.expectNothingPending()
    }

    @Test("a link of an exercise the server refused waits for it; the others go up")
    func linkWaitsForItsExercise() async throws {
        let onOwn = try add(world.squat.id, "squat")
        let onCatalogue = try add(world.bench.id, "bench")
        await server.failNext(.upsert, with: InMemoryTrainingRemoteStore.foreignKeyViolation("refused"))

        let report = try await world.engine.push()

        let squat = SyncAggregateRef(.exercise, id: world.squat.id)
        #expect(report.rejected.map(\.aggregate) == [squat])
        #expect(report.skipped == [
            .init(aggregate: SyncAggregateRef(.exerciseLink, id: onOwn.id), reason: .waitsFor(squat))
        ])
        #expect(await world.stored(RemoteExerciseLinkRow.self) == [row(onCatalogue)])
        #expect(try store.syncState.pending(.exerciseLink).map(\.id) == [onOwn.id])
    }

    // MARK: - Two devices

    @Test("a link added on one device shows on the other, and a rename follows (AC5)")
    func addedAndRenamedLinkArrives() async throws {
        let tablet = try PushWorld(sharing: world)
        try await tablet.engine.sync()
        let link = try add(world.bench.id, "bench")
        try await world.engine.sync()

        let report = try await tablet.engine.pull()

        #expect(report.created == [SyncAggregateRef(.exerciseLink, id: link.id)])
        #expect(try tablet.store.exerciseLinks.links(exerciseId: world.bench.id) == [link])
        try tablet.expectNothingPending()
        let last = try #require(await server.stored(RemoteExerciseLinkRow.self).last)
        #expect(try tablet.store.pulled.cursor(.exerciseLinks, userId: world.userId)
            == RemoteCursor(updatedAt: #require(last.updatedAt), id: last.id))

        try world.store.exerciseLinks.rename(id: link.id, title: "Bench, explained")
        try await world.engine.sync()
        try await tablet.engine.sync()

        var renamed = link
        renamed.title = "Bench, explained"
        #expect(try tablet.store.exerciseLinks.links(exerciseId: world.bench.id) == [renamed])
        try tablet.expectNothingPending()
    }

    @Test("a link deleted on one device goes from the other through its tombstone (AC5)")
    func deletedLinkGoesFromTheOther() async throws {
        let tablet = try PushWorld(sharing: world)
        let gone = try add(world.bench.id, "gone")
        let kept = try add(world.bench.id, "kept")
        try await world.engine.sync()
        try await tablet.engine.sync()
        #expect(try tablet.store.exerciseLinks.links(exerciseId: world.bench.id).map(\.id) == [gone.id, kept.id])

        try world.store.exerciseLinks.delete(id: gone.id)
        let push = try await world.engine.push()

        #expect(push.deleted == [SyncAggregateRef(.exerciseLink, id: gone.id)])
        #expect(try store.syncState.tombstones().isEmpty)
        #expect(await world.stored(RemoteExerciseLinkRow.self) == [row(kept)])
        #expect(await server.stored(RemoteTombstoneRow.self).map { "\($0.tableName):\($0.rowId)" }
            == ["exercise_links:\(gone.id)"])

        let pull = try await tablet.engine.pull()

        #expect(pull.deletions == [.init(table: .exerciseLinks, id: gone.id, rule: .serverApplied)])
        #expect(try tablet.store.exerciseLinks.links(exerciseId: world.bench.id) == [kept])
        #expect(try tablet.store.syncState.tombstones().isEmpty, "applying a deletion is not a local change")
        try tablet.expectNothingPending()
    }

    @Test("deleting a link that never reached the server sends no delete")
    func unsentDeleteSendsNothing() async throws {
        let link = try add(world.bench.id, "local")
        try store.exerciseLinks.delete(id: link.id)

        let report = try await world.engine.push()

        #expect(report.deleted.isEmpty)
        #expect(await !server.calls.contains {
            if case .delete = $0 {
                true
            } else {
                false
            }
        })
        #expect(await world.stored(RemoteExerciseLinkRow.self).isEmpty)
    }

    @Test("a link deleted on the server with a rename waiting is kept and written back")
    func deletionWithLocalChangeKeepsTheLink() async throws {
        let link = try add(world.bench.id, "bench")
        try await world.engine.push()
        try await server.deleteOnServer(.exerciseLinks, ids: [link.id])
        try store.exerciseLinks.rename(id: link.id, title: "Mine still")

        let report = try await world.engine.pull()

        #expect(report.deletions == [.init(table: .exerciseLinks, id: link.id, rule: .localKept)])
        try await world.engine.sync()
        var renamed = link
        renamed.title = "Mine still"
        #expect(await world.stored(RemoteExerciseLinkRow.self) == [row(renamed)])
        #expect(await server.stored(RemoteTombstoneRow.self).isEmpty)
        try world.expectNothingPending()
    }

    @Test("an exercise deleted on the server takes its links from the device too")
    func exerciseDeletionTakesItsLinks() async throws {
        let link = try add(world.squat.id, "squat")
        try await world.engine.push()
        try await server.deleteOnServer(.exercises, ids: [world.squat.id])
        #expect(await Set(server.stored(RemoteTombstoneRow.self).map { "\($0.tableName):\($0.rowId)" })
            == ["exercises:\(world.squat.id)", "exercise_links:\(link.id)"])

        try await world.engine.pull()

        #expect(try store.exercises.exercise(id: world.squat.id) == nil)
        #expect(try store.exerciseLinks.links(exerciseId: world.squat.id).isEmpty)
        #expect(try store.context.fetchExerciseLink(id: link.id) == nil)
    }

    @Test("an exercise deleted on the server also takes a link of it the server never held")
    func exerciseDeletionTakesUnsentLinks() async throws {
        try await world.engine.push()
        let unsent = try add(world.squat.id, "unsent")
        try await server.deleteOnServer(.exercises, ids: [world.squat.id])

        try await world.engine.pull()

        #expect(try store.exercises.exercise(id: world.squat.id) == nil)
        #expect(try store.context.fetchExerciseLink(id: unsent.id) == nil)
        #expect(try store.syncState.tombstones().isEmpty)
        try world.expectNothingPending()
    }

    // MARK: - Pull edge cases

    @Test("every field another client changed is applied: address, source and position too")
    func everyPulledFieldIsApplied() async throws {
        let link = try add(world.bench.id, "bench")
        try await world.engine.push()
        let moved = RemoteExerciseLinkRow(
            id: link.id, userId: world.userId, exerciseId: world.bench.id, title: "Bench video",
            url: "https://video.example.test/watch?v=ddd444", source: "video.example.test", position: 3
        )
        try await server.insertOnServer(moved)

        try await world.engine.pull()

        #expect(try store.exerciseLinks.links(exerciseId: world.bench.id) == [ExerciseLink(
            id: link.id, exerciseId: world.bench.id, title: "Bench video",
            url: "https://video.example.test/watch?v=ddd444", source: "video.example.test", position: 3
        )])
        try world.expectNothingPending()
    }

    @Test("S10 a pull that answers a link of another user applies nothing of it")
    func linkOfAnotherUserIsNeverApplied() async throws {
        let theirs = RemoteExerciseLinkRow(
            id: UUID(), userId: UUID(), exerciseId: world.bench.id, title: "Theirs",
            url: "https://blog.example.test/theirs", source: "blog.example.test", position: 1
        )
        try await server.insertOnServer(theirs)

        await #expect(throws: TrainingSyncError.pulledRowsOfAnotherUser) { try await world.engine.pull() }

        #expect(try store.context.fetchExerciseLink(id: theirs.id) == nil)
        #expect(try store.pulled.cursor(.exerciseLinks, userId: world.userId) == nil)
    }

    @Test("a link of an exercise the device does not hold waits for it")
    func linkWithoutExerciseWaits() throws {
        var orphan = RemoteExerciseLinkRow(
            id: UUID(), userId: world.userId, exerciseId: UUID(), title: "Orphan",
            url: "https://blog.example.test/orphan", source: "blog.example.test", position: 1
        )
        orphan.updatedAt = InMemoryTrainingRemoteStore.timestamp(1)

        let report = try store.pulled.apply(PulledBatch(exerciseLinks: [orphan]), userId: world.userId)

        #expect(report.skipped == [.init(table: .exerciseLinks, id: orphan.id, reason: .missingParent)])
        #expect(try store.pulled.cursor(.exerciseLinks, userId: world.userId) == nil)
        #expect(try store.exerciseLinks.links(exerciseId: orphan.exerciseId).isEmpty)
    }

    @Test("a link of an exercise the device deleted is passed over, and its cursor moves on")
    func linkOfDeletedExerciseIsPassedOver() throws {
        let gone = UUID()
        store.context.insert(SyncTombstoneModel(
            kindRaw: SyncTombstoneKind.exercise.rawValue, rowId: gone, sessionId: nil, revision: 1, deletedAt: world.t0
        ))
        try store.context.save()
        var orphan = RemoteExerciseLinkRow(
            id: UUID(), userId: world.userId, exerciseId: gone, title: "Orphan",
            url: "https://blog.example.test/orphan", source: "blog.example.test", position: 1
        )
        orphan.updatedAt = InMemoryTrainingRemoteStore.timestamp(1)

        let report = try store.pulled.apply(PulledBatch(exerciseLinks: [orphan]), userId: world.userId)

        #expect(report.skipped == [.init(table: .exerciseLinks, id: orphan.id, reason: .deletedOnDevice)])
        #expect(try store.pulled.cursor(.exerciseLinks, userId: world.userId)?.id == orphan.id)
        #expect(try store.context.fetchExerciseLink(id: orphan.id) == nil)
    }

    @Test("a link the device deleted is not brought back by a pull before the push")
    func deletedLinkIsNotBroughtBack() async throws {
        let link = try add(world.bench.id, "bench")
        try await world.engine.push()
        try store.exerciseLinks.delete(id: link.id)
        await server.advanceClock(seconds: 60)
        // Another device renamed it meanwhile, so the pull reads it again.
        var renamed = row(link)
        renamed.title = "Renamed elsewhere"
        try await server.insertOnServer(renamed)

        let report = try await world.engine.pull()

        #expect(report.skipped == [.init(table: .exerciseLinks, id: link.id, reason: .deletedOnDevice)])
        #expect(try store.exerciseLinks.links(exerciseId: world.bench.id).isEmpty)
        #expect(try store.syncState.tombstones().map(\.id) == [link.id])
    }
}
