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
    /// The account's store is stamped with `owner`, not the signed-in user
    /// (each account has its own store, so this should never happen): the sync
    /// never runs and nothing is deleted (S10).
    case storeNotOwned(owner: UUID?)
}

/// Runs `TrainingSyncEngine.sync()` for the signed-in user on their own store
/// when something asks for it: a sign-in, a finished workout, the app coming to
/// the foreground, the network coming back (S3, S12). Each account's store has
/// its own scheduler (S10).
///
/// - Signing in claims the store for the user before anything else, so the
///   user's writes are their own data from the first one. A store stamped with
///   another user is not claimed and never syncs.
/// - `requestSync()` never waits for the sync and never throws: callers such as
///   finishing a workout carry on at once.
/// - Never two syncs at once: a request made while one runs makes exactly one
///   more run after it, however many requests arrive, so the changes made
///   during a sync are sent too.
/// - Signed out, a request does nothing; a run already going is stopped, and the
///   sign-out waits until it has. Signing in again stops the running engine
///   first: the new one runs only once the old run has ended, and the old one
///   writes nothing more to the store.
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

    /// Claims the store for `userId` and starts a sync. A store stamped with
    /// another user is left as it is and never syncs; one that cannot be read is
    /// treated the same way, as its owner is unknown.
    public func signIn(userId: UUID) {
        stop()
        do {
            switch try store.ownership.claim(userId: userId, at: now()) {
            case .claimed, .owned:
                engine = TrainingSyncEngine(store: store, remote: remote, userId: userId)
                status = .idle
                requestSync()
            case let .mismatch(ownerId):
                refuse(owner: ownerId)
            }
        } catch {
            let kind = Self.category(of: error)
            logger.error("Sync: claiming the store failed (\(kind, privacy: .public)): \(error, privacy: .private)")
            refuse(owner: nil)
        }
    }

    /// Stops syncing for the user who signed out, and returns once a sync that
    /// was running has stopped: from then on nothing reads or writes the store
    /// for the sync, nor talks to the server. The store keeps its data and owner.
    public func signOut() async {
        stop()
        await waitUntilIdle()
    }

    /// Stops syncing at once, without waiting: the running engine sends and
    /// writes nothing more (it checks before every request and store write, on
    /// the main actor), so the store can be reset right after this returns.
    public func stop() {
        let engine = engine
        self.engine = nil
        runAgain = false
        status = .signedOut
        engine?.stop()
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
            let kind = category(of: error)
            logger.error("Sync failed (\(kind, privacy: .public)); kept for the next try: \(error, privacy: .private)")
            return .failed
        }
    }

    /// A coarse kind of error, safe to log in public: no row, id or message.
    private static func category(of error: any Error) -> String {
        switch error {
        case is URLError: "network"
        case is CancellationError: "stopped"
        case is RemoteSessionError: "session"
        case is RemoteServerError: "server"
        case is RemoteStoreError: "refused"
        case is TrainingSyncError: "account"
        default: "other"
        }
    }

    private func refuse(owner: UUID?) {
        logger.error("Sync: the account's store is stamped with another user; it is not synced")
        status = .storeNotOwned(owner: owner)
    }
}
