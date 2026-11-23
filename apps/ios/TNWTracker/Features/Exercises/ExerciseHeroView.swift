import SwiftUI
import TNWTrackerKit

// MARK: - ExerciseHeroView

/// The top of the exercise sheet (#182 S9): the photo, always visible; else a
/// neutral placeholder saying why there is none. The video has its own section
/// (`ExerciseVideoSection`).
struct ExerciseHeroView: View {
    let model: ExerciseHeroModel
    let exerciseName: String

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 40

    var body: some View {
        if let reason = model.placeholder {
            // Its own height: the message grows with Dynamic Type.
            placeholder(reason)
                .frame(maxWidth: .infinity)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        } else {
            photo
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    @ViewBuilder
    private var photo: some View {
        if let image = model.image {
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .accessibilityElement()
                .accessibilityLabel(Text("exercise-sheet.image-label \(exerciseName)"))
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier(AXID.ExerciseSheet.image)
        } else {
            ProgressView {
                Text("exercise-sheet.media.loading")
            }
            .accessibilityIdentifier(AXID.ExerciseSheet.loading)
        }
    }

    private func placeholder(_ reason: ExerciseMediaLibrary.Unavailable) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: placeholderSymbol(reason))
                .font(.system(size: iconSize))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(placeholderText(reason))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AXID.ExerciseSheet.placeholder)
    }

    private func placeholderSymbol(_ reason: ExerciseMediaLibrary.Unavailable) -> String {
        switch reason {
        case .none: "photo"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.triangle"
        }
    }

    private func placeholderText(_ reason: ExerciseMediaLibrary.Unavailable) -> LocalizedStringKey {
        switch reason {
        case .none: "exercise-sheet.media.none"
        case .offline: "exercise-sheet.media.offline"
        case .failed: "exercise-sheet.media.failed"
        }
    }
}
