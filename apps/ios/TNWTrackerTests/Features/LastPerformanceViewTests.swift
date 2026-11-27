import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// How «La última vez» writes each set (fast-add-exercise S3 AC4). The words
/// depend on the device language, so only the numbers are checked.
@Suite("LastPerformanceView")
struct LastPerformanceViewTests {
    @Test("reps and weight, reps only, a timed set, and nothing")
    func describesEachKindOfSet() {
        let withWeight = LastPerformanceView.describe(SetValues(reps: 15, weight: .kg(10.1)))
        #expect(withWeight.contains("15 × 10"))
        #expect(withWeight.hasSuffix("1 kg"))
        let repsOnly = LastPerformanceView.describe(SetValues(reps: 12))
        #expect(repsOnly.hasPrefix("12 "))
        #expect(!repsOnly.contains("kg"))
        #expect(LastPerformanceView.describe(SetValues(durationSeconds: 300)) == "5:00")
        #expect(LastPerformanceView.describe(SetValues()) == "–")
    }
}
