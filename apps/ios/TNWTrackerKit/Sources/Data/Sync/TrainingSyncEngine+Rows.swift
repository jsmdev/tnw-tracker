import Foundation

/// Turns local aggregates into the rows the server stores, every column the
/// server has, owned by `userId`. Reads only; it never changes the store.
@MainActor
struct PushRows {
    let userId: UUID
    /// True when the aggregate was acknowledged earlier in the same push.
    let acknowledgedNow: (SyncAggregateRef) -> Bool

    // MARK: - Aggregates

    func exercise(_ model: ExerciseModel) -> TrainingSyncEngine.Upload {
        let exercise = model.snapshot
        let row = RemoteExerciseRow(
            id: exercise.id,
            userId: userId,
            name: exercise.name,
            type: exercise.type,
            equipment: exercise.equipment,
            setupSteps: Self.steps(exercise.instructions?.setup),
            executionSteps: Self.steps(exercise.instructions?.execution),
            tips: Self.steps(exercise.instructions?.tips),
            imageURI: exercise.media?.imageURI,
            videoURI: exercise.media?.videoURI,
            externalRef: exercise.externalRef
        )
        // In the snapshot's order, numbered from 1, under the id the server holds them by.
        let groups = MuscleGroupModel.inOrder(model.muscleGroups)
            .compactMap { group in group.snapshot.map { (id: group.rowId(exerciseId: exercise.id), value: $0) } }
        let muscles = groups.enumerated().map { index, group in
            RemoteMuscleGroupRow(
                id: group.id, exerciseId: exercise.id, muscle: group.value.muscle, role: group.value.role,
                position: index + 1
            )
        }
        // An unchanged list stays as the server holds it, children another device added included (L12).
        let children = model.childListChanged ? model.childrenFingerprint : nil
        return .send({ remote in
            try await remote.upsert([row])
            guard children != nil else { return }
            // The server then holds exactly the device's list (L7): the others go
            // first, so a row another client wrote under its own id for the same
            // muscle cannot collide with the device's.
            try await remote.deleteChildren(.exerciseMuscleGroups, of: exercise.id, keeping: muscles.map(\.id))
            try await remote.upsert(muscles)
        }, children: children)
    }

    func routine(_ model: RoutineModel) -> TrainingSyncEngine.Upload {
        for item in model.items {
            // Without its exercise the item would be left out, and the push
            // would delete its row on the server.
            guard let exercise = item.exercise else { return .skip(.incomplete) }
            if let reason = missingOnServer(exercise) { return .skip(reason) }
        }
        let routine = model.snapshot
        let rowIds = Dictionary(
            model.items.map { ($0.order, $0.rowId(routineId: routine.id)) }, uniquingKeysWith: { first, _ in first }
        )
        let row = RemoteRoutineRow(
            id: routine.id,
            userId: userId,
            name: routine.name,
            description: routine.description,
            isFavorite: routine.isFavorite,
            externalRef: routine.externalRef
        )
        let items = routine.items.map { item in
            RemoteRoutineItemRow(
                id: rowIds[item.order] ?? RemoteRoutineItemRow.id(routineId: routine.id, position: item.order),
                userId: userId,
                routineId: routine.id,
                position: item.order,
                exerciseId: item.exerciseId,
                targetSets: item.targetSets,
                targetReps: item.targetReps,
                targetWeight: item.targetWeight,
                targetDurationSeconds: item.targetDurationSeconds,
                restSeconds: item.restSeconds,
                notes: item.notes
            )
        }
        let children = model.childListChanged ? model.childrenFingerprint : nil
        return .send({ remote in
            try await remote.upsert([row])
            guard children != nil else { return }
            // Items at positions the routine no longer has go first (L7), as for muscle groups.
            try await remote.deleteChildren(.routineItems, of: routine.id, keeping: items.map(\.id))
            try await remote.upsert(items)
        }, children: children)
    }

    /// A setting goes up once its exercise is on the server (catalogue ones are).
    func setting(_ model: ExerciseSettingModel, exercise: ExerciseModel?) -> TrainingSyncEngine.Upload {
        guard let exercise else { return .skip(.incomplete) }
        if let reason = missingOnServer(exercise) { return .skip(reason) }
        let row = RemoteExerciseSettingRow(
            exerciseId: model.exerciseId,
            userId: userId,
            restEnabled: model.restEnabled,
            restSeconds: model.restSeconds
        )
        return .send { remote in
            try await remote.upsert([row])
        }
    }

