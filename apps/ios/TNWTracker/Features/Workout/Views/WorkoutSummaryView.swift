import SwiftData
import SwiftUI
import TNWTrackerKit

// MARK: - WorkoutSummaryView

/// Full-screen summary shown after a workout completes.
/// Presented via `.fullScreenCover(item: $router.presentedWorkoutSummary)`.
/// REQ-WS-01, REQ-WS-02, REQ-WS-03, REQ-WS-04.
struct WorkoutSummaryView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let workoutId: UUID

    @State private var summary: WorkoutSummary?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingState(message: "summary.loading")
                } else if let summary {
                    content(summary: summary)
                } else {
                    EmptyState(
                        systemImage: "exclamationmark.triangle",
                        title: "summary.not-found-title",
                        message: "summary.not-found-message"
                    )
                }
            }
            .navigationTitle(Text("summary.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    closeButton
                }
            }
        }
        .task {
            await load()
        }
    }

    // MARK: - Content

    private func content(summary: WorkoutSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                workoutNameHeader(summary: summary)
                statsSection(summary: summary)
                prSection(summary: summary)
                exercisesSection(summary: summary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
    }

    // MARK: - Workout name header

    private func workoutNameHeader(summary: WorkoutSummary) -> some View {
        Text(verbatim: summary.workoutName)
            .font(.title2)
            .fontWeight(.bold)
            .padding(.top, Spacing.sm)
    }

    // MARK: - Stats (duration + volume)

    private func statsSection(summary: WorkoutSummary) -> some View {
        HStack(spacing: Spacing.md) {
            Card {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("summary.duration-label")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    durationText(seconds: summary.durationSeconds)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }

            Card {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("summary.volume-label")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(summary.totalVolumeKg, format: .number.precision(.fractionLength(0 ... 1)))
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("summary.volume-unit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func durationText(seconds: Int) -> some View {
        let duration = Duration.seconds(seconds)
        if seconds >= 3600 {
            Text(duration, format: .time(pattern: .hourMinuteSecond))
        } else {
            Text(duration, format: .time(pattern: .minuteSecond))
        }
    }

    // MARK: - Personal Records

    private func prSection(summary: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "summary.pr-section")

            if summary.personalRecords.isEmpty {
                Card {
                    Text("summary.no-prs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(summary.personalRecords, id: \.exerciseName) { pr in
                    Card {
                        HStack {
                            Label {
                                Text(verbatim: pr.exerciseName)
                                    .font(.body)
                                    .fontWeight(.medium)
                            } icon: {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(.yellow)
                            }

                            Spacer()

                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(pr.newValue, format: .number.precision(.fractionLength(0 ... 1)))
                                    .font(.body)
                                    .fontWeight(.semibold)
                                Text("summary.volume-unit")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Exercises

    private func exercisesSection(summary: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "summary.exercises-section")

            if summary.exerciseRows.isEmpty {
                Card {
                    Text("summary.no-exercises")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(summary.exerciseRows) { row in
                    Card {
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(verbatim: row.exerciseName)
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("summary.sets-count \(row.setCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if row.totalVolumeKg > 0 {
                                VStack(alignment: .trailing, spacing: Spacing.xs) {
                                    Text(row.totalVolumeKg, format: .number.precision(.fractionLength(0 ... 1)))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("summary.volume-unit")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Close

    private var closeButton: some View {
        Button {
            closeAndGoHome()
        } label: {
            Text("summary.close-button")
        }
    }

    private func closeAndGoHome() {
        // REQ-WS-03: dismiss cover and clear NavigationStack to home
        appEnv.router.presentedWorkoutSummary = nil
        appEnv.router.presentedActiveWorkout = nil
        appEnv.router.popToRoot()
    }

    // MARK: - Data Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        let ctx = ModelContext(modelContext.container)

        // Fetch the completed workout by ID
        var workoutDescriptor = FetchDescriptor<Workout>()
        workoutDescriptor.predicate = #Predicate<Workout> { $0.id == workoutId }
        workoutDescriptor.fetchLimit = 1

        guard let workout = (try? ctx.fetch(workoutDescriptor))?.first else {
            summary = nil
            return
        }

        summary = WorkoutSummaryBuilder.build(from: workout, context: ctx)
    }
}

// MARK: - Preview

#Preview("WorkoutSummaryView") {
    let container = try! ModelContainerFactory.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let userId = UUID()
    let exerciseId = UUID()

    let exercise = Exercise(name: "Bench Press", category: "strength")
    exercise.id = exerciseId
    context.insert(exercise)

    let workout = Workout(userId: userId, name: "Push Day")
    workout.completedAt = Date()
    workout.durationSeconds = 3720 // 62 min
    context.insert(workout)

    let we = WorkoutExercise(workoutId: workout.id, exerciseId: exerciseId, orderIndex: 0)
    context.insert(we)
    workout.workoutExercises.append(we)

    for i in 1 ... 4 {
        let s = ExerciseSet(workoutExerciseId: we.id, setNumber: i)
        s.reps = 8; s.weight = 80.0; s.weightUnit = .kg; s.isWarmup = false
        context.insert(s); we.exerciseSets.append(s)
    }
    try! context.save()

    let appEnv = AppEnvironment.bootstrap(modelContext: context)
    return WorkoutSummaryView(workoutId: workout.id)
        .environment(appEnv)
        .modelContainer(container)
}
