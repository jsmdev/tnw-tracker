import Foundation
import Testing
@testable import TNWTrackerKit

/// Entry refs the server holds on another entry than the device (L2, L8): an
/// importer on the server regrouped an entry into another session. The pull
/// follows the server, as it does for imported sets, so the device never
/// pushes a `null` ref over the server's nor collides with it (23505).
/// Real store and repositories, in-memory server. Invented data only.
@Suite("Sync engine entry refs")
@MainActor
struct TrainingSyncEngineEntryRefTests {
    let world: PushWorld

    init() throws {
        world = try PushWorld()
    }

    private var server: InMemoryTrainingRemoteStore { world.server }

    @Test("an entry ref an importer moved to another session stays there on the server, and the device follows it")
    func movedEntryRefStaysOnTheServer() async throws {
        try await world.uploadPrerequisites()
        let first = world.importedSessionRows(entryRef: "e-1")
        try await world.writeOnServer(first)
        try await world.engine.sync()
        // The importer regroups the entry and its set into a session of another day.
        var vacated = first.entries[0]
        vacated.externalRef = nil
        try await server.insertOnServer(vacated)
        let day = world.t0.addingTimeInterval(2 * 86_400)
        let session = RemoteSessionRow(
            id: UUID(), userId: world.userId, name: "Regrouped", startedAt: day,
            completedAt: day.addingTimeInterval(3_600), timeZone: "Europe/Madrid", externalRef: world.ref("2030-03-06")
        )
        let entry = RemoteEntryRow(
            id: UUID(), userId: world.userId, sessionId: session.id, position: 1, exerciseId: world.bench.id,
            status: .done, completedAt: day.addingTimeInterval(1_800), externalRef: world.ref("e-1")
        )
        var set = first.sets[0]
        set.entryId = entry.id
        try await server.insertOnServer(session)
        try await server.insertOnServer(entry)
        try await server.insertOnServer(set)

        let reports = try await [world.engine.sync(), world.engine.sync()]

        #expect(reports.flatMap(\.push.rejected).isEmpty)
        // The set moved under its own id: nothing took another id.
        #expect(reports.flatMap(\.pull.adopted).isEmpty)
        #expect(try await world.serverEntry(entry.id).externalRef == world.ref("e-1"))
        #expect(try await world.serverSet(set.id).entryId == entry.id)
        let local = try world.session(session.id)
        #expect(local.entries.map(\.id) == [entry.id])
        #expect(local.entries.first?.externalRef == world.ref("e-1"))
        #expect(local.entries.first?.sets.map(\.id) == [set.id])
        // The session the importer emptied was imported only: it goes on both sides.
        #expect(try store.sessions.session(id: first.session.id) == nil)
        #expect(await server.stored(RemoteSessionRow.self).map(\.id) == [session.id])
        try world.expectNothingPending()
    }

    @Test("an entry ref the device imported and the server holds in another session ends there, refused only once")
    func deviceImportedRefConvergesOnTheServersSession() async throws {
        try await world.uploadPrerequisites()
        // The in-app importer and an importer on the server brought the same entry
        // and set, each in a session of its own (different session refs).
        let onServer = world.importedSessionRows(entryRef: "e-1")
        try await world.writeOnServer(onServer)
        var onDevice = onServer
        onDevice.session.externalRef = world.ref("device-day")
        let result = try store.importer.importBundle(try bundle(matching: onDevice))
        let deviceSession = try #require(result.sessionIds.values.first)

        let first = try await world.engine.sync()
        let rest = try await [world.engine.sync(), world.engine.sync()]

        // Refused once (the server holds the entry ref), then never again.
        #expect(first.push.rejected.map(\.aggregate) == [SyncAggregateRef(.session, id: deviceSession)])
        #expect(rest.flatMap(\.push.rejected).isEmpty)
        #expect(try await world.serverEntry(onServer.entries[0].id).externalRef == world.ref("e-1"))
        #expect(try await world.serverSet(onServer.sets[0].id).entryId == onServer.entries[0].id)
        #expect(await server.stored(RemoteSessionRow.self).map(\.id) == [onServer.session.id])
        #expect(try store.sessions.session(id: deviceSession) == nil)
        let local = try world.session(onServer.session.id)
        #expect(local.entries.first?.externalRef == world.ref("e-1"))
        #expect(local.entries.first?.sets.map(\.id) == [onServer.sets[0].id])
        try world.expectNothingPending()
    }

    private var store: TrainingStore { world.store }

    /// The bundle the in-app importer builds for the same provider data as `rows`.
    private func bundle(matching rows: RemoteSessionAggregate) throws -> TrainingBundle {
        let set = rows.sets[0]
        // Without a ref, the bundle's exercise is the catalogue's bench press.
        let bench = Exercise(name: "Bench Press", type: .strength)
        return TrainingBundle(
            exercises: [bench],
            sessions: [BundleSession(
                id: UUID(), externalRef: try #require(rows.session.externalRef), name: rows.session.name,
                startedAt: rows.session.startedAt, completedAt: rows.session.completedAt,
                timeZone: rows.session.timeZone, durationSeconds: rows.session.durationSeconds,
                entries: [ImportedEntry(
                    exerciseId: bench.id, externalRef: try #require(rows.entries[0].externalRef),
                    completedAt: rows.entries[0].completedAt,
                    sets: [ImportedSet(
                        externalRef: try #require(set.externalRef), order: 1,
                        values: SetValues(reps: set.reps, weight: set.weight), completedAt: set.completedAt
                    )]
                )]
            )]
        )
    }
}
