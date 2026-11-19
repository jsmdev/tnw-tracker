import Foundation
import SwiftData

// Exercises, their muscle groups, routines and their items, as the pull applies
// them. An exercise or routine is one aggregate: with a local change waiting,
// none of its server values is applied. Exercises and routines the server
// deleted go with its tombstones (`SwiftDataPullApplier+Tombstones.swift`);
// muscle groups and routine items it no longer lists are not removed here (T6).

extension SwiftDataPullApplier {
    func applyTemplates(_ batch: PulledBatch, _ run: PullRun) throws {
        for row in batch.exercises {
            try applyExercise(row, run)
        }
        for row in batch.muscleGroups {
            try applyMuscleGroup(row, run)
        }
        for row in batch.routines {
            try applyRoutine(row, run)
        }
        for row in batch.routineItems {
            try applyRoutineItem(row, run)
        }
    }

    // MARK: - Exercises

    private func applyExercise(_ row: RemoteExerciseRow, _ run: PullRun) throws {
        guard row.userId != nil else { return try applyCatalogue(row) }
        let aggregate = SyncAggregateRef(.exercise, id: row.id)
        if let model = try context.fetchExercise(id: row.id) ?? adoptExercise(row, run) {
            if run.rule(for: aggregate, model: model) == .serverApplied { write(row, to: model) }
            return
        }
        if try hasTombstone(.exercise, row.id) { return run.report.skip(.exercises, row.id, .deletedOnDevice) }
        let model = ExerciseModel(id: row.id, name: row.name, typeRaw: row.type.rawValue)
        context.insert(model)
        write(row, to: model)
        model.markPulled()
        run.create(aggregate)
    }

    /// The curated catalogue belongs to the server: always applied, never synced back.
    private func applyCatalogue(_ row: RemoteExerciseRow) throws {
        let model = try context.fetchExercise(id: row.id) ?? {
            let model = ExerciseModel(id: row.id, name: row.name, typeRaw: row.type.rawValue)
            context.insert(model)
            return model
        }()
        write(row, to: model)
        model.isCatalogue = true
    }

    private func adoptExercise(_ row: RemoteExerciseRow, _ run: PullRun) throws -> ExerciseModel? {
        guard let ref = row.externalRef, let local = try context.fetchExercise(ref: ref),
              local.isSyncable, !local.isCatalogue
        else { return nil }
        // The server holds the ref under its own id, so the local row never reached it.
        run.adopt(.exercises, localId: local.id, serverId: row.id)
        local.id = row.id
        local.syncSent = true
        return local
    }

    private func write(_ row: RemoteExerciseRow, to model: ExerciseModel) {
        model.name = row.name
        model.typeRaw = row.type.rawValue
        model.equipmentRaw = row.equipment?.rawValue
        model.instructionsSetup = row.setupSteps
        model.instructionsExecution = row.executionSteps
        model.instructionsTips = row.tips
        model.mediaImageURI = row.imageURI
        model.mediaVideoURI = row.videoURI
        model.externalProvider = row.externalRef?.provider
        model.externalId = row.externalRef?.id
    }

    /// A muscle the exercise does not list yet is added after the others.
    private func applyMuscleGroup(_ row: RemoteMuscleGroupRow, _ run: PullRun) throws {
        guard let exercise = try context.fetchExercise(id: row.exerciseId) else {
            return run.hold(.exerciseMuscleGroups, row.id)
        }
        if !exercise.isCatalogue, run.rule(for: .init(.exercise, id: exercise.id), model: exercise) == .localKept {
            return
        }
        let known = exercise.muscleGroups.contains {
            $0.muscleRaw == row.muscle.rawValue && $0.roleRaw == row.role.rawValue
        }
        guard !known else { return }
        let group = MuscleGroupModel(
            muscleRaw: row.muscle.rawValue,
            roleRaw: row.role.rawValue,
            position: (exercise.muscleGroups.map(\.position).max() ?? -1) + 1
        )
        context.insert(group)
        exercise.muscleGroups.append(group)
    }

    // MARK: - Routines

    private func applyRoutine(_ row: RemoteRoutineRow, _ run: PullRun) throws {
        let aggregate = SyncAggregateRef(.routine, id: row.id)
        if let model = try context.fetchRoutine(id: row.id) ?? adoptRoutine(row, run) {
            if run.rule(for: aggregate, model: model) == .serverApplied { write(row, to: model) }
            return
        }
        if try hasTombstone(.routine, row.id) { return run.report.skip(.routines, row.id, .deletedOnDevice) }
        let model = RoutineModel(id: row.id, name: row.name)
        context.insert(model)
        write(row, to: model)
        model.markPulled()
        run.create(aggregate)
    }

    private func adoptRoutine(_ row: RemoteRoutineRow, _ run: PullRun) throws -> RoutineModel? {
        guard let ref = row.externalRef, let local = try context.fetchRoutine(ref: ref), local.isSyncable else {
            return nil
        }
        run.adopt(.routines, localId: local.id, serverId: row.id)
        local.id = row.id
        local.syncSent = true
        return local
    }

    private func write(_ row: RemoteRoutineRow, to model: RoutineModel) {
        model.name = row.name
        model.routineDescription = row.description
        model.isFavorite = row.isFavorite
        model.externalProvider = row.externalRef?.provider
        model.externalId = row.externalRef?.id
    }

    /// The item at the row's position is updated, or added.
    private func applyRoutineItem(_ row: RemoteRoutineItemRow, _ run: PullRun) throws {
        guard let routine = try context.fetchRoutine(id: row.routineId),
              let exercise = try context.fetchExercise(id: row.exerciseId)
        else { return run.hold(.routineItems, row.id) }
        guard run.rule(for: .init(.routine, id: routine.id), model: routine) == .serverApplied else { return }
        let item = routine.items.first { $0.order == row.position } ?? {
            let item = RoutineItemModel(order: row.position)
            context.insert(item)
            routine.items.append(item)
            return item
        }()
        item.exercise = exercise
        item.targetSets = row.targetSets
        item.targetRepsMin = row.targetReps?.min
        item.targetRepsMax = row.targetReps?.max
        item.targetWeightValue = row.targetWeight?.value
        item.targetWeightUnitRaw = row.targetWeight?.unit.rawValue
        item.targetDurationSeconds = row.targetDurationSeconds
        item.restSeconds = row.restSeconds
        item.notes = row.notes
    }
}
