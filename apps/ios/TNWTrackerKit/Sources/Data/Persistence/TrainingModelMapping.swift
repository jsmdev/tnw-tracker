import Foundation

// Conversions between the `@Model` rows and the value snapshots.

extension ExerciseModel {
    var snapshot: Exercise {
        let instructions = ExerciseInstructions(
            setup: instructionsSetup ?? [],
            execution: instructionsExecution ?? [],
            tips: instructionsTips ?? []
        )
        let media = ExerciseMedia(imageURI: mediaImageURI, videoURI: mediaVideoURI)
        return Exercise(
            id: id,
            externalRef: externalRef(provider: externalProvider, id: externalId),
            isCatalogue: isCatalogue,
            name: name,
            type: ExerciseType(rawValue: typeRaw) ?? .strength,
            equipment: equipmentRaw.flatMap(Equipment.init(rawValue:)),
            muscleGroups: MuscleGroupModel.inOrder(muscleGroups).compactMap(\.snapshot),
            instructions: instructions.isEmpty ? nil : instructions,
            media: media.isEmpty ? nil : media,
            relatedLinks: relatedLinks
        )
    }

    /// The stored related links; `nil` when there are none. Setting `nil` or an
    /// empty list clears them.
    var relatedLinks: [RelatedLink]? {
        get {
            relatedVideosData.flatMap { try? JSONDecoder().decode([RelatedLink].self, from: $0) }
        }
        set {
            relatedVideosData = newValue.flatMap { $0.isEmpty ? nil : try? JSONEncoder().encode($0) }
        }
    }
}

extension MuscleGroupModel {
    /// The exercise's list order: by position, then by the server row's id, so
    /// rows the server holds at the same position (the seed writes none) keep
    /// the server's id order on every device.
    static func inOrder(_ groups: [MuscleGroupModel]) -> [MuscleGroupModel] {
        groups.sorted { lhs, rhs in
            lhs.position == rhs.position
                ? (lhs.serverId?.uuidString ?? "") < (rhs.serverId?.uuidString ?? "")
                : lhs.position < rhs.position
        }
    }

    var snapshot: MuscleGroup? {
        guard let muscle = Muscle(rawValue: muscleRaw), let role = MuscleRole(rawValue: roleRaw) else { return nil }
        return MuscleGroup(muscle: muscle, role: role)
    }
}

extension RoutineModel {
    var snapshot: Routine {
        Routine(
            id: id,
            externalRef: externalRef(provider: externalProvider, id: externalId),
            name: name,
            description: routineDescription,
            items: items.sorted { $0.order < $1.order }.compactMap(\.snapshot),
            isFavorite: isFavorite
        )
    }
}

extension RoutineItemModel {
    var snapshot: RoutineItem? {
        guard let exerciseId = exercise?.id else { return nil }
        let reps: RepRange? = if let targetRepsMin, let targetRepsMax {
            RepRange(min: targetRepsMin, max: targetRepsMax)
        } else {
            nil
        }
        return RoutineItem(
            order: order,
            exerciseId: exerciseId,
            targetSets: targetSets,
            targetReps: reps,
            targetWeight: weight(value: targetWeightValue, unitRaw: targetWeightUnitRaw),
            targetDurationSeconds: targetDurationSeconds,
            restSeconds: restSeconds,
            notes: notes
        )
    }
}

extension SessionModel {
    var snapshot: TrainingSession {
        TrainingSession(
            id: id,
            externalRef: externalRef(provider: externalProvider, id: externalId),
            name: name,
            notes: notes,
            startedAt: startedAt,
            completedAt: completedAt,
            timeZone: timeZone,
            durationSeconds: durationSeconds,
            routineId: routine?.id,
            entries: entries.sorted { $0.order < $1.order }.compactMap(\.snapshot)
        )
    }
}

extension SessionEntryModel {
    var snapshot: SessionEntry? {
        guard let exerciseId = exercise?.id else { return nil }
        let ordered = sets.sorted { lhs, rhs in
            lhs.sourceRaw == rhs.sourceRaw ? lhs.order < rhs.order : lhs.sourceRaw == SetSource.manual.rawValue
        }
        return SessionEntry(
            id: id,
            externalRef: externalRef(provider: externalProvider, id: externalId),
            exerciseId: exerciseId,
            order: order,
            status: EntryStatus(rawValue: statusRaw) ?? .done,
            replacedExerciseId: replacedExercise?.id,
            completedAt: completedAt,
            sets: ordered.map(\.snapshot),
            reconciliation: reconciliation,
            notes: notes
        )
    }

    /// The stored reconciliation decision, if any.
    var reconciliation: Reconciliation? {
        guard let keep = reconciliationKeepRaw.flatMap(SetSource.init(rawValue:)) else { return nil }
        return Reconciliation(
            keep: keep,
            decidedBy: reconciliationDecidedByRaw.flatMap(ReconciliationDecider.init(rawValue:)) ?? .default,
            decidedAt: reconciliationDecidedAt
        )
    }

    var hasBothSources: Bool {
        let sources = Set(sets.map(\.sourceRaw))
        return sources.contains(SetSource.manual.rawValue) && sources.contains(SetSource.imported.rawValue)
    }

    /// Records the decision and marks every set of the source not kept as superseded.
    func setReconciliation(keep: SetSource, decidedBy: ReconciliationDecider, at date: Date) {
        reconciliationKeepRaw = keep.rawValue
        reconciliationDecidedByRaw = decidedBy.rawValue
        reconciliationDecidedAt = date
        for set in sets {
            set.superseded = set.sourceRaw != keep.rawValue
        }
    }

    /// An entry back to a single source has no reconciliation and nothing superseded.
    func clearReconciliation() {
        reconciliationKeepRaw = nil
        reconciliationDecidedByRaw = nil
        reconciliationDecidedAt = nil
        for set in sets {
            set.superseded = false
        }
    }
}

extension ExerciseSetModel {
    var snapshot: ExerciseSet {
        ExerciseSet(
            id: id,
            order: order,
            source: SetSource(rawValue: sourceRaw) ?? .manual,
            externalRef: externalRef(provider: externalProvider, id: externalId),
            values: SetValues(
                reps: reps,
                weight: weight(value: weightValue, unitRaw: weightUnitRaw),
                durationSeconds: durationSeconds,
                distanceMeters: distanceMeters,
                rir: rir,
                restSeconds: restSeconds
            ),
            completedAt: completedAt,
            superseded: superseded,
            warmup: warmup
        )
    }

    func apply(_ values: SetValues) {
        reps = values.reps
        weightValue = values.weight?.value
        weightUnitRaw = values.weight?.unit.rawValue
        durationSeconds = values.durationSeconds
        distanceMeters = values.distanceMeters
        rir = values.rir
        restSeconds = values.restSeconds
    }
}

private func externalRef(provider: String?, id: String?) -> ExternalRef? {
    guard let provider, let id else { return nil }
    return ExternalRef(provider: provider, id: id)
}

private func weight(value: Double?, unitRaw: String?) -> Weight? {
    guard let value, let unit = unitRaw.flatMap(WeightUnit.init(rawValue:)) else { return nil }
    return Weight(value: value, unit: unit)
}
