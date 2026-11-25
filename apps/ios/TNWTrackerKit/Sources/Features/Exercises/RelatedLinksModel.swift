import Foundation
import Observation

/// «Información relacionada» of the exercise sheet (S10): our links first, in
/// their stored order, then the user's own («Personal»), by position. Only the
/// user's own can be renamed or deleted.
@Observable
@MainActor
public final class RelatedLinksModel {
    public private(set) var items: [RelatedLinkItem]

    private let exerciseId: UUID
    private let ours: [RelatedLinkItem]
    private let repository: any ExerciseLinkRepositoryProtocol
    private let previews: any LinkPreviewProviding

    public init(
        content: ExerciseSheetContent,
        repository: any ExerciseLinkRepositoryProtocol,
        previews: any LinkPreviewProviding
    ) {
        exerciseId = content.id
        ours = content.relatedLinks
        items = content.relatedLinks
        self.repository = repository
        self.previews = previews
    }

    /// Reads the user's links again, after them ours. Ours still show when
    /// the user's cannot be read.
    public func load() {
        let personal = (try? repository.links(exerciseId: exerciseId)) ?? []
        items = ours + personal.map(RelatedLinkItem.init)
    }

    /// The form that adds a link to this exercise.
    public func addForm() -> RelatedLinkFormModel {
        RelatedLinkFormModel(
            mode: .add(exerciseId: exerciseId), title: "", repository: repository, previews: previews
        )
    }

    /// The form that renames one of the user's links; `nil` for ours.
    public func editForm(for item: RelatedLinkItem) -> RelatedLinkFormModel? {
        guard let id = item.personalID else { return nil }
        return RelatedLinkFormModel(
            mode: .editTitle(linkId: id), title: item.title, repository: repository, previews: previews
        )
    }

    /// Deletes one of the user's links; ours are never deleted. False when it failed.
    @discardableResult
    public func delete(_ item: RelatedLinkItem) -> Bool {
        guard let id = item.personalID else { return false }
        defer { load() }
        do {
            try repository.delete(id: id)
            return true
        } catch {
            return false
        }
    }
}

/// The sheet that adds a link (paste the address, see its preview, keep or
/// change its title) or renames one of the user's links (S10).
@Observable
@MainActor
public final class RelatedLinkFormModel: Identifiable {
    public enum Mode: Equatable, Sendable {
        case add(exerciseId: UUID)
        case editTitle(linkId: UUID)
    }

    /// Why «Guardar» was refused.
    public enum Problem: Equatable, Sendable {
        /// Not `https`, with spaces, or with no host.
        case invalidAddress
        case emptyTitle
        /// The exercise already has a personal link with this address.
        case duplicate
        case failed
    }

    public nonisolated let id = UUID()
    public let mode: Mode
    public var address = ""
    public var title: String
    public private(set) var problem: Problem?

    private var loaded: (address: String, preview: LinkPreview)?
    private var loadingAddress: String?
    private var failedAddress: String?
    /// The title the preview filled in; a title the user typed is never replaced.
    private var prefilledTitle: String?
    private let repository: any ExerciseLinkRepositoryProtocol
    private let previews: any LinkPreviewProviding

    init(
        mode: Mode,
        title: String,
        repository: any ExerciseLinkRepositoryProtocol,
        previews: any LinkPreviewProviding
    ) {
        self.mode = mode
        self.title = title
        self.repository = repository
        self.previews = previews
    }

    public var isAdding: Bool {
        if case .add = mode {
            true
        } else {
            false
        }
    }

    /// True while the preview of the address as it is now is being fetched.
    public var isLoadingPreview: Bool {
        loadingAddress != nil && loadingAddress == trimmedAddress
    }

    /// True when the address as it is now has no preview (offline, or the page
    /// gave none): it is still saved, with the typed title and the host as site.
    public var previewFailed: Bool {
        failedAddress != nil && failedAddress == trimmedAddress
    }

    /// The preview of the address as it is now; none for an earlier one.
    public var preview: LinkPreview? {
        loaded.flatMap { $0.address == trimmedAddress ? $0.preview : nil }
    }

    /// The site the link is saved with: the preview's, else the address's host.
    public var site: String? {
        guard let url = validURL else { return nil }
        return preview?.site.flatMap { $0.isEmpty ? nil : $0 } ?? LinkPreview.site(of: url)
    }

    /// Fetches the preview of the current address, and fills in the title from
    /// it unless the user typed one. An answer for an address the user has since
    /// changed is dropped.
    public func loadPreview() async {
        let requested = trimmedAddress
        guard let url = validURL, loaded?.address != requested, loadingAddress != requested else { return }
        loadingAddress = requested
        failedAddress = nil
        defer {
            if loadingAddress == requested {
                loadingAddress = nil
            }
        }
        do {
            let preview = try await previews.preview(for: url)
            guard trimmedAddress == requested else { return }
            loaded = (requested, preview)
            if let fetched = preview.title.map(Self.trimmed), !fetched.isEmpty,
               Self.trimmed(title).isEmpty || title == prefilledTitle {
                title = fetched
                prefilledTitle = fetched
            }
        } catch {
            failedAddress = requested
        }
    }

    /// Saves the link, or says why not in `problem`. True when it was saved.
    public func save() -> Bool {
        problem = nil
        let title = Self.trimmed(title)
        switch mode {
        case let .add(exerciseId):
            guard validURL != nil, let site else {
                problem = .invalidAddress
                return false
            }
            guard !title.isEmpty else {
                problem = .emptyTitle
                return false
            }
            let url = trimmedAddress
            return attempt { try repository.add(exerciseId: exerciseId, title: title, url: url, source: site) }
        case let .editTitle(linkId):
            guard !title.isEmpty else {
                problem = .emptyTitle
                return false
            }
            return attempt { try repository.rename(id: linkId, title: title) }
        }
    }

    // MARK: - Rules

    private func attempt(_ write: () throws -> Void) -> Bool {
        do {
            try write()
            return true
        } catch TrainingDataError.duplicateLink {
            problem = .duplicate
        } catch {
            problem = .failed
        }
        return false
    }

    private var trimmedAddress: String {
        Self.trimmed(address)
    }

    /// The address as the server accepts it, with a host to name the site by.
    private var validURL: URL? {
        let address = trimmedAddress
        guard RelatedLink.isHTTPSAddress(address), let url = URL(string: address),
              LinkPreview.site(of: url) != nil else { return nil }
        return url
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