    /// `pending` carries the entries and sets removed since the last acknowledged push.
    func session(_ model: SessionModel, completedAt: Date, pending: PendingSyncAggregate) -> TrainingSyncEngine.Upload {
        if let reason = model.routine.flatMap(missingOnServer) { return .skip(reason) }
        for entry in model.entries {
            // The store keeps an entry's exercise (delete rule `deny`); without
            // it the session would go out incomplete.
            guard let exercise = entry.exercise else { return .skip(.incomplete) }
            if let reason = missingOnServer(exercise) ?? entry.replacedExercise.flatMap(missingOnServer) {
                return .skip(reason)
            }
        }
        var rows = sessionAggregate(model.snapshot, completedAt: completedAt)
        rows.removedEntryIds = pending.removedEntryIds
        rows.removedSetIds = pending.removedSetIds
        let aggregate = rows
        return .send { remote in
            try await remote.pushSession(aggregate)
        }
    }

    // MARK: - Prerequisites

    /// Why a session or routine cannot refer to `exercise` on the server yet, if it cannot.
    private func missingOnServer(_ exercise: ExerciseModel) -> SyncSkipReason? {
        exercise.isCatalogue ? nil : missingOnServer(exercise, ref: .init(.exercise, id: exercise.id))
    }

    private func missingOnServer(_ routine: RoutineModel) -> SyncSkipReason? {
        missingOnServer(routine, ref: .init(.routine, id: routine.id))
    }

    /// A syncable aggregate is on the server once a push of it was acknowledged.
    private func missingOnServer(_ model: any SyncTrackedModel, ref: SyncAggregateRef) -> SyncSkipReason? {
        guard model.isSyncable else { return .usesLocalOnlyData(ref) }
        return model.syncedRevision > 0 || acknowledgedNow(ref) ? nil : .waitsFor(ref)
    }

    // MARK: - Session rows

    /// The rows of a completed session, as the server stores them. The pull
    /// compares them with what it read to tell an echo from a local difference.
    func sessionAggregate(_ session: TrainingSession, completedAt: Date) -> RemoteSessionAggregate {
        let row = RemoteSessionRow(
            id: session.id,
            userId: userId,
            routineId: session.routineId,
            name: session.name,
            notes: session.notes,
            startedAt: session.startedAt,
            completedAt: completedAt,
            timeZone: session.timeZone,
            durationSeconds: session.durationSeconds,
            externalRef: session.externalRef
        )
        let entries = session.entries.map { entry in
            RemoteEntryRow(
                id: entry.id,
                userId: userId,
                sessionId: session.id,
                position: entry.order,
                exerciseId: entry.exerciseId,
                status: entry.status,
                replacedExerciseId: entry.replacedExerciseId,
                completedAt: entry.completedAt,
                notes: entry.notes,
                reconciliationKeep: entry.reconciliation?.keep,
                reconciliationDecidedBy: entry.reconciliation?.decidedBy,
                reconciliationDecidedAt: entry.reconciliation?.decidedAt,
                externalRef: entry.externalRef
            )
        }
        let sets = session.entries.flatMap { entry in
            entry.sets.map { set in
                RemoteSetRow(
                    id: set.id,
                    userId: userId,
                    entryId: entry.id,
                    position: set.order,
                    source: set.source,
                    reps: set.values.reps,
                    weight: set.values.weight,
                    durationSeconds: set.values.durationSeconds,
                    distanceMeters: set.values.distanceMeters,
                    rir: set.values.rir,
                    restSeconds: set.values.restSeconds,
                    completedAt: set.completedAt,
                    superseded: set.superseded,
                    warmup: set.warmup,
                    externalRef: set.externalRef
                )
            }
        }
        return RemoteSessionAggregate(session: row, entries: entries, sets: sets)
    }

    /// The server refuses an empty step list: none is `nil`.
    private static func steps(_ steps: [String]?) -> [String]? {
        steps.flatMap { $0.isEmpty ? nil : $0 }
    }
}

// MARK: - Child row ids

extension MuscleGroupModel {
    /// The id of this muscle group's row on the server: the one the pull brought
    /// it under, else the one derived from its natural key.
    func rowId(exerciseId: UUID) -> UUID {
        serverId ?? RemoteMuscleGroupRow.id(exerciseId: exerciseId, muscle: muscleRaw, role: roleRaw)
    }

    var rowId: UUID? {
        exercise.map { rowId(exerciseId: $0.id) }
    }
}

extension RoutineItemModel {
    /// The id of this item's row on the server: the one the pull brought it
    /// under, else the one derived from its routine and position.
    func rowId(routineId: UUID) -> UUID {
        serverId ?? RemoteRoutineItemRow.id(routineId: routineId, position: order)
    }

    var rowId: UUID? {
        routine.map { rowId(routineId: $0.id) }
    }
}
