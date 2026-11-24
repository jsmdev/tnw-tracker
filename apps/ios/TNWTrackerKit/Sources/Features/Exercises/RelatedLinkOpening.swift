import Foundation

/// Where a related link goes when tapped (#182 S10 T5d).
public enum RelatedLinkOpening: Equatable, Sendable {
    /// A YouTube video: it plays in the exercise sheet.
    case playInSheet
    /// The in-app browser.
    case inApp(URL)
    /// Outside the app: Safari, or the app that handles the address.
    case outside(URL)
}

public extension RelatedLinkItem {
    /// The row's tap: a YouTube video plays in the sheet whatever the setting;
    /// any other web page opens in the app while «Abrir enlaces en la app» is
    /// on, else outside. An address that is not a web page always goes outside,
    /// since the in-app browser only shows `http` and `https` pages. `nil` when
    /// the link has no address.
    func opening(opensLinksInApp: Bool) -> RelatedLinkOpening? {
        if playsInApp {
            return .playInSheet
        }
        guard let url = externalURL else { return nil }
        let isWebPage = ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        return opensLinksInApp && isWebPage ? .inApp(url) : .outside(url)
    }

    /// «Abrir en YouTube» under a playing video: always outside the app.
    /// `nil` for a link that is not a YouTube video.
    var youTubeOpening: RelatedLinkOpening? {
        guard playsInApp, let url = externalURL else { return nil }
        return .outside(url)
    }
}
