import Foundation
import Testing
@testable import TNWTrackerKit

/// Two devices of the same user on one server: what one device changes either
/// reaches the other or stays where it is, and neither pushes the same value
/// back and forth (S13). Real stores and repositories, in-memory server.
@Suite("Sync engine two devices")
@MainActor
struct TrainingSyncEngineTwoDeviceTests {
    let phone: PushWorld
    let tablet: PushWorld

    init() throws {
        phone = try PushWorld()
        tablet = try PushWorld(sharing: phone)
    }

    private var server: InMemoryTrainingRemoteStore { phone.server }

    /// The phone logs a session, an importer adds a set to it on the server,
    /// and both devices sync until nothing is pending.
    private func sharedMixedSession() async throws -> (entryId: UUID, importedId: UUID) {
        let session = try phone.finishedSession()
        try await phone.engine.sync()
        let entryId = try #require(session.entries.first { $0.exerciseId == phone.squat.id }?.id)
        let imported = phone.importedSetRow(entryId: entryId, ref: "e-9#1", reps: 10, at: phone.t0)
        try await server.insertOnServer(imported)
        // Merges the set and decides the default, then pushes the decision.
        try await phone.engine.sync()
        try await phone.engine.sync()
        try await tablet.engine.sync()
        try await tablet.engine.sync()
        try phone.expectNothingPending()
        try tablet.expectNothingPending()
        return (entryId, imported.id)
    }

    private func sessionPushes() async -> Int {
        await server.calls.filter { call in
            if case .pushSession = call { true } else { false }
        }.count
    }

    private func syncBoth(times: Int) async throws {
        for _ in 0 ..< times {
            try await tablet.engine.sync()
            try await phone.engine.sync()
        }
    }

    @Test("a warm-up marked on one device settles on the server and is never pushed back and forth")
    func warmupSettles() async throws {
        let shared = try await sharedMixedSession()
        try phone.store.sessions.setWarmup(true, setId: shared.importedId)
        try await phone.engine.sync()

        try await syncBoth(times: 2)
        let pushes = await sessionPushes()
        try await syncBoth(times: 2)

        #expect(await sessionPushes() == pushes)
        #expect(try await phone.serverSet(shared.importedId).warmup)
        try phone.expectNothingPending()
        try tablet.expectNothingPending()
        // The tablet keeps its own annotation of an imported set until the user changes it there (S8).
        let onTablet = try #require(try tablet.completedSessions().first?.entries.first { $0.id == shared.entryId })
        #expect(onTablet.sets.first { $0.id == shared.importedId }?.warmup == false)
    }

    @Test("a reconciliation the user chose on one device reaches the other and settles")
    func userChoiceReachesTheOtherDevice() async throws {
        let shared = try await sharedMixedSession()
        try phone.store.sessions.chooseReconciliation(entryId: shared.entryId, keep: .manual, at: phone.t0)
        try await phone.engine.sync()

        try await syncBoth(times: 2)
        let pushes = await sessionPushes()
        try await syncBoth(times: 2)

        #expect(await sessionPushes() == pushes)
        let onTablet = try #require(try tablet.completedSessions().first?.entries.first { $0.id == shared.entryId })
        #expect(onTablet.reconciliation?.keep == .manual)
        #expect(onTablet.reconciliation?.decidedBy == .user)
        #expect(onTablet.sets.first { $0.id == shared.importedId }?.superseded == true)
        #expect(onTablet.sets.filter { $0.source == .manual }.allSatisfy { !$0.superseded })
        #expect(try await phone.serverEntry(shared.entryId).reconciliationKeep == .manual)
        try phone.expectNothingPending()
        try tablet.expectNothingPending()
    }
}
