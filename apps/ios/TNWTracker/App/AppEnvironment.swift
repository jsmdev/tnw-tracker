import Foundation
import notify
import Observation
import os.log
import Supabase
import SwiftData
import TNWTrackerKit

private let logger = Logger(subsystem: "com.tnwtracker", category: "auth")
private let drainLogger = Logger(subsystem: "com.tnwtracker", category: "drain")

@Observable
@MainActor
public final class AppEnvironment {
    /// Routing
    public let router = Router()

    // Auth
    public var isAuthenticated: Bool = false
    public var currentUserId: UUID?

    // Repositories
    public let exerciseRepository: ExerciseRepository
    public let planRepository: PlanRepository
    public let routineRepository: RoutineRepository
    public let sessionRepository: SessionRepository
    public let workoutRepository: WorkoutRepository
    public let authRepository: any AuthRepositoryProtocol

    /// Sync
    public let syncEngine: SyncEngineImpl

    /// Live Activity
    public let liveActivity: LiveActivityController

    /// Connectivity (NWPathMonitor wrapper). Shared across services that gate
    /// remote calls on online status.
    public let networkMonitor: any NetworkMonitoring

    private let supabase: SupabaseClient
    private let modelContext: ModelContext

    // MARK: - Auth listener Task (cancelable)

    private var authListenerTask: Task<Void, Never>?

    // MARK: - Darwin notification observer (intent drain)

    /// The active workout coordinator — set by ActiveWorkoutCover when a workout starts.
    public var activeCoordinator: (any DrainCoordinatorProtocol)?

    /// BSD notify token — used to cancel the Darwin registration in deinit.
    private var darwinNotifyToken: Int32 = NOTIFY_TOKEN_INVALID

    // MARK: - Bootstrap (production)

    public static func bootstrap(modelContext: ModelContext) -> AppEnvironment {
        AppEnvironment(modelContext: modelContext)
    }

    private init(modelContext: ModelContext) {
        self.modelContext = modelContext
        let supabaseProvider = SupabaseClientProvider.shared
        let supabase = supabaseProvider.client
        self.supabase = supabase

        let monitor = NetworkMonitor()
        networkMonitor = monitor
        let engine = SyncEngineImpl(modelContext: modelContext, supabase: supabase, networkMonitor: monitor)
        syncEngine = engine
        liveActivity = LiveActivityController()

        exerciseRepository = ExerciseRepository(modelContext: modelContext, syncEngine: engine)
        planRepository = PlanRepository(modelContext: modelContext, syncEngine: engine)
        routineRepository = RoutineRepository(modelContext: modelContext, syncEngine: engine)
        sessionRepository = SessionRepository(modelContext: modelContext, syncEngine: engine)
        workoutRepository = WorkoutRepository(modelContext: modelContext, syncEngine: engine)
        authRepository = AuthRepository(supabase: supabase)
    }

    /// Init interno para inyección de dependencias (tests y variantes controladas).
    private init(
        modelContext: ModelContext,
        supabase: SupabaseClient,
        authRepository: any AuthRepositoryProtocol,
        networkMonitor: any NetworkMonitoring
    ) {
        self.modelContext = modelContext
        self.supabase = supabase
        self.networkMonitor = networkMonitor

        let engine = SyncEngineImpl(modelContext: modelContext, supabase: supabase, networkMonitor: networkMonitor)
        syncEngine = engine
        liveActivity = LiveActivityController()

        exerciseRepository = ExerciseRepository(modelContext: modelContext, syncEngine: engine)
        planRepository = PlanRepository(modelContext: modelContext, syncEngine: engine)
        routineRepository = RoutineRepository(modelContext: modelContext, syncEngine: engine)
        sessionRepository = SessionRepository(modelContext: modelContext, syncEngine: engine)
        workoutRepository = WorkoutRepository(modelContext: modelContext, syncEngine: engine)
        self.authRepository = authRepository
    }

    // MARK: - Deinit

