import SwiftUI
import TNWTrackerKit

// MARK: - WorkoutSummaryView

/// Full-screen summary shown after a workout completes.
/// Presented via `.fullScreenCover(item: $router.presentedWorkoutSummary)`.
/// REQ-WS-01, REQ-WS-02, REQ-WS-03, REQ-WS-04.
struct WorkoutSummaryView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.dismiss) private var dismiss

    let workoutId: UUID

    @State private var summary: WorkoutSummary?
    @State private var isLoading = true
    /// Where the workout's name ends in the content, and whether it has
    /// scrolled under the bar, which then shows it instead of «Resumen» (AC6).
    @State private var nameBottom: CGFloat = 0
    @State private var showsNameInBar = false

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
                ToolbarItem(placement: .principal) {
                    ZStack {
                        BarTitle(
                            text: Text("summary.title"),
                            isShown: !showsNameInBar,
                            identifier: AXID.Summary.title
                        )
                        if let summary {
                            BarTitle(
                                text: Text(verbatim: summary.workoutName),
                                isShown: showsNameInBar,
                                identifier: AXID.Summary.barTitle
                            )
                        }
                    }
                }
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
            .scrollAwayTitleContent()
        }
        .scrollAwayTitle(below: nameBottom, isScrolledAway: $showsNameInBar)
    }

    // MARK: - Workout name header

    private func workoutNameHeader(summary: WorkoutSummary) -> some View {
        Text(verbatim: summary.workoutName)
            .font(.title2)
            .fontWeight(.bold)
            .padding(.top, Spacing.sm)
            .accessibilityIdentifier(AXID.Summary.workoutNameLabel)
            .scrollAwayTitleHeader(bottom: $nameBottom)
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
        .accessibilityIdentifier(AXID.Summary.closeButton)
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

        guard let session = try? appEnv.sessionRepository.session(id: workoutId) else {
            summary = nil
            return
        }
        let names = ((try? appEnv.exerciseRepository.exercises()) ?? [])
            .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }
        let bests = (try? appEnv.sessionRepository.bestWeights(
            completedBefore: session.completedAt ?? Date()
        )) ?? [:]
        summary = WorkoutSummaryBuilder.build(from: session, exerciseNames: names, previousBests: bests)
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("WorkoutSummaryView") {
        let appEnv = AppEnvironment.preview()
        let lastSession = try? appEnv.sessionRepository.completedSessions(
            in: DateInterval(start: .distantPast, end: Date())
        ).first
        WorkoutSummaryView(workoutId: lastSession?.id ?? UUID())
            .environment(appEnv)
    }
#endif
