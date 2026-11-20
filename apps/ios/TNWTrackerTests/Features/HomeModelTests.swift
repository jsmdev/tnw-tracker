import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

@Suite("HomeModel")
@MainActor
struct HomeModelTests {
    let fx: TrainingFixtures
    let calendar: Calendar
    /// Wednesday 2030-03-06 12:00 UTC.
    let now = Date(timeIntervalSince1970: 1_899_028_800)

    init() throws {
        fx = try TrainingFixtures()
        var utc = Calendar(identifier: .iso8601)
        utc.timeZone = .gmt
        calendar = utc
    }

    private func makeModel() -> HomeModel {
        HomeModel(sessions: fx.sessions, routines: fx.routines, calendar: calendar, now: { now })
    }

    private func completedSession(at date: Date, sets: [SetValues], exercise: Exercise) throws -> TrainingSession {
        let session = try fx.sessions.startSession(
            routineId: nil,
            name: nil,
            at: date.addingTimeInterval(-600),
            timeZone: .gmt
        )
        for values in sets {
            try fx.sessions.logManualSet(values, exerciseId: exercise.id, sessionId: session.id, at: date)
        }
        return try fx.sessions.finishSession(id: session.id, at: date, durationSeconds: nil)
    }

    @Test("weeklyProgress returns zero when no sessions exist")
    func zeroWithoutSessions() async {
        let model = makeModel()
        await model.load()
        #expect(model.weeklyCompletedCount == 0)
        #expect(model.weeklyVolume == 0)
    }

    @Test("weeklyProgress counts only sessions completed in the current week")
    func countsCurrentWeek() async throws {
        _ = try completedSession(at: now.addingTimeInterval(-3600), sets: [SetValues(reps: 5)], exercise: fx.squat)
        _ = try completedSession(at: now.addingTimeInterval(-8 * 86400), sets: [SetValues(reps: 5)], exercise: fx.squat)
        let model = makeModel()
        await model.load()
        #expect(model.weeklyCompletedCount == 1)
    }

    @Test("weeklyVolume sums weight × reps of counted sets only")
    func volumeOfCountedSets() async throws {
        let session = try fx.sessions.startSession(
            routineId: nil,
            name: nil,
            at: now.addingTimeInterval(-7200),
            timeZone: .gmt
        )
        try fx.sessions.logManualSet(
            SetValues(reps: 10, weight: .kg(20)),
            exerciseId: fx.squat.id,
            sessionId: session.id,
            at: now
        )
        try fx.sessions.logManualSet(
            SetValues(reps: 8, weight: .kg(20)),
            exerciseId: fx.squat.id,
            sessionId: session.id,
            at: now
        )
        // Manual press sets are superseded by the imported ones (default reconciliation).
        try fx.sessions.logManualSet(
            SetValues(reps: 10, weight: .kg(100)),
            exerciseId: fx.press.id,
            sessionId: session.id,
            at: now
        )
        try fx.sessions.importEntry(fx.importedSets("e-1", reps: [10], weight: 40), into: session.id)
        try fx.sessions.finishSession(id: session.id, at: now.addingTimeInterval(-3600), durationSeconds: nil)

        let model = makeModel()
        await model.load()
        let expected: Double = 10 * 20 + 8 * 20 + 10 * 40
        #expect(model.weeklyVolume == expected)
    }

    @Test("nextSession returns nil when no routines exist")
    func noRoutine() async {
        let model = makeModel()
        await model.load()
        #expect(model.nextSession == nil)
        #expect(model.hasSessionToday == false)
    }

    @Test("nextSession returns the first routine by name")
    func firstRoutine() async throws {
        _ = try fx.makeRoutine(name: "Full Body B")
        _ = try fx.makeRoutine(name: "Full Body A")
        let model = makeModel()
        await model.load()
        #expect(model.nextSession?.name == "Full Body A")
        #expect(model.hasSessionToday)
    }

