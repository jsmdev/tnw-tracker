import Foundation
import SwiftData

// SwiftData adapter of the routine repository; see docs/training-data-format.md.

@MainActor
final class SwiftDataRoutineRepository: RoutineRepositoryProtocol {
    private let context: ModelContext
    /// The context does not keep its container alive; the adapter does.
    private let container: ModelContainer

    /// Refuses the user's writes while the store is not theirs (S10).
    private let gate: UserWriteGate

    init(context: ModelContext, gate: UserWriteGate = UserWriteGate()) {
        self.context = context
        container = context.container
        self.gate = gate
    }

    func routines(_ query: RoutineQuery) throws -> [Routine] {
        var descriptor = FetchDescriptor<RoutineModel>(sortBy: [SortDescriptor(\.name)])
        if !query.search.isEmpty {
            let search = query.search
            descriptor.predicate = #Predicate { $0.name.localizedStandardContains(search) }
        }
        var models = try context.fetch(descriptor)
        if query.onlyPerformed {
            models = models.filter { routine in routine.sessions.contains { $0.completedAt != nil } }
        }
        // Favourites first, each group keeping the name order (AC5.1). A `Bool`
        // is not a sort key for SwiftData, so the partition happens here, before paging.
        models = models.filter(\.isFavorite) + models.filter { !$0.isFavorite }
        let page = models.dropFirst(query.offset).prefix(query.limit ?? Int.max)
        return page.map(\.snapshot)
    }

    func routine(id: UUID) throws -> Routine? {
        try context.fetchRoutine(id: id)?.snapshot
    }

    func nextRoutine() throws -> Routine? {
        try context.nextRoutine()?.snapshot
    }

    func setFavorite(_ favorite: Bool, routineId: UUID) throws {
        guard let model = try context.fetchRoutine(id: routineId) else { throw TrainingDataError.notFound }
        model.isFavorite = favorite
        model.markChanged()
        try context.saveUserChange(gate)
    }

    func save(_ routine: Routine) throws {
        try write(routine)
        try context.saveUserChange(gate)
    }

    /// Validates and writes the routine without saving the context.
    func write(_ routine: Routine) throws {
        try Self.validate(routine)
        if let ref = routine.externalRef,
           let owner = try context.fetchRoutine(ref: ref), owner.id != routine.id {
            throw TrainingDataError.duplicateExternalRef
        }
        var exercises: [UUID: ExerciseModel] = [:]
        for item in routine.items {
            try Self.validateTargets(of: item)
            guard let exercise = try context.fetchExercise(id: item.exerciseId) else {
                throw TrainingDataError.invalidRoutine("unknown exercise \(item.exerciseId)")
            }
            exercises[item.exerciseId] = exercise
        }

        let model = try context.fetchRoutine(id: routine.id)
            ?? RoutineModel(id: routine.id, name: routine.name)
        if model.modelContext == nil {
            context.insert(model)
            try context.trackNew(model)
        } else {
            model.markChanged()
        }
        model.name = routine.name
        model.routineDescription = routine.description
        model.externalProvider = routine.externalRef?.provider
        model.externalId = routine.externalRef?.id

        for old in model.items {
            context.delete(old)
        }
        model.items = []
        for item in routine.items.sorted(by: { $0.order < $1.order }) {
            let row = RoutineItemModel(order: item.order)
            context.insert(row)
            row.exercise = exercises[item.exerciseId]
            row.targetSets = item.targetSets
            row.targetRepsMin = item.targetReps?.min
            row.targetRepsMax = item.targetReps?.max
            row.targetWeightValue = item.targetWeight?.value
            row.targetWeightUnitRaw = item.targetWeight?.unit.rawValue
            row.targetDurationSeconds = item.targetDurationSeconds
            row.restSeconds = item.restSeconds
            row.notes = item.notes
            model.items.append(row)
        }
    }

    /// Field rules of the format's `routine` that do not need the store.
    private static func validate(_ routine: Routine) throws {
        guard !routine.name.isEmpty else { throw TrainingDataError.invalidRoutine("name is empty") }
        guard !routine.items.isEmpty else {
            throw TrainingDataError.invalidRoutine("a routine needs at least one item")
        }
        let orders = routine.items.map(\.order)
        guard orders.allSatisfy({ $0 >= 1 }), Set(orders).count == orders.count else {
            throw TrainingDataError.invalidRoutine("item positions must be unique and start at 1")
        }
        if let ref = routine.externalRef, !ref.isValid { throw TrainingDataError.invalidExternalRef }
    }

    /// Field rules of a routine item's targets.
    private static func validateTargets(of item: RoutineItem) throws {
        if let range = item.targetReps, range.min < 1 || range.min > range.max {
            throw TrainingDataError.invalidRoutine("targetReps needs 1 ≤ min ≤ max")
        }
        if let sets = item.targetSets, sets < 1 {
            throw TrainingDataError.invalidRoutine("targetSets must be at least 1")
        }
        if [item.targetDurationSeconds, item.restSeconds].contains(where: { ($0 ?? 0) < 0 }) {
            throw TrainingDataError.invalidRoutine("durations must not be negative")
        }
        if let weight = item.targetWeight, weight.value < 0 {
            throw TrainingDataError.invalidRoutine("targetWeight must not be negative")
        }
    }
}