    deinit {
        // `AppEnvironment` es `@MainActor` — deinit corre en el main actor.
        // `assumeIsolated` es seguro aquí porque el runtime garantiza que tipos
        // `@MainActor` se deallocan en el hilo del main actor.
        MainActor.assumeIsolated {
            authListenerTask?.cancel()
            if darwinNotifyToken != NOTIFY_TOKEN_INVALID {
                notify_cancel(darwinNotifyToken)
            }
        }
        logger.info("AppEnvironment deinit — authListenerTask cancelado, darwin observer desregistrado")
    }

    // MARK: - Auth Listener

    public func startAuthListener() {
        // Cancelar listener previo (idempotente — soporta re-runs / re-auth)
        authListenerTask?.cancel()

        // Capturar el stream ANTES del Task para no retener `self` durante la espera.
        // El stream es un value-type AsyncStream; quien lo retiene es el Task, no `self`.
        let stream = authRepository.authStateChanges()

        authListenerTask = Task { [weak self] in
            logger.info("Auth listener iniciado")
            for await change in stream {
                guard !Task.isCancelled else { break }
                await self?.handle(change)
            }
            logger.info("Auth listener terminado")
        }
    }

    private func handle(_ change: AuthStateChange) async {
        switch change.event {
        // `.signedIn` (login fresco) e `.initialSession` (restauración al arrancar)
        // traen el userId en el propio evento. Lo usamos directamente: re-consultar
        // `auth.session` desde aquí devuelve nil por reentrancy del actor de auth.
        case .signedIn, .initialSession:
            if let uid = change.userId {
                isAuthenticated = true
                currentUserId = uid
                logger.info("Auth: \(String(describing: change.event)) — userId resuelto")
                try? await syncEngine.fullSync()
            } else {
                logger.info("Auth: \(String(describing: change.event)) sin sesión")
            }
        case .signedOut:
            isAuthenticated = false
            currentUserId = nil
            logger.info("Auth: signedOut")
        default:
            break
        }
    }

    // MARK: - Darwin Notification Observer

    /// Registers a Darwin notification observer for `com.tnwtracker.workout.intent`.
    /// Uses `notify_register_dispatch` — the idiomatic BSD notify API on Darwin.
    /// Must be called once at app startup. Cleaned up in deinit.
    public func startIntentObserver() {
        // Cancel existing registration before re-registering (idempotent).
        if darwinNotifyToken != NOTIFY_TOKEN_INVALID {
            notify_cancel(darwinNotifyToken)
            darwinNotifyToken = NOTIFY_TOKEN_INVALID
        }

        var token: Int32 = NOTIFY_TOKEN_INVALID
        let status = notify_register_dispatch(
            "com.tnwtracker.workout.intent",
            &token,
            DispatchQueue.global(qos: .utility)
        ) { [weak self] _ in
            // Callback runs on the utility queue — hop to MainActor to call drain.
            Task { @MainActor [weak self] in
                await self?.drainIfActive()
            }
        }

        if status == NOTIFY_STATUS_OK {
            darwinNotifyToken = token
            drainLogger.info("IntentObserver registrado (notify_register_dispatch) — token \(token)")
        } else {
            drainLogger.error("notify_register_dispatch falló con status \(status)")
        }
    }

    /// Called when a Darwin notification arrives or the app foregrounds.
    public func drainIfActive() async {
        guard let coordinator = activeCoordinator,
              let workoutId = coordinator.activeWorkoutId
        else { return }

        do {
            try await AppEnvironment.drainPendingIntents(
                context: modelContext,
                coordinator: coordinator,
                coordinatorWorkoutId: workoutId
            )
        } catch {
            drainLogger.error("drainPendingIntents falló: \(error, privacy: .public)")
        }
    }

