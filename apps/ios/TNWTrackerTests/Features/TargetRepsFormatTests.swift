import Testing
@testable import TNWTracker

/// T8 (D9): the routine detail shows the target reps as "3 × 8–12", or as one
/// number, "3 × 10", when min == max or only one bound is set.
@Suite("TargetRepsFormat")
struct TargetRepsFormatTests {
    @Test("AC8.1 a range shows both bounds; equal bounds or a single bound show one number", arguments: [
        (3, 8 as Int?, 12 as Int?, "3 × 8–12"),
        (3, 10, 10, "3 × 10"),
        (4, 6, nil, "4 × 6"),
        (2, nil, 15, "2 × 15")
    ])
    func setsAndReps(sets: Int, min: Int?, max: Int?, expected: String) {
        #expect(TargetRepsFormat.setsReps(sets: sets, minReps: min, maxReps: max) == expected)
    }

    @Test("AC8.1 without reps there is nothing to show")
    func noReps() {
        #expect(TargetRepsFormat.setsReps(sets: 3, minReps: nil, maxReps: nil) == nil)
    }
}
