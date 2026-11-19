import Foundation
@testable import TNWTrackerKit

// Deletes and tombstones of the in-memory server, as its triggers write them
// (supabase/migrations/20261119120000_sync_tombstones.sql).
extension InMemoryTrainingRemoteStore {
    /// One delete statement: the rows with `ids` and every row its cascades
    /// reach go at once, each tracked one leaving a tombstone of its owner at the
    /// same new `updated_at`. An exercise still in use refuses the whole delete
    /// (`ON DELETE RESTRICT`); a deleted routine leaves its sessions without it
    /// (`ON DELETE SET NULL`, an update).
    func remove(_ table: RemoteTable, ids: [UUID]) throws {
        let ids = ids.filter { tables[table]?[$0] != nil }
        guard !ids.isEmpty else { return }
        if table == .exercises {
            let used = rows(RemoteEntryRow.self).contains { ids.contains($0.exerciseId) }
                || rows(RemoteEntryRow.self).contains { $0.replacedExerciseId.map(ids.contains) ?? false }
                || rows(RemoteRoutineItemRow.self).contains { ids.contains($0.exerciseId) }
            if used { throw Self.foreignKeyViolation("entries_exercise_id_fkey") }
        }
        clock += 1
        let now = Self.timestamp(clock)
        if table == .routines {
            for var session in rows(RemoteSessionRow.self) where session.routineId.map(ids.contains) ?? false {
                session.routineId = nil
                session.updatedAt = now
                tables[.sessions]?[session.id] = session
            }
        }
        for (table, id) in cascade(table, ids) {
            if let owner = tables[table]?[id].flatMap(Self.owner) {
                let tombstone = RemoteTombstoneRow(userId: owner, tableName: table.rawValue, rowId: id, updatedAt: now)
                tables[.tombstones, default: [:]][tombstone.id] = tombstone
            }
            tables[table]?[id] = nil
        }
    }

    /// The rows a delete of `ids` reaches: those, then the rows that cascade from them.
    private func cascade(_ table: RemoteTable, _ ids: [UUID]) -> [(RemoteTable, UUID)] {
        let children: [(RemoteTable, UUID)] = switch table {
        case .sessions:
            cascade(.entries, rows(RemoteEntryRow.self).filter { ids.contains($0.sessionId) }.map(\.id))
        case .entries:
            cascade(.sets, rows(RemoteSetRow.self).filter { ids.contains($0.entryId) }.map(\.id))
        case .routines:
            rows(RemoteRoutineItemRow.self).filter { ids.contains($0.routineId) }.map { (.routineItems, $0.id) }
        case .exercises:
            rows(RemoteMuscleGroupRow.self)
                .filter { ids.contains($0.exerciseId) }
                .map { (.exerciseMuscleGroups, $0.id) }
        default:
            []
        }
        return ids.map { (table, $0) } + children
    }

    /// The owner a tombstone records: catalogue exercises, muscle groups and
    /// routine items leave none.
    private static func owner(of row: any RemoteRow) -> UUID? {
        switch row {
        case let row as RemoteSessionRow: row.userId
        case let row as RemoteEntryRow: row.userId
        case let row as RemoteSetRow: row.userId
        case let row as RemoteRoutineRow: row.userId
        case let row as RemoteExerciseRow: row.userId
        default: nil
        }
    }

    /// Rows inserted again under their ids are no longer deleted: their
    /// owner's tombstones go, another user's stay.
    func clearTombstones(_ table: RemoteTable, ids: [UUID]) {
        let ids = Set(ids)
        for tombstone in rows(RemoteTombstoneRow.self)
            where tombstone.tableName == table.rawValue && ids.contains(tombstone.rowId)
            && tables[table]?[tombstone.rowId].flatMap(Self.owner) == tombstone.userId {
            tables[.tombstones]?[tombstone.id] = nil
        }
    }

    /// Writes the entries and then their sets again unchanged, as two updates
    /// do: both are read again after their tables' cursors.
    func touch(entries ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for (table, rowIds) in [(RemoteTable.entries, ids), (.sets, ids.flatMap { setsOf($0).map(\.id) })] {
            clock += 1
            let now = Self.timestamp(clock)
            for id in rowIds {
                guard var row = tables[table]?[id] else { continue }
                row.updatedAt = now
                tables[table]?[id] = row
            }
        }
    }

    func rows<Row: RemoteRow>(_ type: Row.Type) -> [Row] {
        tables[Row.table]?.values.compactMap { $0 as? Row } ?? []
    }
}
