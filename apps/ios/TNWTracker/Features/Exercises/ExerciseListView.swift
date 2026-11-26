import SwiftUI
import TNWTrackerKit

// MARK: - ExerciseListView

/// "Exercises" (#137 S7, T2b): every exercise of the account's local store, its
/// own and the catalogue's, sorted by name; a row opens the exercise's sheet.
/// Reads only the local store, which the sync fills, so it works offline.
/// With `onPick`, a row picks the exercise instead (adding one to a session, #137 S5).
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
            } else {
                exerciseList
            }
        }
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
        List(model.exercises) { exercise in
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

/// A row: the exercise's initial, its name as stored, its equipment and main muscles.
private struct ExerciseRow: View {
    let exercise: Exercise
    /// The row opens a sheet; picking rows have no chevron.
    let showsChevron: Bool

    @ScaledMetric(relativeTo: .headline) private var thumbnailSide: CGFloat = 44

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(verbatim: exercise.name.first.map(String.init) ?? "")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(width: thumbnailSide, height: thumbnailSide)
                .background(Color.surfacePrimary, in: RoundedRectangle(cornerRadius: Radius.sm))
                .accessibilityHidden(true)

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
