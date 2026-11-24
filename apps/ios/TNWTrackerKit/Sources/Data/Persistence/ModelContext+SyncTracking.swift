import Foundation
import SwiftData

// Change tracking for the sync (S7, S11), written by the repositories before
// their own `save()`, so a change and its mark are saved together. Rules in
// `Data/Sync/LocalSyncState.swift`.

/// An aggregate root the sync uploads as a unit.
protocol SyncTrackedModel: AnyObject {
    var syncRevision: Int { get set }
    var syncedRevision: Int { get set }
    var syncSent: Bool { get set }
    var isSyncable: Bool { get set }
    var syncFailureCount: Int { get set }
    var syncLastError: String? { get set }
}

extension SyncTrackedModel {
    /// Records a local change: the aggregate is pending until the server
    /// acknowledges this revision or a later one.
    func markChanged() {
        syncRevision += 1
    }
}

extension ExerciseModel: SyncTrackedModel {}
extension RoutineModel: SyncTrackedModel {}
extension SessionModel: SyncTrackedModel {}
extension ExerciseSettingModel: SyncTrackedModel {}
extension ExerciseLinkModel: SyncTrackedModel {}

extension ModelContext {
    /// True when the store has an owner, so the aggregates created now are the owner's data.
    func storeHasOwner() throws -> Bool {
        try fetchCount(FetchDescriptor<StoreOwnerModel>()) > 0
    }

    /// Stamps a newly inserted aggregate: syncable only when the store has an owner.
    func trackNew(_ model: some SyncTrackedModel, syncable: Bool = true) throws {
        model.isSyncable = try syncable && storeHasOwner()
        model.markChanged()
    }

    // MARK: Tombstones

    /// A set removed from `session` (deleted, or moved to another session).
    /// Leaves a tombstone only when the set may exist on the server.
    func recordRemoval(of set: ExerciseSetModel, from session: SessionModel?) throws {
        guard let session else { return }
        session.markChanged()
        guard set.syncSent, session.isSyncable else { return }
        try insertTombstone(.set, rowId: set.id, sessionId: session.id, revision: session.syncRevision)
    }

    /// An entry deleted from `session`. Leaves a tombstone only when the entry may exist on the server.
    func recordRemoval(of entry: SessionEntryModel, from session: SessionModel?) throws {
        guard let session else { return }
        session.markChanged()
        guard entry.syncSent, session.isSyncable else { return }
        try insertTombstone(.entry, rowId: entry.id, sessionId: session.id, revision: session.syncRevision)
    }

    /// A session about to be deleted. Its entry and set tombstones go: deleting
    /// the session on the server deletes its rows.
    func recordDeletion(of session: SessionModel) throws {
        let sessionId: UUID? = session.id
        let children = FetchDescriptor<SyncTombstoneModel>(predicate: #Predicate { $0.sessionId == sessionId })
        for child in try fetch(children) {
            delete(child)
        }
        guard session.syncSent, session.isSyncable else { return }
        try insertTombstone(.session, rowId: session.id, sessionId: nil, revision: session.syncRevision + 1)
    }

    /// A personal link about to be deleted. Leaves a tombstone only when the
    /// link may exist on the server.
    func recordDeletion(of link: ExerciseLinkModel) throws {
        guard link.syncSent, link.isSyncable else { return }
        try insertTombstone(.exerciseLink, rowId: link.id, sessionId: nil, revision: link.syncRevision + 1)
    }

    /// A set that joins `session` again is no longer removed from it.
    func dropRemoval(ofSet setId: UUID, in session: SessionModel) throws {
        let sessionId: UUID? = session.id
        let kind = SyncTombstoneKind.set.rawValue
        let descriptor = FetchDescriptor<SyncTombstoneModel>(
            predicate: #Predicate { $0.sessionId == sessionId && $0.kindRaw == kind && $0.rowId == setId }
        )
        for tombstone in try fetch(descriptor) {
            delete(tombstone)
        }
    }

    private func insertTombstone(_ kind: SyncTombstoneKind, rowId: UUID, sessionId: UUID?, revision: Int) throws {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<SyncTombstoneModel>(
            predicate: #Predicate { $0.kindRaw == kindRaw && $0.rowId == rowId && $0.sessionId == sessionId }
        )
        // Defensive: no command removes the same row from the same session twice today.
        if let existing = try fetch(descriptor).first {
            existing.revision = revision
            existing.deletedAt = Date()
            return
        }
        insert(SyncTombstoneModel(
            kindRaw: kindRaw,
            rowId: rowId,
            sessionId: sessionId,
            revision: revision,
            deletedAt: Date()
        ))
    }
}
