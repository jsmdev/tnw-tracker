import SwiftUI
import TNWTrackerKit

// MARK: - ExerciseListView

/// "Exercises" (#137 S7, T2b): every exercise of the account's local store, its
/// own and the catalogue's, sorted by name; a row opens the exercise's sheet.
/// Reads only the local store, which the sync fills, so it works offline.
/// With `onPick`, a row picks the exercise instead (adding one to a session, #137 S5).
/// A search field filters the list by name (fast-add-exercise S8), and each row
/// shows the exercise's photo when it has one (S7).
struct ExerciseListView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var model: ExerciseListModel
    private let onPick: ((UUID) -> Void)?

    init(exerciseRepository: any ExerciseRepositoryProtocol, onPick: ((UUID) -> Void)? = nil) {
        _model = State(initialValue: ExerciseListModel(exercises: exerciseRepository))
        self.onPick = onPick
    }

    var body: some View {
        Group {
            if model.loadFailed {
                EmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "exercises.load-failed-title",
                    message: "exercises.load-failed-message"
                )
            } else if model.exercises.isEmpty {
                EmptyState(
                    systemImage: "dumbbell",
                    title: "exercises.empty-title",
                    message: "exercises.empty-message"
                )
            } else if model.visibleExercises.isEmpty {
                ContentUnavailableView.search(text: model.query)
                    .accessibilityIdentifier(AXID.Exercises.noResults)
            } else {
                exerciseList
            }
        }
        .searchable(
            text: $model.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("exercises.search-prompt")
        )
        .navigationTitle(Text("exercises.title"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            model.load()
        }
        .refreshable {
            model.load()
        }
    }

    private var exerciseList: some View {
        List(model.visibleExercises) { exercise in
            Button {
                if let onPick {
                    onPick(exercise.id)
                } else {
                    appEnv.router.presentExercise(exercise.id)
                }
            } label: {
                ExerciseRow(exercise: exercise, showsChevron: onPick == nil)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AXID.Exercises.row(exercise.id))
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - ExerciseRow

/// A row: the exercise's photo (else its initial), its name as stored, its
/// equipment and main muscles.
private struct ExerciseRow: View {
    @Environment(AppEnvironment.self) private var appEnv
    let exercise: Exercise
    /// The row opens a sheet; picking rows have no chevron.
    let showsChevron: Bool

    @ScaledMetric(relativeTo: .headline) private var thumbnailSide: CGFloat = 44

    var body: some View {
        HStack(spacing: Spacing.md) {
            ExerciseThumbnail(exercise: exercise, library: appEnv.exerciseMedia, side: thumbnailSide)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: exercise.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let details {
                    Text(verbatim: details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
    }

    /// "Machine · Back, Biceps": the equipment, then the primary muscles.
    private var details: String? {
        let equipment = exercise.equipment.map { String(localized: $0.label) }
        let primary = exercise.muscleGroups.filter { $0.role == .primary }.map { String(localized: $0.muscle.label) }
        let muscles = primary.isEmpty ? nil : primary.formatted(.list(type: .and))
        let parts = [equipment, muscles].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - ExerciseThumbnail

/// The exercise's photo in a small square, read from the media cache or loaded
/// once; its initial while there is none (no photo, offline, still loading).
private struct ExerciseThumbnail: View {
    let exercise: Exercise
    let library: ExerciseMediaLibrary
    let side: CGFloat

    @State private var image: UIImage?

    private var path: String? {
        exercise.media?.imageURI
    }

    var body: some View {
        Group {
            if let image = image ?? path.flatMap(library.memoryCachedImage(path:)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel(Text("exercise-sheet.image-label \(exercise.name)"))
                    .accessibilityIdentifier(AXID.Exercises.photo(exercise.id))
            } else {
                // Decorative: the row's name says which exercise it is.
                Text(verbatim: exercise.name.first.map(String.init) ?? "")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side)
        .background(Color.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .task(id: path) {
            image = nil
            guard let path else { return }
            image = try? await library.image(path: path)
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("ExerciseListView — sample data") {
        let appEnv = AppEnvironment.preview()
        NavigationStack {
            ExerciseListView(exerciseRepository: appEnv.exerciseRepository)
        }
        .environment(appEnv)
    }

    #Preview("ExerciseListView — empty") {
        let appEnv = AppEnvironment.preview(withSampleData: false)
        NavigationStack {
            ExerciseListView(exerciseRepository: appEnv.exerciseRepository)
        }
        .environment(appEnv)
    }
#endif
