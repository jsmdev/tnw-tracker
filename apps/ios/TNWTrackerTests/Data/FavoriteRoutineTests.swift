import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

/// T5: favourite routines (AC5.1–AC5.4) and the "Próxima sesión" proposal
/// shared by Home and the widget (AC5.2, AC5.3).
@Suite("FavoriteRoutines")
@MainActor
struct FavoriteRoutineTests {
    let fx: TrainingFixtures
    let t0 = TrainingFixtures.t0
    let day: TimeInterval = 86400

    init() throws {
        fx = try TrainingFixtures()
    }

    /// Completes a session started from `routine`, finished at `date`.
    private func complete(_ routine: Routine, at date: Date) throws {
        let session = try fx.sessions.startSession(
            routineId: routine.id, name: nil, at: date.addingTimeInterval(-600), timeZone: TrainingFixtures.zone
        )
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: session.id, at: date)
        try fx.sessions.finishSession(id: session.id, at: date, durationSeconds: nil)
    }

    private func widgetProposal() -> String? {
        NextSessionQuery(container: fx.store.container).nextSessionName()
    }

    // MARK: - AC5.1

    @Test("AC5.1 the list shows favourites first, then the rest, each group by name")
    func favouritesFirstThenByName() throws {
        for name in ["Pull Day", "Push Day", "Legs Day", "Core Day"] {
            _ = try fx.makeRoutine(name: name)
        }
        let all = try fx.routines.routines(RoutineQuery())
        for name in ["Push Day", "Legs Day"] {
            try fx.routines.setFavorite(true, routineId: #require(all.first { $0.name == name }).id)
        }

        let listed = try fx.routines.routines(RoutineQuery())
        #expect(listed.map(\.name) == ["Legs Day", "Push Day", "Core Day", "Pull Day"])
        #expect(listed.map(\.isFavorite) == [true, true, false, false])
    }

    @Test("AC5.1 search and paging keep the favourites-first order")
    func orderSurvivesSearchAndPaging() throws {
        for name in ["Pull Day", "Push Day", "Legs Day"] {
            _ = try fx.makeRoutine(name: name)
        }
        let push = try #require(try fx.routines.routines(RoutineQuery()).first { $0.name == "Push Day" })
        try fx.routines.setFavorite(true, routineId: push.id)

        #expect(try fx.routines.routines(RoutineQuery(search: "pu")).map(\.name) == ["Push Day", "Pull Day"])
        #expect(try fx.routines.routines(RoutineQuery(offset: 0, limit: 1)).map(\.name) == ["Push Day"])
        #expect(try fx.routines.routines(RoutineQuery(offset: 1, limit: 2)).map(\.name) == ["Legs Day", "Pull Day"])
    }

    // MARK: - AC5.4

    @Test("AC5.4 a favourite persists across launches (fresh context) and can be unmarked")
    func favouritePersists() throws {
        let routine = try fx.makeRoutine(name: "Full Body A")
        try fx.routines.setFavorite(true, routineId: routine.id)

        let fresh = SwiftDataRoutineRepository(context: ModelContext(fx.store.container))
        #expect(try fresh.routine(id: routine.id)?.isFavorite == true)

        try fresh.setFavorite(false, routineId: routine.id)
        let again = SwiftDataRoutineRepository(context: ModelContext(fx.store.container))
        #expect(try again.routine(id: routine.id)?.isFavorite == false)
    }

    @Test("AC5.4 a new routine is not a favourite, and marking an unknown routine throws notFound")
    func defaultsAndUnknown() throws {
        let routine = try fx.makeRoutine(name: "Full Body A")
        #expect(try fx.routines.routine(id: routine.id)?.isFavorite == false)
        #expect(throws: TrainingDataError.notFound) {
            try fx.routines.setFavorite(true, routineId: UUID())
        }
    }

    @Test("D-T5a saving the routine again or re-importing it keeps the user's favourite")
    func saveAndImportKeepFavourite() throws {
        var routine = try fx.makeRoutine(name: "Full Body A")
        try fx.routines.setFavorite(true, routineId: routine.id)
        routine.name = "Full Body A+"
        routine.isFavorite = false
        try fx.routines.save(routine)
        #expect(try fx.routines.routine(id: routine.id)?.isFavorite == true)

        let bundleExercise = Exercise(
            externalRef: fx.ref("ex-1"), name: "Chest Press Machine", type: .strength, equipment: .connectedMachine
        )
        let imported = Routine(
            externalRef: fx.ref("r-9"), name: "Imported Day",
            items: [RoutineItem(order: 1, exerciseId: bundleExercise.id, targetSets: 2)]
        )
        let first = try fx.store.importer.importBundle(TrainingBundle(exercises: [bundleExercise], routines: [imported]))
        let localId = try #require(first.routineIds[imported.id])
        try fx.routines.setFavorite(true, routineId: localId)

        var renamed = imported
        renamed.id = UUID()
        renamed.name = "Imported Day v2"
        let second = try fx.store.importer.importBundle(TrainingBundle(exercises: [bundleExercise], routines: [renamed]))
        #expect(second.routineIds[renamed.id] == localId)
        let reloaded = try #require(try fx.routines.routine(id: localId))
        #expect(reloaded.name == "Imported Day v2")
        #expect(reloaded.isFavorite)
    }

    // MARK: - AC5.2

    @Test("AC5.2 without routines there is no proposal")
    func noRoutines() throws {
        #expect(try fx.routines.nextRoutine() == nil)
        #expect(widgetProposal() == nil)
    }

    @Test("AC5.2 never-done routines come first, by name")
    func neverDoneFirst() throws {
        let done = try fx.makeRoutine(name: "Alpha Day")
        _ = try fx.makeRoutine(name: "Zulu Day")
        _ = try fx.makeRoutine(name: "Mike Day")
        try complete(done, at: t0)

        #expect(try fx.routines.nextRoutine()?.name == "Mike Day")
        #expect(widgetProposal() == "Mike Day")
    }

    @Test("AC5.2 then the routine whose last completed session is the oldest")
    func oldestLastSession() throws {
        let alpha = try fx.makeRoutine(name: "Alpha Day")
        let bravo = try fx.makeRoutine(name: "Bravo Day")
        let charlie = try fx.makeRoutine(name: "Charlie Day")
        try complete(alpha, at: t0.addingTimeInterval(-5 * day))
        try complete(bravo, at: t0.addingTimeInterval(-3 * day))
        try complete(charlie, at: t0.addingTimeInterval(-1 * day))
        // Alpha was also done yesterday: its last session is the newest.
        try complete(alpha, at: t0)

        #expect(try fx.routines.nextRoutine()?.name == "Bravo Day")
        #expect(widgetProposal() == "Bravo Day")
    }

    @Test("AC5.2 completing the proposed routine moves the proposal on (rotation)")
    func rotation() throws {
        let alpha = try fx.makeRoutine(name: "Alpha Day")
        let bravo = try fx.makeRoutine(name: "Bravo Day")
        #expect(try fx.routines.nextRoutine()?.id == alpha.id)
        try complete(alpha, at: t0)
        #expect(try fx.routines.nextRoutine()?.id == bravo.id)
        try complete(bravo, at: t0.addingTimeInterval(day))
        #expect(try fx.routines.nextRoutine()?.id == alpha.id)
    }

    @Test("AC5.2 a session still in progress does not count as done")
    func inProgressDoesNotCount() throws {
        let alpha = try fx.makeRoutine(name: "Alpha Day")
        let bravo = try fx.makeRoutine(name: "Bravo Day")
        try complete(bravo, at: t0)
        _ = try fx.sessions.startSession(routineId: alpha.id, name: nil, at: t0, timeZone: TrainingFixtures.zone)

        #expect(try fx.routines.nextRoutine()?.name == "Alpha Day")
    }

    // MARK: - AC5.3

    @Test("AC5.3 with favourites, the proposal rotates among favourites only, same rule")
    func favouritesOnly() throws {
        let alpha = try fx.makeRoutine(name: "Alpha Day")
        let bravo = try fx.makeRoutine(name: "Bravo Day")
        let charlie = try fx.makeRoutine(name: "Charlie Day")
        _ = try fx.makeRoutine(name: "Delta Day") // never done, not a favourite
        try fx.routines.setFavorite(true, routineId: bravo.id)
        try fx.routines.setFavorite(true, routineId: charlie.id)
        try complete(alpha, at: t0.addingTimeInterval(-9 * day))
        try complete(charlie, at: t0.addingTimeInterval(-2 * day))
        try complete(bravo, at: t0.addingTimeInterval(-1 * day))

        #expect(try fx.routines.nextRoutine()?.name == "Charlie Day")
        #expect(widgetProposal() == "Charlie Day")

        try complete(charlie, at: t0)
        #expect(try fx.routines.nextRoutine()?.name == "Bravo Day")
        #expect(widgetProposal() == "Bravo Day")
    }

    @Test("AC5.3 a never-done favourite comes before the other favourites")
    func neverDoneFavourite() throws {
        let alpha = try fx.makeRoutine(name: "Alpha Day")
        let zulu = try fx.makeRoutine(name: "Zulu Day")
        try fx.routines.setFavorite(true, routineId: alpha.id)
        try fx.routines.setFavorite(true, routineId: zulu.id)
        try complete(alpha, at: t0)

        #expect(try fx.routines.nextRoutine()?.name == "Zulu Day")
        #expect(widgetProposal() == "Zulu Day")
    }
}
