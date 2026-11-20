import Foundation
import SwiftData

// Rows the server deleted, as the pull applies them (S11). Rules in
// docs/database-schema.md, "Sync":
//
// - Children first (sets, entries, sessions, routine items, routines, muscle
//   groups, exercise settings, exercises), so a session's rows go before it
//   and an exercise goes after the rows this pull deleted that used it.
// - A muscle group or routine item is found by the id the server holds it
//   under (`serverId`, else the one derived from its natural key); a setting
//   by its exercise id.
// - A deletion follows the conflict rule of the row's aggregate
//   (`SyncConflictRule`, change `.deleted`): with no local change waiting, the
//   row goes; with one, it is kept and the next push writes it back. A muscle
//   group or routine item follows the rule of its list instead
//   (`PullRun.childRule`): it goes unless the device changed that list.
// - Applying a deletion is not a local change: it leaves no tombstone and
//   marks nothing pending, so it is never echoed back.
// - A row the device does not hold, or holds as data that never leaves it, is
//   passed over.

extension SwiftDataPullApplier {
    func applyTombstones(_ rows: [RemoteTombstoneRow], _ run: PullRun) throws {
        let order: [RemoteTable] = [
            .sets, .entries, .sessions, .routineItems, .routines, .exerciseMuscleGroups, .exerciseSettings, .exercises
        ]
        for table in order {
            for row in rows where row.deletedTable == table {
                try applyTombstone(table, id: row.rowId, run)
            }
        }
    }

    private func applyTombstone(_ table: RemoteTable, id: UUID, _ run: PullRun) throws {
        switch table {
        case .sets: try deleteSet(id, run)
        case .entries: try deleteEntry(id, run)
        case .sessions: try deleteSession(id, run)
        case .routineItems: try deleteRoutineItem(id, run)
        case .routines: try deleteRoutine(id, run)
        case .exerciseMuscleGroups: try deleteMuscleGroup(id, run)
        case .exerciseSettings: try deleteSetting(id, run)
        case .exercises: try deleteExercise(id, run)
        case .tombstones: break
        }
    }

    private func deleteRoutineItem(_ id: UUID, _ run: PullRun) throws {
        guard let item = try context.fetch(FetchDescriptor<RoutineItemModel>()).first(where: { $0.rowId == id }),
              let routine = item.routine, routine.isSyncable
        else { return }
        let rule = run.childRule(for: .init(.routine, id: routine.id), model: routine, change: .deleted)
        guard report(.routineItems, id, rule: rule, run) else { return }
        run.removedItems.insert(item.persistentModelID)
        routine.items.removeAll { $0.persistentModelID == item.persistentModelID }
        context.delete(item)
    }

    private func deleteMuscleGroup(_ id: UUID, _ run: PullRun) throws {
        guard let group = try context.fetch(FetchDescriptor<MuscleGroupModel>()).first(where: { $0.rowId == id }),
              let exercise = group.exercise, exercise.isSyncable, !exercise.isCatalogue
        else { return }
        let rule = run.childRule(for: .init(.exercise, id: exercise.id), model: exercise, change: .deleted)
        guard report(.exerciseMuscleGroups, id, rule: rule, run) else { return }
        exercise.muscleGroups.removeAll { $0.persistentModelID == group.persistentModelID }
        context.delete(group)
    }

    private func deleteSetting(_ exerciseId: UUID, _ run: PullRun) throws {
        guard let setting = try context.fetchExerciseSetting(exerciseId: exerciseId), setting.isSyncable else { return }
        let aggregate = SyncAggregateRef(.exerciseSetting, id: exerciseId)
        guard decide(.exerciseSettings, exerciseId, aggregate: aggregate, model: setting, run) else { return }
        context.delete(setting)
    }

    private func deleteSet(_ id: UUID, _ run: PullRun) throws {
        guard let set = try fetchSetModel(id: id), let entry = set.entry, let session = entry.session,
              session.isSyncable
        else { return }
        guard decide(.sets, id, aggregate: .init(.session, id: session.id), model: session, run) else { return }
        entry.sets.removeAll { $0.id == id }
        context.delete(set)
    }

    private func deleteEntry(_ id: UUID, _ run: PullRun) throws {
        guard let entry = try fetchEntryModel(id: id), let session = entry.session, session.isSyncable else { return }
        guard decide(.entries, id, aggregate: .init(.session, id: session.id), model: session, run) else { return }
        session.entries.removeAll { $0.id == id }
        context.delete(entry)
    }

    private func deleteSession(_ id: UUID, _ run: PullRun) throws {
        guard let session = try context.fetchSession(id: id), session.isSyncable, session.completedAt != nil else {
            return
        }
        guard decide(.sessions, id, aggregate: .init(.session, id: id), model: session, run) else { return }
        let sessionId: UUID? = id
        for child in try context.fetch(FetchDescriptor<SyncTombstoneModel>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )) {
            context.delete(child)
        }
        context.delete(session)
    }

    private func deleteRoutine(_ id: UUID, _ run: PullRun) throws {
        guard let routine = try context.fetchRoutine(id: id), routine.isSyncable else { return }
        guard decide(.routines, id, aggregate: .init(.routine, id: id), model: routine, run) else { return }
        // Its sessions keep their rows without it, as on the server (`ON DELETE SET NULL`).
        context.delete(routine)
    }

    /// The server only deletes an exercise nothing of it uses. One the device
    /// still uses (a workout in progress, a session not sent yet) cannot go:
    /// it is kept and marked changed, so the push writes it back first.
    private func deleteExercise(_ id: UUID, _ run: PullRun) throws {
        guard let exercise = try context.fetchExercise(id: id), exercise.isSyncable, !exercise.isCatalogue else {
            return
        }
        // Rows this pull deleted still list the exercise until the save. A
        // session's entries leave their own tombstones; a routine's items do
        // only when deleted on their own.
        let inUse = exercise.entries.contains { !run.deletes(.entries, $0.id) }
            || exercise.routineItems.contains {
                !run.deletes(.routines, $0.routine?.id) && !run.removedItems.contains($0.persistentModelID)
            }
        if inUse {
            exercise.markChanged()
            return run.report.skip(.exercises, id, .conflict("the device still uses it, so it is sent again"))
        }
        guard decide(.exercises, id, aggregate: .init(.exercise, id: id), model: exercise, run) else { return }
        // The server deletes the exercise's settings with it.
        for setting in try context.fetch(FetchDescriptor<ExerciseSettingModel>(
            predicate: #Predicate { $0.exerciseId == id }
        )) {
            context.delete(setting)
        }
        context.delete(exercise)
    }

    /// Reports the conflict rule's decision; `true` when the row goes.
    private func decide(
        _ table: RemoteTable,
        _ id: UUID,
        aggregate: SyncAggregateRef,
        model: any SyncTrackedModel,
        _ run: PullRun
    ) -> Bool {
        report(table, id, rule: run.rule(for: aggregate, model: model, change: .deleted), run)
    }

    /// Reports the deletion's rule; `true` when the row goes.
    private func report(_ table: RemoteTable, _ id: UUID, rule: SyncConflictRule, _ run: PullRun) -> Bool {
        run.report.deletions.append(.init(table: table, id: id, rule: rule))
        if rule == .serverApplied { run.markDeleted(table, id) }
        return rule == .serverApplied
    }
}
