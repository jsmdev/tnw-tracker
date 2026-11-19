import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - SetLogFormState Tests

@Suite("SetLogFormState")
struct SetLogFormStateTests {
    @Test("default state has reps 0, weight 0, no RIR, not a warm-up")
    func defaultState() {
        let state = SetLogFormState()
        #expect(state.reps == 0)
        #expect(state.weight == 0.0)
        #expect(state.rir == nil)
        #expect(!state.warmup)
    }

    @Test("isValid requires reps > 0")
    func isValidRequiresPositiveReps() {
        var state = SetLogFormState()
        #expect(!state.isValid)

        state.reps = 5
        #expect(state.isValid)
    }

    @Test("isValid allows weight 0 (bodyweight exercises)")
    func isValidAllowsZeroWeight() {
        var state = SetLogFormState()
        state.reps = 10
        state.weight = 0.0
        #expect(state.isValid)
    }

    @Test("RIR is chosen directly in 0–10; nothing else is valid", arguments: [
        (nil, true), (0, true), (3, true), (10, true), (-1, false), (11, false)
    ] as [(Int?, Bool)])
    func rirValidRange(rir: Int?, valid: Bool) {
        var state = SetLogFormState()
        state.reps = 5
        state.rir = rir
        #expect(state.isValid == valid)
        #expect(state.rir == rir, "stored as chosen, no RPE conversion")
    }
}

// MARK: - RIRScale Tests

@Suite("RIRScale")
struct RIRScaleTests {
    @Test("with the default maximum 4 the options are 0, 1, 2, 3 and 4+")
    func defaultOptions() {
        let scale = RIRScale(maximum: RIRScale.defaultMaximum)
        #expect(RIRScale.defaultMaximum == 4)
        #expect(scale.options == [.value(0), .value(1), .value(2), .value(3), .atLeast(4)])
        #expect(scale.options.map(\.label) == ["0", "1", "2", "3", "4+"])
    }

    @Test("choosing N+ stores rir = N, any other option stores its value")
    func choosingStoresRIR() {
        let scale = RIRScale(maximum: 4)
        #expect(scale.rir(for: .atLeast(4)) == 4)
        #expect(scale.rir(for: .value(2)) == 2)
    }

    @Test("changing the maximum to 6 gives 0…5 and 6+")
    func maximumSix() {
        let scale = RIRScale(maximum: 6)
        #expect(scale.options == (0 ... 5).map(RIRScale.Option.value) + [.atLeast(6)])
    }

    @Test("the maximum stays in 1–10", arguments: [(0, 1), (1, 1), (10, 10), (11, 10)])
    func maximumClamped(input: Int, maximum: Int) {
        #expect(RIRScale(maximum: input).maximum == maximum)
    }

    @Test("a stored 7 with maximum 4 is shown as 4+ and is never rewritten")
    func storedAboveMaximum() {
        let scale = RIRScale(maximum: 4)
        var state = SetLogFormState()
        state.reps = 5
        state.rir = 7
        #expect(scale.option(for: state.rir) == .atLeast(4))
        #expect(scale.option(for: 3) == .value(3))
        #expect(scale.option(for: nil) == nil)
        #expect(state.rir == 7)
        #expect(state.isValid)
    }
}
