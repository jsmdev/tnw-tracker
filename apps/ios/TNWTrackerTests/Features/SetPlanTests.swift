import Foundation
import Testing
@testable import TNWTrackerKit

/// The set table of the current exercise (fast-add-exercise S5): the rows it
/// starts with, before anything is tapped.
struct SetPlanTests {
    private let date = Date(timeIntervalSince1970: 1_898_845_200)

    private func target(
        sets: Int? = 4,
        reps: RepRange? = RepRange(min: 8, max: 12),
        weight: Weight? = .kg(40)
    ) -> RoutineItem {
        RoutineItem(order: 1, exerciseId: UUID(), targetSets: sets, targetReps: reps, targetWeight: weight)
    }

    @Test("one row per counted set of the last time, with its reps and kg only (AC1)")
    func lastTimeRows() {
        let last = LastPerformance(completedAt: date, sets: [
            SetValues(reps: 20, weight: .kg(9), rir: 2, restSeconds: 90),
            SetValues(reps: 15, weight: .kg(10.1)),
            SetValues(reps: 12)
        ])
        let rows = SetPlan.planned(last: last, target: target())
        #expect(rows == [
            SetValues(reps: 20, weight: .kg(9)),
            SetValues(reps: 15, weight: .kg(10.1)),
            SetValues(reps: 12, weight: .kg(0))
        ], "the last time wins over the routine; RIR and rest are never copied; no weight shows as 0 kg")
    }

    @Test("never done and no routine target: 3 rows of 15 reps and 0 kg (AC2)")
    func defaultRows() {
        let expected = Array(repeating: SetValues(reps: 15, weight: .kg(0)), count: 3)
        #expect(SetPlan.planned(last: nil, target: nil) == expected)
        #expect(SetPlan.planned(last: nil, target: target(sets: nil, reps: nil, weight: nil)) == expected)
        let timedOnly = LastPerformance(completedAt: date, sets: [SetValues(durationSeconds: 45)])
        #expect(SetPlan.planned(last: timedOnly, target: nil) == expected, "a last time without reps is passed over")
    }

    @Test("never done, with a routine target: its sets, its minimum reps and its weight (AC3)")
    func targetRows() {
        #expect(SetPlan.planned(last: nil, target: target()) == Array(
            repeating: SetValues(reps: 8, weight: .kg(40)), count: 4
        ))
        #expect(SetPlan.planned(last: nil, target: target(sets: nil, weight: nil)) == Array(
            repeating: SetValues(reps: 8, weight: .kg(0)), count: 3
        ), "a missing part of the target takes the default")
        #expect(SetPlan.planned(last: nil, target: target(sets: 0)).count == 1, "never an empty table")
    }

    @Test("the rows still to do skip the working sets already logged today")
    func pendingAfterLogged() {
        let planned = [SetValues(reps: 10), SetValues(reps: 9), SetValues(reps: 8)]
        #expect(SetPlan.pending(planned: planned, loggedCount: 0) == planned)
        #expect(SetPlan.pending(planned: planned, loggedCount: 2) == [SetValues(reps: 8)])
        #expect(SetPlan.pending(planned: planned, loggedCount: 5).isEmpty)
    }

    @Test("«Añadir serie» copies the reps and kg of the row above, or starts at 15 reps and 0 kg (AC5)")
    func addedRow() {
        #expect(SetPlan.added(after: SetValues(reps: 9, weight: .kg(30), rir: 1)) == SetValues(
            reps: 9,
            weight: .kg(30)
        ))
        #expect(SetPlan.added(after: nil) == SetValues(reps: 15, weight: .kg(0)))
    }
}
