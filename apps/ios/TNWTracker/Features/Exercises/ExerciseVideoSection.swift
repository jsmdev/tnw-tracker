import AVKit
import SwiftUI
import TNWTrackerKit

// MARK: - ExerciseVideoSection

/// The exercise's own video (#182 S9), under a collapsible "Ver vídeo" title.
/// Closed at first: the video is read or downloaded only when the user opens
/// it, and plays in the system player, with full screen and Picture in Picture.
struct ExerciseVideoSection: View {
    let model: ExerciseHeroModel
    let exerciseName: String

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, Spacing.sm)
        } label: {
            Label("exercise-sheet.video.show", systemImage: "play.rectangle")
                .font(.headline)
                .foregroundStyle(Color.primary)
                .accessibilityIdentifier(AXID.ExerciseSheet.videoToggle)
        }
        .task(id: isExpanded) {
            if isExpanded { await model.loadVideo() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let file = model.videoFile {
            SystemVideoPlayer(url: file, isActive: isExpanded, label: String(
                localized: "exercise-sheet.video-label \(exerciseName)"
            ))
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        } else if let notice = model.videoNotice {
            Label {
                Text(notice == .offline ? "exercise-sheet.video.offline" : "exercise-sheet.video.failed")
            } icon: {
                Image(systemName: "video.slash")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(AXID.ExerciseSheet.videoNotice)
        } else {
            ProgressView {
                Text("exercise-sheet.media.loading")
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(AXID.ExerciseSheet.videoLoading)
        }
    }
}

// MARK: - SystemVideoPlayer

/// `AVPlayerViewController`: the system controls, full screen and Picture in
/// Picture. Pauses when its section closes or the sheet goes away, unless the
/// video went on in Picture in Picture.
private struct SystemVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    let isActive: Bool
    let label: String

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = context.coordinator
        // SwiftUI modifiers do not reach a hosted controller's view: set them on it.
        controller.view.accessibilityIdentifier = AXID.ExerciseSheet.video
        controller.view.accessibilityLabel = label
        context.coordinator.url = url
        // Picture in Picture needs the playback category; it is set only here,
        // when the user opens a video, so other audio is left alone until then.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            controller.player?.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        if !isActive, !context.coordinator.isInPictureInPicture {
            controller.player?.pause()
        }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        if !coordinator.isInPictureInPicture {
            controller.player?.pause()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var url: URL?
        var isInPictureInPicture = false

        func playerViewControllerWillStartPictureInPicture(_: AVPlayerViewController) {
            isInPictureInPicture = true
        }

        func playerViewControllerDidStopPictureInPicture(_: AVPlayerViewController) {
            isInPictureInPicture = false
        }
    }
}
