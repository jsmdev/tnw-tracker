import SwiftUI
import TNWTrackerKit

// MARK: - HomeView

/// Home screen: weekly progress + next session + quick start.
/// REQ-HOME-01, REQ-HOME-02, REQ-HOME-03, REQ-HOME-04.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var model: HomeModel

    init(sessionRepository: any SessionRepositoryProtocol, routineRepository: any RoutineRepositoryProtocol) {
        _model = State(initialValue: HomeModel(sessions: sessionRepository, routines: routineRepository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                weeklyProgressSection
                nextSessionSection
                freeSessionButton
                otherRoutinesSection
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.lg)
        }
        .navigationTitle(Text("home.title"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await model.load()
        }
        .refreshable {
            await model.load()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    appEnv.router.showExercises()
                } label: {
                    Image(systemName: "dumbbell")
                }
                .accessibilityLabel("a11y.exercises-button")
                .accessibilityIdentifier(AXID.Home.exercisesButton)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    appEnv.router.push(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("a11y.settings-button")
                .accessibilityIdentifier(AXID.Home.settingsButton)
            }
        }
    }

    // MARK: - Free Session

    /// "Entrenamiento libre" (#137 S5): a session without a routine, shown even
    /// with no routine, so a new install can start training.
    private var freeSessionButton: some View {
        SecondaryButton(title: "home.free-session.button") {
            appEnv.router.presentedActiveWorkout = .free()
        }
        .accessibilityIdentifier(AXID.Home.freeSessionButton)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    // MARK: - Weekly Progress Section

    private var weeklyProgressSection: some View {
        VStack(alignment: .leading) {
            SectionHeader(title: "home.weekly-progress.title")

            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("home.weekly-progress.sessions-label")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(model.weeklyCompletedCount, format: .number)
                                .font(.title2)
                                .fontWeight(.bold)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: Spacing.xs) {
                            Text("home.weekly-progress.volume-label")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(model.weeklyVolume, format: .number)
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Next Session Section

    private var nextSessionSection: some View {
        VStack(alignment: .leading) {
            SectionHeader(title: "home.next-session.title")

            if model.isLoading {
                LoadingState(message: "home.next-session.loading")
            } else if let session = model.nextSession {
                nextSessionCard(session: session)
            } else {
                EmptyState(
                    systemImage: "calendar.badge.plus",
                    title: "home.next-session.empty-title",
                    message: "home.next-session.empty-message"
                )
                .padding(.top, Spacing.sm)
            }
        }
    }

    private func nextSessionCard(session: Routine) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: session.name)
                    .font(.headline)
                    .accessibilityIdentifier(AXID.Home.nextSessionTitle)

                Text("home.next-session.exercises-count \(session.items.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if model.hasSessionToday {
                    PrimaryButton(title: "home.quick-start.button") {
                        appEnv.router.presentedActiveWorkout = ActiveWorkoutPresentation(id: session.id)
                    }
                    .accessibilityIdentifier(AXID.Home.quickStartButton)
                    .padding(.top, Spacing.xs)
                }
            }
        }
    }
}

// MARK: - Other Routines Section

extension HomeView {
    /// "Otras rutinas" (T10 AC10.1): the routines "Próxima sesión" does not
    /// propose, favourites first with a star, and "Ver todas" to the routine list.
    /// Shown whenever there is a routine, so the list is always reachable.
    @ViewBuilder
    private var otherRoutinesSection: some View {
        if model.nextSession != nil || !model.otherRoutines.isEmpty {
            VStack(alignment: .leading) {
                SectionHeader(title: "home.other-routines.title") {
                    Button {
                        appEnv.router.push(.sessionHistory)
                    } label: {
                        // Primary colour with a chevron: the default tint does not
                        // reach the contrast minimum on this background. The 44 pt
                        // frame is the minimum hit area.
                        HStack(spacing: Spacing.xs) {
                            Text("home.other-routines.see-all")
                            Image(systemName: "chevron.right")
                                .imageScale(.small)
                                .accessibilityHidden(true)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                    }
                    .accessibilityIdentifier(AXID.Home.seeAllRoutinesButton)
                }

                VStack(spacing: Spacing.sm) {
                    ForEach(model.otherRoutines) { routine in
                        otherRoutineRow(routine)
                    }
                }
            }
        }
    }

    private func otherRoutineRow(_ routine: Routine) -> some View {
        Button {
            appEnv.router.push(.sessionDetail(sessionID: routine.id))
        } label: {
            Card {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: routine.name)
                            .font(.headline)
                        Text("session-list.row.exercises-count \(routine.items.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if routine.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(routine.isFavorite ? Text("routine.favorite.value") : Text(verbatim: ""))
        .accessibilityIdentifier(AXID.Home.otherRoutine(routine.id))
    }
}

// MARK: - Preview

#if DEBUG
#Preview("HomeView — with data") {
    let appEnv = AppEnvironment.preview()
    NavigationStack {
        HomeView(sessionRepository: appEnv.sessionRepository, routineRepository: appEnv.routineRepository)
    }
    .environment(appEnv)
}

#Preview("HomeView — empty") {
    let appEnv = AppEnvironment.preview(withSampleData: false)
    NavigationStack {
        HomeView(sessionRepository: appEnv.sessionRepository, routineRepository: appEnv.routineRepository)
    }
    .environment(appEnv)
}
#endif
