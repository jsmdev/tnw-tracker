import Foundation
import SwiftData

// Sessions, entries and sets as the pull applies them (S2, S8, S13).
//
// - The session is the aggregate. With a local change waiting, the fields a
//   user edits keep the device's values; otherwise the server's are applied.
// - Imported data always merges: imported sets through the import rules
//   (`SwiftDataSessionRepository.mergeImportedSet`), entry refs as aliases.
// - The device's annotations are never taken from a row it already holds:
//   `warmup` of imported sets, and the reconciliation choice unless the server
//   holds one the user made on another device (an importer writes none).
//   `superseded` is always derived from the entry's choice.
// - Afterwards, a session the pull changed into something the server did not
//   send is marked changed, so the push sends it; an echo, or a value the
//   device only kept, leaves it as it was.

extension SwiftDataPullApplier {
    func applySessions(_ batch: PulledBatch, _ run: PullRun) throws {
        let before = try projections(of: sessionIds(in: batch), userId: run.userId)
        for row in batch.sessions {
            try applySession(row, run)
        }
        for row in batch.entries {
            try applyEntry(row, run)
        }
        // By position, so new imported sets keep the server's numbering.
        for row in batch.sets.sorted(by: { ($0.source.rawValue, $0.position) < ($1.source.rawValue, $1.position) }) {
            try applySet(row, run)
        }
        for entry in run.touchedEntries {
            sessions.reconcileAfterMerge(entry, movedChoice: nil, at: run.now)
        }
        for move in run.vacated {
            let left = try sessions.tidyVacated([move.from], keeping: move.into)
            try sessions.removeEmptiedImportedSessions(left.filter { $0.id != move.into.session?.id })
        }
        try markDifferences(batch, before: before, run)
    }

    // MARK: - Sessions

    private func applySession(_ row: RemoteSessionRow, _ run: PullRun) throws {
        var routine: RoutineModel?
        if let routineId = row.routineId {
            guard let found = try context.fetchRoutine(id: routineId) else { return run.hold(.sessions, row.id) }
            routine = found
        }
        let aggregate = SyncAggregateRef(.session, id: row.id)
        if let model = try context.fetchSession(id: row.id) ?? adoptSession(row, run) {
            if run.rule(for: aggregate, model: model) == .serverApplied { write(row, routine: routine, to: model) }
            return
        }
        if try hasTombstone(.session, row.id) { return run.report.skip(.sessions, row.id, .deletedOnDevice) }
        let model = SessionModel(id: row.id, timeZone: row.timeZone)
        context.insert(model)
        write(row, routine: routine, to: model)
        model.markPulled()
        run.create(aggregate)
    }

    private func adoptSession(_ row: RemoteSessionRow, _ run: PullRun) throws -> SessionModel? {
        guard let ref = row.externalRef, let local = try context.fetchSession(ref: ref),
              local.isSyncable, local.completedAt != nil
        else { return nil }
        // The server holds the ref under its own id, so the local row never reached it.
        let oldId: UUID? = local.id
        for tombstone in try context.fetch(FetchDescriptor<SyncTombstoneModel>(
            predicate: #Predicate { $0.sessionId == oldId }
        )) {
            tombstone.sessionId = row.id
        }
        run.adopt(.sessions, localId: local.id, serverId: row.id)
        local.id = row.id
        local.syncSent = true
        return local
    }

    private func write(_ row: RemoteSessionRow, routine: RoutineModel?, to model: SessionModel) {
        model.name = row.name
        model.notes = row.notes
        model.startedAt = row.startedAt
        model.completedAt = row.completedAt
        model.timeZone = row.timeZone
        model.durationSeconds = row.durationSeconds
        model.routine = routine
        model.externalProvider = row.externalRef?.provider
        model.externalId = row.externalRef?.id
    }

    // MARK: - Entries

    /// The rows an entry row names, all held by the device.
    private struct EntryParents {
        var session: SessionModel
        var exercise: ExerciseModel
        var replaced: ExerciseModel?
    }