    /// Drains unconsumed WorkoutIntentEvent rows for the given workoutId,
    /// dispatching to the coordinator in FIFO (createdAt ascending) order.
    /// Marks consumedAt on each processed event. Safe to call multiple times (idempotent).
    @MainActor
    public static func drainPendingIntents(
        context: ModelContext,
        coordinator: any DrainCoordinatorProtocol,
        coordinatorWorkoutId: UUID
    ) async throws {
        var descriptor = FetchDescriptor<WorkoutIntentEvent>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.predicate = #Predicate { $0.consumedAt == nil }

        let events = try context.fetch(descriptor)
        drainLogger.debug("drainPendingIntents — \(events.count) unconsumed events")

        for event in events {
            guard event.workoutId == coordinatorWorkoutId else { continue }

            drainLogger.info(
                """
                Dispatching intent \(event.kind, privacy: .public) \
                for workout \(event.workoutId, privacy: .private)
                """
            )
            switch event.kind {
            case "skip":
                await coordinator.skipTimer()
            case "pause":
                try await coordinator.pause()
            case "resume":
                try await coordinator.resume()
            case "end":
                try await coordinator.finish()
            default:
                drainLogger.warning("Unknown intent kind: \(event.kind, privacy: .public)")
            }

            event.consumedAt = Date()
        }

        try context.save()
    }

    // MARK: - Factories

    /// Crea un `RestTimerService` vinculado al `LiveActivityController` compartido.
    public func makeRestTimerService() -> RestTimerService {
        RestTimerService(
            supabase: supabase,
            modelContext: modelContext,
            liveActivity: liveActivity,
            networkMonitor: networkMonitor
        )
    }

    /// Factory para el coordinator del workout activo.
    /// Devuelve `nil` si no hay userId resuelto — el callsite degrada cerrando el
    /// cover en vez de crashear (antes hacía `fatalError`).
    public func makeActiveWorkoutCoordinator() -> ActiveWorkoutCoordinator? {
        guard let uid = currentUserId else {
            logger.error("makeActiveWorkoutCoordinator sin userId — sesión no resuelta")
            return nil
        }
        return ActiveWorkoutCoordinator(
            userId: uid,
            workoutRepository: workoutRepository,
            syncEngine: syncEngine,
            timerService: makeRestTimerService(),
            liveActivity: liveActivity,
            supabase: supabase,
            modelContext: modelContext
        )
    }
}

// MARK: - Testing Support

#if DEBUG
    extension AppEnvironment {
        /// UUID estable para UI testing — usado por bootstrapForUITesting.
        /// Coincide con el userId implícito en el seed de SeedService.
        static let uiTestingUserId: UUID = {
            guard let uid = UUID(uuidString: "00000000-0000-0000-0000-000000000001") else {
                preconditionFailure("Invalid UUID literal for uiTestingUserId")
            }
            return uid
        }()

        /// Bootstrap para UI tests: retorna instancia pre-autenticada con userId fijo.
        /// NO arranca authListener, NO consulta currentSession.
        /// Skips: startAuthListener(), authRepository.currentSession().
        /// Keeps: startIntentObserver(), SeedService (llamados por TnwTrackerApp.task).
        static func bootstrapForUITesting(modelContext: ModelContext) -> AppEnvironment {
            let env = AppEnvironment(modelContext: modelContext)
            env.isAuthenticated = true
            env.currentUserId = uiTestingUserId
            return env
        }

        /// Crea una instancia mínima de `AppEnvironment` con un `authRepository` inyectable.
        /// Exclusivo para tests — usa un `ModelContainer` in-memory y un `SupabaseClient` stub.
        static func makeForTesting(authRepository: any AuthRepositoryProtocol) -> AppEnvironment {
            let container: ModelContainer
            do {
                container = try ModelContainerFactory.makeContainer(inMemory: true)
            } catch {
                fatalError("makeForTesting: no se pudo crear ModelContainer in-memory: \(error)")
            }
            guard let stubURL = URL(string: "https://test.supabase.co") else {
                preconditionFailure("Invalid stub Supabase URL")
            }
            let stubSupabase = SupabaseClient(
                supabaseURL: stubURL,
                supabaseKey: "test-anon-key"
            )
            return AppEnvironment(
                modelContext: ModelContext(container),
                supabase: stubSupabase,
                authRepository: authRepository,
                networkMonitor: StubNetworkMonitor(isOnline: true)
            )
        }

        /// Cancela el auth listener activo.
        /// Solo para tests que necesitan control determinista sobre el ciclo de vida del listener.
        func stopAuthListener() {
            authListenerTask?.cancel()
            authListenerTask = nil
        }
    }
#endif
