import Foundation
import SwiftData

// Sets as the pull applies them, and the check that tells an echo from a
// difference the device keeps. Rules in `SwiftDataPullApplier+Sessions.swift`.

extension SwiftDataPullApplier {
    func applySet(_ row: RemoteSetRow, _ run: PullRun) throws {
        if try hasTombstone(.entry, row.entryId) { return run.report.skip(.sets, row.id, .deletedOnDevice) }
        guard let entry = try fetchEntryModel(id: row.entryId), let session = entry.session,
              let exercise = entry.exercise
        else {
            // Not a missing parent: the device deleted its session, and the deletion goes up next push (L8).
            if let sessionId = run.entrySessions[row.entryId], try hasTombstone(.session, sessionId) {
                return run.report.skip(.sets, row.id, .deletedOnDevice)
            }
            return run.hold(.sets, row.id)
        }
        let values = SetValues(
            reps: row.reps, weight: row.weight, durationSeconds: row.durationSeconds,
            distanceMeters: row.distanceMeters, rir: row.rir, restSeconds: row.restSeconds
        )
        do {
            try SwiftDataSessionRepository.validate(values, for: exercise)
        } catch let error as TrainingDataError {
            return run.report.skip(.sets, row.id, .invalid(String(describing: error)))
        }
        let known = try fetchSetModel(id: row.id)
        if known == nil, try hasTombstone(.set, row.id) { return run.report.skip(.sets, row.id, .deletedOnDevice) }
        let rule = run.rule(for: SyncAggregateRef(.session, id: session.id), model: session)
        switch row.source {
        case .imported:
            guard try mergeImported(row, values: values, known: known, into: entry, run) else { return }
        case .manual:
            guard rule == .serverApplied || known == nil else { break }
            applyManual(row, values: values, known: known, into: entry)
        }
        // A planned entry that gains sets is done (the server's rule, and the importer's).
        if entry.statusRaw == EntryStatus.skipped.rawValue { entry.statusRaw = EntryStatus.done.rawValue }
        run.touch(entry)
    }

    /// Imported data always merges, as the importer merges it. A set the device
    /// holds only takes the new values: its `superseded` and `warmup` are the app's.
    /// Returns `false` for a set without a valid external ref, which is skipped.
    private func mergeImported(
        _ row: RemoteSetRow,
        values: SetValues,
        known: ExerciseSetModel?,
        into entry: SessionEntryModel,
        _ run: PullRun
    ) throws -> Bool {
        guard let ref = row.externalRef, ref.isValid, let session = entry.session else {
            run.report.skip(.sets, row.id, .invalid("an imported set needs an external ref"))
            return false
        }
        if let known {
            known.apply(values)
            known.completedAt = row.completedAt
            known.syncSent = true
            return true
        }
        if let holder = try context.fetchSet(ref: ref) {
            // The device holds the ref under its own id. Sent without the ref,
            // the server may hold that id too, so that row goes.
            if holder.syncSent { try context.recordRemoval(of: holder, from: holder.entry?.session) }
            run.adopt(.sets, localId: holder.id, serverId: row.id)
            holder.id = row.id
        }
        let incoming = ImportedSet(
            externalRef: ref, order: row.position, values: values, completedAt: row.completedAt, warmup: row.warmup
        )
        let keep = entry.reconciliationKeepRaw.flatMap(SetSource.init(rawValue:))
        let merged = try sessions.mergeImportedSet(incoming, into: entry, of: session, keep: keep, newId: row.id)
        merged.set.syncSent = true
        if let vacated = merged.vacated { run.vacated.append((into: entry, from: vacated)) }
        return true
    }

    private func applyManual(
        _ row: RemoteSetRow,
        values: SetValues,
        known: ExerciseSetModel?,
        into entry: SessionEntryModel
    ) {
        let set = known ?? {
            let set = ExerciseSetModel(id: row.id, order: row.position, sourceRaw: SetSource.manual.rawValue)
            context.insert(set)
            entry.sets.append(set)
            return set
        }()
        guard set.sourceRaw == SetSource.manual.rawValue else { return }
        set.order = row.position
        set.apply(values)
        set.completedAt = row.completedAt
        set.warmup = row.warmup
        set.syncSent = true
    }

