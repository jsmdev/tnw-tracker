import SwiftUI
import TNWTrackerKit

// MARK: - SessionDetailView

/// Shows a routine (name, description) + its exercises list.
/// Tapping an exercise navigates to `.exerciseDetail(exerciseID:)`.
/// REQ-SESSLIST-04.
struct SessionDetailView: View {
    @Environment(AppEnvironment.self) private var appEnv

    let sessionID: UUID

    @State private var session: Routine?
    @State private var exercises: [(item: RoutineItem, exercise: Exercise?)] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                LoadingState(message: "session-detail.loading")
            } else if let session {
                content(session: session)
            } else {
                EmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "session-detail.not-found-title",
                    message: "session-detail.not-found-message"
                )
            }
        }
        .navigationTitle(session.map { Text(verbatim: $0.name) } ?? Text("session-detail.title"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await load()
        }
    }

    // MARK: - Content

    private func content(session: Routine) -> some View {
        List {
            // Session info header
            Section {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if let desc = session.description, !desc.isEmpty {
                        Text(verbatim: desc)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }

            // Exercises section
            Section(header: Text("session-detail.exercises-section")) {
                if exercises.isEmpty {
                    Text("session-detail.no-exercises")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(exercises, id: \.item.order) { item in
                        exerciseRow(item: item)
                    }
                }
            }

            // Quick-start section
            Section {
                PrimaryButton(title: "session-detail.start-button") {
                    appEnv.router.presentedActiveWorkout = ActiveWorkoutPresentation(id: sessionID)
                }
                .listRowInsets(EdgeInsets(
                    top: Spacing.sm,
                    leading: Spacing.md,
                    bottom: Spacing.sm,
                    trailing: Spacing.md
                ))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func exerciseRow(item: (item: RoutineItem, exercise: Exercise?)) -> some View {
        let se = item.item
        let ex = item.exercise

        return Button {
            appEnv.router.push(.exerciseDetail(exerciseID: se.exerciseId))
        } label: {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: ex?.name ?? se.exerciseId.uuidString)
                        .font(.body)
                        .fontWeight(.medium)

                    if let sets = se.targetSets, let reps = se.targetReps?.min {
                        // Use verbatim + String(localized:) to avoid creating a literal
                        // LocalizedStringKey like "session-detail.sets-reps %lld %lld".
                        // The catalog key "session-detail.sets-reps" carries %lld format args.
                        Text(verbatim: String(
                            format: String(localized: "session-detail.sets-reps"),
                            sets, reps
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        guard let routine = try? appEnv.routineRepository.routine(id: sessionID) else {
            session = nil
            return
        }
        session = routine
        let allExercises = (try? appEnv.exerciseRepository.exercises()) ?? []
        let exerciseMap = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })
        exercises = routine.items.map { item in
            (item: item, exercise: exerciseMap[item.exerciseId])
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("SessionDetailView — with exercises") {
    NavigationStack {
        SessionDetailView(sessionID: SampleTrainingData.RoutineID.fullBodyA)
    }
    .environment(AppEnvironment.preview())
}
#endif
