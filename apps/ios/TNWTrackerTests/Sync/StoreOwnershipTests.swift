import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

/// S10: the local store is stamped with the user its data belongs to. Another
/// user signing in is refused while that data is there, and nothing is deleted.
/// S9: data written before any sign-in (the debug sample data) is never attributed.
@Suite("Store ownership (S10, S9)")
@MainActor
struct StoreOwnershipTests {
    let fx: TrainingFixtures
    let t0 = TrainingFixtures.t0
    let userA = UUID()
    let userB = UUID()

    init() throws {
        fx = try TrainingFixtures()
    }

    private var ownership: any StoreOwnershipProtocol { fx.store.ownership }
    private var sync: any SyncStateRepositoryProtocol { fx.store.syncState }

    /// Owner rows as saved, read through a context of its own.
    private func savedOwners() throws -> [UUID] {
        try ModelContext(fx.store.container).fetch(FetchDescriptor<StoreOwnerModel>()).map(\.userId)
    }

    private func finishedSession() throws -> TrainingSession {
        let session = try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        return try fx.sessions.finishSession(id: session.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
    }

    private func nothingPending() throws -> Bool {
        try SyncAggregateKind.allCases.allSatisfy { try sync.pending($0).isEmpty }
    }

    @Test("the first sign-in claims an unowned store and saves the stamp")
    func firstSignInClaims() throws {
        #expect(try ownership.owner() == nil)
        #expect(try ownership.claim(userId: userA, at: t0) == .claimed)
        #expect(try ownership.owner() == userA)
        #expect(try savedOwners() == [userA])
    }

    @Test("the owner signing in again keeps the stamp")
    func ownerSignsInAgain() throws {
        try ownership.claim(userId: userA, at: t0)
        #expect(try ownership.claim(userId: userA, at: t0.addingTimeInterval(60)) == .owned)
        #expect(try savedOwners() == [userA])
    }

    @Test("another user is refused while the owner's data is in the store, and nothing is deleted")
    func anotherUserIsRefused() throws {
        try ownership.claim(userId: userA, at: t0)
        let session = try finishedSession()

        #expect(try ownership.claim(userId: userB, at: t0) == .mismatch(ownerId: userA))

        #expect(try ownership.owner() == userA)
        #expect(try savedOwners() == [userA])
        #expect(try fx.sessions.session(id: session.id) == session)
        #expect(try sync.pendingSessions().map(\.id) == [session.id], "the owner's changes are still pending")
    }

    @Test("another user claims a store whose owner left no user data in it")
    func anotherUserClaimsAnEmptyStore() throws {
        try ownership.claim(userId: userA, at: t0)
        #expect(try ownership.claim(userId: userB, at: t0) == .claimed)
        #expect(try savedOwners() == [userB])
    }

    @Test("a catalogue exercise saved after the claim is not the owner's data")
    func catalogueIsNotOwnedData() throws {
        try ownership.claim(userId: userA, at: t0)
        try fx.exercises.save(Exercise(isCatalogue: true, name: "Deadlift", type: .strength))

        #expect(try ownership.claim(userId: userB, at: t0) == .claimed)
        #expect(try savedOwners() == [userB])
    }

    @Test("data written before any sign-in is never attributed and does not block a claim")
    func unownedDataStaysLocal() throws {
        try SampleTrainingData.loadIfEmpty(into: fx.store, now: t0)

        #expect(try ownership.claim(userId: userA, at: t0) == .claimed)
        #expect(try nothingPending())
        #expect(try ownership.claim(userId: userB, at: t0) == .claimed, "sample data is nobody's data")
        #expect(try nothingPending())
    }

    @Test("replacing the data with the sample data resets the stamp and leaves nothing to sync")
    func replaceAllResetsOwnership() throws {
        try ownership.claim(userId: userA, at: t0)
        let session = try finishedSession()
        let revision = try #require(try sync.pendingSessions().first).revision
        try sync.markSent(.session, id: session.id, ifRevision: revision)
        try fx.sessions.deleteManualSet(id: try #require(session.entries.first?.sets.first).id)
        let tombstones = try ModelContext(fx.store.container).fetchCount(FetchDescriptor<SyncTombstoneModel>())
        #expect(tombstones == 2, "the set and its emptied entry")

        try SampleTrainingData.replaceAll(in: fx.store, now: t0)

        #expect(try ownership.owner() == nil)
        #expect(try savedOwners().isEmpty)
        #expect(try nothingPending())
        #expect(
            try ModelContext(fx.store.container).fetchCount(FetchDescriptor<SyncTombstoneModel>()) == 0,
            "a local reset never deletes anything on the server"
        )
        #expect(try ownership.claim(userId: userA, at: t0) == .claimed)
        #expect(try nothingPending())
    }
}
