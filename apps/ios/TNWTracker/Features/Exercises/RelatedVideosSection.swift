import SwiftUI
import TNWTrackerKit
import WebKit

// MARK: - Network seam

extension EnvironmentValues {
    /// False in UI tests: covers and the player never reach the network and
    /// show their stand-ins instead.
    @Entry var relatedVideosUseNetwork = true
}

// MARK: - RelatedVideosSection

/// External videos that explain the exercise (#182 S9): each one by its
/// cover, our title and its source, never its address. A YouTube video
/// plays in the sheet with sound when tapped, one at a time; any other link
/// opens outside the app.
struct RelatedVideosSection: View {
    let videos: [RelatedVideoLink]
    /// The video playing in the sheet, if any.
    @Binding var playing: RelatedVideoLink.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("exercise-sheet.related")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AXID.ExerciseSheet.relatedHeader)
            ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                RelatedVideoRow(video: video, number: index + 1, isPlaying: playing == video.id) {
                    playing = playing == video.id ? nil : video.id
                }
            }
        }
        // A container, so the rows keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.ExerciseSheet.relatedVideos)
    }
}

// MARK: - RelatedVideoRow

private struct RelatedVideoRow: View {
    let video: RelatedVideoLink
    let number: Int
    let isPlaying: Bool
    let toggle: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Button(action: video.playsInApp ? toggle : openOutside) {
                    HStack(spacing: Spacing.md) {
                        RelatedVideoCover(video: video)
                            .frame(width: 112)
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(verbatim: video.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.primary)
                                .multilineTextAlignment(.leading)
                            Text(verbatim: video.source)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: trailingSymbol)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(
                    video.playsInApp ? "exercise-sheet.related.hint.play" : "exercise-sheet.related.hint.open"
                )
                .accessibilityIdentifier(AXID.ExerciseSheet.relatedVideo(number))

                if isPlaying, let id = video.youTubeID {
                    RelatedVideoPlayer(videoID: id, title: video.title)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    Button(action: openOutside) {
                        Label("exercise-sheet.related.open-youtube", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier(AXID.ExerciseSheet.relatedVideoOpen(number))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var trailingSymbol: String {
        guard video.playsInApp else { return "arrow.up.right.square" }
        return isPlaying ? "chevron.up" : "play.circle"
    }

    private func openOutside() {
        if let url = video.externalURL {
            openURL(url)
        }
    }
}

// MARK: - RelatedVideoCover

private struct RelatedVideoCover: View {
    let video: RelatedVideoLink
    @Environment(\.relatedVideosUseNetwork) private var useNetwork

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if useNetwork, let url = video.coverURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: video.playsInApp ? "play.rectangle" : "link")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - RelatedVideoPlayer

/// Plays a YouTube video in the sheet, or says it cannot (no connection, or
/// the video is unavailable). In UI tests a stand-in takes its place.
private struct RelatedVideoPlayer: View {
    let videoID: String
    let title: String

    @Environment(\.relatedVideosUseNetwork) private var useNetwork
    @State private var isUnavailable = false

    var body: some View {
        if isUnavailable {
            Label("exercise-sheet.related.unavailable", systemImage: "video.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.tertiarySystemFill))
                .accessibilityIdentifier(AXID.ExerciseSheet.relatedVideoNotice)
        } else if useNetwork, let html = RelatedVideoLink.playerHTML(videoID: videoID) {
            YouTubeWebView(html: html, label: label) { isUnavailable = true }
        } else {
            Color.black
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityIdentifier(AXID.ExerciseSheet.relatedVideoPlayer)
        }
    }

    private var label: String {
        String(localized: "exercise-sheet.related.player-label \(title)")
    }
}

/// The web view that hosts YouTube's player. It loads under the app's own
/// `https` origin, plays inline and starts with sound when it appears; it
/// stops when it goes away.
private struct YouTubeWebView: UIViewRepresentable {
    let html: String
    let label: String
    let onUnavailable: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        // The user's tap on the row is the request to play.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "player")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.accessibilityIdentifier = AXID.ExerciseSheet.relatedVideoPlayer
        view.accessibilityLabel = label
        let origin = RelatedVideoLink.playerOrigin(bundleID: Bundle.main.bundleIdentifier)
        view.loadHTMLString(html, baseURL: origin)
        return view
    }

    func updateUIView(_: WKWebView, context: Context) {
        context.coordinator.onUnavailable = onUnavailable
    }

    static func dismantleUIView(_ view: WKWebView, coordinator _: Coordinator) {
        view.navigationDelegate = nil
        view.pauseAllMediaPlayback(completionHandler: nil)
        view.configuration.userContentController.removeScriptMessageHandler(forName: "player")
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onUnavailable: onUnavailable)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onUnavailable: () -> Void

        init(onUnavailable: @escaping () -> Void) {
            self.onUnavailable = onUnavailable
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.body as? String == "unavailable" {
                onUnavailable()
            }
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: any Error) {
            onUnavailable()
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError _: any Error) {
            onUnavailable()
        }
    }
}
