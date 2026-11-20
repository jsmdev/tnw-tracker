import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.tnwtracker", category: "sync")

/// Where the sync of the signed-in user stands.
public enum SyncStatus: Equatable, Sendable {
    /// Nobody is signed in: nothing syncs.
    case signedOut
    /// Signed in and not syncing: the last sync finished, or none ran yet.
    case idle
    case syncing
    /// The last sync failed (no network, a timeout, a server fault). Nothing
    /// that was not acknowledged was marked synced; the next trigger retries (S4).
    case failed
    /// The store holds the data of `owner`, not the signed-in user's: the sync
    /// never runs and the user's writes are refused, so nothing of theirs reaches
    /// the owner's data or account. Nothing is deleted (S10).
    case storeNotOwned(owner: UUID?)
}

/// Runs `TrainingSyncEngine.sync()` for the signed-in user when something asks
/// for it: a sign-in, a finished workout, the app coming to the foreground, the
/// network coming back (S3, S12).
///
/// - Signing in claims the store for the user before anything else, so the
///   user's writes are their own data from the first one (S10). A store that
///   holds another user's data is not claimed: the sync stays off and the
///   user's writes are refused until that user signs out.
/// - `requestSync()` never waits for the sync and never throws: callers such as
///   finishing a workout carry on at once.
/// - Never two syncs at once: a request made while one runs makes exactly one
///   more run after it, however many requests arrive, so the changes made
///   during a sync are sent too.
/// - Signed out, a request does nothing; a run already going finishes, and no
///   further run follows it.
@MainActor
@Observable
public final class SyncScheduler {
    public private(set) var status: SyncStatus = .signedOut

    private let store: TrainingStore
    private let remote: any TrainingRemoteStore
    private let now: () -> Date
    /// The signed-in user's engine; nil while signed out or not the owner.
    private var engine: TrainingSyncEngine?
    private var running: Task<Void, Never>?
    private var runAgain = false

    public init(store: TrainingStore, remote: any TrainingRemoteStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.remote = remote
        self.now = now
    }

    /// Claims the store for `userId` and starts a sync. When the store holds
    /// another user's data, it is left as it is: no sync, and the user's writes
    /// are refused (`TrainingDataError.storeNotOwned`). A store that cannot be
    /// read is treated the same way, as its owner is unknown.
    public func signIn(userId: UUID) {
        engine = nil
        runAgain = false
        do {
            switch try store.ownership.claim(userId: userId, at: now()) {
            case .claimed, .owned:
                store.userWrites.setBlocked(false)
                engine = TrainingSyncEngine(store: store, remote: remote, userId: userId)
                status = .idle
                requestSync()
            case let .mismatch(ownerId):
                refuse(owner: ownerId)
            }
        } catch {
            logger.error("Sync: claiming the store failed: \(error, privacy: .public)")
            refuse(owner: nil)
        }
    }

    /// Stops syncing for the user who signed out. The store keeps its data and its owner.
    public func signOut() {
        // A run already going stops after this sync: it finds no engine.
        engine = nil
        store.userWrites.setBlocked(false)
        status = .signedOut
    }

    /// Asks for a sync and returns at once. Does nothing while signed out or
    /// while the store is not the user's.
    public func requestSync() {
        guard engine != nil else { return }
        guard running == nil else {
            runAgain = true
            return
        }
        status = .syncing
        running = Task { [weak self] in
            await self?.runUntilCaughtUp()
        }
    }

    /// Waits until no sync is running or due.
    public func waitUntilIdle() async {
        while let running {
            await running.value
        }
    }

    private func runUntilCaughtUp() async {
        defer { running = nil }
        repeat {
            runAgain = false
            guard let engine else { return }
            status = .syncing
            let outcome = await Self.run(engine)
            // After a sign-out or another sign-in during the run, the status is theirs.
            if engine === self.engine { status = outcome }
        } while runAgain
    }

    private static func run(_ engine: TrainingSyncEngine) async -> SyncStatus {
        do {
            try await engine.sync()
            return .idle
        } catch let TrainingSyncError.storeNotOwned(_, owner) {
            return .storeNotOwned(owner: owner)
        } catch {
            logger.error("Sync failed; kept for the next try: \(error, privacy: .public)")
            return .failed
        }
    }

    private func refuse(owner: UUID?) {
        store.userWrites.setBlocked(true)
        status = .storeNotOwned(owner: owner)
    }
}
