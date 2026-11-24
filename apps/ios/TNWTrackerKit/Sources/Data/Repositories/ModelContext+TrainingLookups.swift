import Foundation
import SwiftData

// Lookups shared by the SwiftData training adapters, the importer and the widget.

extension ModelContext {
    /// The routine "Próxima sesión" proposes (`NextRoutineRule`). Shared by the
    /// routine repository (Home) and `NextSessionQuery` (widget).
    func nextRoutine() throws -> RoutineModel? {
        let models = try fetch(FetchDescriptor<RoutineModel>())
        let candidates = models.map { model in
            NextRoutineRule.Candidate(
                id: model.id,
                name: model.name,
                isFavorite: model.isFavorite,
                lastCompletedAt: model.sessions.compactMap(\.completedAt).max()
            )
        }
        guard let id = NextRoutineRule.next(among: candidates) else { return nil }
        return models.first { $0.id == id }
    }

    func fetchExercise(id: UUID) throws -> ExerciseModel? {
        var descriptor = FetchDescriptor<ExerciseModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func fetchExercise(ref: ExternalRef) throws -> ExerciseModel? {
        let provider: String? = ref.provider
        let externalId: String? = ref.id
        var descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate { $0.externalProvider == provider && $0.externalId == externalId }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    /// An exercise without provider data, matched by its name and type.
    func fetchExerciseWithoutRef(name: String, typeRaw: String) throws -> ExerciseModel? {
        var descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate { $0.externalProvider == nil && $0.name == name && $0.typeRaw == typeRaw }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func fetchSession(ref: ExternalRef) throws -> SessionModel? {
        let provider: String? = ref.provider
        let externalId: String? = ref.id
        var descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.externalProvider == provider && $0.externalId == externalId }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func fetchRoutine(id: UUID) throws -> RoutineModel? {
        var descriptor = FetchDescriptor<RoutineModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func fetchRoutine(ref: ExternalRef) throws -> RoutineModel? {
        let provider: String? = ref.provider
        let externalId: String? = ref.id
        var descriptor = FetchDescriptor<RoutineModel>(
            predicate: #Predicate { $0.externalProvider == provider && $0.externalId == externalId }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func fetchSession(id: UUID) throws -> SessionModel? {
        var descriptor = FetchDescriptor<SessionModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    /// The entry an external entry ref was merged into.
    func fetchEntry(ref: ExternalRef) throws -> SessionEntryModel? {
        let provider = ref.provider
        let externalId = ref.id
        var descriptor = FetchDescriptor<EntryExternalRefModel>(
            predicate: #Predicate { $0.provider == provider && $0.externalId == externalId }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first?.entry
    }

    func fetchSet(ref: ExternalRef) throws -> ExerciseSetModel? {
        let provider: String? = ref.provider
        let externalId: String? = ref.id
        var descriptor = FetchDescriptor<ExerciseSetModel>(
            predicate: #Predicate { $0.externalProvider == provider && $0.externalId == externalId }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    /// The user's setting of an exercise, keyed by the exercise id.
    func fetchExerciseSetting(exerciseId: UUID) throws -> ExerciseSettingModel? {
        var descriptor = FetchDescriptor<ExerciseSettingModel>(predicate: #Predicate { $0.exerciseId == exerciseId })
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    /// A personal link of an exercise, by its id.
    func fetchExerciseLink(id: UUID) throws -> ExerciseLinkModel? {
        var descriptor = FetchDescriptor<ExerciseLinkModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    /// The personal links of an exercise, unordered.
    func fetchExerciseLinks(exerciseId: UUID) throws -> [ExerciseLinkModel] {
        try fetch(FetchDescriptor<ExerciseLinkModel>(predicate: #Predicate { $0.exerciseId == exerciseId }))
    }
}
