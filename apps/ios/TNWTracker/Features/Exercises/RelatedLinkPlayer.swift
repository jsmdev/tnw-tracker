import SwiftUI
import TNWTrackerKit
import WebKit

// MARK: - RelatedLinkPlayer

/// Plays a YouTube video in the sheet, or says it cannot (no connection, or
/// the video is unavailable). In UI tests a stand-in takes its place.
struct RelatedLinkPlayer: View {
    let videoID: String
    let title: String

    @Environment(\.relatedLinksUseNetwork) private var useNetwork
    @State private var isUnavailable = false

    var body: some View {
        if isUnavailable {
            Label("exercise-sheet.related.unavailable", systemImage: "video.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.tertiarySystemFill))
                .accessibilityIdentifier(AXID.ExerciseSheet.relatedLinkNotice)
        } else if useNetwork, let html = RelatedLinkItem.playerHTML(videoID: videoID) {
            YouTubeWebView(html: html, label: label) { isUnavailable = true }
        } else {
            Color.black
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityIdentifier(AXID.ExerciseSheet.relatedLinkPlayer)
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
        view.accessibilityIdentifier = AXID.ExerciseSheet.relatedLinkPlayer
        view.accessibilityLabel = label
        let origin = RelatedLinkItem.playerOrigin(bundleID: Bundle.main.bundleIdentifier)
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
