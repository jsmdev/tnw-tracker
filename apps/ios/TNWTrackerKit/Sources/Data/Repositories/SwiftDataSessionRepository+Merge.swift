import Foundation
import SwiftData

// Import merge of the SwiftData session repository (D8, D-T7e, D-T7f).

extension SwiftDataSessionRepository {
    /// Merges one imported entry into `session` without saving. `imported.exerciseId`
    /// is ignored: `exercise` is the local exercise it resolved to.
    ///
    /// D8: a ref (entry or set) that already belongs to another session moves here
    /// with the user's annotations (`warmup`, `superseded`, the reconciliation
    /// choice). Returns the other sessions that lost data, for
    /// `removeEmptiedImportedSessions` once every entry of the import is merged.
    @discardableResult
    func merge(
        _ imported: ImportedEntry,
        exercise: ExerciseModel,
        into session: SessionModel
    ) throws -> [SessionModel] {
        // Validate everything before writing anything.
        try Self.validate(imported, for: exercise)
        let found = try context.fetchEntry(ref: imported.externalRef)
        let known = found?.session?.id == session.id ? found : nil
        var vacatedEntries: [SessionEntryModel] = []

        // One entry per exercise: a second provider entry merges into the same entry.
        let entry = known ?? doneEntry(in: session, for: exercise)
        var movedChoice: Reconciliation?
        if let found, known == nil {
            movedChoice = moveRef(imported.externalRef, from: found, to: entry)
            vacatedEntries.append(found)
        }
        if entry.externalId == nil {
            entry.externalProvider = imported.externalRef.provider
            entry.externalId = imported.externalRef.id
        }
        if found == nil {
            let alias = EntryExternalRefModel(
                provider: imported.externalRef.provider,
                externalId: imported.externalRef.id
            )
            context.insert(alias)
            entry.mergedRefs.append(alias)
        }
        // Rule `range`: no entry ends after its session.
        if let completedAt = imported.completedAt, session.completedAt.map({ completedAt <= $0 }) ?? true {
            entry.completedAt = completedAt
        }

        let keep = entry.reconciliationKeepRaw.flatMap(SetSource.init(rawValue:))
        for incoming in imported.sets.sorted(by: { $0.order < $1.order }) {
            if let stored = try context.fetchSet(ref: incoming.externalRef) {
                if let previous = stored.entry, previous.id != entry.id {
                    // D8: the set moves into this entry, after its imported sets;
                    // `superseded` and `warmup` move with it.
                    previous.sets.removeAll { $0.id == stored.id }
                    stored.order = nextOrder(in: entry, source: .imported)
                    entry.sets.append(stored)
                    vacatedEntries.append(previous)
                }
                // Re-import: values replace the stored ones. The set keeps its
                // position in the merged entry; `superseded` and `warmup` belong to the app.
                stored.apply(incoming.values)
                stored.completedAt = incoming.completedAt
            } else {
                // Imported sets are numbered within the merged entry, so sets of
                // several provider entries never share an order.
                let set = ExerciseSetModel(
                    id: UUID(),
                    order: nextOrder(in: entry, source: .imported),
                    sourceRaw: SetSource.imported.rawValue
                )
                context.insert(set)
                set.externalProvider = incoming.externalRef.provider
                set.externalId = incoming.externalRef.id
                set.apply(incoming.values)
                set.completedAt = incoming.completedAt
                set.superseded = keep == .manual
                set.warmup = incoming.warmup
                entry.sets.append(set)
            }
        }
        reconcileAfterMerge(entry, movedChoice: movedChoice, at: Date())
        return tidyVacated(vacatedEntries, keeping: entry).filter { $0.id != session.id }
    }

