import Foundation
import Observation
import os.log
import TNWTrackerKit

private let drainLogger = Logger(subsystem: "com.tnwtracker", category: "drain")

/// The environment of the signed-in account (S10): its own store, the
/// repositories and sync built on it, and the screens' state. `AppAccounts`
/// creates one when the account signs in and drops it when it signs out, so
/// nothing of one account is left for the next to read or write.
@Observable
@MainActor
public final class AppEnvironment {
    /// Routing
    public let router = Router()

    /// The signed-in account.
    public let userId: UUID

    // Repositories, on the account's store
    public let exerciseRepository: any ExerciseRepositoryProtocol
    public let routineRepository: any RoutineRepositoryProtocol
    public let sessionRepository: any SessionRepositoryProtocol
    public let exerciseSettingRepository: any ExerciseSettingRepositoryProtocol

    /// Sync (#135): claims the store at sign-in and runs the sync on its triggers.
    public let syncScheduler: SyncScheduler

    /// Live Activity, shared by every account of the app.
    public let liveActivity: LiveActivityController

    let store: TrainingStore
    private let intentInbox: IntentInbox

    /// The active workout coordinator — set by ActiveWorkoutCover when a workout starts.
    public var activeCoordinator: (any DrainCoordinatorProtocol)?

    init(
        userId: UUID,
        store: TrainingStore,
        remote: any TrainingRemoteStore,
        intentInbox: IntentInbox,
        liveActivity: LiveActivityController
    ) {
        self.userId = userId
        self.store = store
        self.intentInbox = intentInbox
        self.liveActivity = liveActivity
        syncScheduler = SyncScheduler(store: store, remote: remote)
        exerciseRepository = store.exercises
        routineRepository = store.routines
        sessionRepository = store.sessions
        exerciseSettingRepository = store.exerciseSettings
    }

    /// The account signed out: the workout in progress stays where it is in this
    /// account's store, its timers stop, and the sync stops. Returns once a sync
    /// that was running has stopped. The screens' state goes with this environment.
    func close() async {
        await activeCoordinator?.abandon()
        activeCoordinator = nil
        await syncScheduler.signOut()
    }

    /// The next routine's name, for the widget.
    func nextRoutineName() -> String? {
        NextSessionQuery(container: store.container).nextSessionName()
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
                inbox: intentInbox,
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

    /// Factory para el coordinator del workout activo, sobre el store de la cuenta.
    public func makeActiveWorkoutCoordinator() -> ActiveWorkoutCoordinator {
        ActiveWorkoutCoordinator(
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
        /// Replaces the local training data with the invented sample data. The
        /// reset forgets the owner, so the store is claimed again for the
        /// signed-in user; the sample data stays on the device (S9). A sync
        /// running now is stopped first, so it writes no row nor cursor it read
        /// before into the reset store.
        func replaceWithSampleData() throws {
            syncScheduler.stop()
            defer { syncScheduler.signIn(userId: userId) }
            try SampleTrainingData.replaceAll(in: store)
        }

        /// The user the account's store is stamped with, for tests.
        func storeOwner() -> UUID? {
            try? store.ownership.owner()
        }
    }
#endif
