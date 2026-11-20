import Foundation

/// The server side of the sync: the only boundary the sync engine talks to.
///
/// `SupabaseTrainingRemoteStore` implements it over PostgREST; tests use an
/// in-memory fake that keeps the same contract (TNWTrackerTests/Sync).
public protocol TrainingRemoteStore: Sendable {
    /// Stores one finished session with its entries and sets, all owned by
    /// `aggregate.session.userId`. Calling it again with the same aggregate is
    /// harmless, so a failed push is retried by pushing the aggregate again.
    ///
    /// The writes run in this order, each one valid on its own against the
    /// server's constraints and triggers:
    /// 1. delete `removedSetIds`, then `removedEntryIds` (an entry can only turn
    ///    `skipped` once the server holds none of its sets). A delete only
    ///    reaches rows that are still in this session on the server, and
    ///    deleting an entry deletes every set it holds there;
    /// 2. upsert the session, then its entries, then their sets (parents first,
    ///    for the composite foreign keys and the entry `completed_at` check).
    ///
    /// A failure part way leaves a prefix of those writes on the server: a
    /// valid but incomplete session that the next push completes. The caller
    /// marks the aggregate synced only after this returns.
    func pushSession(_ aggregate: RemoteSessionAggregate) async throws

    /// Upserts rows of one table by `id`, every column the client owns
    /// included. For tables pushed on their own (routines and user exercises,
    /// once their rows exist).
    func upsert<Row: RemoteRow>(_ rows: [Row]) async throws

    /// Rows of `Row.table` the signed-in user can read whose (`updated_at`, `id`)
    /// is after `cursor` (all rows when `nil`), in that order, at most `limit`.
    func pull<Row: RemoteRow>(_ type: Row.Type, after cursor: RemoteCursor?, limit: Int) async throws -> RemotePage<Row>
}

/// The unit the sync uploads: a finished session with all its entries and sets.
public struct RemoteSessionAggregate: Sendable, Equatable {
    public var session: RemoteSessionRow
    public var entries: [RemoteEntryRow]
    public var sets: [RemoteSetRow]
    /// Entries deleted on the device since the last successful push.
    public var removedEntryIds: [UUID]
    /// Sets deleted on the device since the last successful push.
    public var removedSetIds: [UUID]

    public init(
        session: RemoteSessionRow,
        entries: [RemoteEntryRow],
        sets: [RemoteSetRow],
        removedEntryIds: [UUID] = [],
        removedSetIds: [UUID] = []
    ) {
        self.session = session
        self.entries = entries
        self.sets = sets
        self.removedEntryIds = removedEntryIds
        self.removedSetIds = removedSetIds
    }

    /// Checks that every row sent belongs to this session and its owner. Runs
    /// before any write.
    public func validate() throws {
        let owner = session.userId
        let entryIds = Set(entries.map(\.id))
        if let entry = entries.first(where: { $0.sessionId != session.id || $0.userId != owner }) {
            throw RemoteStoreError.invalidAggregate("entry \(entry.id) is not part of session \(session.id)")
        }
        if let set = sets.first(where: { !entryIds.contains($0.entryId) || $0.userId != owner }) {
            throw RemoteStoreError.invalidAggregate("set \(set.id) is not part of session \(session.id)")
        }
        if !entryIds.isDisjoint(with: removedEntryIds) || !Set(sets.map(\.id)).isDisjoint(with: removedSetIds) {
            throw RemoteStoreError.invalidAggregate("a row cannot be both stored and removed")
        }
    }
}

public enum RemoteStoreError: Error, Equatable, Sendable {
    /// The aggregate is inconsistent; nothing was written.
    case invalidAggregate(String)
}