    /// Rules an imported entry and its sets must meet before anything is written.
    private static func validate(_ imported: ImportedEntry, for exercise: ExerciseModel) throws {
        guard !imported.sets.isEmpty else {
            throw TrainingDataError.invalidSet("an imported entry needs at least one set")
        }
        guard imported.externalRef.isValid else { throw TrainingDataError.invalidExternalRef }
        for incoming in imported.sets {
            guard incoming.externalRef.isValid else { throw TrainingDataError.invalidExternalRef }
            guard incoming.order >= 1 else { throw TrainingDataError.invalidSet("set order starts at 1") }
            try validate(incoming.values, for: exercise)
        }
    }

    /// D8: moves the entry ref `ref` from `source` (in another session) to `entry`.
    /// Returns the source's reconciliation choice, which moves with the ref.
    private func moveRef(
        _ ref: ExternalRef,
        from source: SessionEntryModel,
        to entry: SessionEntryModel
    ) -> Reconciliation? {
        if let alias = source.mergedRefs.first(where: { $0.provider == ref.provider && $0.externalId == ref.id }) {
            source.mergedRefs.removeAll { $0.persistentModelID == alias.persistentModelID }
            entry.mergedRefs.append(alias)
        }
        if source.externalProvider == ref.provider, source.externalId == ref.id {
            let next = source.mergedRefs.first
            source.externalProvider = next?.provider
            source.externalId = next?.externalId
        }
        return source.reconciliation
    }

    /// Reconciliation rules 4 and 5 after a merge (D-T7e): every set's `superseded`
    /// in `entry` is derived from the entry's choice. The target's own choice wins,
    /// else the choice that moved with the ref, else the default (keep imported)
    /// when the entry starts mixing sources. A single-source entry has no choice.
    private func reconcileAfterMerge(_ entry: SessionEntryModel, movedChoice: Reconciliation?, at date: Date) {
        guard entry.hasBothSources else {
            entry.clearReconciliation()
            return
        }
        if let choice = entry.reconciliation ?? movedChoice {
            entry.setReconciliation(keep: choice.keep, decidedBy: choice.decidedBy, at: choice.decidedAt ?? date)
        } else {
            applyReconciliationOnMerge(entry, at: date)
        }
    }

    /// Entries that lost refs or sets to `kept`: an emptied entry is removed (a
    /// planned one goes back to skipped), a single-source one loses its
    /// reconciliation. Returns their sessions.
    private func tidyVacated(_ entries: [SessionEntryModel], keeping kept: SessionEntryModel) -> [SessionModel] {
        var sessions: [SessionModel] = []
        for source in entries where source.id != kept.id {
            guard let session = source.session else { continue }
            if !sessions.contains(where: { $0.id == session.id }) { sessions.append(session) }
            if source.sets.isEmpty, source.mergedRefs.isEmpty {
                if isPlanned(source, in: session) {
                    source.statusRaw = EntryStatus.skipped.rawValue
                    source.completedAt = nil
                    source.externalProvider = nil
                    source.externalId = nil
                    source.clearReconciliation()
                } else {
                    session.entries.removeAll { $0.id == source.id }
                    context.delete(source)
                }
            } else if !source.hasBothSources {
                source.clearReconciliation()
            }
        }
        return sessions
    }

    /// D8: a completed session that lost its data to another session is removed
    /// when it was imported-only (no manual set) and has no counted set left.
    /// D-T7f: only a session an import created (it carries the import's session
    /// `externalRef`) can be removed; a session the user logged, or one in
    /// progress, is always kept.
    func removeEmptiedImportedSessions(_ sessions: [SessionModel]) {
        for session in sessions where session.completedAt != nil && session.externalId != nil {
            let sets = session.entries.flatMap(\.sets)
            let hasManual = sets.contains { $0.sourceRaw == SetSource.manual.rawValue }
            let hasCounted = session.entries.contains { entry in
                entry.statusRaw != EntryStatus.removed.rawValue && entry.sets.contains { !$0.superseded && !$0.warmup }
            }
            if !hasManual, !hasCounted {
                context.delete(session)
            }
        }
    }
}
