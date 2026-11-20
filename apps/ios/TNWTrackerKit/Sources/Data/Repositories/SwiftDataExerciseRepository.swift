import Foundation
import SwiftData

// SwiftData adapter of the exercise repository; see docs/training-data-format.md.

@MainActor
final class SwiftDataExerciseRepository: ExerciseRepositoryProtocol {
    private let context: ModelContext
    /// The context does not keep its container alive; the adapter does.
    private let container: ModelContainer

    init(context: ModelContext) {
        self.context = context
        container = context.container
    }

    func exercises() throws -> [Exercise] {
        try context.fetch(FetchDescriptor<ExerciseModel>(sortBy: [SortDescriptor(\.name)])).map(\.snapshot)
    }

    func exercise(id: UUID) throws -> Exercise? {
        try context.fetchExercise(id: id)?.snapshot
    }

    func save(_ exercise: Exercise) throws {
        try write(exercise)
        try context.save()
    }

    /// Validates and writes the exercise without saving the context.
    func write(_ exercise: Exercise) throws {
        try Self.validate(exercise)
        if let ref = exercise.externalRef,
           let owner = try context.fetchExercise(ref: ref), owner.id != exercise.id {
            throw TrainingDataError.duplicateExternalRef
        }
        let model = try context.fetchExercise(id: exercise.id)
            ?? ExerciseModel(id: exercise.id, name: exercise.name, typeRaw: exercise.type.rawValue)
        if model.modelContext == nil {
            context.insert(model)
            // A catalogue exercise is shared app data, never the user's to upload (S9).
            try context.trackNew(model, syncable: !exercise.isCatalogue)
        } else {
            model.markChanged()
        }

        model.name = exercise.name
        model.typeRaw = exercise.type.rawValue
        model.externalProvider = exercise.externalRef?.provider
        model.externalId = exercise.externalRef?.id
        model.isCatalogue = exercise.isCatalogue
        model.equipmentRaw = exercise.equipment?.rawValue
        let instructions = exercise.instructions.flatMap { $0.isEmpty ? nil : $0 }
        model.instructionsSetup = instructions.map(\.setup).flatMap { $0.isEmpty ? nil : $0 }
        model.instructionsExecution = instructions.map(\.execution).flatMap { $0.isEmpty ? nil : $0 }
        model.instructionsTips = instructions.map(\.tips).flatMap { $0.isEmpty ? nil : $0 }
        model.mediaImageURI = exercise.media?.imageURI
        model.mediaVideoURI = exercise.media?.videoURI

        for old in model.muscleGroups {
            context.delete(old)
        }
        model.muscleGroups = []
        for (position, group) in exercise.muscleGroups.enumerated() {
            let row = MuscleGroupModel(
                muscleRaw: group.muscle.rawValue,
                roleRaw: group.role.rawValue,
                position: position
            )
            context.insert(row)
            model.muscleGroups.append(row)
        }
    }

    /// Field rules of the format's `exercise` that a JSON Schema states.
    static func validate(_ exercise: Exercise) throws {
        guard !exercise.name.isEmpty else { throw TrainingDataError.invalidExercise("name is empty") }
        if let ref = exercise.externalRef, !ref.isValid { throw TrainingDataError.invalidExternalRef }
        if exercise.isCatalogue, exercise.externalRef != nil {
            throw TrainingDataError.invalidExercise("a catalogue exercise has no externalRef")
        }
        guard Set(exercise.muscleGroups).count == exercise.muscleGroups.count else {
            throw TrainingDataError.invalidExercise("muscle groups must be unique")
        }
        if let media = exercise.media, media.imageURI == "" || media.videoURI == "" {
            throw TrainingDataError.invalidExercise("a media uri is empty")
        }
        if let steps = exercise.instructions, (steps.setup + steps.execution + steps.tips).contains(where: \.isEmpty) {
            throw TrainingDataError.invalidExercise("an instruction step is empty")
        }
    }
}
