import SwiftData
import SwiftUI
import TNWTrackerKit

struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.modelContext) private var modelContext

    /// Coordinator created lazily when the fullScreenCover opens.
    /// Stored in @State so it survives re-renders without recreation.
    @State private var activeCoordinator: ActiveWorkoutCoordinator?

    var body: some View {
        @Bindable var router = appEnv.router
        NavigationStack(path: $router.path) {
            HomeView(container: modelContext.container)
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .fullScreenCover(item: $router.presentedActiveWorkout) { presentation in
            activeWorkoutCover(presentation: presentation)
        }
        .fullScreenCover(item: $router.presentedWorkoutSummary) { presentation in
            WorkoutSummaryView(workoutId: presentation.id)
        }
        .onOpenURL { url in
            router.handle(deepLink: url)
        }
        .onChange(of: router.presentedActiveWorkout) { _, newValue in
            if newValue != nil, activeCoordinator == nil {
                activeCoordinator = appEnv.makeActiveWorkoutCoordinator()
            } else if newValue == nil {
                activeCoordinator = nil
            }
        }
    }

    @ViewBuilder
    private func activeWorkoutCover(presentation: ActiveWorkoutPresentation) -> some View {
        if let coordinator = activeCoordinator {
            NavigationStack {
                ActiveWorkoutView(coordinator: coordinator)
            }
        } else {
            // Coordinator not ready — dismiss cover immediately
            Color.clear
                .onAppear {
                    appEnv.router.presentedActiveWorkout = nil
                }
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case let .sessionDetail(sessionID):
            SessionDetailView(sessionID: sessionID)
        case let .exerciseDetail(exerciseID):
            Text(verbatim: exerciseID.uuidString)
        case .sessionHistory:
            SessionListView(container: modelContext.container)
        case .settings:
            SettingsView()
        }
    }
}
