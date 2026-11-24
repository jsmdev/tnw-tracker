import Foundation
import SwiftData

/// Writes what the sync pulls into the store, outside the user commands: it
/// never raises a revision for what the server already holds (an echo), only
/// for a difference the device keeps, so that difference is pushed.
///
/// Rules (docs/database-schema.md, "Sync"):
/// - A row the device does not hold is created with the server's id, as the
///   server holds it: synced, never pending.
/// - A row the device holds follows the conflict rule of its aggregate
///   (`SyncConflictRule`); imported sets always merge through the import rules.
/// - A row the device deleted is not brought back (S11): its deletion goes up
///   with the next push. A row the server deleted goes, unless its aggregate has
///   a change waiting (`SwiftDataPullApplier+Tombstones.swift`).
/// - A row whose external ref the device holds under another id gives that
///   local row the server's id (adoption), so its push stops colliding (23505).
/// - Catalogue exercises are always the server's.
@MainActor
final class SwiftDataPullApplier {
    let context: ModelContext
    /// The context does not keep its container alive; the adapter does.
    private let container: ModelContainer
    /// For the import rules the pull shares with the importer.
    let sessions: SwiftDataSessionRepository

    init(context: ModelContext, sessions: SwiftDataSessionRepository) {
        self.context = context
        container = context.container
        self.sessions = sessions
    }

    /// Where the last pull of `table` stopped for `userId`.
    func cursor(_ table: RemoteTable, userId: UUID) throws -> RemoteCursor? {
        try cursorModel(table, userId: userId).map { RemoteCursor(updatedAt: $0.updatedAt, id: $0.rowId) }
    }

