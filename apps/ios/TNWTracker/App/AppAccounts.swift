import Foundation
import notify
import Observation
import os.log
import Supabase
import TNWTrackerKit
import WidgetKit

private let logger = Logger(subsystem: "com.tnwtracker", category: "auth")
private let drainLogger = Logger(subsystem: "com.tnwtracker", category: "drain")

/// The accounts of the app (S10): each signs in on its own local store, so
/// whoever signs in on the device sees only their own data, and it syncs to
/// every device they sign in on.
///
/// - Signing in opens the account's store (creating it, or reopening it as it
///   was left) and claims it before the training screens show; the first sync
///   fills a new one from the server.
/// - Signing out, or another account signing in, first closes the account: the
///   screens go at once, the workout in progress stays in its store, and its
///   sync stops; the next account opens only once that sync has stopped. Then
///   nothing keeps the previous store open.
/// - Signed out, no store of any account is open: the app shows the login.
@Observable
@MainActor
public final class AppAccounts {
    /// The signed-in account; nil while signed out.
    public private(set) var current: AppEnvironment?
    /// False until the auth service first answers whether a session was saved:
    /// until then nobody is signed in yet, but the login must not show (it would
    /// flash before the saved session opens its account).
    public private(set) var isSessionResolved = false

    public let authRepository: any AuthRepositoryProtocol
    /// Connectivity (NWPathMonitor wrapper): the network coming back syncs (S3).
    public let networkMonitor: any NetworkMonitoring

    private let liveActivity: LiveActivityController
    private let openStore: @MainActor (UUID) throws -> (store: TrainingStore, isNew: Bool)
    private let makeRemote: @MainActor (UUID) -> any TrainingRemoteStore
    /// The account's exercise media, in its own folder (#137).
    private let openMedia: @MainActor (UUID) throws -> ExerciseMediaLibrary
    private let intentInbox: IntentInbox
    private let widget: NextRoutineSnapshot?
    /// Debug builds: a new store gets the invented sample data before it is claimed.
    private let loadsSampleData: Bool
    /// False in UI tests, which never sync.
    private let syncs: Bool
    /// Emptied at every sign-out: responses an earlier build kept there.
    private let urlCache: URLCache
    /// The close of the previous account, which the next one waits for.
    private var closing: Task<Void, Never>?

    @ObservationIgnored private var authListenerTask: Task<Void, Never>?
    /// BSD notify token — used to cancel the Darwin registration in deinit.
    @ObservationIgnored private var darwinNotifyToken: Int32 = NOTIFY_TOKEN_INVALID

    public var isAuthenticated: Bool {
        current != nil
    }

    init(
        authRepository: any AuthRepositoryProtocol,
        networkMonitor: any NetworkMonitoring,
        liveActivity: LiveActivityController,
        openStore: @escaping @MainActor (UUID) throws -> (store: TrainingStore, isNew: Bool),
        makeRemote: @escaping @MainActor (UUID) -> any TrainingRemoteStore,
        openMedia: @escaping @MainActor (UUID) throws -> ExerciseMediaLibrary,
        intentInbox: IntentInbox,
        widget: NextRoutineSnapshot?,
        loadsSampleData: Bool,
        syncs: Bool = true,
        urlCache: URLCache = .shared
    ) {
        self.authRepository = authRepository
        self.networkMonitor = networkMonitor
        self.liveActivity = liveActivity
        self.openStore = openStore
        self.makeRemote = makeRemote
        self.openMedia = openMedia
        self.intentInbox = intentInbox
        self.widget = widget
        self.loadsSampleData = loadsSampleData
        self.syncs = syncs
        self.urlCache = urlCache
        networkMonitor.onReconnect = { [weak self] in
            self?.current?.syncScheduler.requestSync()
        }
    }

    // MARK: - Bootstrap (production)

    public static func bootstrap() throws -> AppAccounts {
        let supabase = SupabaseClientProvider.shared.client
        let stores = try AccountStores.onDevice()
        return try AppAccounts(
            authRepository: AuthRepository(supabase: supabase),
            networkMonitor: NetworkMonitor(),
            liveActivity: LiveActivityController(),
            openStore: { try stores.open(for: $0) },
            makeRemote: { SupabaseTrainingRemoteStore(client: supabase, userId: $0) },
            openMedia: { userId in
                try ExerciseMediaLibrary(store: stores.mediaStore(
                    for: userId, source: SupabaseExerciseMediaSource(client: supabase, userId: userId)
                ))
            },
            intentInbox: IntentInbox(container: ModelContainerFactory.makeIntentMailboxContainer()),
            widget: .shared(),
            loadsSampleData: true
        )
    }

