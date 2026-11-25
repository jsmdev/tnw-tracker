import Foundation

/// How the exercise sheet shows a related link (#182 S9, S10): ours, curated
/// with the catalogue, or one of the user's own («Personal»). A YouTube video
/// has a cover and plays in the app; any other link only opens outside it.
public struct RelatedLinkItem: Identifiable, Hashable, Sendable {
    public let title: String
    public let source: String
    /// The user's own link (`ExerciseLink.id`); `nil` for ours, which cannot be
    /// edited or deleted.
    public let personalID: UUID?
    /// The YouTube video id, `nil` when the link is not a YouTube video.
    public let youTubeID: String?
    /// Where "Abrir en YouTube" (or the row, for other links) goes.
    public let externalURL: URL?

    /// A personal link by its own id: it may share its address with one of ours.
    public var id: String {
        personalID?.uuidString ?? externalURL?.absoluteString ?? title
    }

    public init(_ link: RelatedLink) {
        self.init(title: link.title, url: link.url, source: link.source, personalID: nil)
    }

    public init(_ link: ExerciseLink) {
        self.init(title: link.title, url: link.url, source: link.source, personalID: link.id)
    }

    private init(title: String, url: String, source: String, personalID: UUID?) {
        self.title = title
        self.source = source
        self.personalID = personalID
        let url = URL(string: url)
        youTubeID = url.flatMap(Self.youTubeID(in:))
        externalURL = youTubeID.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") } ?? url
    }

    public var isPersonal: Bool {
        personalID != nil
    }

    public var playsInApp: Bool {
        youTubeID != nil
    }

    public var coverURL: URL? {
        youTubeID.flatMap { URL(string: "https://i.ytimg.com/vi/\($0)/hqdefault.jpg") }
    }

    // MARK: - Player page

    /// The page that plays a YouTube video in a web view, through the
    /// privacy-enhanced host. It reports to the `player` message handler:
    /// `playing`, or `unavailable` when the player cannot load or play.
    /// `nil` for anything that is not a video id.
    public static func playerHTML(videoID: String) -> String? {
        guard isVideoID(videoID) else { return nil }
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}#player{width:100%;height:100%}</style>
        </head><body><div id="player"></div><script>
        function post(m){window.webkit.messageHandlers.player.postMessage(m)}
        var api=document.createElement('script');api.src='https://www.youtube.com/iframe_api';
        api.onerror=function(){post('unavailable')};document.head.appendChild(api);
        function onYouTubeIframeAPIReady(){new YT.Player('player',{host:'https://www.youtube-nocookie.com',
          videoId:'\(videoID)',playerVars:{playsinline:1,autoplay:1,rel:0},
          events:{onReady:function(e){e.target.playVideo()},
            onStateChange:function(e){if(e.data===1){post('playing')}},
            onError:function(){post('unavailable')}}})}
        </script></body></html>
        """
    }

    /// The `https` origin the player page loads under, from the app's bundle
    /// id: YouTube refuses to play an embed without one (error 153).
    public static func playerOrigin(bundleID: String?) -> URL? {
        bundleID.flatMap { URL(string: "https://\($0.lowercased())") }
    }

    // MARK: - Parsing

    private static func youTubeID(in url: URL) -> String? {
        guard url.scheme == "https", let host = url.host()?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        let candidate: String? = switch host {
        case "youtu.be":
            path.first
        case "youtube.com", "www.youtube.com", "m.youtube.com", "www.youtube-nocookie.com", "youtube-nocookie.com":
            if path.first == "watch" {
                URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "v" }?.value
            } else if path.count >= 2, ["embed", "shorts"].contains(path[0]) {
                path[1]
            } else {
                nil
            }
        default:
            nil
        }
        return candidate.flatMap { isVideoID($0) ? $0 : nil }
    }

    /// YouTube video ids are 11 characters of `A-Z a-z 0-9 _ -`.
    private static func isVideoID(_ text: String) -> Bool {
        text.count == 11 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}
