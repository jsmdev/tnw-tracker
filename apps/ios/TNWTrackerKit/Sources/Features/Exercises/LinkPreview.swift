import Foundation
import LinkPresentation
import UIKit

/// What a pasted address shows before it is saved (S10): its title, its site
/// and an image. Only shown while adding; nothing of it but the title and the
/// site is stored.
public struct LinkPreview: Equatable, Sendable {
    public var title: String?
    public var site: String?
    public var imageData: Data?

    public init(title: String?, site: String?, imageData: Data?) {
        self.title = title
        self.site = site
        self.imageData = imageData
    }

    /// The site of an address when nothing better is known: its host, without
    /// a leading `www.`. `nil` for an address with no host.
    public static func site(of url: URL) -> String? {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Fetches the preview of an address: a network boundary, so the app uses
/// `LiveLinkPreviewProvider` and UI tests and previews a stand-in.
public protocol LinkPreviewProviding: Sendable {
    func preview(for url: URL) async throws -> LinkPreview
}

// MARK: - Live

/// The preview from LinkPresentation. It names no site, so the site is the
/// host of the address the page resolved to.
public struct LiveLinkPreviewProvider: LinkPreviewProviding {
    public init() {}

    @MainActor
    public func preview(for url: URL) async throws -> LinkPreview {
        let provider = LPMetadataProvider()
        provider.timeout = 10
        let metadata = try await provider.startFetchingMetadata(for: url)
        let imageData = await Self.data(from: metadata.imageProvider ?? metadata.iconProvider)
        return LinkPreview(
            title: metadata.title,
            site: LinkPreview.site(of: metadata.url ?? url),
            imageData: imageData
        )
    }

    @MainActor
    private static func data(from provider: NSItemProvider?) async -> Data? {
        guard let provider else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

// MARK: - Stand-in

/// A preview with no network, for UI tests, previews and unit tests: an
/// invented title, site and image for any address, and no connection for the
/// host `offline.test`.
public struct StandInLinkPreviewProvider: LinkPreviewProviding {
    public static let title = "Invented article"
    public static let site = "Invented Site"
    public static let offlineHost = "offline.test"

    public init() {}

    public func preview(for url: URL) async throws -> LinkPreview {
        guard url.host() != Self.offlineHost else { throw URLError(.notConnectedToInternet) }
        return LinkPreview(title: Self.title, site: Self.site, imageData: Self.imageData)
    }

    /// A plain invented image, drawn in code.
    public static let imageData: Data = {
        let size = CGSize(width: 64, height: 36)
        return UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }()
}
