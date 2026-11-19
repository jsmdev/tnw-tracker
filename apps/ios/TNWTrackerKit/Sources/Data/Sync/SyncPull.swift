import Foundation

// What the pull half of the sync reports, and the conflict rule it applies.
// Rules in docs/database-schema.md, "Sync".

/// Which version of an aggregate held on both sides the pull kept (S13).
public enum SyncConflictRule: Equatable, Sendable {
    /// The aggregate had no local change waiting: the server's values were applied.
    case serverApplied
    /// The aggregate has a local change waiting to be pushed: its user-edited
    /// fields kept the device's values, which the next push sends. Imported
    /// rows were still merged in.
    case localKept

    /// The conflict rule (S13). An assumption until the owner confirms it: the
    /// device's pending change wins over the server, field by field for the
    /// fields a user edits; imported data always merges. Changing the rule
    /// means changing only this function.
    static func rule(localPending: Bool) -> Self {
        localPending ? .localKept : .serverApplied
    }
}

/// Why a pulled row was not applied. It is not lost: rows the cursor has not
/// passed are read again by the next pull.
public enum SyncPullSkipReason: Equatable, Sendable {
    /// It names a row the device does not hold (its session, entry, exercise or
    /// routine). The table's cursor stays before it, so the next pull reads it again.
    case missingParent
    /// The device deleted it and the deletion is still waiting to reach the server (T5).
    case deletedOnDevice
    /// It breaks a rule of the format; it is passed over.
    case invalid(String)
    /// It cannot be placed without losing data on one side, for example a second
    /// `done` entry of the same exercise in a session the device already sent.
    case conflict(String)
}

/// What one pull did.
public struct SyncPullReport: Equatable, Sendable {
    public struct Resolution: Equatable, Sendable {
        public var aggregate: SyncAggregateRef
        public var rule: SyncConflictRule
    }

    /// A local row that took the id the server holds the same external ref under,
    /// so its next push updates that row instead of colliding with it (23505).
    public struct Adoption: Equatable, Sendable {
        public var table: RemoteTable
        public var localId: UUID
        public var serverId: UUID
    }

    public struct Skip: Equatable, Sendable {
        public var table: RemoteTable
        public var id: UUID
        public var reason: SyncPullSkipReason
    }

    /// Rows read per table, the overlap re-read included.
    public var read: [RemoteTable: Int] = [:]
    /// Aggregates the device did not hold, created from the server.
    public var created: [SyncAggregateRef] = []
    /// Aggregates the device already held, with the rule that decided them, in apply order.
    public var resolved: [Resolution] = []
    public var adopted: [Adoption] = []
    public var skipped: [Skip] = []
    /// Sessions the pull changed into something the server does not hold (a
    /// reconciliation the merge decided, server values merged next to a value the
    /// device keeps), so they are pending for the next push.
    public var changedLocally: [UUID] = []

    public init() {}

    mutating func resolve(_ aggregate: SyncAggregateRef, localPending: Bool) -> SyncConflictRule {
        let rule = SyncConflictRule.rule(localPending: localPending)
        if !resolved.contains(where: { $0.aggregate == aggregate }) {
            resolved.append(.init(aggregate: aggregate, rule: rule))
        }
        return rule
    }

    mutating func skip(_ table: RemoteTable, _ id: UUID, _ reason: SyncPullSkipReason) {
        skipped.append(.init(table: table, id: id, reason: reason))
    }
}

/// What `TrainingSyncEngine.fullSync()` did.
public struct SyncReport: Equatable, Sendable {
    public var push: SyncPushReport
    public var pull: SyncPullReport
}

extension RemoteCursor {
    /// The id below every other, so a cursor at it includes every row of its `updated_at`.
    static let lowestId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// A cursor `seconds` before this one, to read again the rows a transaction
    /// that committed late may have written behind it. `nil` when the server's
    /// `updated_at` text cannot be read, so the caller keeps the exact cursor.
    func rewound(by seconds: TimeInterval) -> RemoteCursor? {
        guard let date = Self.date(from: updatedAt) else { return nil }
        // Whole seconds, rounded down, so the bound is never later than intended.
        let bound = (date.addingTimeInterval(-seconds).timeIntervalSince1970).rounded(.down)
        let text = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: bound)).dropLast() + "+00:00"
        return RemoteCursor(updatedAt: String(text), id: Self.lowestId)
    }

    /// Reads `2026-11-19T10:00:00.123456+00:00` (fraction and offset as Postgres writes them).
    static func date(from text: String) -> Date? {
        guard let match = text.wholeMatch(of: /(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:?\d{2})/)
        else { return nil }
        let offset = match.3 == "Z" ? "Z" : String(match.3)
        guard let whole = ISO8601DateFormatter().date(from: String(match.1) + offset) else { return nil }
        let fraction = match.2.flatMap { Double("0" + $0) } ?? 0
        return whole.addingTimeInterval(fraction)
    }
}