    deinit {
        // `AppAccounts` es `@MainActor` — deinit corre en el main actor.
        MainActor.assumeIsolated {
            authListenerTask?.cancel()
            if darwinNotifyToken != NOTIFY_TOKEN_INVALID {
                notify_cancel(darwinNotifyToken)
            }
        }
    }

    // MARK: - Auth

    public func startAuthListener() {
        // Cancelar listener previo (idempotente — soporta re-runs / re-auth)
        authListenerTask?.cancel()

        // Capturar el stream ANTES del Task para no retener `self` durante la espera.
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

    /// Internal for tests, which drive it without the auth stream. The listener
    /// awaits each change before the next, so a sign-in waits for the close of
    /// the account before it.
    func handle(_ change: AuthStateChange) async {
        switch change.event {
        // `.signedIn` (login fresco) e `.initialSession` (restauración al arrancar)
        // traen el userId en el propio evento: re-consultar `auth.session` desde
        // aquí devuelve nil por reentrancy del actor de auth.
        case .signedIn, .initialSession:
            // After the account opens (or closes): the splash gives way to the final screen.
            defer { isSessionResolved = true }
            guard let userId = change.userId else {
                // No session (one that expired while the app was closed): clear what an account left.
                await closeCurrent()
                logger.info("Auth: \(String(describing: change.event)) sin sesión")
                return
            }
            if let current, current.userId == userId {
                current.syncScheduler.requestSync()
                return
            }
            await closeCurrent()
            open(userId)
            logger.info("Auth: \(String(describing: change.event)) — cuenta abierta")
        case .signedOut:
            await closeCurrent()
            isSessionResolved = true
            logger.info("Auth: signedOut")
        default:
            break
        }
    }

    /// The user signs out (Settings): the session ends with the auth service and
    /// the account closes, its data staying in its store for its next sign-in.
    /// The account closes even when the auth service cannot be reached (offline):
    /// nobody is left signed in with no way out. The auth client forgets the
    /// session on the device before it calls the service, and reports the
    /// sign-out to the listener, which may close the account first; a logout
    /// answer arriving after another account signed in closes nothing of it.
    public func signOut() async {
        let account = current
        do {
            try await authRepository.signOut()
        } catch {
            logger.error("Auth: signOut not confirmed by the auth service: \(error, privacy: .private)")
        }
        if let account, current === account {
            await closeCurrent()
        }
    }

    /// Opens the account's store and claims it before the screens can write to it.
    private func open(_ userId: UUID) {
        let opened: (store: TrainingStore, isNew: Bool)
        let media: ExerciseMediaLibrary
        do {
            opened = try openStore(userId)
            // After the store: its folder exists and is protected before the media folder goes in it.
            media = try openMedia(userId)
        } catch {
            logger.error("Auth: the account's store could not be opened: \(error, privacy: .private)")
            return
        }
        #if DEBUG
            if opened.isNew, loadsSampleData {
                // Before the claim: data written while a store has no owner is never synced (S9).
                do {
                    try SampleTrainingData.loadIfEmpty(into: opened.store)
                } catch {
                    logger.error("Sample data not loaded: \(error, privacy: .public)")
                }
            }
        #endif
        let account = AppEnvironment(
            userId: userId,
            store: opened.store,
            remote: makeRemote(userId),
            intentInbox: intentInbox,
            liveActivity: liveActivity,
            exerciseMedia: media
        )
        if syncs { account.syncScheduler.signIn(userId: userId) }
        current = account
        publishWidget()
    }

    /// Closes the signed-in account, if any, and clears what an account leaves
    /// on the device outside its store, even one from an earlier launch: the
    /// widget's routine, the lock-screen intents, Live Activities, the URL
    /// cache and the account's decoded exercise images (its media files stay in
    /// its own folder, like its store). Waits for any close still running.
    private func closeCurrent() async {
        let account = current
        current = nil
        publishWidget()
        let previous = closing
        let inbox = intentInbox
        let urlCache = urlCache
        closing = Task {
            await previous?.value
            await account?.close()
            account?.exerciseMedia.clearMemory()
            do {
                try inbox.removeAll()
            } catch {
                drainLogger.error("Intent mailbox not cleared: \(error, privacy: .public)")
            }
            await LiveActivityController.endAll()
            urlCache.removeAllCachedResponses()
        }
        await closing?.value
    }

    // MARK: - Widget

    /// The app went to the background: the widget shows what the account has now.
    public func sceneDidEnterBackground() {
        publishWidget()
    }

    /// The widget shows the signed-in account's next routine, and nothing while signed out.
    private func publishWidget() {
        guard let widget else { return }
        widget.publish(current?.nextRoutineName())
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Darwin Notification Observer

    /// Registers a Darwin notification observer for `com.tnwtracker.workout.intent`.
    /// Uses `notify_register_dispatch` — the idiomatic BSD notify API on Darwin.
    /// Must be called once at app startup. Cleaned up in deinit.
    public func startIntentObserver() {
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
                await self?.current?.drainIfActive()
            }
        }

        if status == NOTIFY_STATUS_OK {
            darwinNotifyToken = token
            drainLogger.info("IntentObserver registrado (notify_register_dispatch) — token \(token)")
        } else {
            drainLogger.error("notify_register_dispatch falló con status \(status)")
        }
    }
}

