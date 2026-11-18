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
                    appEnv.router.push(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("a11y.settings-button")
                .accessibilityIdentifier(AXID.Home.settingsButton)
            }
        }
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
