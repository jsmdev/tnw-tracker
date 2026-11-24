import Foundation

/// Format field `exercise.relatedLinks[]` (1.2; `relatedVideos` in 1.1): an external
/// link (a video, an article…) that explains the exercise, curated with the
/// catalogue. Shown by its own `title` and `source`, never by its address.
public struct RelatedLink: Hashable, Codable, Sendable {
    public var title: String
    /// An `https` address.
    public var url: String
    /// The name of the site, shown to the user (for example YouTube).
    public var source: String

    public init(title: String, url: String, source: String) {
        self.title = title
        self.url = url
        self.source = source
    }
}

public extension RelatedLink {
    /// The address rule of a related link, curated or personal, as the server
    /// checks it: `https://` followed by an address with no spaces.
    static func isHTTPSAddress(_ url: String) -> Bool {
        let address = url.dropFirst("https://".count)
        return url.hasPrefix("https://") && !address.isEmpty && !address.contains(where: \.isWhitespace)
    }
}