    /// Applies every row, parents first, and moves the cursors, in one save. On
    /// any error nothing is kept.
    func apply(_ batch: PulledBatch, userId: UUID) throws -> SyncPullReport {
        let run = PullRun(userId: userId, entries: batch.entries)
        do {
            // Deletions first: the feed was read before the rows, so a row read
            // after its tombstone was written again since.
            try applyTombstones(batch.tombstones, run)
            try applyTemplates(batch, run)
            run.stampServerLists()
            try applySessions(batch, run)
            try saveCursor(batch.exercises, run)
            try saveCursor(batch.muscleGroups, run)
            try saveCursor(batch.routines, run)
            try saveCursor(batch.routineItems, run)
            try saveCursor(batch.exerciseSettings, run)
            try saveCursor(batch.exerciseLinks, run)
            try saveCursor(batch.sessions, run)
            try saveCursor(batch.entries, run)
            try saveCursor(batch.sets, run)
            try saveCursor(batch.tombstones, run)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return run.report
    }

    // MARK: - Cursors

    /// The table's cursor moves to its last row read, or to the row before the
    /// first one held back for a missing parent, so that one is read again.
    private func saveCursor<Row: RemoteRow>(_ rows: [Row], _ run: PullRun) throws {
        guard !rows.isEmpty else { return }
        run.report.read[Row.table] = rows.count
        let held = run.held[Row.table] ?? []
        guard let last = rows.prefix(while: { !held.contains($0.id) }).last, let updatedAt = last.updatedAt else {
            return
        }
        let cursor = RemoteCursor(updatedAt: updatedAt, id: last.id)
        if let model = try cursorModel(Row.table, userId: run.userId) {
            model.updatedAt = cursor.updatedAt
            model.rowId = cursor.id
        } else {
            context.insert(SyncCursorModel(userId: run.userId, table: Row.table, cursor: cursor))
        }
    }

    private func cursorModel(_ table: RemoteTable, userId: UUID) throws -> SyncCursorModel? {
        let key = SyncCursorModel.key(userId: userId, table: table)
        var descriptor = FetchDescriptor<SyncCursorModel>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Lookups

    /// True when the device deleted the row and the deletion has not reached the server.
    func hasTombstone(_ kind: SyncTombstoneKind, _ id: UUID) throws -> Bool {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<SyncTombstoneModel>(
            predicate: #Predicate { $0.kindRaw == kindRaw && $0.rowId == id }
        )
        return try context.fetchCount(descriptor) > 0
    }
}

/// The state of one pull while it is applied.
@MainActor
final class PullRun {
    let userId: UUID
    let now = Date()
    var report = SyncPullReport()
    /// The session of every entry row read, for sets whose entry the device does not hold.
    let entrySessions: [UUID: UUID]
    /// Rows left for a missing parent, per table.
    var held: [RemoteTable: Set<UUID>] = [:]
    /// Entries whose sets changed, with the entries an imported set left for them (D8).
    var touchedEntries: [SessionEntryModel] = []
    var vacated: [(into: SessionEntryModel, from: SessionEntryModel)] = []
    private var created: Set<SyncAggregateRef> = []
    /// Rows this pull deleted from the device, by table. They are gone only at the save.
    private var deleted: [RemoteTable: Set<UUID>] = [:]
    /// Routine items this pull deleted on their own, which their exercise still lists until the save.
    var removedItems: Set<PersistentIdentifier> = []
    /// Whether each aggregate had a local change waiting when the pull first reached it.
    private var pending: [SyncAggregateRef: Bool] = [:]
    /// Whether each child list had changed on the device when the pull first reached it.
    private var childListsChanged: [SyncAggregateRef: Bool] = [:]
    /// Parents whose child list now is the server's, stamped synced before the save.
    private var serverLists: [SyncAggregateRef: any SyncChildListOwner] = [:]

    init(userId: UUID, entries: [RemoteEntryRow] = []) {
        self.userId = userId
        entrySessions = Dictionary(entries.map { ($0.id, $0.sessionId) }, uniquingKeysWith: { first, _ in first })
    }

    /// The conflict rule of an aggregate the device holds, for `change`, decided
    /// on its state when the pull first reaches it. An update is reported in
    /// `resolved`; the caller reports a deletion. An aggregate this pull
    /// created has no conflict.
    func rule(
        for aggregate: SyncAggregateRef,
        model: any SyncTrackedModel,
        change: SyncServerChange = .updated
    ) -> SyncConflictRule {
        if created.contains(aggregate) {
            return .serverApplied
        }
        let localPending = pending[aggregate] ?? (model.syncRevision > model.syncedRevision)
        pending[aggregate] = localPending
        let rule = SyncConflictRule.rule(localPending: localPending, change: change)
        if change == .updated {
            report.resolve(aggregate, rule: rule)
        }
        return rule
    }

    /// The conflict rule of an exercise's muscle groups or a routine's items,
    /// apart from their parent (`SyncConflictRule.childListChanged`), decided on
    /// the list as it was when the pull first reached it: applying the first
    /// server row changes the list. The caller reports a deletion.
    func childRule(
        for aggregate: SyncAggregateRef,
        model: any SyncChildListOwner,
        change: SyncServerChange = .updated
    ) -> SyncConflictRule {
        let changed = !created.contains(aggregate) && (childListsChanged[aggregate] ?? model.childListChanged)
        childListsChanged[aggregate] = changed
        let rule = SyncConflictRule.rule(localPending: changed, change: change)
        if rule == .serverApplied {
            serverLists[aggregate] = model
        }
        return rule
    }

    /// A parent this pull created holds the server's list, children or none.
    func create(_ aggregate: SyncAggregateRef, list model: any SyncChildListOwner) {
        create(aggregate)
        serverLists[aggregate] = model
    }

    /// Records the server's lists the pull applied as the ones the server holds,
    /// so a later change of the parent alone does not send them again.
    func stampServerLists() {
        for (aggregate, model) in serverLists {
            let table: RemoteTable = aggregate.kind == .routine ? .routines : .exercises
            if !deletes(table, aggregate.id) {
                model.markChildrenSynced()
            }
        }
    }

    func markDeleted(_ table: RemoteTable, _ id: UUID) {
        deleted[table, default: []].insert(id)
    }

    /// True when this pull deleted the row, which its relationships still list until the save.
    func deletes(_ table: RemoteTable, _ id: UUID?) -> Bool {
        id.map { deleted[table]?.contains($0) ?? false } ?? false
    }

    func create(_ aggregate: SyncAggregateRef) {
        created.insert(aggregate)
        report.created.append(aggregate)
    }

    /// The row is not applied and its table's cursor stays before it, so the next pull reads it again.
    func hold(_ table: RemoteTable, _ id: UUID, _ reason: SyncPullSkipReason = .missingParent) {
        held[table, default: []].insert(id)
        report.skip(table, id, reason)
    }

    func adopt(_ table: RemoteTable, localId: UUID, serverId: UUID) {
        report.adopted.append(.init(table: table, localId: localId, serverId: serverId))
    }

    func touch(_ entry: SessionEntryModel) {
        if !touchedEntries.contains(where: { $0 === entry }) {
            touchedEntries.append(entry)
        }
    }
}

extension SyncTrackedModel {
    /// A new aggregate as the server holds it: the user's, sent and acknowledged,
    /// so it is not pending and sessions that use it can be pushed.
    func markPulled() {
        isSyncable = true
        syncSent = true
        syncRevision = 1
        syncedRevision = 1
    }
}
