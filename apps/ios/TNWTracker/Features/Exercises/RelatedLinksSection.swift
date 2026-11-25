import SwiftUI
import TNWTrackerKit

// MARK: - Network seam

extension EnvironmentValues {
    /// False in UI tests: covers, the player and link previews never reach the
    /// network and show their stand-ins instead.
    @Entry var relatedLinksUseNetwork = true
}

// MARK: - RelatedLinksSection

/// «Información relacionada» (#182 S9, S10): our links, then the user's own
/// («Personal»), each by its cover, title and source, never its address; then
/// «Añadir enlace». It shows even with no links, so the user can add one. A
/// YouTube video plays in the sheet with sound when tapped, one at a time; any
/// other link opens in the in-app browser, or outside the app when «Abrir
/// enlaces en la app» is off (T5d). Only the user's own have a menu to edit
/// their title or delete them.
struct RelatedLinksSection: View {
    let model: RelatedLinksModel
    /// The video playing in the sheet, if any.
    @Binding var playing: RelatedLinkItem.ID?

    @State private var form: RelatedLinkFormModel?
    @State private var toDelete: RelatedLinkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("exercise-sheet.related")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AXID.ExerciseSheet.relatedHeader)
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, link in
                RelatedLinkRow(
                    link: link, number: index + 1, isPlaying: playing == link.id,
                    toggle: { playing = playing == link.id ? nil : link.id },
                    editTitle: { form = model.editForm(for: link) },
                    delete: { toDelete = link }
                )
            }
            Button {
                form = model.addForm()
            } label: {
                Label("exercise-sheet.related.add", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier(AXID.ExerciseSheet.addLinkButton)
        }
        // A container, so the rows keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.ExerciseSheet.relatedLinks)
        .sheet(item: $form, onDismiss: model.load) { form in
            RelatedLinkFormSheet(model: form)
        }
        // An alert, not a confirmation dialog: on iOS 26 the dialog's popover hides its cancel button.
        .alert(
            "exercise-sheet.related.delete.title",
            isPresented: Binding(get: { toDelete != nil }, set: {
                if !$0 {
                    toDelete = nil
                }
            }),
            presenting: toDelete
        ) { link in
            Button("exercise-sheet.related.delete", role: .destructive) {
                if playing == link.id {
                    playing = nil
                }
                model.delete(link)
            }
            .accessibilityIdentifier(AXID.ExerciseSheet.relatedLinkDeleteConfirm)
            Button("exercise-sheet.related.cancel", role: .cancel) {}
        } message: { link in
            Text("exercise-sheet.related.delete.message \(link.title)")
        }
    }
}

// MARK: - RelatedLinkRow

private struct RelatedLinkRow: View {
    let link: RelatedLinkItem
    let number: Int
    let isPlaying: Bool
    let toggle: () -> Void
    let editTitle: () -> Void
    let delete: () -> Void

    @Environment(\.openURL) private var openURL
    @AppStorage(OpenLinksInAppPreference.enabledKey)
    private var opensLinksInApp = OpenLinksInAppPreference.defaultEnabled

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Button(action: tapRow) {
                        rowLabel
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(hint)
                    .accessibilityIdentifier(AXID.ExerciseSheet.relatedLink(number))

                    if link.isPersonal {
                        menu
                    }
                }

                if isPlaying, let id = link.youTubeID {
                    RelatedLinkPlayer(videoID: id, title: link.title)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    Button { open(link.youTubeOpening) } label: {
                        Label("exercise-sheet.related.open-youtube", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier(AXID.ExerciseSheet.relatedLinkOpen(number))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rowLabel: some View {
        HStack(spacing: Spacing.md) {
            RelatedLinkCover(link: link)
                .frame(width: 112)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: link.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                Text(verbatim: link.source)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if link.isPersonal {
                    Text("exercise-sheet.related.personal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }
            Spacer(minLength: 0)
            Image(systemName: trailingSymbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private var menu: some View {
        Menu {
            Button(action: editTitle) {
                Label("exercise-sheet.related.edit-title", systemImage: "pencil")
            }
            .accessibilityIdentifier(AXID.ExerciseSheet.relatedLinkEditTitle)
            Button(role: .destructive, action: delete) {
                Label("exercise-sheet.related.delete", systemImage: "trash")
            }
            .accessibilityIdentifier(AXID.ExerciseSheet.relatedLinkDelete)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("exercise-sheet.related.options \(link.title)"))
        .accessibilityIdentifier(AXID.ExerciseSheet.relatedLinkMenu(number))
    }

    private var hint: LocalizedStringKey {
        switch link.opening(opensLinksInApp: opensLinksInApp) {
        case .playInSheet: "exercise-sheet.related.hint.play"
        case .inApp: "exercise-sheet.related.hint.open-in-app"
        case .outside, nil: "exercise-sheet.related.hint.open"
        }
    }

    private var trailingSymbol: String {
        guard link.playsInApp else { return "arrow.up.right.square" }
        return isPlaying ? "chevron.up" : "play.circle"
    }

    private func tapRow() {
        open(link.opening(opensLinksInApp: opensLinksInApp))
    }

    private func open(_ opening: RelatedLinkOpening?) {
        switch opening {
        case .playInSheet:
            toggle()
        case let .inApp(url):
            InAppBrowser.present(url)
        case let .outside(url):
            openURL(url)
        case nil:
            break
        }
    }
}

// MARK: - RelatedLinkCover

private struct RelatedLinkCover: View {
    let link: RelatedLinkItem
    @Environment(\.relatedLinksUseNetwork) private var useNetwork

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if useNetwork, let url = link.coverURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: link.playsInApp ? "play.rectangle" : "link")
                .foregroundStyle(.secondary)
        }
    }
}
