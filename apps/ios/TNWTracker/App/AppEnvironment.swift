import Foundation
import notify
import Observation
import os.log
import Supabase
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
    public let exerciseRepository: any ExerciseRepositoryProtocol
    public let routineRepository: any RoutineRepositoryProtocol
    public let sessionRepository: any SessionRepositoryProtocol
    public let exerciseSettingRepository: any ExerciseSettingRepositoryProtocol
    public let authRepository: any AuthRepositoryProtocol

    /// Sync (#135): claims the store at sign-in and runs the sync on its triggers.
    public let syncScheduler: SyncScheduler

    /// Live Activity
    public let liveActivity: LiveActivityController

    /// Connectivity (NWPathMonitor wrapper). Shared across services that gate
    /// remote calls on online status.
    public let networkMonitor: any NetworkMonitoring

    private let supabase: SupabaseClient
    private let store: TrainingStore

    // MARK: - Auth listener Task (cancelable)

    private var authListenerTask: Task<Void, Never>?

    // MARK: - Darwin notification observer (intent drain)

    /// The active workout coordinator — set by ActiveWorkoutCover when a workout starts.
    public var activeCoordinator: (any DrainCoordinatorProtocol)?

    /// BSD notify token — used to cancel the Darwin registration in deinit.
    private var darwinNotifyToken: Int32 = NOTIFY_TOKEN_INVALID

    // MARK: - Bootstrap (production)

    public static func bootstrap(store: TrainingStore) -> AppEnvironment {
        AppEnvironment(store: store)
    }

    private init(store: TrainingStore, liveActivity: LiveActivityController = LiveActivityController()) {
        self.store = store
        let supabaseProvider = SupabaseClientProvider.shared
        let supabase = supabaseProvider.client
        self.supabase = supabase

        networkMonitor = NetworkMonitor()
        syncScheduler = SyncScheduler(store: store, remote: SupabaseTrainingRemoteStore(client: supabase))
        self.liveActivity = liveActivity

        exerciseRepository = store.exercises
        routineRepository = store.routines
        sessionRepository = store.sessions
        exerciseSettingRepository = store.exerciseSettings
        authRepository = AuthRepository(supabase: supabase)
        observeReconnect()
    }

    /// Init interno para inyección de dependencias (tests y variantes controladas).
    private init(
        store: TrainingStore,
        supabase: SupabaseClient,
        authRepository: any AuthRepositoryProtocol,
        remote: any TrainingRemoteStore,
        networkMonitor: any NetworkMonitoring
    ) {
        self.store = store
        self.supabase = supabase
        self.networkMonitor = networkMonitor

        syncScheduler = SyncScheduler(store: store, remote: remote)
        liveActivity = LiveActivityController()

        exerciseRepository = store.exercises
        routineRepository = store.routines
        sessionRepository = store.sessions
        exerciseSettingRepository = store.exerciseSettings
        self.authRepository = authRepository
        observeReconnect()
    }

    /// The network coming back sends what was saved offline (S3).
    private func observeReconnect() {
        networkMonitor.onReconnect = { [weak self] in
            self?.syncScheduler.requestSync()
        }
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

    /// Internal for tests, which drive it without the auth stream.
    func handle(_ change: AuthStateChange) async {
        switch change.event {
        // `.signedIn` (login fresco) e `.initialSession` (restauración al arrancar)
        // traen el userId en el propio evento. Lo usamos directamente: re-consultar
        // `auth.session` desde aquí devuelve nil por reentrancy del actor de auth.
        case .signedIn, .initialSession:
            if let uid = change.userId {
                // Claim the store before the UI can write to it (S10): the app
                // shows the training screens only once `isAuthenticated` is set.
                syncScheduler.signIn(userId: uid)
                currentUserId = uid
                isAuthenticated = true
                logger.info("Auth: \(String(describing: change.event)) — userId resuelto")
            } else {
                logger.info("Auth: \(String(describing: change.event)) sin sesión")
            }
        case .signedOut:
            isAuthenticated = false
            currentUserId = nil
            syncScheduler.signOut()
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

    /// The app came to the foreground: sync (S12) and drain the intents that
    /// arrived while it was in the background.
    public func sceneDidBecomeActive() {
        syncScheduler.requestSync()
        Task { await drainIfActive() }
    }

    /// Called when a Darwin notification arrives or the app foregrounds.
    public func drainIfActive() async {
        guard let coordinator = activeCoordinator,
              let workoutId = coordinator.activeWorkoutId
        else { return }

        do {
            try await AppEnvironment.drainPendingIntents(
                inbox: store.intentInbox,
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
        inbox: IntentInbox,
        coordinator: any DrainCoordinatorProtocol,
        coordinatorWorkoutId: UUID
    ) async throws {
        try await inbox.drain(workoutId: coordinatorWorkoutId) { kind in
            drainLogger.info("Dispatching intent \(kind, privacy: .public)")
            switch kind {
            case "skip":
                await coordinator.skipTimer()
            case "pause":
                try await coordinator.pause()
            case "resume":
                try await coordinator.resume()
            case "end":
                try await coordinator.finish()
            default:
                drainLogger.warning("Unknown intent kind: \(kind, privacy: .public)")
            }
        }
    }

    // MARK: - Factories

    /// Crea un `RestTimerService` vinculado al `LiveActivityController` compartido.
    public func makeRestTimerService() -> RestTimerService {
        RestTimerService(liveActivity: liveActivity)
    }

    /// Factory para el coordinator del workout activo.
    /// Devuelve `nil` si no hay userId resuelto — el callsite degrada cerrando el
    /// cover en vez de crashear (antes hacía `fatalError`).
    public func makeActiveWorkoutCoordinator() -> ActiveWorkoutCoordinator? {
        guard currentUserId != nil else {
            logger.error("makeActiveWorkoutCoordinator sin userId — sesión no resuelta")
            return nil
        }
        return ActiveWorkoutCoordinator(
            sessions: sessionRepository,
            routines: routineRepository,
            exerciseSettings: exerciseSettingRepository,
            changeExerciseRest: { ChangeExerciseRestPreference(defaults: .standard).restSeconds },
            requestSync: { [weak syncScheduler] in syncScheduler?.requestSync() },
            timerService: makeRestTimerService(),
            liveActivity: liveActivity
        )
    }
}

// MARK: - Testing Support

#if DEBUG
    extension AppEnvironment {
        /// UUID estable para UI testing — usado por bootstrapForUITesting.
        /// UUID fijo del usuario de UI testing.
        static let uiTestingUserId: UUID = {
            guard let uid = UUID(uuidString: "00000000-0000-0000-0000-000000000001") else {
                preconditionFailure("Invalid UUID literal for uiTestingUserId")
            }
            return uid
        }()

        /// Bootstrap para UI tests: retorna instancia pre-autenticada con userId fijo.
        /// NO arranca authListener, NO consulta currentSession.
        /// Skips: startAuthListener(), authRepository.currentSession().
        /// Keeps: startIntentObserver(), sample data (llamados por TnwTrackerApp.task).
        static func bootstrapForUITesting(store: TrainingStore) -> AppEnvironment {
            // No Live Activities: one left by a test that stops mid-workout makes the
            // system relaunch the app in the background without `--uitesting` (T11).
            let env = AppEnvironment(store: store, liveActivity: LiveActivityController(requestsActivities: false))
            env.isAuthenticated = true
            env.currentUserId = uiTestingUserId
            return env
        }

        /// UI tests of a store that holds another account's data (S10): the store
        /// is claimed by another user with a routine of theirs, then the UI testing
        /// user signs in on it. The sync never runs against a store it does not own.
        func signInOnStoreOfAnotherUserForUITesting() {
            do {
                let other = UUID()
                _ = try store.ownership.claim(userId: other, at: Date())
                let exerciseId = SampleTrainingData.ExerciseID.gobletSquat
                try store.routines.save(Routine(
                    name: "Full Body C",
                    items: [RoutineItem(order: 1, exerciseId: exerciseId, targetSets: 3)]
                ))
            } catch {
                preconditionFailure("signInOnStoreOfAnotherUserForUITesting: \(error)")
            }
            syncScheduler.signIn(userId: AppEnvironment.uiTestingUserId)
        }

        /// Crea una instancia mínima de `AppEnvironment` con un `authRepository` inyectable.
        /// Exclusivo para tests — usa un `ModelContainer` in-memory y un `SupabaseClient` stub.
        /// `remote` is the server the sync talks to: tests pass an in-memory one.
        static func makeForTesting(
            authRepository: any AuthRepositoryProtocol,
            remote: any TrainingRemoteStore,
            networkMonitor: any NetworkMonitoring = StubNetworkMonitor(isOnline: true)
        ) -> AppEnvironment {
            let store: TrainingStore
            do {
                store = try TrainingStore(inMemory: true)
            } catch {
                fatalError("makeForTesting: no se pudo crear TrainingStore in-memory: \(error)")
            }
            guard let stubURL = URL(string: "https://test.supabase.co") else {
                preconditionFailure("Invalid stub Supabase URL")
            }
            let stubSupabase = SupabaseClient(
                supabaseURL: stubURL,
                supabaseKey: "test-anon-key"
            )
            return AppEnvironment(
                store: store,
                supabase: stubSupabase,
                authRepository: authRepository,
                remote: remote,
                networkMonitor: networkMonitor
            )
        }

        /// Loads the invented sample data into an empty store that nobody owns
        /// yet: a store a sign-in claimed holds that user's data, pulled or not.
        func loadSampleDataIfUnowned() {
            do {
                guard try store.ownership.owner() == nil else { return }
                try SampleTrainingData.loadIfEmpty(into: store)
            } catch {
                logger.error("Sample data not loaded: \(error, privacy: .public)")
            }
        }

        /// Replaces the local training data with the invented sample data. The
        /// reset forgets the owner, so the store is claimed again for the
        /// signed-in user; the sample data stays on the device (S9). Refused
        /// while the store holds another user's data.
        func replaceWithSampleData() throws {
            try SampleTrainingData.replaceAll(in: store)
            if let currentUserId {
                syncScheduler.signIn(userId: currentUserId)
            }
        }

        /// The user the local store belongs to, for tests.
        func storeOwner() -> UUID? {
            try? store.ownership.owner()
        }

        /// Cancela el auth listener activo.
        /// Solo para tests que necesitan control determinista sobre el ciclo de vida del listener.
        func stopAuthListener() {
            authListenerTask?.cancel()
            authListenerTask = nil
        }
    }
#endif
