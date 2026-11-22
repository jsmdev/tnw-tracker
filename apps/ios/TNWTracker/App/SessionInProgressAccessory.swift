import SwiftUI
import TNWTrackerKit

// MARK: - SessionInProgressAccessory

/// "Sesión en curso" above the tab bar (#174 S5): the workout left in progress,
/// with its running time. Tapping it reopens the workout. When the tab bar
/// minimizes, the system shows it inline and smaller.
struct SessionInProgressAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let session: TrainingSession
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    if placement != .inline {
                        Text("session-accessory.title")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Group {
                        if let name = session.name {
                            Text(verbatim: name)
                        } else {
                            Text("free-session.name")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                }
                Spacer(minLength: Spacing.sm)
                if let startedAt = session.startedAt {
                    Text(startedAt, style: .timer)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("session-accessory.hint"))
        .accessibilityIdentifier(AXID.SessionAccessory.button)
    }
}

// MARK: - SessionAccessoryModifier

/// Shows `SessionInProgressAccessory` while `session` is set. Showing and
/// hiding the accessory needs iOS 26.1; on 26.0 Home's "Continuar" card is the
/// way back to the workout.
struct SessionAccessoryModifier: ViewModifier {
    let session: TrainingSession?
    let onOpen: (TrainingSession) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: session != nil) {
                if let session {
                    SessionInProgressAccessory(session: session) { onOpen(session) }
                }
            }
        } else {
            content
        }
    }
}
