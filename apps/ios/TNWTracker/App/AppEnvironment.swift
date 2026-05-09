import Foundation
import Observation
import os.log
import Supabase
import SwiftData
import TNWTrackerKit

private let logger = Logger(subsystem: "com.tnwtracker", category: "auth")

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

    private let supabase: SupabaseClient
    private let modelContext: ModelContext

    // MARK: - Auth listener Task (cancelable)

    private var authListenerTask: Task<Void, Never>?

    // MARK: - Bootstrap (production)

    public static func bootstrap(modelContext: ModelContext) -> AppEnvironment {
        AppEnvironment(modelContext: modelContext)
    }

    private init(modelContext: ModelContext) {
        self.modelContext = modelContext
        let supabaseProvider = SupabaseClientProvider.shared
        let supabase = supabaseProvider.client
        self.supabase = supabase

        let engine = SyncEngineImpl(modelContext: modelContext, supabase: supabase)
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
        authRepository: any AuthRepositoryProtocol
    ) {
        self.modelContext = modelContext
        self.supabase = supabase

        let engine = SyncEngineImpl(modelContext: modelContext, supabase: supabase)
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
        }
        logger.info("AppEnvironment deinit — authListenerTask cancelado")
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
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self?.handle(authEvent: event)
            }
            logger.info("Auth listener terminado")
        }
    }

    private func handle(authEvent event: AuthChangeEvent) async {
        switch event {
        case .signedIn:
            isAuthenticated = true
            logger.info("Auth: signedIn")
            if let session = await authRepository.currentSession() {
                currentUserId = UUID(uuidString: session.user.id.uuidString)
            }
            try? await syncEngine.fullSync()
        case .signedOut:
            isAuthenticated = false
            currentUserId = nil
            logger.info("Auth: signedOut")
        default:
            break
        }
    }

    // MARK: - Factories

    /// Crea un `RestTimerService` vinculado al `LiveActivityController` compartido.
    public func makeRestTimerService() -> RestTimerService {
        RestTimerService(
            supabase: supabase,
            modelContext: modelContext,
            liveActivity: liveActivity
        )
    }

    /// Factory para el coordinator del workout activo.
    public func makeActiveWorkoutCoordinator() -> ActiveWorkoutCoordinator {
        guard let uid = currentUserId else {
            fatalError("makeActiveWorkoutCoordinator llamado sin userId — asegurar login previo")
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
        /// Crea una instancia mínima de `AppEnvironment` con un `authRepository` inyectable.
        /// Exclusivo para tests — usa un `ModelContainer` in-memory y un `SupabaseClient` stub.
        static func makeForTesting(authRepository: any AuthRepositoryProtocol) -> AppEnvironment {
            let container: ModelContainer
            do {
                container = try ModelContainerFactory.makeContainer(inMemory: true)
            } catch {
                fatalError("makeForTesting: no se pudo crear ModelContainer in-memory: \(error)")
            }
            let stubSupabase = SupabaseClient(
                supabaseURL: URL(string: "https://test.supabase.co")!,
                supabaseKey: "test-anon-key"
            )
            return AppEnvironment(
                modelContext: ModelContext(container),
                supabase: stubSupabase,
                authRepository: authRepository
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
