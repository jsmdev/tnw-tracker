import SwiftUI
import TNWTrackerKit

struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.scenePhase) private var scenePhase
    /// The workout left in progress, shown above the tab bar while its screen is closed.
    @State private var sessionInProgress: TrainingSession?

    var body: some View {
        @Bindable var router = appEnv.router
        TabView(selection: $router.selectedTab) {
            Tab("tab.home", systemImage: "house", value: AppTab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView(
                        sessionRepository: appEnv.sessionRepository,
                        routineRepository: appEnv.routineRepository
                    )
                    .navigationDestination(for: Route.self) { destination(for: $0) }
                }
                .exerciseSheet(in: .home)
            }
            .accessibilityIdentifier(AXID.Tabs.home)

            Tab("tab.history", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                NavigationStack(path: $router.historyPath) {
                    HistoryListView(
                        sessionRepository: appEnv.sessionRepository,
                        exerciseRepository: appEnv.exerciseRepository
                    )
                    .navigationDestination(for: Route.self) { destination(for: $0) }
                }
                .exerciseSheet(in: .history)
            }
            .accessibilityIdentifier(AXID.Tabs.history)

            Tab("tab.exercises", systemImage: "dumbbell", value: AppTab.exercises) {
                NavigationStack(path: $router.exercisesPath) {
                    ExerciseListView(exerciseRepository: appEnv.exerciseRepository)
                        .navigationDestination(for: Route.self) { destination(for: $0) }
                }
                .exerciseSheet(in: .exercises)
            }
            .accessibilityIdentifier(AXID.Tabs.exercises)
        }
        .tabViewStyle(.sidebarAdaptable)
        // The bar shrinks while scrolling down and comes back on scrolling up (#174 S3).
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(SessionAccessoryModifier(session: showsSessionAccessory ? sessionInProgress : nil) { session in
            router.presentedActiveWorkout = ActiveWorkoutPresentation(id: session.id)
        })
        .task { refreshSessionInProgress() }
        .onChange(of: router.presentedActiveWorkout == nil) { _, _ in
            refreshSessionInProgress()
        }
        .fullScreenCover(item: $router.presentedActiveWorkout) { presentation in
            // El summary cover se anida AQUÍ (no a nivel del padre): SwiftUI
            // solo activa el primer fullScreenCover en cadena, así que para
            // que el summary aparezca encima del active workout debe vivir
            // como modifier sobre el cover activo.
            ActiveWorkoutCover(
                sessionID: presentation.id,
                isFree: presentation.isFree,
                startingExerciseId: presentation.startingExerciseId
            )
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
            // Foreground: sync, and drain the intents that arrived while the
            // app was backgrounded / suspended.
            if newPhase == .active {
                appEnv.sceneDidBecomeActive()
                refreshSessionInProgress()
            }
        }
    }

    private var showsSessionAccessory: Bool {
        sessionInProgress != nil && appEnv.router.presentedActiveWorkout == nil
    }

    private func refreshSessionInProgress() {
        sessionInProgress = (try? appEnv.sessionRepository.activeSession()) ?? nil
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case let .sessionDetail(sessionID):
            SessionDetailView(sessionID: sessionID)
        case .exerciseDetail:
            // Never pushed: `Router.push` opens the exercise sheet instead.
            EmptyView()
        case let .workoutDetail(sessionID):
            WorkoutDetailView(
                sessionID: sessionID,
                sessions: appEnv.sessionRepository,
                exercises: appEnv.exerciseRepository
            )
        case .sessionHistory:
            SessionListView(routineRepository: appEnv.routineRepository)
        case .settings:
            SettingsView()
        }
    }
}

/// Contenedor del cover que crea el coordinator y arranca el workout
/// desde la rutina referida en `sessionID`, o sin rutina cuando `isFree`.
/// El `@State` propio evita el race que sufría el patrón `@State` en el padre + `.onChange`.
private struct ActiveWorkoutCover: View {
    let sessionID: UUID
    let isFree: Bool
    /// The exercise to add once the workout has started or resumed.
    let startingExerciseId: UUID?
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
            let c = appEnv.makeActiveWorkoutCoordinator()
            coordinator = c
            appEnv.activeCoordinator = c
            // Arrancar el workout desde la rutina. Si la rutina no existe o el
            // start falla, cerramos el cover para volver al Home.
            do {
                if isFree {
                    try await c.startAdHoc(name: String(localized: "free-session.name"))
                } else {
                    try await c.start(routineId: sessionID)
                }
                if let startingExerciseId {
                    c.addExercise(startingExerciseId)
                }
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

// MARK: - Exercise sheet

/// The exercise sheet (AC1-AC5), one at a time: `Router.presentedExercise`,
/// presented by the selected tab, as the catalogue presented it before.
/// «Entrenar este ejercicio» closes it first; the workout opens once it has
/// closed (AC3, AC4).
private struct ExerciseSheetModifier: ViewModifier {
    let tab: AppTab
    @Environment(AppEnvironment.self) private var appEnv

    func body(content: Content) -> some View {
        let router = appEnv.router
        content.sheet(
            item: Binding(
                get: { router.selectedTab == tab ? router.presentedExercise : nil },
                set: { router.presentedExercise = $0 }
            ),
            onDismiss: {
                let inProgress = (try? appEnv.sessionRepository.activeSession()) ?? nil
                router.exerciseSheetDidClose(sessionInProgressId: inProgress?.id)
            },
            content: { presentation in
                ExerciseSheetHost(exerciseID: presentation.id)
            }
        )
    }
}

private extension View {
    func exerciseSheet(in tab: AppTab) -> some View {
        modifier(ExerciseSheetModifier(tab: tab))
    }
}
