import Foundation
import SwiftData

/// SwiftData adapter of the per-exercise settings.
@MainActor
final class SwiftDataExerciseSettingRepository: ExerciseSettingRepositoryProtocol {
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

    func setting(exerciseId: UUID) throws -> ExerciseSetting? {
        try fetch(exerciseId: exerciseId).map {
            ExerciseSetting(exerciseId: $0.exerciseId, restEnabled: $0.restEnabled, restSeconds: $0.restSeconds)
        }
    }

    func save(_ setting: ExerciseSetting) throws {
        guard setting.restSeconds >= 0 else {
            throw TrainingDataError.invalidExercise("rest seconds must not be negative")
        }
        guard try context.fetchExercise(id: setting.exerciseId) != nil else {
            throw TrainingDataError.notFound
        }
        if let model = try fetch(exerciseId: setting.exerciseId) {
            model.restEnabled = setting.restEnabled
            model.restSeconds = setting.restSeconds
            model.markChanged()
        } else {
            let model = ExerciseSettingModel(
                exerciseId: setting.exerciseId,
                restEnabled: setting.restEnabled,
                restSeconds: setting.restSeconds
            )
            context.insert(model)
            // The user's setting, also on a catalogue exercise.
            try context.trackNew(model)
        }
        try context.saveUserChange(gate)
    }

    private func fetch(exerciseId: UUID) throws -> ExerciseSettingModel? {
        var descriptor = FetchDescriptor<ExerciseSettingModel>(predicate: #Predicate { $0.exerciseId == exerciseId })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
