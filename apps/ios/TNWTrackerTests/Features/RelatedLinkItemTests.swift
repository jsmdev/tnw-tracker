import Foundation
import Testing
@testable import TNWTrackerKit

/// #182 S9 (T4b-ui): a related video plays in the app when it is a YouTube
/// video, with its cover; any other link only opens outside the app.
@Suite("Related video link")
struct RelatedLinkItemTests {
    private func link(_ url: String) -> RelatedLinkItem {
        RelatedLinkItem(RelatedLink(title: "Invented title", url: url, source: "YouTube"))
    }

    @Test(arguments: [
        "https://www.youtube.com/watch?v=Abc123_-xyZ",
        "https://youtube.com/watch?feature=share&v=Abc123_-xyZ",
        "https://m.youtube.com/watch?v=Abc123_-xyZ",
        "https://youtu.be/Abc123_-xyZ",
        "https://youtu.be/Abc123_-xyZ?si=InventedShare",
        "https://www.youtube.com/embed/Abc123_-xyZ",
        "https://www.youtube-nocookie.com/embed/Abc123_-xyZ",
        "https://www.youtube.com/shorts/Abc123_-xyZ"
    ])
    func youTubeAddressesGiveTheVideoId(url: String) {
        let link = link(url)

        #expect(link.youTubeID == "Abc123_-xyZ")
        #expect(link.coverURL == URL(string: "https://i.ytimg.com/vi/Abc123_-xyZ/hqdefault.jpg"))
        #expect(link.externalURL == URL(string: "https://www.youtube.com/watch?v=Abc123_-xyZ"))
        #expect(link.playsInApp)
    }

    @Test(arguments: [
        "https://example.test/videos/press",
        "https://www.youtube.com/channel/Invented",
        "https://www.youtube.com/watch?v=short",
        "https://youtu.be/",
        "https://notyoutube.com/watch?v=Abc123_-xyZ"
    ])
    func otherAddressesOnlyOpenOutside(url: String) {
        let link = link(url)

        #expect(link.youTubeID == nil)
        #expect(link.coverURL == nil)
        #expect(link.externalURL == URL(string: url))
        #expect(!link.playsInApp)
    }

    @Test func theTitleAndSourceAreKept() {
        let link = link("https://youtu.be/Abc123_-xyZ")

        #expect(link.title == "Invented title")
        #expect(link.source == "YouTube")
        #expect(link.id == "https://www.youtube.com/watch?v=Abc123_-xyZ", "one row per address")
    }

    /// The player loads under an `https` origin of the app: without one,
    /// YouTube refuses to play (error 153).
    @Test func thePlayerPageNamesTheVideoAndPlaysInline() throws {
        let html = try #require(RelatedLinkItem.playerHTML(videoID: "Abc123_-xyZ"))

        #expect(html.contains("videoId:'Abc123_-xyZ'"))
        #expect(html.contains("host:'https://www.youtube-nocookie.com'"))
        #expect(html.contains("playsinline:1"))
        #expect(html.contains("autoplay:1"))
        #expect(html.contains("rel:0"))
        #expect(RelatedLinkItem.playerOrigin(bundleID: "com.Invented.App") == URL(string: "https://com.invented.app"))
        #expect(RelatedLinkItem.playerOrigin(bundleID: nil) == nil)
    }

    /// Only a well-formed id reaches the page, so no address can inject script.
    @Test func thePlayerPageRefusesAnythingButAnId() {
        #expect(RelatedLinkItem.playerHTML(videoID: "Abc'</script>") == nil)
        #expect(RelatedLinkItem.playerHTML(videoID: "") == nil)
    }
}
