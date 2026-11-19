import SwiftUI
import TNWTrackerKit

// MARK: - RestDurationControl

/// A rest duration with −15 s / +15 s buttons, kept in `RestPolicy.allowedSeconds`.
/// Greyed out when disabled (the rest is off), while still showing the kept value.
struct RestDurationControl: View {
    @Binding var seconds: Int
    let durationIdentifier: String
    let decreaseIdentifier: String
    let increaseIdentifier: String

    @Environment(\.isEnabled) private var isEnabled

    private var range: ClosedRange<Int> { RestPolicy.allowedSeconds }

    var body: some View {
        // The system lays label and controls out for every text size.
        LabeledContent {
            controls
        } label: {
            Text("rest-duration.label")
        }
        .foregroundStyle(isEnabled ? .primary : .secondary)
    }

    private var controls: some View {
        HStack(spacing: Spacing.md) {
            stepButton(
                systemImage: "minus.circle.fill",
                label: "rest-duration.decrease",
                identifier: decreaseIdentifier,
                delta: -RestPolicy.stepSeconds
            )
            .disabled(seconds <= range.lowerBound)
            Text(Duration.seconds(seconds), format: .time(pattern: .minuteSecond))
                .monospacedDigit()
                .fixedSize()
                .accessibilityLabel(Text("rest-duration.value \(seconds)"))
                .accessibilityIdentifier(durationIdentifier)
            stepButton(
                systemImage: "plus.circle.fill",
                label: "rest-duration.increase",
                identifier: increaseIdentifier,
                delta: RestPolicy.stepSeconds
            )
            .disabled(seconds >= range.upperBound)
        }
    }

    private func stepButton(
        systemImage: String,
        label: LocalizedStringKey,
        identifier: String,
        delta: Int
    ) -> some View {
        Button {
            seconds = min(max(seconds + delta, range.lowerBound), range.upperBound)
        } label: {
            Image(systemName: systemImage)
                .font(.title2)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("RestDurationControl") {
    @Previewable @State var seconds = 90
    Form {
        RestDurationControl(
            seconds: $seconds,
            durationIdentifier: "d",
            decreaseIdentifier: "m",
            increaseIdentifier: "p"
        )
        RestDurationControl(
            seconds: $seconds,
            durationIdentifier: "d2",
            decreaseIdentifier: "m2",
            increaseIdentifier: "p2"
        )
            .disabled(true)
    }
}
#endif