    func fetchSetModel(id: UUID) throws -> ExerciseSetModel? {
        var descriptor = FetchDescriptor<ExerciseSetModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Echo or difference

    /// Sessions the batch may change, by the ids the server gave them.
    func sessionIds(in batch: PulledBatch) throws -> Set<UUID> {
        var ids = Set(batch.sessions.map(\.id)).union(batch.entries.map(\.sessionId))
        let pulledEntries = Dictionary(
            batch.entries.map { ($0.id, $0.sessionId) }, uniquingKeysWith: { first, _ in first }
        )
        for set in batch.sets {
            if let sessionId = try pulledEntries[set.entryId] ?? fetchEntryModel(id: set.entryId)?.session?.id {
                ids.insert(sessionId)
            }
        }
        return ids
    }

    /// The rows the device holds for each completed session, as the server would store them.
    func projections(of ids: Set<UUID>, userId: UUID) throws -> [UUID: RemoteSessionAggregate] {
        let rows = PushRows(userId: userId) { _ in false }
        var projections: [UUID: RemoteSessionAggregate] = [:]
        for id in ids {
            guard let model = try context.fetchSession(id: id), let completedAt = model.completedAt else { continue }
            projections[id] = rows.sessionAggregate(model.snapshot, completedAt: completedAt)
        }
        return projections
    }

    /// A session the pull changed into something the server did not send (a
    /// decision the merge took, a server value merged next to a value the device
    /// keeps, a row moved out) is marked changed, so the push sends it.
    func markDifferences(_ batch: PulledBatch, before: [UUID: RemoteSessionAggregate], _ run: PullRun) throws {
        let pulled = PulledRows(batch)
        let after = try projections(of: sessionIds(in: batch), userId: run.userId)
        for (id, rows) in after.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard pulled.differs(rows, before: before[id]), let model = try context.fetchSession(id: id) else {
                continue
            }
            model.markChanged()
            run.report.changedLocally.append(id)
        }
    }
}

/// The session rows of a batch by id, without the server's `updated_at`.
private struct PulledRows {
    var sessions: [UUID: RemoteSessionRow] = [:]
    var entries: [UUID: RemoteEntryRow] = [:]
    var sets: [UUID: RemoteSetRow] = [:]

    init(_ batch: PulledBatch) {
        sessions = Self.byId(batch.sessions)
        entries = Self.byId(batch.entries)
        sets = Self.byId(batch.sets)
    }

    func differs(_ rows: RemoteSessionAggregate, before: RemoteSessionAggregate?) -> Bool {
        let entriesBefore = Self.byId(before?.entries ?? [])
        let setsBefore = Self.byId(before?.sets ?? [])
        let left = Set(entriesBefore.keys).subtracting(rows.entries.map(\.id))
            .union(Set(setsBefore.keys).subtracting(rows.sets.map(\.id)))
        return !left.isEmpty
            || Self.changed(rows.session, pulled: sessions[rows.session.id], before: before?.session)
            || rows.entries.contains { Self.changed($0, pulled: entries[$0.id], before: entriesBefore[$0.id]) }
            || rows.sets.contains { Self.changed($0, pulled: sets[$0.id], before: setsBefore[$0.id]) }
    }

    /// A row the server sent must now match it, unless the device kept it exactly
    /// as it was: a value the device keeps (its own annotation, or a pending
    /// edit) is not a new difference, so two devices never push it back and
    /// forth. A row the server did not send must be as it was.
    private static func changed<Row: Equatable>(_ row: Row, pulled: Row?, before: Row?) -> Bool {
        guard let pulled else { return before != row }
        return pulled != row && before != row
    }

    private static func byId<Row: RemoteRow>(_ rows: [Row]) -> [UUID: Row] {
        Dictionary(rows.map { row in
            var row = row
            row.updatedAt = nil
            return (row.id, row)
        }, uniquingKeysWith: { _, last in last })
    }
}
