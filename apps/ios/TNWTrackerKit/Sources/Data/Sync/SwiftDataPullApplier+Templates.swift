import Foundation
import SwiftData

// Exercises, their muscle groups, routines and their items, and exercise
// settings, as the pull applies them. An exercise, a routine or a setting is
// one aggregate: with a local change waiting, none of its own server values is
// applied. Its muscle groups or items are decided as one list, apart from it
// (`PullRun.childRule`): the server's list applies unless the device's list
// changed since the server last held it, so a favourite or a rename waiting
// here does not hold back items another device added (L12). Every field the
// push sends is applied, muscle order included. Rows
// the server deleted, children included, go with its tombstones
// (`SwiftDataPullApplier+Tombstones.swift`). A child row keeps the id the
// server holds it under (`serverId`), so its tombstone finds it even when
// another client wrote it under an id of its own.

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
        for row in batch.exerciseSettings {
            try applySetting(row, run)
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
        run.create(aggregate, list: model)
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
        // The server holds the curated list; `null` there means none.
        model.relatedVideos = row.relatedVideos
        model.externalProvider = row.externalRef?.provider
        model.externalId = row.externalRef?.id
    }

    /// The muscle takes the server's position (from 1 on the server, from 0 on
    /// the device); one the exercise does not list yet is added. A muscle-group
    /// row names no owner, so it is applied only under a catalogue exercise or
    /// one of the user's own that the server holds (S10), never under data
    /// that never leaves the device.
    private func applyMuscleGroup(_ row: RemoteMuscleGroupRow, _ run: PullRun) throws {
        guard let exercise = try context.fetchExercise(id: row.exerciseId) else {
            return run.hold(.exerciseMuscleGroups, row.id)
        }
        guard exercise.isCatalogue || exercise.isSyncable else {
            return run.report.skip(.exerciseMuscleGroups, row.id, .invalid("its exercise is not the user's"))
        }
        if !exercise.isCatalogue, run.childRule(for: .init(.exercise, id: exercise.id), model: exercise) == .localKept {
            return
        }
        let group = exercise.muscleGroups.first {
            $0.muscleRaw == row.muscle.rawValue && $0.roleRaw == row.role.rawValue
        } ?? {
            let group = MuscleGroupModel(muscleRaw: row.muscle.rawValue, roleRaw: row.role.rawValue, position: 0)
            context.insert(group)
            exercise.muscleGroups.append(group)
            return group
        }()
        group.position = row.position - 1
        group.serverId = row.id
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
        run.create(aggregate, list: model)
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
        guard run.childRule(for: .init(.routine, id: routine.id), model: routine) == .serverApplied else { return }
        let item = routine.items.first { $0.order == row.position } ?? {
            let item = RoutineItemModel(order: row.position)
            context.insert(item)
            routine.items.append(item)
            return item
        }()
        item.serverId = row.id
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

    // MARK: - Exercise settings

    /// A setting of an exercise the device does not hold waits for it, unless
    /// the device deleted that exercise (its deletion goes up next push).
    private func applySetting(_ row: RemoteExerciseSettingRow, _ run: PullRun) throws {
        guard try context.fetchExercise(id: row.exerciseId) != nil else {
            if try hasTombstone(.exercise, row.exerciseId) {
                return run.report.skip(.exerciseSettings, row.id, .deletedOnDevice)
            }
            return run.hold(.exerciseSettings, row.id)
        }
        let aggregate = SyncAggregateRef(.exerciseSetting, id: row.exerciseId)
        if let model = try context.fetchExerciseSetting(exerciseId: row.exerciseId) {
            if run.rule(for: aggregate, model: model) == .serverApplied {
                model.restEnabled = row.restEnabled
                model.restSeconds = row.restSeconds
            }
            return
        }
        let model = ExerciseSettingModel(
            exerciseId: row.exerciseId, restEnabled: row.restEnabled, restSeconds: row.restSeconds
        )
        context.insert(model)
        model.markPulled()
        run.create(aggregate)
    }
}
