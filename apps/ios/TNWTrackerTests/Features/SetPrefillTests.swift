import Foundation
import Testing
@testable import TNWTrackerKit

/// The values a new set starts with (fast-add-exercise S3 AC1–AC3):
/// last time's set N, then this session's previous working set, then the
/// routine target, then nothing. Only reps and weight are prefilled.
struct SetPrefillTests {
    private let date = Date(timeIntervalSince1970: 1_898_845_200)

    private var last: LastPerformance {
        LastPerformance(completedAt: date, sets: [
            SetValues(reps: 20, weight: .kg(9), rir: 2, restSeconds: 90),
            SetValues(reps: 15, weight: .kg(10.1)),
            SetValues(reps: 15, weight: .kg(10.1))
        ])
    }

    private var target: RoutineItem {
        RoutineItem(
            order: 1, exerciseId: UUID(), targetSets: 3, targetReps: RepRange(min: 8, max: 12), targetWeight: .kg(40)
        )
    }

    @Test("set N starts with last time's set N, reps and weight only (AC1)")
    func lastTimeSetN() {
        let first = SetPrefill.values(forSet: 1, last: last, loggedToday: [], target: target)
        #expect(first == SetValues(reps: 20, weight: .kg(9)), "RIR and rest are never prefilled")
        let second = SetPrefill.values(
            forSet: 2, last: last, loggedToday: [SetValues(reps: 22, weight: .kg(12))], target: target
        )
        #expect(second == SetValues(reps: 15, weight: .kg(10.1)), "last time wins over today's previous set")
    }

    @Test("past last time's sets, the previous working set of this session (AC2)")
    func previousSetToday() {
        let today = [SetValues(reps: 20, weight: .kg(9)), SetValues(reps: 14, weight: .kg(11), rir: 1)]
        let fourth = SetPrefill.values(
            forSet: 4, last: last, loggedToday: today + [SetValues(reps: 13, weight: .kg(11))], target: target
        )
        #expect(fourth == SetValues(reps: 13, weight: .kg(11)))
        let neverDone = SetPrefill.values(forSet: 3, last: nil, loggedToday: today, target: target)
        #expect(neverDone == SetValues(reps: 14, weight: .kg(11)))
    }

    @Test("with nothing before, the routine target: minimum reps and target weight (AC3)")
    func routineTarget() {
        let fromTarget = SetPrefill.values(forSet: 1, last: nil, loggedToday: [], target: target)
        #expect(fromTarget == SetValues(reps: 8, weight: .kg(40)))
        let repsOnly = RoutineItem(order: 1, exerciseId: UUID(), targetReps: RepRange(min: 10, max: 10))
        #expect(SetPrefill.values(forSet: 1, last: nil, loggedToday: [], target: repsOnly) == SetValues(reps: 10))
    }

    @Test("with nothing at all, the set starts empty")
    func empty() {
        #expect(SetPrefill.values(forSet: 1, last: nil, loggedToday: [], target: nil) == SetValues())
        let noSets = LastPerformance(completedAt: date, sets: [])
        #expect(SetPrefill.values(forSet: 1, last: noSets, loggedToday: [], target: nil) == SetValues())
    }
}
