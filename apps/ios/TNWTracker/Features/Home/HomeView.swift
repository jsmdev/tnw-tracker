import SwiftData
import SwiftUI
import TNWTrackerKit

// MARK: - HomeView

/// Home screen: weekly progress + next session + quick start.
/// REQ-HOME-01, REQ-HOME-02, REQ-HOME-03, REQ-HOME-04.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.modelContext) private var modelContext
    @State private var model: HomeModel

    init(container: ModelContainer) {
        _model = State(initialValue: HomeModel(container: container))
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

    private func nextSessionCard(session: Session) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: session.name)
                    .font(.headline)

                Text("home.next-session.exercises-count \(session.sessionExercises.count)")
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

#Preview("HomeView — with data") {
    let container = try! ModelContainerFactory.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let userId = UUID()
    let session = Session(userId: userId, name: "Push Day")
    context.insert(session)
    let se = SessionExercise(sessionId: session.id, exerciseId: UUID(), orderIndex: 0)
    context.insert(se)
    try! context.save()

    return NavigationStack {
        HomeView(container: container)
    }
    .environment(AppEnvironment.bootstrap(modelContext: container.mainContext))
    .modelContainer(container)
}

#Preview("HomeView — empty") {
    let container = try! ModelContainerFactory.makeContainer(inMemory: true)
    return NavigationStack {
        HomeView(container: container)
    }
    .environment(AppEnvironment.bootstrap(modelContext: container.mainContext))
    .modelContainer(container)
}
