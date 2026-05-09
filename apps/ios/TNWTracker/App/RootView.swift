import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnv

    var body: some View {
        @Bindable var router = appEnv.router
        NavigationStack(path: $router.path) {
            Text("TNW Tracker")
                .navigationTitle("TNW Tracker")
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .fullScreenCover(item: $router.presentedActiveWorkout) { _ in
            Text("Active Workout")
        }
        .fullScreenCover(item: $router.presentedWorkoutSummary) { _ in
            Text("Workout Summary")
        }
        .onOpenURL { url in
            router.handle(deepLink: url)
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case let .sessionDetail(sessionID):
            Text("Session \(sessionID.uuidString)")
        case let .exerciseDetail(exerciseID):
            Text("Exercise \(exerciseID.uuidString)")
        case .sessionHistory:
            Text("Session History")
        case .settings:
            Text("Settings")
        }
    }
}
