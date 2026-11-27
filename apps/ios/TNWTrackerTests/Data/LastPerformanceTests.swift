import Foundation
import Testing
@testable import TNWTrackerKit

/// "La última vez" (fast-add-exercise S3 AC1, AC4): the counted sets of the most
/// recent completed session that has counted sets for the exercise.
@MainActor
struct LastPerformanceTests {
    let fx: TrainingFixtures
    let t0 = TrainingFixtures.t0

    init() throws {
        fx = try TrainingFixtures()
    }

    /// Logs `sets` (reps, kg) for `exercise` in a new session started at `start`
    /// and completes it ten minutes later. Returns the session.
    @discardableResult
    private func completedSession(
        _ exercise: Exercise,
        _ sets: [(Int, Double)],
        warmups: Set<Int> = [],
        at start: Date
    ) throws -> TrainingSession {
        let session = try fx.sessions.startSession(
            routineId: nil, name: nil, at: start, timeZone: TrainingFixtures.zone
        )
        for (index, set) in sets.enumerated() {
            try fx.sessions.logManualSet(
                SetValues(reps: set.0, weight: .kg(set.1)),
                warmup: warmups.contains(index),
                exerciseId: exercise.id,
                sessionId: session.id,
                at: start.addingTimeInterval(Double(index + 1) * 60)
            )
        }
        return try fx.sessions.finishSession(id: session.id, at: start.addingTimeInterval(600), durationSeconds: nil)
    }

    @Test("the most recent completed session gives its counted sets, in order, and its date")
    func mostRecentSessionWins() throws {
        try completedSession(fx.squat, [(10, 40), (10, 40)], at: t0)
        let recent = try completedSession(fx.squat, [(20, 9), (15, 10.1), (15, 10.1)], at: t0.addingTimeInterval(86400))
        try completedSession(fx.press, [(8, 50)], at: t0.addingTimeInterval(2 * 86400))

        let last = try #require(try fx.sessions.lastPerformance(exerciseId: fx.squat.id))
        #expect(last.completedAt == recent.completedAt)
        #expect(last.sets.map(\.reps) == [20, 15, 15])
        #expect(last.sets.map { $0.weight?.kilograms } == [9, 10.1, 10.1])
    }

    @Test("a session in progress is not last time")
    func sessionInProgressIgnored() throws {
        let session = try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(
            SetValues(reps: 5, weight: .kg(60)), warmup: false, exerciseId: fx.squat.id, sessionId: session.id, at: t0
        )
        #expect(try fx.sessions.lastPerformance(exerciseId: fx.squat.id) == nil)
    }

    @Test("never done gives nothing")
    func neverDone() throws {
        try completedSession(fx.press, [(8, 50)], at: t0)
        #expect(try fx.sessions.lastPerformance(exerciseId: fx.squat.id) == nil)
    }

    @Test("warm-ups do not count; a session with only warm-ups is passed over")
    func warmupsExcluded() throws {
        let older = try completedSession(fx.squat, [(12, 20), (8, 60)], warmups: [0], at: t0)
        try completedSession(fx.squat, [(12, 20)], warmups: [0], at: t0.addingTimeInterval(86400))

        let last = try #require(try fx.sessions.lastPerformance(exerciseId: fx.squat.id))
        #expect(last.completedAt == older.completedAt)
        #expect(last.sets.map(\.reps) == [8])
    }

    @Test("superseded sets do not count: the reconciliation's kept source is last time")
    func supersededExcluded() throws {
        let session = try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(
            SetValues(reps: 5, weight: .kg(100)), warmup: false, exerciseId: fx.press.id, sessionId: session.id, at: t0
        )
        try fx.sessions.importEntry(fx.importedSets("e-l", reps: [12, 10], weight: 45), into: session.id)
        try fx.sessions.finishSession(id: session.id, at: t0.addingTimeInterval(600), durationSeconds: nil)

        let last = try #require(try fx.sessions.lastPerformance(exerciseId: fx.press.id))
        #expect(last.sets.map(\.reps) == [12, 10])
        #expect(last.sets.map { $0.weight?.kilograms } == [45, 45])
    }

    @Test("a removed entry is passed over for an older session")
    func removedEntryIgnored() throws {
        let older = try completedSession(fx.squat, [(10, 40)], at: t0)
        let later = try fx.sessions.startSession(
            routineId: nil, name: nil, at: t0.addingTimeInterval(86400), timeZone: TrainingFixtures.zone
        )
        try fx.sessions.logManualSet(
            SetValues(reps: 3, weight: .kg(90)),
            warmup: false,
            exerciseId: fx.squat.id,
            sessionId: later.id,
            at: t0.addingTimeInterval(86460)
        )
        try fx.sessions.logManualSet(
            SetValues(reps: 8, weight: .kg(50)),
            warmup: false,
            exerciseId: fx.press.id,
            sessionId: later.id,
            at: t0.addingTimeInterval(86520)
        )
        let squatEntry = try #require(
            try fx.sessions.session(id: later.id)?.entries.first { $0.exerciseId == fx.squat.id }
        )
        try fx.sessions.removeEntry(id: squatEntry.id)
        try fx.sessions.finishSession(id: later.id, at: t0.addingTimeInterval(87000), durationSeconds: nil)

        let last = try #require(try fx.sessions.lastPerformance(exerciseId: fx.squat.id))
        #expect(last.completedAt == older.completedAt)
        #expect(last.sets.map(\.reps) == [10])
    }
}
