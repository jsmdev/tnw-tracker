import Foundation
import Supabase
import Testing
@testable import TNWTrackerKit

/// From the independent verifier (S11, S4; docs "Deletions from the server": a user exercise
/// a session not sent yet uses is kept and sent again). An importer deletes on
/// the server a user exercise that a finished, unsent session uses. The real
/// server refuses the session's entries with row-level security (42501), not a
/// foreign key error, so the push must not stop the pull that re-sends it.
@Suite(
    "Sync: an in-use exercise deleted on the server (local stack)",
    .enabled("needs the service role key") { await LocalSupabaseStack.hasServiceRole() }
)
struct InUseExerciseDeletedOnServerTests {
    @Test("S11 S4 a session using an exercise deleted on the server still syncs, and the exercise is sent again")
    func sessionStillSyncs() async throws {
        try await LocalSupabaseStack.withThrowawayUser { client, userId in
            try await Self.run(client: client, userId: userId)
        }
    }

    @MainActor
    private static func run(client: SupabaseClient, userId: UUID) async throws {
        let world = try PushWorld(userId: userId)
        let row = Exercise(name: "Cable row", type: .strength)
        try world.store.exercises.save(row)
        let remote = SupabaseTrainingRemoteStore(client: client, userId: userId)
        let engine = TrainingSyncEngine(store: world.store, remote: remote, userId: userId)
        try await engine.sync()
        try world.expectNothingPending()
        // A workout with the row, finished offline.
        let session = try world.finishedSession(exerciseId: row.id, at: 7_200)
        // Meanwhile an importer deletes the exercise on the server (nothing there uses it).
        let admin = try #require(LocalSupabaseStack.adminClient())
        try await admin.from("exercises").delete(returning: .minimal)
            .eq("id", value: row.id.uuidString.lowercased()).execute()
        withExtendedLifetime(admin) {}

        var failures = 0
        for _ in 0 ..< 3 {
            do { try await engine.sync() } catch { failures += 1 }
        }

        #expect(failures == 0, "every sync fails, so the pull that would re-send the exercise never runs")
        let exercises = try await TrainingRemoteStoreContract.pullAll(RemoteExerciseRow.self, from: remote)
        #expect(exercises.contains { $0.id == row.id })
        let entries = try await TrainingRemoteStoreContract.pullAll(RemoteEntryRow.self, from: remote)
        #expect(entries.contains { $0.sessionId == session.id }, "the session is on the server without entries")
        try world.expectNothingPending()
    }
}

/// From the independent verifier (S2, S13 "imported sets always merge, never lost"): an
/// importer adds a done entry of an exercise to a session the device already
/// pushed, while the device imported its own entry of that exercise into it.
/// The server holds one done entry per exercise per session. Latent today: only
/// the debug sample data calls the in-app importer.
@Suite(
    "Sync: a done entry an importer added for the same exercise (local stack)",
    .enabled("needs the service role key") { await LocalSupabaseStack.hasServiceRole() }
)
struct ConcurrentDoneEntryTests {
    @Test("S13 an imported set in an entry an importer added for the same exercise is not lost, and the sync settles")
    func importedSetIsNotLost() async throws {
        try await LocalSupabaseStack.withThrowawayUser { client, userId in
            try await Self.run(client: client, userId: userId)
        }
    }

