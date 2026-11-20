import Foundation

/// An aggregate the sync pushes: its kind and id.
public struct SyncAggregateRef: Hashable, Sendable {
    public var kind: SyncAggregateKind
    public var id: UUID

    public init(_ kind: SyncAggregateKind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}

/// Why a pending aggregate was not sent. It stays pending and is looked at again next time.
public enum SyncSkipReason: Equatable, Sendable {
    /// It uses a routine or exercise that never leaves the device (sample data,
    /// data written before any sign-in), which the server would refuse.
    case usesLocalOnlyData(SyncAggregateRef)
    /// It uses a routine or exercise the server does not hold yet, because its
    /// own push was refused or skipped.
    case waitsFor(SyncAggregateRef)
    /// A row of it lost a reference the server requires.
    case incomplete
}

/// What one push did. Aggregates not listed were not pending.
public struct SyncPushReport: Equatable, Sendable {
    public struct Skip: Equatable, Sendable {
        public var aggregate: SyncAggregateRef
        public var reason: SyncSkipReason
    }

    public struct Rejection: Equatable, Sendable {
        public var aggregate: SyncAggregateRef
        public var error: RemoteStoreError
    }

    /// Acknowledged by the server, in push order. One edited during its upload
    /// is listed here and is still pending.
    public var pushed: [SyncAggregateRef] = []
    public var skipped: [Skip] = []
    /// Refused by the server; recorded on the aggregate, which stays pending.
    public var rejected: [Rejection] = []

    public init() {}
}

public enum TrainingSyncError: Error, Equatable, Sendable {
    /// The local store does not belong to the signed-in user (it belongs to
    /// `owner`, or to nobody yet): nothing was sent and nothing changed (S10).
    case storeNotOwned(userId: UUID, owner: UUID?)
}

/// The sync between the local store and the server (#135): `fullSync()` pushes
/// local changes, then pulls the server's (`TrainingSyncEngine+Pull.swift`).
/// A push and a pull never run at the same time: each waits for the other.
///
/// Push rules (docs/database-schema.md, "Sync"):
/// - Only when the store's owner is the signed-in user (S10).
/// - Exercises, then routines, then sessions, so every row a session refers to
///   is on the server first. Catalogue exercises are already there.
/// - An aggregate is read, turned into rows and marked sent in one MainActor
///   stretch, then uploaded, then marked synced at the revision it was read
///   at: an edit during the upload keeps it pending (S7).
/// - The server refusing an aggregate is recorded on it and the push carries
///   on with the next; any other error stops the push and is thrown, leaving
///   everything not acknowledged pending (S3, S4).
/// - Every pending aggregate is tried at most once per push.
@MainActor
public final class TrainingSyncEngine: SyncEngine {
    let store: TrainingStore
    let remote: any TrainingRemoteStore
    let userId: UUID
    /// Rows asked for per pull request.
    let pageSize: Int
    /// How far before its cursor each table is read again (L5 item 5).
    let pullOverlap: TimeInterval
    private var pushing: Task<SyncPushReport, any Error>?
    private var pulling: Task<SyncPullReport, any Error>?

    /// - Parameters:
    ///   - pageSize: rows per pull request.
    ///   - pullOverlap: seconds of rows read again before each cursor, for rows a
    ///     transaction that committed late wrote behind it. Re-reading is harmless:
    ///     applying the same row twice changes nothing.
    public init(
        store: TrainingStore,
        remote: any TrainingRemoteStore,
        userId: UUID,
        pageSize: Int = 500,
        pullOverlap: TimeInterval = 5
    ) {
        self.store = store
        self.remote = remote
        self.userId = userId
        self.pageSize = pageSize
        self.pullOverlap = pullOverlap
    }

    public func fullSync() async throws {
        try await sync()
    }

    /// Pushes, then pulls: local changes reach the server before its state is
    /// applied, so the pull reads them back as echoes instead of conflicts.
    @discardableResult
    public func sync() async throws -> SyncReport {
        let push = try await push()
        let pull = try await pull()
        return SyncReport(push: push, pull: pull)
    }

