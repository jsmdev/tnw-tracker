import SwiftUI
import TNWTrackerKit

// MARK: - RestTimerView

/// Displays the active rest timer countdown with a skip button.
/// REQ-AWV-04 (timer sync), REQ-AWV-07 (Duration.TimeFormatStyle).
///
/// Reads `RestTimerState` from the coordinator's timer service.
/// Emits a single action: `onSkip`.
struct RestTimerView: View {
    let state: RestTimerState
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Remaining duration as a `Duration` for TimeFormatStyle.
    private var remaining: Duration {
        Duration.seconds(max(0, state.remaining))
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            timerLabel
            skipButton
        }
        .animation(reduceMotion ? nil : .smooth, value: remaining)
    }

    // MARK: - Subviews

    private var timerLabel: some View {
        VStack(spacing: Spacing.xs) {
            Text("rest-timer.label")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // REQ-AWV-07: Duration.TimeFormatStyle — no manual "Xs" interpolation
            Text(remaining, format: .time(pattern: .minuteSecond))
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText(countsDown: true))
        }
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            Label("rest-timer.skip-button", systemImage: "forward.fill")
                .font(.headline)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .symbolEffect(.bounce, value: remaining.components.seconds)
    }
}

// MARK: - Preview

#Preview("RestTimerView — 90s remaining") {
    let state = RestTimerState(
        id: UUID(),
        workoutId: UUID(),
        type: .betweenSets,
        startedAt: Date(),
        endsAt: Date().addingTimeInterval(90)
    )
    return RestTimerView(state: state, onSkip: {})
        .padding()
}

#Preview("RestTimerView — almost done") {
    let state = RestTimerState(
        id: UUID(),
        workoutId: UUID(),
        type: .betweenSets,
        startedAt: Date(),
        endsAt: Date().addingTimeInterval(5)
    )
    return RestTimerView(state: state, onSkip: {})
        .padding()
}