// MARK: - Testing Support

#if DEBUG
    extension AppAccounts {
        /// UUID fijo del usuario de UI testing.
        static let uiTestingUserId: UUID = {
            guard let uid = UUID(uuidString: "00000000-0000-0000-0000-000000000001") else {
                preconditionFailure("Invalid UUID literal for uiTestingUserId")
            }
            return uid
        }()

        /// UI tests: the fixed user signs in on an in-memory store with the
        /// invented sample data, without the auth service and without syncing.
        static func bootstrapForUITesting() async -> AppAccounts {
            let supabase = SupabaseClientProvider.shared.client
            let accounts: AppAccounts
            do {
                accounts = try AppAccounts(
                    // Never the auth service: a session a developer left on the simulator stays untouched.
                    authRepository: UITestingAuthRepository(),
                    networkMonitor: NetworkMonitor(),
                    // No Live Activities: one left by a test that stops mid-workout makes the
                    // system relaunch the app in the background without `--uitesting` (T11).
                    liveActivity: LiveActivityController(requestsActivities: false),
                    openStore: { _ in try (TrainingStore.inMemory(), true) },
                    makeRemote: { SupabaseTrainingRemoteStore(client: supabase, userId: $0) },
                    // Never the network: the sample image comes from an invented in-memory source.
                    openMedia: { _ in .sampleForUITesting() },
                    intentInbox: IntentInbox.inMemory(),
                    widget: nil,
                    loadsSampleData: true,
                    syncs: false
                )
            } catch {
                preconditionFailure("bootstrapForUITesting: \(error)")
            }
            await accounts.handle(AuthStateChange(event: .signedIn, userId: uiTestingUserId))
            return accounts
        }

        /// Accounts for unit tests: `remote` gives each account its server,
        /// `openStore` its store (in memory and new by default).
        static func makeForTesting(
            authRepository: any AuthRepositoryProtocol,
            remote: @escaping @MainActor (UUID) -> any TrainingRemoteStore,
            networkMonitor: any NetworkMonitoring = StubNetworkMonitor(isOnline: true),
            openStore: (@MainActor (UUID) throws -> (store: TrainingStore, isNew: Bool))? = nil,
            openMedia: (@MainActor (UUID) throws -> ExerciseMediaLibrary)? = nil,
            intentInbox: IntentInbox? = nil,
            widget: NextRoutineSnapshot? = nil,
            loadsSampleData: Bool = false,
            urlCache: URLCache = URLCache(memoryCapacity: 1 << 20, diskCapacity: 0)
        ) -> AppAccounts {
            do {
                return try AppAccounts(
                    authRepository: authRepository,
                    networkMonitor: networkMonitor,
                    liveActivity: LiveActivityController(requestsActivities: false),
                    openStore: openStore ?? { _ in try (TrainingStore.inMemory(), true) },
                    makeRemote: remote,
                    openMedia: openMedia ?? { _ in .offlineForTesting() },
                    intentInbox: intentInbox ?? IntentInbox.inMemory(),
                    widget: widget,
                    loadsSampleData: loadsSampleData,
                    urlCache: urlCache
                )
            } catch {
                preconditionFailure("makeForTesting: \(error)")
            }
        }

        /// UI tests' auth service: no network, no session; signing out ends nothing
        /// more than the app's account, signing in is refused.
        @MainActor
        final class UITestingAuthRepository: AuthRepositoryProtocol {
            func signIn(email _: String, password _: String) async throws -> Auth.Session {
                throw URLError(.userAuthenticationRequired)
            }

            func signOut() async throws {}

            func currentSession() async -> Auth.Session? {
                nil
            }

            func authStateChanges() -> AsyncStream<AuthStateChange> {
                AsyncStream { $0.finish() }
            }
        }

        /// Cancela el auth listener activo.
        /// Solo para tests que necesitan control determinista sobre el ciclo de vida del listener.
        func stopAuthListener() {
            authListenerTask?.cancel()
            authListenerTask = nil
        }
    }
#endif
