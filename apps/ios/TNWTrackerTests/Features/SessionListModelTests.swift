import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

@Suite("SessionListModel")
@MainActor
struct SessionListModelTests {
    let fx: TrainingFixtures

    init() throws {
        fx = try TrainingFixtures()
    }

    private func makeRoutines(_ count: Int) throws {
        for index in 0 ..< count {
            _ = try fx.makeRoutine(name: String(format: "Routine %03d", index))
        }
    }

    @Test("loadFirstPage returns at most 50 routines when more exist")
    func firstPageCapped() async throws {
        try makeRoutines(60)
        let model = SessionListModel(routines: fx.routines)
        await model.loadFirstPage()
        #expect(model.sessions.count == 50)
        #expect(model.hasNextPage)
    }

    @Test("loadMore appends the next page when more routines exist")
    func loadMoreAppends() async throws {
        try makeRoutines(60)
        let model = SessionListModel(routines: fx.routines)
        await model.loadFirstPage()
        await model.loadMore()
        #expect(model.sessions.count == 60)
        #expect(!model.hasNextPage)
        #expect(Set(model.sessions.map(\.id)).count == 60)
    }

    @Test("pagination returns every routine when fewer than 50 exist")
    func fewerThanAPage() async throws {
        try makeRoutines(7)
        let model = SessionListModel(routines: fx.routines)
        await model.loadFirstPage()
        #expect(model.sessions.count == 7)
        #expect(!model.hasNextPage)
    }

    @Test("routines are ordered by name")
    func orderedByName() async throws {
        _ = try fx.makeRoutine(name: "Pull Day")
        _ = try fx.makeRoutine(name: "Legs Day")
        let model = SessionListModel(routines: fx.routines)
        await model.loadFirstPage()
        #expect(model.sessions.map(\.name) == ["Legs Day", "Pull Day"])
    }

    @Test("AC5.1 AC5.4 marking a routine as favourite moves it first; unmarking moves it back")
    func favouriteMovesFirst() async throws {
        _ = try fx.makeRoutine(name: "Legs Day")
        _ = try fx.makeRoutine(name: "Pull Day")
        let model = SessionListModel(routines: fx.routines)
        await model.loadFirstPage()
        let pull = try #require(model.sessions.last)

        await model.setFavorite(true, for: pull)
        #expect(model.sessions.map(\.name) == ["Pull Day", "Legs Day"])
        #expect(model.sessions.first?.isFavorite == true)

        await model.setFavorite(false, for: try #require(model.sessions.first))
        #expect(model.sessions.map(\.name) == ["Legs Day", "Pull Day"])
        #expect(model.sessions.allSatisfy { !$0.isFavorite })
    }

    @Test("filter .withWorkouts returns only routines with a completed session")
    func withWorkoutsFilter() async throws {
        let performed = try fx.makeRoutine(name: "Routine A")
        _ = try fx.makeRoutine(name: "Routine B")
        let session = try fx.sessions.startSession(
            routineId: performed.id,
            name: nil,
            at: TrainingFixtures.t0,
            timeZone: .gmt
        )
        try fx.sessions.logManualSet(
            SetValues(reps: 5),
            exerciseId: fx.squat.id,
            sessionId: session.id,
            at: TrainingFixtures.t0
        )
        try fx.sessions.finishSession(
            id: session.id,
            at: TrainingFixtures.t0.addingTimeInterval(60),
            durationSeconds: nil
        )

        let model = SessionListModel(routines: fx.routines)
        model.filter = .withWorkouts
        await model.loadFirstPage()
        #expect(model.sessions.map(\.name) == ["Routine A"])
    }

    @Test("search by name filters routines, and an empty search returns all")
    func searchByName() async throws {
        for name in ["Push Day", "Pull Day", "Legs Day"] {
            _ = try fx.makeRoutine(name: name)
        }
        let model = SessionListModel(routines: fx.routines)
        model.searchQuery = "Pu"
        await model.loadFirstPage()
        #expect(model.sessions.map(\.name) == ["Pull Day", "Push Day"])

        model.searchQuery = ""
        await model.loadFirstPage()
        #expect(model.sessions.count == 3)
    }
}
