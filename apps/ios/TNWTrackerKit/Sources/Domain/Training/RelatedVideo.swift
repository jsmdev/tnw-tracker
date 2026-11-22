import Foundation

/// Format field `exercise.relatedVideos[]` (1.1): an external video that explains
/// the exercise, curated with the catalogue. Shown by its own `title` and
/// `source`, never by its address.
public struct RelatedVideo: Hashable, Codable, Sendable {
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
