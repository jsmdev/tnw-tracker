import SwiftUI
import TNWTrackerKit

// MARK: - RestTimerView

/// Displays the active rest timer countdown with −15 s / +15 s and skip.
/// The same view serves both timers (between sets and changing exercise).
/// REQ-AWV-04 (timer sync), REQ-AWV-07 (Duration.TimeFormatStyle).
///
/// Reads `RestTimerState` from the coordinator's timer service.
/// Emits `onSkip` and `onAdjust(seconds)`.
struct RestTimerView: View {
    let state: RestTimerState
    let onSkip: () -> Void
    var onAdjust: (Int) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // REQ-DS-05: el size del countdown escala con Dynamic Type vía @ScaledMetric
    // (NO hardcodear `.font(.system(size: N))` — rompe accessibility XXL).
    @ScaledMetric private var countdownSize: CGFloat = 52

    /// Remaining duration as a `Duration` for TimeFormatStyle.
    private var remaining: Duration {
        Duration.seconds(max(0, state.remaining))
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            timerLabel
            HStack(spacing: Spacing.md) {
                adjustButton(title: "rest-timer.decrease-button", label: "rest-duration.decrease",
                             identifier: AXID.RestTimer.decreaseButton, delta: -RestPolicy.stepSeconds)
                skipButton
                adjustButton(title: "rest-timer.increase-button", label: "rest-duration.increase",
                             identifier: AXID.RestTimer.increaseButton, delta: RestPolicy.stepSeconds)
            }
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
                .font(.system(size: countdownSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText(countsDown: true))
                .accessibilityIdentifier(AXID.RestTimer.timerLabel)
        }
    }

    private func adjustButton(
        title: LocalizedStringKey,
        label: LocalizedStringKey,
        identifier: String,
        delta: Int
    ) -> some View {
        Button(title) { onAdjust(delta) }
            .font(.headline)
            .monospacedDigit()
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel(Text(label))
            .accessibilityIdentifier(identifier)
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
        .accessibilityIdentifier(AXID.RestTimer.skipButton)
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
