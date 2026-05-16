import Foundation
import SwiftData
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - SessionListModelTests

// Tests SessionListModel logic: pagination, filter, ordering, search.
// Uses in-memory ModelContainer. Covers REQ-SESSLIST-01, REQ-SESSLIST-02, REQ-SESSLIST-03.

@Suite("SessionListModel", .serialized)
@MainActor
struct SessionListModelTests {
    let container: ModelContainer
    let devUserId: UUID = {
        guard let uid = UUID(uuidString: "00000000-0000-0000-0000-000000000001") else {
            preconditionFailure("Invalid devUserId UUID literal")
        }
        return uid
    }()

    init() throws {
        container = try ModelContainerFactory.makeContainer(inMemory: true)
    }

    // MARK: - Pagination

    @Test("loadFirstPage returns at most 50 sessions when more exist")
    func paginationReturnsFirst50() async throws {
        let context = ModelContext(container)
        // Insert 60 sessions
        for i in 0 ..< 60 {
            let session = Session(userId: devUserId, name: "Session \(i)")
            context.insert(session)
        }
        try context.save()

        let model = SessionListModel(container: container)
        await model.loadFirstPage()

        #expect(model.sessions.count == 50)
    }

    @Test("loadMore appends next page when more sessions exist")
    func loadMoreAppendsNextPage() async throws {
        let context = ModelContext(container)
        // Insert 60 sessions
        for i in 0 ..< 60 {
            let session = Session(userId: devUserId, name: "Session \(i)")
            context.insert(session)
        }
        try context.save()

        let model = SessionListModel(container: container)
        await model.loadFirstPage()
        #expect(model.sessions.count == 50)
        #expect(model.hasNextPage)

        await model.loadMore()
        #expect(model.sessions.count == 60)
        #expect(!model.hasNextPage)
    }

    @Test("pagination returns all sessions when fewer than 50 exist")
    func paginationReturnsAllWhenUnder50() async throws {
        let context = ModelContext(container)
        for i in 0 ..< 10 {
            let session = Session(userId: devUserId, name: "Session \(i)")
            context.insert(session)
        }
        try context.save()

        let model = SessionListModel(container: container)
        await model.loadFirstPage()

        #expect(model.sessions.count == 10)
        #expect(!model.hasNextPage)
    }

    // MARK: - Ordering

    @Test("sessions are ordered most recent first by createdAt")
    func sessionsOrderedMostRecentFirst() async throws {
        let context = ModelContext(container)
        let older = Session(userId: devUserId, name: "Older Session")
        let newer = Session(userId: devUserId, name: "Newer Session")

        // Force ordering via updatedAt which is set on init
        // Insert older first, then newer
        context.insert(older)
        try context.save()
        // Small wait to ensure different timestamps
        let newerDate = Date().addingTimeInterval(1)
        newer.updatedAt = newerDate
        context.insert(newer)
        try context.save()

        let model = SessionListModel(container: container)
        await model.loadFirstPage()

        #expect(model.sessions.count == 2)
        // Most recent (newer) should be first
        #expect(model.sessions.first?.name == "Newer Session")
    }

    // MARK: - Filter

    @Test("filter .all returns all sessions")
    func filterAllReturnsAllSessions() async throws {
        let context = ModelContext(container)
        for i in 0 ..< 5 {
            context.insert(Session(userId: devUserId, name: "Session \(i)"))
        }
        try context.save()

        let model = SessionListModel(container: container)
        model.filter = .all
        await model.loadFirstPage()

        #expect(model.sessions.count == 5)
    }

    @Test("filter .withWorkouts returns only sessions that have associated completed workouts")
    func filterWithWorkoutsReducesSessions() async throws {
        let context = ModelContext(container)

        let sessionA = Session(userId: devUserId, name: "Session A")
        let sessionB = Session(userId: devUserId, name: "Session B")
        context.insert(sessionA)
        context.insert(sessionB)

        // Workout with sessionId pointing to sessionA
        let workout = Workout(userId: devUserId, name: "Session A")
        workout.sessionId = sessionA.id
        workout.status = .completed
        workout.completedAt = Date()
        context.insert(workout)
        try context.save()

        let model = SessionListModel(container: container)
        model.filter = .withWorkouts
        await model.loadFirstPage()

        // Only sessionA has a completed workout referencing it
        #expect(model.sessions.count == 1)
        #expect(model.sessions.first?.name == "Session A")
    }

    // MARK: - Search

    @Test("search by name filters sessions")
    func searchByNameFiltersResults() async throws {
        let context = ModelContext(container)
        context.insert(Session(userId: devUserId, name: "Push Day"))
        context.insert(Session(userId: devUserId, name: "Pull Day"))
        context.insert(Session(userId: devUserId, name: "Legs Day"))
        try context.save()

        let model = SessionListModel(container: container)
        model.searchQuery = "Push"
        await model.loadFirstPage()

        #expect(model.sessions.count == 1)
        #expect(model.sessions.first?.name == "Push Day")
    }

    @Test("empty search returns all sessions")
    func emptySearchReturnsAll() async throws {
        let context = ModelContext(container)
        context.insert(Session(userId: devUserId, name: "Push Day"))
        context.insert(Session(userId: devUserId, name: "Pull Day"))
        try context.save()

        let model = SessionListModel(container: container)
        model.searchQuery = ""
        await model.loadFirstPage()

        #expect(model.sessions.count == 2)
    }
}
