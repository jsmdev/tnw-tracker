import SwiftUI
import TNWTrackerKit

/// «La última vez · 12 nov» and its sets, under the current exercise's name
/// (fast-add-exercise S3 AC4), so the user sees what to beat before logging.
struct LastPerformanceView: View {
    let last: LastPerformance

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("active-workout.last-time.title \(last.completedAt.formatted(.dateTime.day().month(.abbreviated)))")
                .font(.subheadline.weight(.semibold))
            Text(verbatim: last.sets.map(Self.describe).joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AXID.ActiveWorkout.lastTime)
    }

    /// "15 × 10,1 kg", "12 reps" or "5:00", in the user's locale.
    static func describe(_ set: SetValues) -> String {
        if let reps = set.reps, let weight = set.weight {
            let kilograms = weight.kilograms.formatted(.number.precision(.fractionLength(0 ... 2)))
            return String(localized: "active-workout.last-time.reps-weight \(reps) \(kilograms)")
        }
        if let reps = set.reps {
            return String(localized: "active-workout.last-time.reps \(reps)")
        }
        if let seconds = set.durationSeconds {
            return Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
        }
        return "–"
    }
}