    /// Pushes every pending aggregate once. A call made while a push is running
    /// waits for that push and gets its report, so nothing is sent twice.
    @discardableResult
    public func push() async throws -> SyncPushReport {
        if let pushing {
            return try await pushing.value
        }
        let pull = pulling
        let task = Task {
            _ = try? await pull?.value
            return try await self.pushPending()
        }
        pushing = task
        defer { pushing = nil }
        return try await task.value
    }

    /// Pulls what changed on the server since the last pull and applies it to
    /// the store. A call made while a pull is running gets that pull's report.
    @discardableResult
    public func pull() async throws -> SyncPullReport {
        if let pulling {
            return try await pulling.value
        }
        let push = pushing
        let task = Task {
            _ = try? await push?.value
            return try await self.pullChanges()
        }
        pulling = task
        defer { pulling = nil }
        return try await task.value
    }

    // MARK: - Push

    /// The state of one push.
    private final class PushRun {
        var report = SyncPushReport()
        var attempted: Set<SyncAggregateRef> = []
        /// Acknowledged by the server during this push.
        var acknowledged: Set<SyncAggregateRef> = []
    }

    /// A pending aggregate ready to send, or the reason it cannot go yet.
    enum Upload {
        case send(@Sendable (any TrainingRemoteStore) async throws -> Void)
        case skip(SyncSkipReason)
    }

    private func pushPending() async throws -> SyncPushReport {
        let owner = try store.ownership.owner()
        guard owner == userId else { throw TrainingSyncError.storeNotOwned(userId: userId, owner: owner) }
        let run = PushRun()
        for kind in [SyncAggregateKind.exercise, .routine, .session] {
            try await pushPending(kind, run: run)
        }
        return run.report
    }

    /// Pending aggregates are read again after every upload, so each one is
    /// turned into rows as it is at that moment. `attempted` sends each at most
    /// once per push: one edited during its upload waits for the next push.
    private func pushPending(_ kind: SyncAggregateKind, run: PushRun) async throws {
        while let pending = try store.syncState.pending(kind).first(where: {
            !run.attempted.contains(SyncAggregateRef(kind, id: $0.id))
        }) {
            let ref = SyncAggregateRef(kind, id: pending.id)
            run.attempted.insert(ref)
            switch try upload(for: pending, run: run) {
            case nil:
                continue
            case let .skip(reason):
                run.report.skipped.append(.init(aggregate: ref, reason: reason))
            case let .send(send):
                // Rows that may reach the server from now on leave a tombstone when deleted.
                try store.syncState.markSent(kind, id: ref.id, ifRevision: pending.revision)
                do {
                    try await send(remote)
                } catch let error as RemoteStoreError {
                    try store.syncState.markFailed(kind, id: ref.id, reason: String(describing: error))
                    run.report.rejected.append(.init(aggregate: ref, error: error))
                    continue
                }
                run.acknowledged.insert(ref)
                run.report.pushed.append(ref)
                try store.syncState.markSynced(kind, id: ref.id, ifRevision: pending.revision)
            }
        }
    }

    /// `nil` when the aggregate is gone, which cannot happen within the same
    /// MainActor stretch as the read of `pending`.
    private func upload(for pending: PendingSyncAggregate, run: PushRun) throws -> Upload? {
        let context = store.context
        let rows = PushRows(userId: userId) { run.acknowledged.contains($0) }
        switch pending.kind {
        case .exercise:
            return try context.fetchExercise(id: pending.id).map(rows.exercise)
        case .routine:
            return try context.fetchRoutine(id: pending.id).map(rows.routine)
        case .session:
            guard let model = try context.fetchSession(id: pending.id), let completedAt = model.completedAt else {
                return nil
            }
            return rows.session(model, completedAt: completedAt, pending: pending)
        case .exerciseSetting:
            // Pushed with the exercise settings sync (T6).
            return nil
        }
    }
}
