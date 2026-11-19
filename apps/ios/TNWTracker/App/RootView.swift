import SwiftUI
import TNWTrackerKit

struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = appEnv.router
        NavigationStack(path: $router.path) {
            HomeView(
                sessionRepository: appEnv.sessionRepository,
                routineRepository: appEnv.routineRepository
            )
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .fullScreenCover(item: $router.presentedActiveWorkout) { presentation in
            // El summary cover se anida AQUÍ (no a nivel del padre): SwiftUI
            // solo activa el primer fullScreenCover en cadena, así que para
            // que el summary aparezca encima del active workout debe vivir
            // como modifier sobre el cover activo.
            ActiveWorkoutCover(sessionID: presentation.id)
                .fullScreenCover(item: $router.presentedWorkoutSummary) { summary in
                    WorkoutSummaryView(workoutId: summary.id)
                }
        }
        .onOpenURL { url in
            // REQ-ROUTE-03: el deep link tnwtracker://workout/active reabre el
            // active workout cover si hay un coordinator vivo (Live Activity →
            // tap → app foreground). El Router no accede al coordinator, así
            // que se intercepta aquí.
            if case .openActiveWorkout = DeepLinkParser.parse(url) {
                if let activeId = appEnv.activeCoordinator?.activeWorkoutId {
                    router.presentedActiveWorkout = ActiveWorkoutPresentation(id: activeId)
                }
                // Si no hay workout activo, no-op: el usuario aterriza en Home.
                return
            }
            router.handle(deepLink: url)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Drain pending intents when app foregrounds — catches up events
            // that arrived while the app was backgrounded / suspended.
            if newPhase == .active {
                Task {
                    await appEnv.drainIfActive()
                }
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
            SessionListView(routineRepository: appEnv.routineRepository)
        case .settings:
            SettingsView()
        }
    }
}

/// Contenedor del cover que crea el coordinator y arranca el workout
/// desde la rutina referida en `sessionID`. El `@State` propio evita el
/// race que sufría el patrón `@State` en el padre + `.onChange`.
private struct ActiveWorkoutCover: View {
    let sessionID: UUID
    @Environment(AppEnvironment.self) private var appEnv
    @State private var coordinator: ActiveWorkoutCoordinator?

    var body: some View {
        Group {
            if let coordinator {
                NavigationStack {
                    ActiveWorkoutView(coordinator: coordinator)
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task {
            guard coordinator == nil else { return }
            guard let c = appEnv.makeActiveWorkoutCoordinator() else {
                // Sin userId resuelto no se puede iniciar el workout: cerrar el cover.
                appEnv.router.presentedActiveWorkout = nil
                appEnv.activeCoordinator = nil
                return
            }
            coordinator = c
            appEnv.activeCoordinator = c
            // Arrancar el workout desde la rutina. Si la rutina no existe o el
            // start falla, cerramos el cover para volver al Home.
            do {
                try await c.start(routineId: sessionID)
            } catch {
                appEnv.router.presentedActiveWorkout = nil
                appEnv.activeCoordinator = nil
            }
        }
        .onDisappear {
            appEnv.activeCoordinator = nil
        }
    }
}