    @Test("AC5.2 nextSession proposes the routine not done for the longest time")
    func nextSessionOldest() async throws {
        let alpha = try fx.makeRoutine(name: "Full Body A")
        let bravo = try fx.makeRoutine(name: "Full Body B")
        for (routine, date) in [
            (alpha, now.addingTimeInterval(-2 * 86400)),
            (bravo, now.addingTimeInterval(-4 * 86400))
        ] {
            let session = try fx.sessions.startSession(routineId: routine.id, name: nil, at: date, timeZone: .gmt)
            try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: session.id, at: date)
            try fx.sessions.finishSession(id: session.id, at: date, durationSeconds: nil)
        }
        let model = makeModel()
        await model.load()
        #expect(model.nextSession?.name == "Full Body B")
    }

    @Test("AC5.3 nextSession proposes among favourites only")
    func nextSessionFavourite() async throws {
        _ = try fx.makeRoutine(name: "Full Body A")
        let bravo = try fx.makeRoutine(name: "Full Body B")
        try fx.routines.setFavorite(true, routineId: bravo.id)
        let model = makeModel()
        await model.load()
        #expect(model.nextSession?.name == "Full Body B")
        #expect(model.nextSession?.isFavorite == true)
    }

    @Test("AC10.1 otherRoutines lists every routine but the proposed one, favourites first, then by name")
    func otherRoutinesSkipTheProposal() async throws {
        let charlie = try fx.makeRoutine(name: "Charlie")
        let alpha = try fx.makeRoutine(name: "Alpha")
        let delta = try fx.makeRoutine(name: "Delta")
        let bravo = try fx.makeRoutine(name: "Bravo")
        try fx.routines.setFavorite(true, routineId: delta.id)
        try fx.routines.setFavorite(true, routineId: bravo.id)
        let model = makeModel()
        await model.load()
        // Proposal: among favourites, never done, by name → Bravo.
        #expect(model.nextSession?.id == bravo.id)
        #expect(model.otherRoutines.map(\.id) == [delta.id, alpha.id, charlie.id])
        #expect(model.otherRoutines.map(\.isFavorite) == [true, false, false])
    }

    @Test("AC10.1 with a single routine, otherRoutines is empty")
    func otherRoutinesEmptyWithOneRoutine() async throws {
        _ = try fx.makeRoutine(name: "Alpha")
        let model = makeModel()
        await model.load()
        #expect(model.nextSession != nil)
        #expect(model.otherRoutines.isEmpty)
    }

    @Test("hasSessionToday is true while a session is in progress")
    func activeSessionCounts() async throws {
        _ = try fx.sessions.startSession(routineId: nil, name: nil, at: now, timeZone: .gmt)
        let model = makeModel()
        await model.load()
        #expect(model.hasSessionToday)
    }

    @Test("a session left in progress is offered to continue")
    func sessionInProgressToContinue() async throws {
        let started = try fx.sessions.startSession(
            routineId: nil, name: "Full Body A", at: now.addingTimeInterval(-600), timeZone: .gmt
        )
        let model = makeModel()
        await model.load()
        #expect(model.sessionInProgress?.id == started.id)
        #expect(model.sessionInProgress?.name == "Full Body A")
    }

    @Test("no session in progress: nothing to continue")
    func nothingToContinue() async throws {
        _ = try completedSession(at: now.addingTimeInterval(-3600), sets: [SetValues(reps: 5)], exercise: fx.squat)
        let model = makeModel()
        await model.load()
        #expect(model.sessionInProgress == nil)
    }

    @Test("a session finished after a load is no longer offered on the next load")
    func finishedSessionNoLongerOffered() async throws {
        let started = try fx.sessions.startSession(routineId: nil, name: nil, at: now, timeZone: .gmt)
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: started.id, at: now)
        let model = makeModel()
        await model.load()
        _ = try fx.sessions.finishSession(id: started.id, at: now, durationSeconds: nil)
        await model.load()
        #expect(model.sessionInProgress == nil)
    }
}
