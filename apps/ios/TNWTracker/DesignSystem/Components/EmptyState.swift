import SwiftUI

// MARK: - EmptyState

/// Reusable empty state view. Accepts LocalizedStringKey (REQ-DS-05).
/// NO glass, no fixed heights — grows with Dynamic Type.
struct EmptyState: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var cta: LocalizedStringKey?
    var ctaAction: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let cta, let action = ctaAction {
                PrimaryButton(title: cta, action: action)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.sm)
            }
        }
        .padding(Spacing.xl)
    }
}

// MARK: - LoadingState

/// Reusable loading state placeholder. Accepts LocalizedStringKey (REQ-DS-05).
struct LoadingState: View {
    var message: LocalizedStringKey = "loading.default"

    var body: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.2)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.xl)
    }
}

#Preview("EmptyState — with CTA") {
    EmptyState(
        systemImage: "calendar.badge.exclamationmark",
        title: "session.empty.title",
        message: "session.empty.message",
        cta: "session.empty.cta",
        ctaAction: {}
    )
}

#Preview("EmptyState — no CTA") {
    EmptyState(
        systemImage: "dumbbell",
        title: "workout.empty.title",
        message: "workout.empty.message"
    )
}

#Preview("LoadingState") {
    LoadingState(message: "loading.sessions")
}
