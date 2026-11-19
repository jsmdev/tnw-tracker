import Foundation
import Supabase
import Testing
@testable import TNWTrackerKit

/// S1, S2 and S11 end to end: a session logged through the real repositories
/// reaches the local Supabase stack through the real adapter, a set an
/// importer writes there comes back into the store, and deletions go both ways. Skipped when the stack is
/// not configured or not running (see `LocalSupabaseStack`).
@Suite(
    "Sync engine push (local stack)",
    .enabled("needs the local Supabase stack") { await LocalSupabaseStack.isAvailable() }
)
struct TrainingSyncEngineContractTests {
    @Test("a session logged in the app appears in Supabase with its routine and exercise")
    func loggedSessionAppearsInSupabase() async throws {
        try await LocalSupabaseStack.withThrowawayUser { client, userId in
            try await Self.loggedSessionAppearsInSupabase(client: client, userId: userId)
        }
    }

    @MainActor
    private static func loggedSessionAppearsInSupabase(client: SupabaseClient, userId: UUID) async throws {
        let world = try PushWorld(userId: userId)
        let routine = try world.saveRoutine()
        let session = try world.finishedSession(routineId: routine.id)
        let remote = SupabaseTrainingRemoteStore(client: client, userId: userId)
        let engine = TrainingSyncEngine(store: world.store, remote: remote, userId: userId)

        let report = try await engine.push()

        #expect(report.rejected.isEmpty)
        #expect(report.pushed.map(\.id) == [world.squat.id, routine.id, session.id])
        let local = try #require(try world.store.sessions.session(id: session.id))
        let expected = PushWorld.rows(of: local, userId: userId)
        let sessions = try await TrainingRemoteStoreContract.pullAll(RemoteSessionRow.self, from: remote)
        let entries = try await TrainingRemoteStoreContract.pullAll(RemoteEntryRow.self, from: remote)
        let sets = try await TrainingRemoteStoreContract.pullAll(RemoteSetRow.self, from: remote)
        let items = try await TrainingRemoteStoreContract.pullAll(RemoteRoutineItemRow.self, from: remote)
        let exercises = try await TrainingRemoteStoreContract.pullAll(RemoteExerciseRow.self, from: remote)
        #expect(sessions.map(PushWorld.plain) == [expected.session])
        #expect(PushWorld.byId(entries.map(PushWorld.plain)) == PushWorld.byId(expected.entries))
        #expect(PushWorld.byId(sets.map(PushWorld.plain)) == PushWorld.byId(expected.sets))
        #expect(PushWorld.byId(items.map(PushWorld.plain)) == PushWorld.byId(world.itemRows(routine)))
        #expect(exercises.map(PushWorld.plain).filter { $0.userId != nil } == [world.squatRow])
        try world.expectNothingPending()

        // Pushing again after an edit updates the same rows.
        let setId = try #require(local.entries.first { $0.exerciseId == world.squat.id }?.sets.first?.id)
        try world.store.sessions.setWarmup(true, setId: setId)
        try await engine.push()
        let updated = try await TrainingRemoteStoreContract.pullAll(RemoteSetRow.self, from: remote)
        #expect(updated.count == expected.sets.count)
        #expect(updated.first { $0.id == setId }?.warmup == true)
        try world.expectNothingPending()
    }

    @Test(
        "a set an importer writes in Supabase appears in the app after a full sync, and the sync converges",
        .enabled("needs the service role key") { await LocalSupabaseStack.hasServiceRole() }
    )
    func importedSetAppearsInTheApp() async throws {
        try await LocalSupabaseStack.withThrowawayUser { client, userId in
            try await Self.importedSetAppearsInTheApp(client: client, userId: userId)
        }
    }

