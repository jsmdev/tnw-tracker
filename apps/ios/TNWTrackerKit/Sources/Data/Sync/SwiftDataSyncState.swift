import Foundation
import SwiftData

// SwiftData adapters of the local sync state; see `LocalSyncState.swift`.

@MainActor
final class SwiftDataStoreOwnership: StoreOwnershipProtocol {
    private let context: ModelContext
    /// The context does not keep its container alive; the adapter does.
    private let container: ModelContainer

    init(context: ModelContext) {
        self.context = context
        container = context.container
    }

    func owner() throws -> UUID? {
        try context.fetch(FetchDescriptor<StoreOwnerModel>(sortBy: [SortDescriptor(\.claimedAt)])).first?.userId
    }

    func claim(userId: UUID, at date: Date) throws -> StoreOwnership {
        let owners = try context.fetch(FetchDescriptor<StoreOwnerModel>())
        if owners.map(\.userId) == [userId] { return .owned }
        if let other = owners.first(where: { $0.userId != userId }), try holdsOwnedData() {
            return .mismatch(ownerId: other.userId)
        }
        for owner in owners {
            context.delete(owner)
        }
        context.insert(StoreOwnerModel(userId: userId, claimedAt: date))
        try context.save()
        return .claimed
    }

    /// True when any syncable aggregate or tombstone is stored: data of the current owner.
    private func holdsOwnedData() throws -> Bool {
        let counts = try [
            context.fetchCount(FetchDescriptor<SessionModel>(predicate: #Predicate { $0.isSyncable })),
            context.fetchCount(FetchDescriptor<RoutineModel>(predicate: #Predicate { $0.isSyncable })),
            context.fetchCount(FetchDescriptor<ExerciseModel>(predicate: #Predicate { $0.isSyncable })),
            context.fetchCount(FetchDescriptor<ExerciseSettingModel>(predicate: #Predicate { $0.isSyncable })),
            context.fetchCount(FetchDescriptor<SyncTombstoneModel>())
        ]
        return counts.contains { $0 > 0 }
    }
}

@MainActor
final class SwiftDataSyncStateRepository: SyncStateRepositoryProtocol {
    private let context: ModelContext
    /// The context does not keep its container alive; the adapter does.
    private let container: ModelContainer

    init(context: ModelContext) {
        self.context = context
        container = context.container
    }

    // MARK: Pending aggregates

    func pending(_ kind: SyncAggregateKind) throws -> [PendingSyncAggregate] {
        switch kind {
        case .session:
            return try pendingSessions()
        case .routine:
            let models = try context.fetch(FetchDescriptor<RoutineModel>(
                predicate: #Predicate { $0.isSyncable && $0.syncRevision > $0.syncedRevision }
            ))
            return Self.byId(models.map { PendingSyncAggregate(kind: kind, id: $0.id, revision: $0.syncRevision) })
        case .exercise:
            let models = try context.fetch(FetchDescriptor<ExerciseModel>(
                predicate: #Predicate { $0.isSyncable && !$0.isCatalogue && $0.syncRevision > $0.syncedRevision }
            ))
            return Self.byId(models.map { PendingSyncAggregate(kind: kind, id: $0.id, revision: $0.syncRevision) })
        case .exerciseSetting:
            let models = try context.fetch(FetchDescriptor<ExerciseSettingModel>(
                predicate: #Predicate { $0.isSyncable && $0.syncRevision > $0.syncedRevision }
            ))
            return Self.byId(models.map {
                PendingSyncAggregate(kind: kind, id: $0.exerciseId, revision: $0.syncRevision)
            })
        }
    }

    /// Completed, syncable sessions changed since their last acknowledged
    /// revision, by completion time then id, with the entries and sets removed since.
    private func pendingSessions() throws -> [PendingSyncAggregate] {
        let models = try context.fetch(FetchDescriptor<SessionModel>(
            predicate: #Predicate { session in
                session.isSyncable && session.completedAt != nil && session.syncRevision > session.syncedRevision
            }
        ))
        let ordered = models.sorted { lhs, rhs in
            let left = lhs.completedAt ?? .distantPast
            let right = rhs.completedAt ?? .distantPast
            return left == right ? lhs.id.uuidString < rhs.id.uuidString : left < right
        }
        return try ordered.map { session in
            let removed = try childTombstones(of: session.id)
            return PendingSyncAggregate(
                kind: .session,
                id: session.id,
                revision: session.syncRevision,
                removedEntryIds: removed.filter { $0.kindRaw == SyncTombstoneKind.entry.rawValue }.map(\.rowId),
                removedSetIds: removed.filter { $0.kindRaw == SyncTombstoneKind.set.rawValue }.map(\.rowId)
            )
        }
    }

    private static func byId(_ pending: [PendingSyncAggregate]) -> [PendingSyncAggregate] {
        pending.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    // MARK: Compare and clear

    func markSent(_ kind: SyncAggregateKind, id: UUID, ifRevision revision: Int) throws -> Bool {
        guard let model = try trackedModel(kind, id: id), model.isSyncable, model.syncRevision == revision else {
            return false
        }
        stampSent(model)
        try context.save()
        return true
    }

    func markSynced(_ kind: SyncAggregateKind, id: UUID, ifRevision revision: Int) throws -> Bool {
        guard let model = try trackedModel(kind, id: id), model.isSyncable, model.syncRevision == revision else {
            return false
        }
        stampSent(model)
        model.syncedRevision = revision
        if kind == .session {
            for tombstone in try childTombstones(of: id) where tombstone.revision <= revision {
                context.delete(tombstone)
            }
        }
        try context.save()
        return true
    }

    /// Every row of the aggregate, as it is now, may exist on the server.
    private func stampSent(_ model: any SyncTrackedModel) {
        model.syncSent = true
        guard let session = model as? SessionModel else { return }
        for entry in session.entries {
            entry.syncSent = true
            for set in entry.sets {
                set.syncSent = true
            }
        }
    }

    private func trackedModel(_ kind: SyncAggregateKind, id: UUID) throws -> (any SyncTrackedModel)? {
        switch kind {
        case .session:
            return try context.fetchSession(id: id)
        case .routine:
            return try context.fetchRoutine(id: id)
        case .exercise:
            return try context.fetchExercise(id: id)
        case .exerciseSetting:
            var descriptor = FetchDescriptor<ExerciseSettingModel>(predicate: #Predicate { $0.exerciseId == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first
        }
    }

    // MARK: Tombstones

    func tombstones() throws -> [SyncTombstone] {
        let models = try context.fetch(FetchDescriptor<SyncTombstoneModel>(
            predicate: #Predicate { $0.sessionId == nil },
            sortBy: [SortDescriptor(\.deletedAt)]
        ))
        return models.compactMap { model in
            SyncTombstoneKind(rawValue: model.kindRaw).map {
                SyncTombstone(kind: $0, id: model.rowId, revision: model.revision, deletedAt: model.deletedAt)
            }
        }
    }

    func clearTombstone(_ tombstone: SyncTombstone) throws -> Bool {
        let kindRaw = tombstone.kind.rawValue
        let rowId = tombstone.id
        let revision = tombstone.revision
        let descriptor = FetchDescriptor<SyncTombstoneModel>(predicate: #Predicate {
            $0.sessionId == nil && $0.kindRaw == kindRaw && $0.rowId == rowId && $0.revision == revision
        })
        let matches = try context.fetch(descriptor)
        guard !matches.isEmpty else { return false }
        for model in matches {
            context.delete(model)
        }
        try context.save()
        return true
    }

    /// Entry and set tombstones of a session, oldest first.
    private func childTombstones(of sessionId: UUID) throws -> [SyncTombstoneModel] {
        let id: UUID? = sessionId
        return try context.fetch(FetchDescriptor<SyncTombstoneModel>(
            predicate: #Predicate { $0.sessionId == id },
            sortBy: [SortDescriptor(\.deletedAt)]
        ))
    }
}
