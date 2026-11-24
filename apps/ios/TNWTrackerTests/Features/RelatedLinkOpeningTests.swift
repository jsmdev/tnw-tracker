import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// #182 S10 T5d (AC6, AC7): where a related link opens when tapped. Any link
/// other than a YouTube video opens in the in-app browser while «Abrir enlaces
/// en la app» is on (the default), else outside the app; a YouTube video plays
/// in the sheet, and «Abrir en YouTube» always opens it outside.
@Suite("Related link opening")
struct RelatedLinkOpeningTests {
    private let video = "https://youtu.be/Abc123_-xyZ"
    private let guide = "https://example.test/chest-press-guide"

    private func ours(_ url: String) -> RelatedLinkItem {
        RelatedLinkItem(RelatedLink(title: "Invented title", url: url, source: "Example"))
    }

    private func personal(_ url: String) -> RelatedLinkItem {
        RelatedLinkItem(ExerciseLink(exerciseId: UUID(), title: "Invented", url: url, source: "Example", position: 0))
    }

    @Test("AC6 another site opens in the app while the setting is on, ours and personal")
    func otherLinksOpenInTheAppWhenOn() throws {
        let url = try #require(URL(string: guide))

        #expect(ours(guide).opening(opensLinksInApp: true) == .inApp(url))
        #expect(personal(guide).opening(opensLinksInApp: true) == .inApp(url))
    }

    @Test("AC6 another site opens outside the app while the setting is off, ours and personal")
    func otherLinksOpenOutsideWhenOff() throws {
        let url = try #require(URL(string: guide))

        #expect(ours(guide).opening(opensLinksInApp: false) == .outside(url))
        #expect(personal(guide).opening(opensLinksInApp: false) == .outside(url))
    }

    @Test("AC6 a YouTube video plays in the sheet whatever the setting", arguments: [true, false])
    func videosPlayInTheSheet(opensLinksInApp: Bool) {
        #expect(ours(video).opening(opensLinksInApp: opensLinksInApp) == .playInSheet)
        #expect(personal(video).opening(opensLinksInApp: opensLinksInApp) == .playInSheet)
    }

    @Test("AC6 «Abrir en YouTube» opens the video outside the app whatever the setting")
    func openInYouTubeIsAlwaysOutside() throws {
        let url = try #require(URL(string: "https://www.youtube.com/watch?v=Abc123_-xyZ"))

        #expect(ours(video).youTubeOpening == .outside(url))
        #expect(personal(video).youTubeOpening == .outside(url))
        #expect(ours(guide).youTubeOpening == nil, "only a video has «Abrir en YouTube»")
    }

    /// The in-app browser only shows web pages: any other address goes to the system.
    @Test("AC6 an address that is not a web page opens outside even while the setting is on")
    func nonWebAddressesOpenOutside() throws {
        let url = try #require(URL(string: "mailto:coach@example.test"))

        #expect(ours("mailto:coach@example.test").opening(opensLinksInApp: true) == .outside(url))
        let noScheme = try #require(URL(string: "example.test/guide"))
        #expect(ours("example.test/guide").opening(opensLinksInApp: true) == .outside(noScheme))
        #expect(try ours("http://example.test/guide").opening(opensLinksInApp: true)
            == .inApp(#require(URL(string: "http://example.test/guide"))))
    }

    @Test("AC6 an address that is not a URL does nothing")
    func noAddressDoesNothing() {
        #expect(ours("").opening(opensLinksInApp: true) == nil)
    }

    @Test("AC7 «Abrir enlaces en la app» is on by default and remembered on the device")
    func preferenceDefaultsOnAndIsRemembered() throws {
        let suite = "open-links-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(OpenLinksInAppPreference(defaults: defaults).isEnabled)
        #expect(defaults.object(forKey: OpenLinksInAppPreference.enabledKey) == nil, "reading it stores nothing")

        defaults.set(false, forKey: OpenLinksInAppPreference.enabledKey)
        #expect(!OpenLinksInAppPreference(defaults: defaults).isEnabled)
        defaults.set(true, forKey: OpenLinksInAppPreference.enabledKey)
        #expect(OpenLinksInAppPreference(defaults: defaults).isEnabled)
    }
}