    @MainActor
    private static func importedSetAppearsInTheApp(client: SupabaseClient, userId: UUID) async throws {
        let world = try PushWorld(userId: userId)
        let session = try world.finishedSession()
        let remote = SupabaseTrainingRemoteStore(client: client, userId: userId)
        let engine = TrainingSyncEngine(store: world.store, remote: remote, userId: userId)
        try await engine.sync()
        let entryId = try #require(session.entries.first { $0.exerciseId == world.squat.id }?.id)
        let admin = try #require(LocalSupabaseStack.adminClient())
        let imported = world.importedSetRow(
            entryId: entryId, ref: "set-\(UUID().uuidString)", reps: 10, at: world.t0.addingTimeInterval(900)
        )
        // The importer writes outside the app, past row-level security.
        try await admin.from("sets").insert(imported, returning: .minimal).execute()
        withExtendedLifetime(admin) {}

        let report = try await engine.sync()

        let entry = try #require(try world.session(session.id).entries.first { $0.id == entryId })
        let set = try #require(entry.sets.first { $0.id == imported.id })
        #expect(set.source == .imported)
        #expect(set.values == SetValues(reps: 10, weight: .kg(50)))
        #expect(set.externalRef == imported.externalRef)
        #expect(entry.reconciliation?.keep == .imported)
        #expect(entry.sets.filter { $0.source == .manual }.allSatisfy { $0.superseded })
        #expect(report.pull.changedLocally == [session.id])
        // The device's decision goes up, and reading it back changes nothing.
        try await engine.sync()
        try await engine.sync()
        try world.expectNothingPending()
        let entries = try await TrainingRemoteStoreContract.pullAll(RemoteEntryRow.self, from: remote)
        #expect(entries.first { $0.id == entryId }?.reconciliationKeep == .imported)
        let sets = try await TrainingRemoteStoreContract.pullAll(RemoteSetRow.self, from: remote)
        #expect(sets.filter { $0.entryId == entryId && $0.source == .manual }.allSatisfy { $0.superseded })
    }

    @Test(
        "a session the app removes disappears from Supabase, and a set deleted there disappears from the app",
        .enabled("needs the service role key") { await LocalSupabaseStack.hasServiceRole() }
    )
    func deletionsGoBothWays() async throws {
        try await LocalSupabaseStack.withThrowawayUser { client, userId in
            try await Self.deletionsGoBothWays(client: client, userId: userId)
        }
    }

    @MainActor
    private static func deletionsGoBothWays(client: SupabaseClient, userId: UUID) async throws {
        let world = try PushWorld(userId: userId)
        let remote = SupabaseTrainingRemoteStore(client: client, userId: userId)
        let engine = TrainingSyncEngine(store: world.store, remote: remote, userId: userId)
        // The app removes Wednesday, an import-only session it already sent.
        let ids = try await world.importThenRegroup(using: engine)

        let first = try await engine.sync()

        #expect(first.push.deleted == [SyncAggregateRef(.session, id: ids.wednesday)])
        #expect(first.push.rejected.isEmpty)
        let sessions = try await TrainingRemoteStoreContract.pullAll(RemoteSessionRow.self, from: remote)
        #expect(sessions.map(\.id) == [ids.monday])
        let tombstones = try await TrainingRemoteStoreContract.pullAll(RemoteTombstoneRow.self, from: remote)
        #expect(tombstones.contains { $0.deletedTable == .sessions && $0.rowId == ids.wednesday })
        #expect(try world.store.syncState.tombstones().isEmpty)
        try world.expectNothingPending()

        // Another client deletes one of Monday's sets, past row-level security.
        let set = try #require(try world.session(ids.monday).entries.first?.sets.last)
        let admin = try #require(LocalSupabaseStack.adminClient())
        try await admin.from("sets").delete(returning: .minimal)
            .eq("id", value: set.id.uuidString.lowercased())
            .execute()
        withExtendedLifetime(admin) {}

        let second = try await engine.sync()

        #expect(second.pull.deletions == [.init(table: .sets, id: set.id, rule: .serverApplied)])
        #expect(try world.session(ids.monday).entries.flatMap(\.sets).contains { $0.id == set.id } == false)
        try world.expectNothingPending()
        let calls = try await engine.sync()
        #expect(calls.push.pushed.isEmpty, "the deletion is not echoed back")
    }
}