    @MainActor
    private static func run(client: SupabaseClient, userId: UUID) async throws {
        let world = try PushWorld(userId: userId)
        let session = try world.finishedSession()
        let remote = SupabaseTrainingRemoteStore(client: client, userId: userId)
        let engine = TrainingSyncEngine(store: world.store, remote: remote, userId: userId)
        try await engine.sync()
        // The device imports bench into the finished session (not pushed yet).
        let appSet = ImportedSet(
            externalRef: world.ref("app-e#1"), order: 1, values: SetValues(reps: 5, weight: .kg(60))
        )
        try world.store.sessions.importEntry(
            ImportedEntry(exerciseId: world.bench.id, externalRef: world.ref("app-e"), sets: [appSet]),
            into: session.id
        )
        // Meanwhile an importer adds its own bench entry with one imported set.
        let entry = RemoteEntryRow(
            id: UUID(), userId: userId, sessionId: session.id, position: 3, exerciseId: world.bench.id,
            status: .done, completedAt: world.t0.addingTimeInterval(1_200), externalRef: world.ref("probe-e")
        )
        let imported = world.importedSetRow(
            entryId: entry.id, ref: "probe-e#1", reps: 10, at: world.t0.addingTimeInterval(1_100)
        )
        let admin = try #require(LocalSupabaseStack.adminClient())
        try await admin.from("entries").insert(entry, returning: .minimal).execute()
        try await admin.from("sets").insert(imported, returning: .minimal).execute()
        withExtendedLifetime(admin) {}

        var last: SyncReport?
        for _ in 0 ..< 3 {
            last = try await engine.sync()
        }

        let local = try world.session(session.id)
        #expect(local.entries.flatMap(\.sets).contains { $0.externalRef == imported.externalRef })
        #expect(last?.push.rejected.isEmpty == true, "the session is refused on every push")
        #expect(last?.pull.skipped.contains { $0.id == imported.id } == false, "the sets cursor is stuck before it")
        try world.expectNothingPending()
    }
}

/// From the independent verifier (S11, S13, format rule `reconciliation`): a set of a mixed
/// entry deleted elsewhere; the entry on every device follows "reconciliation
/// is present exactly when an entry mixes sources". Fake server, real stores.
@Suite("Sync: deleting a set of a mixed entry elsewhere")
@MainActor
struct MixedEntryDeletedElsewhereTests {
    struct Shared {
        let sessionId: UUID
        let entryId: UUID
        let importedId: UUID
    }

    let phone: PushWorld
    let tablet: PushWorld

    init() throws {
        phone = try PushWorld()
        tablet = try PushWorld(sharing: phone)
    }

    private var server: InMemoryTrainingRemoteStore { phone.server }

    private func syncBoth(times: Int) async throws {
        for _ in 0 ..< times {
            try await phone.engine.sync()
            try await tablet.engine.sync()
        }
    }

    private func mixed() async throws -> Shared {
        let session = try phone.finishedSession()
        try await phone.engine.sync()
        let entryId = try #require(session.entries.first { $0.exerciseId == phone.squat.id }?.id)
        let imported = phone.importedSetRow(entryId: entryId, ref: "e-9#1", reps: 10, at: phone.t0)
        try await server.insertOnServer(imported)
        try await syncBoth(times: 2)
        try phone.expectNothingPending()
        try tablet.expectNothingPending()
        return Shared(sessionId: session.id, entryId: entryId, importedId: imported.id)
    }

    @Test("S11 the imported set deleted on the server: the manual sets count again and the decision goes")
    func importedSetDeletedOnServer() async throws {
        let shared = try await mixed()
        try await server.deleteOnServer(.sets, ids: [shared.importedId])

        try await syncBoth(times: 2)

        for device in [phone, tablet] {
            let entry = try #require(try device.session(shared.sessionId).entries.first { $0.id == shared.entryId })
            #expect(entry.sets.allSatisfy { $0.source == .manual })
            #expect(entry.reconciliation == nil)
            #expect(entry.sets.allSatisfy { !$0.superseded })
        }
        try phone.expectNothingPending()
        try tablet.expectNothingPending()
    }

    @Test("S11 S13 every manual set deleted on the phone: the tablet ends with the same entry, and it settles")
    func manualSetsDeletedOnPhone() async throws {
        let shared = try await mixed()
        let manual = try #require(try phone.session(shared.sessionId).entries.first { $0.id == shared.entryId })
            .sets.filter { $0.source == .manual }
        for set in manual {
            try phone.store.sessions.deleteManualSet(id: set.id)
        }
        let onPhone = try #require(try phone.session(shared.sessionId).entries.first { $0.id == shared.entryId })

        try await syncBoth(times: 3)

        let onTablet = try #require(try tablet.session(shared.sessionId).entries.first { $0.id == shared.entryId })
        #expect(onTablet.sets.map(\.id) == onPhone.sets.map(\.id))
        #expect(onTablet.reconciliation == onPhone.reconciliation)
        #expect(onTablet.sets.map(\.superseded) == onPhone.sets.map(\.superseded))
        try phone.expectNothingPending()
        try tablet.expectNothingPending()
    }
}
