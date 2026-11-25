import Foundation
import Testing
@testable import TNWTrackerKit

/// S10 T5c: «Información relacionada» lists our links, then the user's own
/// («Personal»), which the user adds from a pasted address with its preview,
/// renames and deletes. The real in-memory store and repositories; the stand-in
/// preview provider instead of the network. Invented data only.
@Suite("Related links (S10 T5c)")
@MainActor
struct RelatedLinksModelTests {
    let store: TrainingStore
    let exercise = Exercise(
        name: "Cable Row", type: .strength,
        relatedLinks: [
            RelatedLink(title: "Invented row tips", url: "https://youtu.be/Abc123_-xyZ", source: "YouTube"),
            RelatedLink(title: "Invented row article", url: "https://example.test/row", source: "Example")
        ]
    )

    init() throws {
        store = try TrainingStore.inMemory()
        _ = try store.ownership.claim(userId: UUID(), at: TrainingFixtures.t0)
        try store.exercises.save(exercise)
    }

    private func model(previews: any LinkPreviewProviding = StandInLinkPreviewProvider()) -> RelatedLinksModel {
        let model = RelatedLinksModel(
            content: ExerciseSheetContent(exercise), repository: store.exerciseLinks, previews: previews
        )
        model.load()
        return model
    }

    private func stored() throws -> [ExerciseLink] {
        try store.exerciseLinks.links(exerciseId: exercise.id)
    }

    // MARK: - AC1 the section

    @Test("AC1 ours first in their stored order, then the user's by position, labelled personal")
    func oursThenPersonal() throws {
        try store.exerciseLinks.add(
            exerciseId: exercise.id, title: "My row notes", url: "https://notes.example.test/row", source: "Notes"
        )
        try store.exerciseLinks.add(
            exerciseId: exercise.id, title: "My row video", url: "https://video.example.test/row", source: "Video"
        )

        let items = model().items

        #expect(items.map(\.title) == ["Invented row tips", "Invented row article", "My row notes", "My row video"])
        #expect(items.map(\.source) == ["YouTube", "Example", "Notes", "Video"])
        #expect(items.map(\.isPersonal) == [false, false, true, true])
        #expect(try items[2].personalID == (stored().first?.id))
    }

    @Test("AC1 with no links of either kind the section has no rows (it still offers «Añadir enlace»)")
    func noLinks() throws {
        let bare = Exercise(name: "Plank", type: .bodyweight)
        try store.exercises.save(bare)
        let model = RelatedLinksModel(
            content: ExerciseSheetContent(bare), repository: store.exerciseLinks,
            previews: StandInLinkPreviewProvider()
        )

        model.load()

        #expect(model.items.isEmpty)
    }

    // MARK: - AC2 add with a preview