    private func applyEntry(_ row: RemoteEntryRow, _ run: PullRun) throws {
        if try hasTombstone(.entry, row.id) { return run.report.skip(.entries, row.id, .deletedOnDevice) }
        guard let parents = try parents(of: row) else { return run.hold(.entries, row.id) }
        let session = parents.session
        if let entry = try fetchEntryModel(id: row.id) ?? adoptEntry(row, in: session, run) {
            guard entry.session?.id == session.id else {
                return run.report.skip(.entries, row.id, .conflict("the device holds the entry in another session"))
            }
            if run.rule(for: SyncAggregateRef(.session, id: session.id), model: session) == .serverApplied {
                write(row, parents: parents, to: entry)
            }
            try mergeRef(row.externalRef, into: entry)
            return
        }
        if row.status == .done, session.entries.contains(where: { $0.isDone && $0.exercise?.id == row.exerciseId }) {
            return run.report.skip(.entries, row.id, .conflict("the session already has a done entry of the exercise"))
        }
        let entry = SessionEntryModel(id: row.id, order: row.position, statusRaw: row.status.rawValue)
        context.insert(entry)
        session.entries.append(entry)
        write(row, parents: parents, to: entry)
        // A new row from the server comes with its decision, as the server holds it.
        entry.reconciliationKeepRaw = row.reconciliationKeep?.rawValue
        entry.reconciliationDecidedByRaw = row.reconciliationDecidedBy?.rawValue
        entry.reconciliationDecidedAt = row.reconciliationDecidedAt
        try mergeRef(row.externalRef, into: entry)
    }

    private func parents(of row: RemoteEntryRow) throws -> EntryParents? {
        guard let session = try context.fetchSession(id: row.sessionId),
              let exercise = try context.fetchExercise(id: row.exerciseId)
        else { return nil }
        var parents = EntryParents(session: session, exercise: exercise)
        if let replacedId = row.replacedExerciseId {
            guard let replaced = try context.fetchExercise(id: replacedId) else { return nil }
            parents.replaced = replaced
        }
        return parents
    }

    /// The local entry that is the server's under another id: the one holding
    /// its ref in the same session, or, for a done entry, the session's done
    /// entry of the same exercise that never reached the server.
    private func adoptEntry(
        _ row: RemoteEntryRow,
        in session: SessionModel,
        _ run: PullRun
    ) throws -> SessionEntryModel? {
        var candidate: SessionEntryModel?
        if let ref = row.externalRef, let holder = try context.fetchEntry(ref: ref), holder.session?.id == session.id {
            candidate = holder
        } else if row.status == .done {
            candidate = session.entries.first { $0.isDone && $0.exercise?.id == row.exerciseId && !$0.syncSent }
        }
        guard let entry = candidate else { return nil }
        // Sent without the ref: the server holds it under the local id too, so that row goes.
        if entry.syncSent { try context.recordRemoval(of: entry, from: session) }
        run.adopt(.entries, localId: entry.id, serverId: row.id)
        entry.id = row.id
        entry.syncSent = true
        return entry
    }

    /// The server's values. The reconciliation choice stays the device's unless
    /// the server holds one the user made (on another device): a missing or
    /// default decision, which is all an importer writes, never replaces it. The
    /// same choice takes the server's `decidedAt`, at the precision it stores.
    private func write(_ row: RemoteEntryRow, parents: EntryParents, to entry: SessionEntryModel) {
        entry.order = row.position
        entry.exercise = parents.exercise
        entry.replacedExercise = parents.replaced
        entry.statusRaw = row.status.rawValue
        entry.completedAt = row.completedAt
        entry.notes = row.notes
        entry.syncSent = true
        if row.reconciliationDecidedBy == .user, let keep = row.reconciliationKeep, entry.hasBothSources {
            entry.setReconciliation(keep: keep, decidedBy: .user, at: row.reconciliationDecidedAt ?? Date())
        } else if entry.reconciliationKeepRaw == row.reconciliationKeep?.rawValue,
                  entry.reconciliationDecidedByRaw == row.reconciliationDecidedBy?.rawValue {
            entry.reconciliationDecidedAt = row.reconciliationDecidedAt
        }
    }

    /// An entry ref the device does not know yet becomes one of the entry's
    /// aliases, so a later in-app import finds the entry by it.
    private func mergeRef(_ ref: ExternalRef?, into entry: SessionEntryModel) throws {
        guard let ref, try context.fetchEntry(ref: ref) == nil else { return }
        let alias = EntryExternalRefModel(provider: ref.provider, externalId: ref.id)
        context.insert(alias)
        entry.mergedRefs.append(alias)
        if entry.externalId == nil {
            entry.externalProvider = ref.provider
            entry.externalId = ref.id
        }
    }

    func fetchEntryModel(id: UUID) throws -> SessionEntryModel? {
        var descriptor = FetchDescriptor<SessionEntryModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

extension SessionEntryModel {
    var isDone: Bool {
        statusRaw == EntryStatus.done.rawValue
    }
}
