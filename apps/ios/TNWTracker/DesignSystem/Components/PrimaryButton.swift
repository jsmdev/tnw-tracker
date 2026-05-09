import SwiftUI

// MARK: - PrimaryButton

/// The only component that uses Liquid Glass (iOS 26+ only).
/// Falls back to .borderedProminent on older OS.
/// NO fixed height — grows with content for Dynamic Type compliance.
struct PrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    var isLoading: Bool = false

    var body: some View {
        if isLoading {
            loadingButton
        } else {
            activeButton
        }
    }

    @ViewBuilder
    private var activeButton: some View {
        if #available(iOS 26, *) {
            Button(action: action) {
                buttonLabel
            }
            .buttonStyle(.glassProminent)
        } else {
            Button(action: action) {
                buttonLabel
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var loadingButton: some View {
        if #available(iOS 26, *) {
            Button(action: {}) {
                loadingLabel
            }
            .disabled(true)
            .buttonStyle(.glassProminent)
        } else {
            Button(action: {}) {
                loadingLabel
            }
            .disabled(true)
            .buttonStyle(.borderedProminent)
        }
    }

    private var buttonLabel: some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(minHeight: 44)
    }

    private var loadingLabel: some View {
        ProgressView()
            .tint(.white)
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(minHeight: 44)
    }
}

// MARK: - SecondaryButton

struct SecondaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    var isLoading: Bool = false

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Text(title)
                        .font(.headline)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(minHeight: 44)
        }
        .disabled(isLoading)
        .buttonStyle(.bordered)
    }
}

// MARK: - Previews

#Preview("PrimaryButton") {
    VStack(spacing: Spacing.md) {
        PrimaryButton(title: "button.start-workout", action: {})
        PrimaryButton(title: "button.loading", action: {}, isLoading: true)
    }
    .padding()
}

#Preview("SecondaryButton") {
    SecondaryButton(title: "button.cancel", action: {})
        .padding()
}
