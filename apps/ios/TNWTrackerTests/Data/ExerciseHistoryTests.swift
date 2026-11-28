import Foundation
import Testing
@testable import TNWTrackerKit

/// The history of one exercise (fast-add-exercise S6): its completed sessions,
/// most recent first, each with its date, name and counted sets; and its best set.
@MainActor
struct ExerciseHistoryTests {
    let fx: TrainingFixtures
    let t0 = TrainingFixtures.t0

    init() throws {
        fx = try TrainingFixtures()
    }

    @discardableResult
    private func completedSession(
        _ exercise: Exercise,
        _ sets: [(Int, Double)],
        warmups: Set<Int> = [],
        name: String? = nil,
        at start: Date
    ) throws -> TrainingSession {
        let session = try fx.sessions.startSession(
            routineId: nil,
            name: name,
            at: start,
            timeZone: TrainingFixtures.zone
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

    @Test("every completed session with the exercise, most recent first, with its date, name and counted sets")
    func sessionsMostRecentFirst() throws {
        let older = try completedSession(fx.squat, [(12, 20), (10, 40)], warmups: [0], name: "Legs", at: t0)
        try completedSession(fx.press, [(8, 50)], at: t0.addingTimeInterval(86400))
        let recent = try completedSession(fx.squat, [(8, 45)], name: "Full", at: t0.addingTimeInterval(2 * 86400))

        let history = try fx.sessions.exerciseHistory(exerciseId: fx.squat.id)

        #expect(history.map(\.sessionId) == [recent.id, older.id])
        #expect(history.map(\.sessionName) == ["Full", "Legs"])
        #expect(history.map(\.completedAt) == [recent.completedAt, older.completedAt])
        #expect(history[1].sets == [SetValues(reps: 10, weight: .kg(40))], "warm-ups are not shown as done sets")
        #expect(history[0].sets.count == 1)
    }

    @Test("sessions in progress, sessions with only warm-ups and removed entries are not history")
    func onlyCountedSessions() throws {
        try completedSession(fx.squat, [(12, 20)], warmups: [0], at: t0)
        let removed = try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: TrainingFixtures.zone)
        let set = try fx.sessions.logManualSet(
            SetValues(reps: 5, weight: .kg(60)), warmup: false, exerciseId: fx.squat.id, sessionId: removed.id, at: t0
        )
        let entry = try #require(try fx.sessions.session(id: removed.id)?.entries
            .first { $0.sets.contains { $0.id == set.id } })
        try fx.sessions.removeEntry(id: entry.id)
        try fx.sessions.logManualSet(
            SetValues(reps: 8, weight: .kg(50)), warmup: false, exerciseId: fx.press.id, sessionId: removed.id, at: t0
        )
        try fx.sessions.finishSession(id: removed.id, at: t0.addingTimeInterval(600), durationSeconds: nil)
        let open = try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(
            SetValues(reps: 5, weight: .kg(70)), warmup: false, exerciseId: fx.squat.id, sessionId: open.id, at: t0
        )

        #expect(try fx.sessions.exerciseHistory(exerciseId: fx.squat.id).isEmpty)
    }

    @Test("the best set is the heaviest, then the one with most reps; none without weighted sets")
    func bestSet() {
        let items = [
            ExerciseHistoryItem(sessionId: UUID(), sessionName: nil, completedAt: t0, sets: [
                SetValues(reps: 12, weight: .kg(40)), SetValues(reps: 6, weight: .kg(50))
            ]),
            ExerciseHistoryItem(sessionId: UUID(), sessionName: nil, completedAt: t0, sets: [
                SetValues(reps: 8, weight: .kg(50)), SetValues(reps: 20)
            ])
        ]
        #expect(ExerciseHistoryItem.best(in: items) == SetValues(reps: 8, weight: .kg(50)))
        let bodyweight = [ExerciseHistoryItem(
            sessionId: UUID(),
            sessionName: nil,
            completedAt: t0,
            sets: [SetValues(reps: 20)]
        )]
        #expect(ExerciseHistoryItem.best(in: bodyweight) == nil)
        #expect(ExerciseHistoryItem.best(in: []) == nil)
    }
}
