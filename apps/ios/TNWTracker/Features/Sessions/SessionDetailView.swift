import SwiftData
import SwiftUI
import TNWTrackerKit

// MARK: - SessionDetailView

/// Shows session info (name, description) + its exercises list.
/// Tapping an exercise navigates to `.exerciseDetail(exerciseID:)`.
/// REQ-SESSLIST-04.
struct SessionDetailView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.modelContext) private var modelContext

    let sessionID: UUID

    @State private var session: Session?
    @State private var exercises: [(sessionExercise: SessionExercise, exercise: Exercise?)] = []
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

    private func content(session: Session) -> some View {
        List {
            // Session info header
            Section {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if let desc = session.sessionDescription, !desc.isEmpty {
                        Text(verbatim: desc)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    if let rest = session.restBetweenExercisesSeconds {
                        HStack {
                            Image(systemName: "timer")
                                .foregroundStyle(.secondary)
                            Text("session-detail.rest-between-exercises \(rest)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
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
                    ForEach(exercises, id: \.sessionExercise.id) { item in
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

    private func exerciseRow(item: (sessionExercise: SessionExercise, exercise: Exercise?)) -> some View {
        let se = item.sessionExercise
        let ex = item.exercise

        return Button {
            appEnv.router.push(.exerciseDetail(exerciseID: se.exerciseId))
        } label: {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: ex?.name ?? se.exerciseId.uuidString)
                        .font(.body)
                        .fontWeight(.medium)

                    if let sets = se.targetSets, let reps = se.targetReps {
                        Text("session-detail.sets-reps \(sets) \(reps)")
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

        let context = ModelContext(modelContext.container)

        // Fetch session by ID
        var sessionDescriptor = FetchDescriptor<Session>()
        sessionDescriptor.predicate = #Predicate<Session> { $0.id == sessionID }
        sessionDescriptor.fetchLimit = 1
        guard let fetchedSession = (try? context.fetch(sessionDescriptor))?.first else {
            session = nil
            return
        }
        session = fetchedSession

        // Fetch session exercises ordered by orderIndex
        var seDescriptor = FetchDescriptor<SessionExercise>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        seDescriptor.predicate = #Predicate<SessionExercise> { $0.sessionId == sessionID }
        let sessionExercises = (try? context.fetch(seDescriptor)) ?? []

        // Fetch exercises for each session exercise
        let exerciseIds = sessionExercises.map(\.exerciseId)
        var exDescriptor = FetchDescriptor<Exercise>()
        // Fetch all exercises and filter in memory (predicate on [UUID] not supported in SwiftData)
        let allExercises = (try? context.fetch(exDescriptor)) ?? []
        let exerciseMap = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })

        exercises = sessionExercises.map { se in
            (sessionExercise: se, exercise: exerciseMap[se.exerciseId])
        }
    }
}

// MARK: - Preview

#Preview("SessionDetailView — with exercises") {
    let container = try! ModelContainerFactory.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let userId = UUID()
    let session = Session(userId: userId, name: "Push Day")
    session.sessionDescription = "Upper body pushing movements"
    context.insert(session)

    let bench = Exercise(name: "Bench Press", category: "strength")
    let ohp = Exercise(name: "Overhead Press", category: "strength")
    context.insert(bench)
    context.insert(ohp)

    let se1 = SessionExercise(sessionId: session.id, exerciseId: bench.id, orderIndex: 0)
    se1.targetSets = 4
    se1.targetReps = 8
    se1.restBetweenSetsSeconds = 90
    let se2 = SessionExercise(sessionId: session.id, exerciseId: ohp.id, orderIndex: 1)
    se2.targetSets = 3
    se2.targetReps = 10
    context.insert(se1)
    context.insert(se2)
    session.sessionExercises = [se1, se2]
    try! context.save()

    return NavigationStack {
        SessionDetailView(sessionID: session.id)
    }
    .environment(AppEnvironment.bootstrap(modelContext: container.mainContext))
    .modelContainer(container)
}
