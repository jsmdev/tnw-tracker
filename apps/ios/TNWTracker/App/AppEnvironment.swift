import Foundation
import Observation
import Supabase
import SwiftData
import TNWTrackerKit

@Observable
@MainActor
public final class AppEnvironment {
    // Auth
    public var isAuthenticated: Bool = false
    public var currentUserId: UUID?

    // Repositories
    public let exerciseRepository: ExerciseRepository
    public let planRepository: PlanRepository
    public let routineRepository: RoutineRepository
    public let sessionRepository: SessionRepository
    public let workoutRepository: WorkoutRepository
    public let authRepository: AuthRepository

    /// Sync
    public let syncEngine: SyncEngineImpl

    /// Live Activity
    public let liveActivity: LiveActivityController

    private let supabase: SupabaseClient
    private let modelContext: ModelContext

    public static func bootstrap(modelContext: ModelContext) -> AppEnvironment {
        AppEnvironment(modelContext: modelContext)
    }

    private init(modelContext: ModelContext) {
        self.modelContext = modelContext
        let supabaseProvider = SupabaseClientProvider.shared
        supabase = supabaseProvider.client

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

    public func startAuthListener() {
        Task {
            for await event in authRepository.authStateChanges() {
                switch event {
                case .signedIn:
                    self.isAuthenticated = true
                    if let session = await authRepository.currentSession() {
                        self.currentUserId = UUID(uuidString: session.user.id.uuidString)
                    }
                    try? await syncEngine.fullSync()
                case .signedOut:
                    self.isAuthenticated = false
                    self.currentUserId = nil
                default:
                    break
                }
            }
        }
    }
}
