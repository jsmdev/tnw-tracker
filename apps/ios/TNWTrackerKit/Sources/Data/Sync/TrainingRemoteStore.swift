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
    ///    reaches rows that are still in this session on the server. A removed
    ///    entry that still holds a set the aggregate does not list (one an
    ///    importer added after the device's last pull) is kept, so that set is
    ///    not lost: it is written again unchanged, with its sets, so the next
    ///    pull brings it back to the device;
    /// 2. upsert the session, then its entries, then their sets (parents first,
    ///    for the composite foreign keys and the entry `completed_at` check).
    ///
    /// A failure part way leaves a prefix of those writes on the server: a
    /// valid but incomplete session that the next push completes. The caller
    /// marks the aggregate synced only after this returns.
    func pushSession(_ aggregate: RemoteSessionAggregate) async throws

    /// Upserts rows of one table by `id` (by `RemoteTable.conflictTarget`),
    /// every column the client owns included, in one statement. For tables
    /// pushed on their own: user exercises with their muscle groups, routines
    /// with their items, exercise settings.
    func upsert<Row: RemoteRow>(_ rows: [Row]) async throws

    /// Deletes, in one statement, the rows of a child table (muscle groups,
    /// routine items: `RemoteTable.parentColumn`) of `parentId` whose ids are
    /// not in `keeping`: the rows the device no longer lists for the exercise or
    /// routine it pushes. Each leaves a tombstone, so other devices drop them
    /// too. Rows already gone are passed over, so sending it again is harmless.
    func deleteChildren(_ table: RemoteTable, of parentId: UUID, keeping ids: [UUID]) async throws

    /// Deletes the rows of `table` with these ids, in one statement: sessions,
    /// routines and exercises deleted on the device. Ids the server does not
    /// hold are passed over, so sending the same delete again is harmless.
    /// Deleting a session deletes its entries and sets; the server records a
    /// tombstone of every row it deletes. A row other rows still use (an
    /// exercise in a session) is refused as `RemoteStoreError.rejected`.
    func delete(_ table: RemoteTable, ids: [UUID]) async throws

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

/// Errors a `TrainingRemoteStore` reports about the data it was given. Any
/// other error (no network, a timeout, an expired session, a server fault)
/// says nothing about the data: the same write may succeed later.
public enum RemoteStoreError: Error, Equatable, Sendable {
    /// The aggregate is inconsistent; nothing was written.
    case invalidAggregate(String)
    /// The server refused the rows: a constraint or validation rule failed
    /// (Postgres error classes 22 and 23, `code` is the SQLSTATE). Sending the
    /// same rows again fails the same way.
    case rejected(code: String, message: String)
}

/// A remote store of one account refused to send a request: the client is not
/// signed in as that account, because another one signed in on the device or
/// nobody is (S10). Nothing was sent; the sync stops and keeps every change.
public enum RemoteSessionError: Error, Equatable, Sendable {
    case notSignedInAsAccount
}
