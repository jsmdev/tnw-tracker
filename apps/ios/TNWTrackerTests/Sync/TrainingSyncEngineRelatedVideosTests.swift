import Foundation
import Testing
@testable import TNWTrackerKit

/// #182 S9, format 1.1: related videos are curated on the server. The pull
/// brings them; the app never sends them, so a push keeps them on the server.
@Suite("Sync engine related videos")
@MainActor
struct TrainingSyncEngineRelatedVideosTests {
    let world: PushWorld

    init() throws {
        world = try PushWorld()
    }

    var store: TrainingStore { world.store }
    var server: InMemoryTrainingRemoteStore { world.server }
    var engine: TrainingSyncEngine { world.engine }

    @Test("arrive, survive a push of a change made here, and go when the server drops them")
    func relatedVideosFollowTheServer() async throws {
        let videos = [
            RelatedVideo(title: "Setup", url: "https://video.example/a", source: "Example"),
            RelatedVideo(title: "Range", url: "https://video.example/b", source: "Example")
        ]
        var row = RemoteExerciseRow(id: UUID(), userId: world.userId, name: "Plank", type: .bodyweight)
        row.relatedVideos = videos
        try await server.insertOnServer(row)

        _ = try await engine.sync()
        var plank = try #require(try store.exercises.exercise(id: row.id))
        #expect(plank.relatedVideos == videos)
        try world.expectNothingPending()

        // Renamed here: the push sends the exercise without the column, so the server keeps them.
        plank.name = "Front plank"
        plank.relatedVideos = nil
        try store.exercises.save(plank)
        let push = try await engine.push()
        #expect(push.pushed == [SyncAggregateRef(.exercise, id: row.id)])
        let onServer = try #require(await server.stored(RemoteExerciseRow.self).first { $0.id == row.id })
        #expect(onServer.name == "Front plank")
        #expect(onServer.relatedVideos == videos)
        #expect(try store.exercises.exercise(id: row.id)?.relatedVideos == videos)

        // Curated away on the server: the next pull removes them here.
        var dropped = onServer
        dropped.relatedVideos = nil
        try await server.insertOnServer(dropped)
        _ = try await engine.sync()
        #expect(try store.exercises.exercise(id: row.id)?.relatedVideos == nil)
        #expect(try store.exercises.exercise(id: row.id)?.name == "Front plank")
        try world.expectNothingPending()
    }
}
