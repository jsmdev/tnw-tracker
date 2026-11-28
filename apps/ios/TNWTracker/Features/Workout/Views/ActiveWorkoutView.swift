import SwiftUI
import TNWTrackerKit

// MARK: - ActiveWorkoutView

/// Full-screen workout view driven by `ActiveWorkoutCoordinator`.
/// REQ-AWV-01 (tab bar hidden), REQ-AWV-02 (set logging), REQ-AWV-03 (RIR),
/// REQ-AWV-04 (timer sync), REQ-AWV-05 (undo), REQ-AWV-06 (pause/resume).
///
/// Phase transitions animate via PhaseAnimator.
/// RIRSelector + SetCard are consumed from DesignSystem.
struct ActiveWorkoutView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.dismiss) private var dismiss

    let coordinator: ActiveWorkoutCoordinator

    @State private var setLogItem: SetLogSheetItem?
    @State private var restItem: ExerciseRestSheetItem?
    /// The exercise whose history is shown (fast-add-exercise S6).
    @State private var historyExercise: SessionEntry?
    @State private var exerciseNames: [UUID: String] = [:]
    /// "No has registrado ninguna serie" prompt (T6 AC6.1).
    @State private var showDiscardPrompt = false
    /// The exercise waiting for "Quitar ejercicio" to be confirmed.
    @State private var exerciseToRemove: SessionEntry?
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
                    guard let entry = coordinator.entries.first(where: { $0.exerciseId == item.exerciseId }) else {
                        return
                    }
                    Task {
                        try? await coordinator.logPendingSet(
                            at: item.pendingIndex,
                            of: entry,
                            values: SetValues(
                                reps: formState.reps ?? 0,
                                weight: formState.loggedWeightKilograms.map { .kg($0) }
                            ),
                            rir: formState.rir,
                            warmup: formState.warmup
                        )
                    }
                },
                onCancel: { setLogItem = nil }
            )
        }
        // An alert, not a confirmation dialog: on iOS 26 the dialog's popover
        // hides the cancel button, and "Seguir entrenando" must be offered (AC6.1).
        .alert("active-workout.discard.title", isPresented: $showDiscardPrompt) {
            Button("active-workout.discard.confirm", role: .destructive) {
                Task { try? await coordinator.finish() }
            }
            .accessibilityIdentifier(AXID.DiscardWorkout.discardButton)
            Button("active-workout.discard.keep", role: .cancel) {}
                .accessibilityIdentifier(AXID.DiscardWorkout.keepTrainingButton)
        }
        .alert(
            "active-workout.remove-exercise.title",
            isPresented: Binding(get: { exerciseToRemove != nil }, set: {
                if !$0 {
                    exerciseToRemove = nil
                }
            }),
            presenting: exerciseToRemove
        ) { exercise in
            Button("active-workout.remove-exercise.confirm", role: .destructive) {
                Task { try? await coordinator.removeExercise(entryId: exercise.id) }
            }
            .accessibilityIdentifier(AXID.ActiveWorkout.removeExerciseConfirm)
            Button("active-workout.remove-exercise.cancel", role: .cancel) {}
        } message: { _ in
            Text("active-workout.remove-exercise.message")
        }
        .sheet(item: $historyExercise) { exercise in
            ExerciseHistorySheet(
                exerciseName: exerciseNames[exercise.exerciseId] ?? "",
                items: coordinator.history(for: exercise.exerciseId)
            )
        }
        .sheet(item: $restItem) { item in
            ExerciseRestSheet(item: item) { setting in
                try? coordinator.saveRestSetting(setting)
            }
        }
        .task {
            await loadExerciseNames()
        }
        .onChange(of: coordinator.entries.map(\.exerciseId)) {
            Task { await loadExerciseNames() }
        }
        .onChange(of: coordinator.lastFinishOutcome) { _, outcome in
            // A discarded workout has no summary: back to Home (T6 AC6.2).
            if outcome == .discarded {
                appEnv.router.presentedActiveWorkout = nil
            }
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
                .accessibilityIdentifier(AXID.ActiveWorkout.progressIndicator)
        } else {
            workoutContent
        }
    }

    private var workoutContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                headerSection
                phaseSection
                if let exercise = coordinator.currentEntry {
                    exerciseSection(exercise: exercise)
                } else {
                    EmptyState(
                        systemImage: "dumbbell",
                        title: "active-workout.no-exercises.title",
                        message: "active-workout.no-exercises.message"
                    )
                }
                AddExerciseButton(coordinator: coordinator)
                controlsSection
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .navigationTitle(Text(verbatim: coordinator.session?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            ElapsedTimeView(coordinator: coordinator)

            Spacer()

            // Exercise progress
            if !coordinator.entries.isEmpty {
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text("active-workout.exercise-progress-label")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // audit: progress "N / M" uses verbatim — "/" separator is not localizable
                    Text(verbatim: "\(coordinator.currentExerciseIndex + 1) / \(coordinator.entries.count)")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Exercise Section

    private func exerciseSection(exercise: SessionEntry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            exerciseHeader(exercise: exercise)
            if let last = coordinator.lastPerformance(for: exercise.exerciseId) {
                // «La última vez» opens the exercise's whole history.
                Button {
                    historyExercise = exercise
                } label: {
                    LastPerformanceView(last: last)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("active-workout.last-time.history-hint"))
                .padding(.horizontal, Spacing.md)
            }
            SetTableView(coordinator: coordinator, entry: exercise) { index, number, values in
                setLogItem = SetLogSheetItem(
                    id: UUID(),
                    exerciseId: exercise.exerciseId,
                    nextSetNumber: number,
                    prefill: values,
                    pendingIndex: index
                )
            }
            undoButton(exercise: exercise)
        }
        // PhaseAnimator on exercise transitions (smooth when coordinator advances)
        .animation(reduceMotion ? nil : .smooth, value: coordinator.currentExerciseIndex)
    }

    private func exerciseHeader(exercise: SessionEntry) -> some View {
        // Exercise name resolved through the exercise repository.
        // Exercise names are domain data (not localization keys) → Text(verbatim:).
        HStack(alignment: .firstTextBaseline) {
            if let name = exerciseNames[exercise.exerciseId] {
                Text(verbatim: name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier(AXID.ActiveWorkout.exerciseTitle)
            } else {
                Text("active-workout.exercise-header")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier(AXID.ActiveWorkout.exerciseTitle)
            }
            Spacer()
            exerciseOptionsMenu(exercise: exercise)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xs)
    }

    /// The exercise's options: "Descanso entre series".
    private func exerciseOptionsMenu(exercise: SessionEntry) -> some View {
        Menu {
            Button {
                restItem = ExerciseRestSheetItem(setting: coordinator.restSetting(for: exercise.exerciseId))
            } label: {
                Label("exercise-rest.title", systemImage: "timer")
            }
            .accessibilityIdentifier(AXID.ActiveWorkout.exerciseRestButton)

            Button(role: .destructive) {
                exerciseToRemove = exercise
            } label: {
                Label("active-workout.exercise.remove-button", systemImage: "minus.circle")
            }
            .accessibilityIdentifier(AXID.ActiveWorkout.removeExerciseButton)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
        .accessibilityLabel(Text("active-workout.exercise-options"))
        .accessibilityIdentifier(AXID.ActiveWorkout.exerciseOptionsMenu)
    }

    // MARK: - Exercise Name Loading

    @MainActor
    private func loadExerciseNames() async {
        let allExercises = (try? appEnv.exerciseRepository.exercises()) ?? []
        let map = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name) })
        exerciseNames = map
    }

    @ViewBuilder
    private func undoButton(exercise: SessionEntry) -> some View {
        // REQ-AWV-05: visible only when at least one set logged
        if !exercise.manualSets.isEmpty {
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

    // MARK: - Controls Section

    private var controlsSection: some View {
        HStack(spacing: Spacing.md) {
            pauseResumeButton
            Spacer()
            endButton
        }
        .padding(.top, Spacing.sm)
    }

    private var endButton: some View {
        Button(role: .destructive) {
            // T6: with no working set, ask before discarding; otherwise save as before.
            if coordinator.hasWorkingSets {
                Task { try? await coordinator.finish() }
            } else {
                showDiscardPrompt = true
            }
        } label: {
            Label("active-workout.controls.end", systemImage: "stop.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .foregroundStyle(.red)
        .accessibilityIdentifier(AXID.ActiveWorkout.endButton)
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
            .accessibilityIdentifier(AXID.ActiveWorkout.minimizeButton)
        }
    }
}

// MARK: - ElapsedTimeView

/// The workout's elapsed time. Its own view so that only it reads
/// `elapsedSeconds`: the screen body would otherwise be rebuilt every second,
/// and rebuilding the exercise options `Menu` while it is open can drop the
/// tapped item's action ("Descanso entre series" never opens its sheet).
private struct ElapsedTimeView: View {
    let coordinator: ActiveWorkoutCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("active-workout.elapsed-label")
                .font(.caption)
                .foregroundStyle(.secondary)
            let elapsed = Duration.seconds(coordinator.elapsedSeconds)
            Text(elapsed, format: .time(pattern: .minuteSecond))
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
                .accessibilityIdentifier(AXID.ActiveWorkout.elapsedTimer)
        }
        .animation(reduceMotion ? nil : .smooth, value: coordinator.elapsedSeconds)
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("ActiveWorkoutView — active") {
        let appEnv = AppEnvironment.preview()
        let coordinator = ActiveWorkoutCoordinator(
            sessions: appEnv.sessionRepository,
            routines: appEnv.routineRepository,
            exerciseSettings: appEnv.exerciseSettingRepository,
            changeExerciseRest: { ChangeExerciseRestPreference.defaultSeconds },
            requestSync: {},
            timerService: appEnv.makeRestTimerService(),
            liveActivity: appEnv.liveActivity,
            exerciseName: { try? appEnv.exerciseRepository.exercise(id: $0)?.name }
        )
        NavigationStack {
            ActiveWorkoutView(coordinator: coordinator)
        }
        .environment(appEnv)
        .task { try? await coordinator.start(routineId: SampleTrainingData.RoutineID.fullBodyA) }
    }
#endif
