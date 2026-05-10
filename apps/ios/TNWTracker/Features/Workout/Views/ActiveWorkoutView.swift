import SwiftData
import SwiftUI
import TNWTrackerKit

// MARK: - ActiveWorkoutView

/// Full-screen workout view driven by `ActiveWorkoutCoordinator`.
/// REQ-AWV-01 (tab bar hidden), REQ-AWV-02 (set logging), REQ-AWV-03 (RPE),
/// REQ-AWV-04 (timer sync), REQ-AWV-05 (undo), REQ-AWV-06 (pause/resume).
///
/// Phase transitions animate via PhaseAnimator.
/// RPESelector + SetCard are consumed from DesignSystem.
struct ActiveWorkoutView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let coordinator: ActiveWorkoutCoordinator

    @State private var setLogItem: SetLogSheetItem?
    @State private var exerciseNames: [UUID: String] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            mainContent
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $setLogItem) { item in
            SetLogSheet(
                item: item,
                onSave: { formState in
                    setLogItem = nil
                    Task {
                        try? await coordinator.recordSet(
                            reps: formState.reps,
                            weight: formState.weight > 0 ? formState.weight : nil,
                            weightUnit: .kg,
                            rpe: formState.rpe,
                            isWarmup: formState.isWarmup
                        )
                    }
                },
                onCancel: { setLogItem = nil }
            )
        }
        .task {
            await loadExerciseNames()
        }
        .onChange(of: coordinator.workoutExercises.count) {
            Task { await loadExerciseNames() }
        }
        .onChange(of: coordinator.completedWorkoutId) { _, newId in
            guard let id = newId else { return }
            // Workout finished: present WorkoutSummaryView
            appEnv.router.presentedWorkoutSummary = WorkoutSummaryPresentation(id: id)
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if coordinator.phase == .idle {
            // Workout aún no arrancó (start está pendiente) — mostrar loading.
            // El arranque real se dispara desde ActiveWorkoutCover.task.
            ProgressView()
                .controlSize(.large)
        } else {
            workoutContent
        }
    }

    private var workoutContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                headerSection
                phaseSection
                if let exercise = coordinator.currentExercise {
                    exerciseSection(exercise: exercise)
                }
                controlsSection
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .navigationTitle(Text(verbatim: coordinator.workout?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            // Elapsed time — Format as Duration
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("active-workout.elapsed-label")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let elapsed = Duration.seconds(coordinator.elapsedSeconds)
                Text(elapsed, format: .time(pattern: .minuteSecond))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            Spacer()

            // Exercise progress
            if !coordinator.workoutExercises.isEmpty {
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text("active-workout.exercise-progress-label")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // audit: progress "N / M" uses verbatim — "/" separator is not localizable
                    Text(verbatim: "\(coordinator.currentExerciseIndex + 1) / \(coordinator.workoutExercises.count)")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: coordinator.elapsedSeconds)
    }

    // MARK: - Phase Section (PhaseAnimator for phase transitions)

    @ViewBuilder
    private var phaseSection: some View {
        switch coordinator.phase {
        case .restingBetweenSets, .restingBetweenExercises:
            if let timerState = coordinator.timerState {
                RestTimerView(state: timerState) {
                    Task { await coordinator.skipTimer() }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        case .finishing:
            finishingBanner
                .transition(.scale(scale: 1.05).combined(with: .opacity))
        case .paused:
            pausedBanner
                .transition(.opacity)
        default:
            EmptyView()
        }
    }

    private var finishingBanner: some View {
        Card {
            Label("active-workout.finishing-banner", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
        }
    }

    private var pausedBanner: some View {
        Card {
            HStack {
                Image(systemName: "pause.circle.fill")
                    .symbolEffect(.pulse)
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("active-workout.paused-banner")
                    .font(.headline)
            }
        }
    }

    // MARK: - Exercise Section

    private func exerciseSection(exercise: WorkoutExercise) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            exerciseHeader(exercise: exercise)
            loggedSetsSection(exercise: exercise)
            logSetButton(exercise: exercise)
            undoButton(exercise: exercise)
        }
        // PhaseAnimator on exercise transitions (smooth when coordinator advances)
        .animation(reduceMotion ? nil : .smooth, value: coordinator.currentExerciseIndex)
    }

    private func exerciseHeader(exercise: WorkoutExercise) -> some View {
        // Exercise name resolved via FK lookup against Exercise model.
        // Pattern: FetchDescriptor<Exercise> by exerciseId — same as SessionDetailView.
        // Exercise names are domain data (not localization keys) → Text(verbatim:).
        HStack(alignment: .firstTextBaseline) {
            if let name = exerciseNames[exercise.exerciseId] {
                Text(verbatim: name)
                    .font(.title3)
                    .fontWeight(.semibold)
            } else {
                Text("active-workout.exercise-header")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xs)
    }

    // MARK: - Exercise Name Loading

    @MainActor
    private func loadExerciseNames() async {
        guard !coordinator.workoutExercises.isEmpty else { return }
        let context = ModelContext(modelContext.container)
        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let map = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name) })
        exerciseNames = map
    }

    private func loggedSetsSection(exercise: WorkoutExercise) -> some View {
        let sets = exercise.exerciseSets.sorted { $0.setNumber < $1.setNumber }
        return VStack(spacing: Spacing.sm) {
            ForEach(sets) { set in
                SetCard(set: SetDisplayData(
                    id: set.id,
                    setNumber: set.setNumber,
                    reps: set.reps ?? 0,
                    weight: set.weight ?? 0,
                    rpe: set.rpe
                ))
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: sets.count)
    }

    private func logSetButton(exercise: WorkoutExercise) -> some View {
        PrimaryButton(title: "active-workout.set.log-button") {
            setLogItem = SetLogSheetItem(
                id: UUID(),
                exercise: exercise,
                nextSetNumber: exercise.exerciseSets.count + 1
            )
        }
    }

    private func undoButton(exercise: WorkoutExercise) -> some View {
        Group {
            // REQ-AWV-05: visible only when at least one set logged
            if !exercise.exerciseSets.isEmpty {
                Button {
                    Task { try? await coordinator.undoLastSet() }
                } label: {
                    Label("active-workout.set.undo-button", systemImage: "arrow.uturn.backward")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        HStack(spacing: Spacing.md) {
            pauseResumeButton
            Spacer()
            endButton
        }
        .padding(.top, Spacing.sm)
    }

    @ViewBuilder
    private var pauseResumeButton: some View {
        switch coordinator.phase {
        case .paused:
            Button {
                Task { try? await coordinator.resume() }
            } label: {
                Label("active-workout.controls.resume", systemImage: "play.fill")
                    .symbolEffect(.bounce, value: coordinator.phase == .paused)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .active, .restingBetweenSets, .restingBetweenExercises:
            Button {
                Task { try? await coordinator.pause() }
            } label: {
                Label("active-workout.controls.pause", systemImage: "pause.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        default:
            EmptyView()
        }
    }

    private var endButton: some View {
        Button(role: .destructive) {
            Task { try? await coordinator.finish() }
        } label: {
            Label("active-workout.controls.end", systemImage: "stop.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .foregroundStyle(.red)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
            }
            .accessibilityLabel("a11y.dismiss-button")
        }
    }
}

// MARK: - Preview

#Preview("ActiveWorkoutView — active") {
    let container = try! ModelContainerFactory.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let appEnv = AppEnvironment.bootstrap(modelContext: context)
    // Preview with a stubbed coordinator state is not trivial because
    // coordinator requires SupabaseClient. Use a Text placeholder instead.
    Text("ActiveWorkoutView (preview requires full AppEnvironment)")
        .environment(appEnv)
        .modelContainer(container)
}
