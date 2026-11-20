import Foundation

// What the device knows about the sync of its own data: who owns the store
// (S10), which aggregates changed since the server last acknowledged them (S7)
// and which rows were deleted locally (S11). No network code lives here.
//
// Rules the repositories keep, in the same save as the change itself:
// - Every command that changes user data raises the revision of the aggregate
//   it changed (a session with its entries and sets, a routine, an exercise,
//   an exercise setting).
// - An aggregate is syncable only when the store had an owner when it was
//   created, and an exercise only when it is not a catalogue exercise. Data
//   written before any sign-in (the debug sample data) stays on the device.
// - Deleting a row that may exist on the server leaves a tombstone; deleting a
//   row that never reached it leaves none.

/// An aggregate the sync uploads as a unit.
public enum SyncAggregateKind: String, Sendable, CaseIterable {
    /// A session with its entries and sets. Only completed sessions are pushed.
    case session
    case routine
    case exercise
    /// Keyed by its exercise id.
    case exerciseSetting
}

/// The kind of a row deleted on the device.
public enum SyncTombstoneKind: String, Sendable, CaseIterable {
    case session
    case entry
    case set
    case routine
    case exercise
}

/// An aggregate changed on the device since the server last acknowledged it.
public struct PendingSyncAggregate: Equatable, Sendable {
    public var kind: SyncAggregateKind
    public var id: UUID
    /// The change token: pass it back to `markSent` and `markSynced`.
    public var revision: Int
    /// Entries of this session deleted on the device since its last acknowledged push.
    public var removedEntryIds: [UUID]
    /// Sets of this session deleted on the device since its last acknowledged push.
    public var removedSetIds: [UUID]
    /// Pushes the server refused since the last acknowledged one.
    public var failureCount: Int
    /// Why the server refused the last push, if it did.
    public var lastError: String?

    public init(
        kind: SyncAggregateKind,
        id: UUID,
        revision: Int,
        removedEntryIds: [UUID] = [],
        removedSetIds: [UUID] = [],
        failureCount: Int = 0,
        lastError: String? = nil
    ) {
        self.kind = kind
        self.id = id
        self.revision = revision
        self.removedEntryIds = removedEntryIds
        self.removedSetIds = removedSetIds
        self.failureCount = failureCount
        self.lastError = lastError
    }
}

/// A session, routine or exercise deleted on the device that may exist on the server.
public struct SyncTombstone: Equatable, Sendable {
    public var kind: SyncTombstoneKind
    public var id: UUID
    public var revision: Int
    public var deletedAt: Date

    public init(kind: SyncTombstoneKind, id: UUID, revision: Int, deletedAt: Date) {
        self.kind = kind
        self.id = id
        self.revision = revision
        self.deletedAt = deletedAt
    }
}

/// The outcome of a sign-in against the store's owner stamp.
public enum StoreOwnership: Equatable, Sendable {
    /// The store now belongs to the user: it had no owner, or its owner had no user data in it.
    case claimed
    /// The store already belonged to the user.
    case owned
    /// The store holds user data of another user. Nothing changed and the sync must not run.
    case mismatch(ownerId: UUID)
}

/// The owner stamp of the local store (S10). It never deletes data.
@MainActor
public protocol StoreOwnershipProtocol: AnyObject {
    /// The user the store's user data belongs to, if any.
    func owner() throws -> UUID?
    /// Claims the store for `userId` when it has no owner, or when its owner has
    /// no syncable data or tombstone left in it. Reports `mismatch` otherwise.
    func claim(userId: UUID, at date: Date) throws -> StoreOwnership
}

/// Change tracking for the sync (S7) and the local tombstones (S11).
@MainActor
public protocol SyncStateRepositoryProtocol: AnyObject {
    /// Syncable aggregates of `kind` changed since their last acknowledged
    /// revision. Sessions in progress are left out until they are completed.
    /// Sessions come in completion order, the others by id; ties break by id.
    func pending(_ kind: SyncAggregateKind) throws -> [PendingSyncAggregate]

    /// Records that the aggregate, as it is at `revision`, is about to reach the
    /// server, so deleting any of its rows from now on leaves a tombstone. Call it
    /// before the upload: a failed push can still leave rows on the server.
    /// Returns `false`, changing nothing, when the aggregate changed since `revision`.
    @discardableResult
    func markSent(_ kind: SyncAggregateKind, id: UUID, ifRevision revision: Int) throws -> Bool

    /// Compare and clear: marks the aggregate synced at `revision`, forgets the
    /// entry and set tombstones that push carried and any recorded failure.
    /// Returns `false`, changing nothing, when the aggregate changed again during
    /// the upload, so it stays pending.
    @discardableResult
    func markSynced(_ kind: SyncAggregateKind, id: UUID, ifRevision revision: Int) throws -> Bool

    /// Records that the server refused the aggregate, with the reason. It stays
    /// pending and its data is untouched; the revision does not change. Returns
    /// `false` for an aggregate that is not stored or not syncable.
    @discardableResult
    func markFailed(_ kind: SyncAggregateKind, id: UUID, reason: String) throws -> Bool

    /// Sessions, routines and exercises deleted on the device that may exist on
    /// the server, oldest first.
    func tombstones() throws -> [SyncTombstone]

    /// Forgets a tombstone once the server applied it. Returns `false` when it is
    /// no longer stored as given.
    @discardableResult
    func clearTombstone(_ tombstone: SyncTombstone) throws -> Bool
}

public extension SyncStateRepositoryProtocol {
    /// Completed sessions ready to push, in completion order.
    func pendingSessions() throws -> [PendingSyncAggregate] {
        try pending(.session)
    }
}
