import SwiftUI
import TNWTrackerKit

// MARK: - RelatedLinkFormSheet

/// «Añadir enlace» (S10): paste an address, see its preview (image, title and
/// site) and keep or change the title it fills in; with no preview (offline)
/// the typed title is saved with the address's host as site. «Editar título»
/// shows only the title of one of the user's links.
struct RelatedLinkFormSheet: View {
    @Bindable var model: RelatedLinkFormModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Field?

    private enum Field { case address, title }

    var body: some View {
        NavigationStack {
            Form {
                if model.isAdding {
                    Section("related-link-form.address") {
                        TextField("related-link-form.address.prompt", text: $model.address)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .address)
                            .accessibilityIdentifier(AXID.RelatedLinkForm.address)
                    }
                    preview
                }
                Section("related-link-form.title") {
                    TextField("related-link-form.title", text: $model.title)
                        .focused($focused, equals: .title)
                        .accessibilityIdentifier(AXID.RelatedLinkForm.title)
                }
                if let problem = model.problem {
                    Section {
                        Label(problem.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.red)
                            .accessibilityIdentifier(AXID.RelatedLinkForm.problem)
                    }
                }
            }
            .navigationTitle(Text(model.isAdding ? "exercise-sheet.related.add" : "exercise-sheet.related.edit-title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("exercise-sheet.related.cancel") { dismiss() }
                        .accessibilityIdentifier(AXID.RelatedLinkForm.cancelButton)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("related-link-form.save") {
                        if model.save() {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier(AXID.RelatedLinkForm.saveButton)
                }
            }
            // A short pause, so typing an address does not ask for every prefix.
            .task(id: model.address) {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await model.loadPreview()
            }
            .onAppear { focused = model.isAdding ? .address : .title }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var preview: some View {
        if let site = model.site {
            Section("related-link-form.preview") {
                if let data = model.preview?.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                        .accessibilityLabel(Text("related-link-form.preview-image"))
                        .accessibilityIdentifier(AXID.RelatedLinkForm.previewImage)
                }
                if model.isLoadingPreview {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text("related-link-form.loading")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(AXID.RelatedLinkForm.previewLoading)
                } else if model.previewFailed {
                    Text("related-link-form.no-preview")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AXID.RelatedLinkForm.noPreview)
                }
                LabeledContent("related-link-form.site") {
                    Text(verbatim: site)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AXID.RelatedLinkForm.site)
            }
        }
    }
}

// MARK: - Messages

private extension RelatedLinkFormModel.Problem {
    var message: LocalizedStringKey {
        switch self {
        case .invalidAddress: "related-link-form.problem.invalid-address"
        case .emptyTitle: "related-link-form.problem.empty-title"
        case .duplicate: "related-link-form.problem.duplicate"
        case .failed: "related-link-form.problem.failed"
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("RelatedLinkFormSheet — add") {
        let appEnv = AppEnvironment.preview()
        let content = SampleTrainingData.exercises.first.map(ExerciseSheetContent.init)
        if let content {
            RelatedLinkFormSheet(
                model: RelatedLinksModel(
                    content: content, repository: appEnv.exerciseLinkRepository, previews: StandInLinkPreviewProvider()
                ).addForm()
            )
        }
    }
#endif