    @Test("AC2 the preview fills in the title, the site and the image; saving adds it after ours as personal")
    func addWithPreview() async throws {
        let model = model()
        let form = model.addForm()
        form.address = "  https://blog.example.test/row-cues \n"

        await form.loadPreview()

        #expect(form.isAdding)
        #expect(form.preview == LinkPreview(
            title: StandInLinkPreviewProvider.title, site: StandInLinkPreviewProvider.site,
            imageData: StandInLinkPreviewProvider.imageData
        ))
        #expect(form.title == StandInLinkPreviewProvider.title)
        #expect(form.site == StandInLinkPreviewProvider.site)
        #expect(!form.isLoadingPreview && !form.previewFailed)

        form.title = "Row cues, edited"
        #expect(form.save())
        #expect(form.problem == nil)

        let link = try #require(try stored().first)
        #expect(try stored().count == 1)
        #expect(link.title == "Row cues, edited")
        #expect(link.url == "https://blog.example.test/row-cues")
        #expect(link.source == StandInLinkPreviewProvider.site)
        model.load()
        #expect(model.items.last == RelatedLinkItem(link))
        #expect(model.items.last?.isPersonal == true)
        #expect(model.items.count == 3)
    }

    @Test("AC2 a title the user typed is kept when the preview arrives")
    func typedTitleKept() async {
        let form = model().addForm()
        form.title = "My own title"
        form.address = "https://blog.example.test/row"

        await form.loadPreview()

        #expect(form.title == "My own title")
        #expect(form.preview?.title == StandInLinkPreviewProvider.title)
    }

    @Test("AC2 a preview for an address the user has since changed is dropped, even when it arrives last")
    func latePreviewDropped() async {
        let firstGate = AsyncGate()
        let secondGate = AsyncGate()
        let previews = GatedLinkPreviewProvider(gates: ["first": firstGate, "second": secondGate])
        let form = model(previews: previews).addForm()
        form.address = "https://blog.example.test/first"
        let first = Task { await form.loadPreview() }
        while !form.isLoadingPreview {
            await Task.yield()
        }

        form.address = "https://blog.example.test/second"
        #expect(!form.isLoadingPreview, "the first address's request is not the current one")
        let second = Task { await form.loadPreview() }
        // The current address answers first; the earlier one last.
        await secondGate.open()
        await second.value
        await firstGate.open()
        await first.value

        #expect(form.title == "Page second")
        #expect(form.preview?.title == "Page second")
        #expect(form.site == "second.example.test")
    }

    // MARK: - AC3 refused or offline

    @Test("AC3 offline: no preview, the typed title is saved with the host as site")
    func addOffline() async throws {
        let model = model()
        let form = model.addForm()
        form.address = "https://\(StandInLinkPreviewProvider.offlineHost)/row"

        await form.loadPreview()

        #expect(form.previewFailed)
        #expect(form.preview == nil)
        #expect(form.title.isEmpty)
        #expect(form.site == StandInLinkPreviewProvider.offlineHost)

        form.title = "Row notes"
        #expect(form.save())
        let link = try #require(try stored().first)
        #expect(link.title == "Row notes")
        #expect(link.source == StandInLinkPreviewProvider.offlineHost)
    }

    @Test("AC3 the host is the site without www.")
    func siteFromHost() throws {
        #expect(try LinkPreview.site(of: #require(URL(string: "https://www.Example.test/a"))) == "example.test")
        #expect(try LinkPreview.site(of: #require(URL(string: "https://blog.example.test"))) == "blog.example.test")
        #expect(try LinkPreview.site(of: #require(URL(string: "file:///tmp/a"))) == nil)
    }

    @Test(
        "AC3 an address that is not https or not valid is refused with a message; nothing is stored",
        arguments: [
            "http://example.test/row",
            "example.test/row",
            "not an address",
            "https://exa mple.test",
            "https://"
        ]
    )
    func invalidAddressRefused(address: String) async throws {
        let form = model().addForm()
        form.address = address
        form.title = "Row"

        await form.loadPreview()

        #expect(form.preview == nil && !form.previewFailed, "no preview is asked for")
        #expect(form.site == nil)
        #expect(!form.save())
        #expect(form.problem == .invalidAddress)
        #expect(try stored().isEmpty)
    }

    @Test("AC3 an empty title is refused with a message")
    func emptyTitleRefused() throws {
        let form = model().addForm()
        form.address = "https://blog.example.test/row"
        form.title = "   "

        #expect(!form.save())
        #expect(form.problem == .emptyTitle)
        #expect(try stored().isEmpty)
    }

    @Test("AC3 an address the exercise already has is refused with a message")
    func duplicateRefused() throws {
        try store.exerciseLinks.add(
            exerciseId: exercise.id, title: "Row", url: "https://blog.example.test/row", source: "Blog"
        )
        let form = model().addForm()
        form.address = "https://blog.example.test/row"
        form.title = "Row again"

        #expect(!form.save())
        #expect(form.problem == .duplicate)
        #expect(try stored().map(\.title) == ["Row"])

        form.address = "https://blog.example.test/other"
        #expect(form.save())
        #expect(form.problem == nil, "a later save clears the message")
    }

    // MARK: - AC4 edit and delete

    @Test("AC4 a personal link's title is edited; ours have no edit form")
    func renamePersonal() throws {
        try store.exerciseLinks.add(
            exerciseId: exercise.id, title: "Row", url: "https://blog.example.test/row", source: "Blog"
        )
        let model = model()
        let personal = try #require(model.items.last)
        #expect(model.editForm(for: model.items[0]) == nil)
        let form = try #require(model.editForm(for: personal))
        #expect(!form.isAdding)
        #expect(form.title == "Row")

        form.title = "  "
        #expect(!form.save())
        #expect(form.problem == .emptyTitle)
        #expect(try stored().first?.title == "Row")

        form.title = " Row, renamed "
        #expect(form.save())
        model.load()
        #expect(try stored().first?.title == "Row, renamed")
        #expect(model.items.last?.title == "Row, renamed")
    }

    @Test("AC4 a personal link is deleted; ours are never deleted")
    func deletePersonal() throws {
        try store.exerciseLinks.add(
            exerciseId: exercise.id, title: "Row", url: "https://blog.example.test/row", source: "Blog"
        )
        let model = model()
        let ours = model.items[0]
        let personal = try #require(model.items.last)

        #expect(!model.delete(ours))
        #expect(model.items.count == 3)

        #expect(model.delete(personal))
        #expect(try stored().isEmpty)
        #expect(model.items.map(\.title) == ["Invented row tips", "Invented row article"])
        #expect(!model.delete(personal), "already gone")
    }

    // MARK: - AC6 YouTube

    @Test("AC6 a personal YouTube link plays in the sheet like ours, under its own id")
    func personalYouTubePlaysInApp() throws {
        try store.exerciseLinks.add(
            exerciseId: exercise.id, title: "My row video", url: "https://youtu.be/Abc123_-xyZ", source: "YouTube"
        )
        try store.exerciseLinks.add(
            exerciseId: exercise.id, title: "My row page", url: "https://blog.example.test/row", source: "Blog"
        )
        let items = model().items

        #expect(items.map(\.playsInApp) == [true, false, true, false])
        #expect(items[2].youTubeID == "Abc123_-xyZ")
        #expect(items[2].id != items[0].id, "the same video as ours is still its own row")
        #expect(Set(items.map(\.id)).count == items.count)
    }
}

/// The preview boundary held at a gate per address (by its last path
/// component), to answer out of order. Each address gets its own title and site.
private struct GatedLinkPreviewProvider: LinkPreviewProviding {
    let gates: [String: AsyncGate]

    func preview(for url: URL) async throws -> LinkPreview {
        await gates[url.lastPathComponent]?.wait()
        let name = url.lastPathComponent
        return LinkPreview(title: "Page \(name)", site: "\(name).example.test", imageData: nil)
    }
}
