import Foundation
import SwiftData

// Persistence model for the training data format 1.0 (docs/training-data-format.md).
//
// Rules for this file:
// - Every stored name follows the format field in camelCase. Deviations are
//   listed in odd/tasks/ios-data-model.md ("format field → Swift model.property").
// - Enumerations are stored as their raw format strings, so predicates stay safe.
// - `externalRef` is flattened to `externalProvider` + `externalId` so the
//   re-import upsert can look it up in a predicate.
// - These types are internal: only the repositories in this module touch them.
//
// A future version copies the models into `TrainingSchemaV2` and adds a stage
// to `TrainingMigrationPlan`.

public enum TrainingSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            ExerciseModel.self,
            MuscleGroupModel.self,
            RoutineModel.self,
            RoutineItemModel.self,
            SessionModel.self,
            SessionEntryModel.self,
            EntryExternalRefModel.self,
            ExerciseSetModel.self,
            WorkoutIntentEvent.self
        ]
    }
}

public enum TrainingMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [TrainingSchemaV1.self]
    }

    /// Empty until a second schema version exists.
    public static var stages: [MigrationStage] {
        []
    }
}

// MARK: - Exercise

@Model final class ExerciseModel {
    #Index<ExerciseModel>([\.name], [\.externalProvider, \.externalId])

    @Attribute(.unique) var id: UUID
    var externalProvider: String?
    var externalId: String?
    /// Curated app exercise shared with every user; never has an external ref.
    var isCatalogue: Bool = false
    var name: String
    var typeRaw: String
    var equipmentRaw: String?
    var instructionsSetup: [String]?
    var instructionsExecution: [String]?
    var instructionsTips: [String]?
    var mediaImageURI: String?
    var mediaVideoURI: String?

    @Relationship(deleteRule: .cascade, inverse: \MuscleGroupModel.exercise)
    var muscleGroups: [MuscleGroupModel] = []

    @Relationship(deleteRule: .deny, inverse: \RoutineItemModel.exercise)
    var routineItems: [RoutineItemModel] = []

    @Relationship(deleteRule: .deny, inverse: \SessionEntryModel.exercise)
    var entries: [SessionEntryModel] = []

    @Relationship(deleteRule: .nullify, inverse: \SessionEntryModel.replacedExercise)
    var replacedInEntries: [SessionEntryModel] = []

    init(id: UUID, name: String, typeRaw: String) {
        self.id = id
        self.name = name
        self.typeRaw = typeRaw
    }
}

/// Format type `{ muscle, role }`, one row per muscle of an exercise.
@Model final class MuscleGroupModel {
    var muscleRaw: String
    var roleRaw: String
    /// Keeps the list order of the source.
    var position: Int
    var exercise: ExerciseModel?

    init(muscleRaw: String, roleRaw: String, position: Int) {
        self.muscleRaw = muscleRaw
        self.roleRaw = roleRaw
        self.position = position
    }
}

// MARK: - Routine

@Model final class RoutineModel {
    #Index<RoutineModel>([\.name], [\.externalProvider, \.externalId])

    @Attribute(.unique) var id: UUID
    var externalProvider: String?
    var externalId: String?
    var name: String
    /// Format field `routine.description` (`description` is reserved in `@Model`).
    var routineDescription: String?

    @Relationship(deleteRule: .cascade, inverse: \RoutineItemModel.routine)
    var items: [RoutineItemModel] = []

    @Relationship(deleteRule: .nullify, inverse: \SessionModel.routine)
    var sessions: [SessionModel] = []

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

@Model final class RoutineItemModel {
    var order: Int
    var exercise: ExerciseModel?
    var routine: RoutineModel?
    var targetSets: Int?
    var targetRepsMin: Int?
    var targetRepsMax: Int?
    var targetWeightValue: Double?
    var targetWeightUnitRaw: String?
    var targetDurationSeconds: Int?
    var restSeconds: Int?
    var notes: String?

    init(order: Int) {
        self.order = order
    }
}

// MARK: - Session

@Model final class SessionModel {
    #Index<SessionModel>([\.completedAt], [\.externalProvider, \.externalId])

    @Attribute(.unique) var id: UUID
    var externalProvider: String?
    var externalId: String?
    var name: String?
    var notes: String?
    var startedAt: Date?
    /// `nil` while the session is in progress in the app (app-local state).
    var completedAt: Date?
    /// IANA identifier. Format field `session.timeZone`.
    var timeZone: String
    var durationSeconds: Int?
    var routine: RoutineModel?

    @Relationship(deleteRule: .cascade, inverse: \SessionEntryModel.session)
    var entries: [SessionEntryModel] = []

    init(id: UUID, timeZone: String) {
        self.id = id
        self.timeZone = timeZone
    }
}

@Model final class SessionEntryModel {
    #Index<SessionEntryModel>([\.externalProvider, \.externalId])

    @Attribute(.unique) var id: UUID
    var externalProvider: String?
    var externalId: String?
    var exercise: ExerciseModel?
    var replacedExercise: ExerciseModel?
    var order: Int
    var statusRaw: String
    var completedAt: Date?
    var notes: String?
    /// Format field `reconciliation.keep`; `nil` means no reconciliation object.
    var reconciliationKeepRaw: String?
    var reconciliationDecidedByRaw: String?
    var reconciliationDecidedAt: Date?
    var session: SessionModel?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSetModel.entry)
    var sets: [ExerciseSetModel] = []

    /// Every external entry merged into this one (app-local). The first is also
    /// `externalProvider`/`externalId`, the entry's format `externalRef`.
    @Relationship(deleteRule: .cascade, inverse: \EntryExternalRefModel.entry)
    var mergedRefs: [EntryExternalRefModel] = []

    init(id: UUID, order: Int, statusRaw: String) {
        self.id = id
        self.order = order
        self.statusRaw = statusRaw
    }
}

/// One external entry identity merged into a session entry (app-local).
/// When imports bring several provider entries for one exercise in one session,
/// they merge into a single entry (one entry per exercise), and this keeps every
/// one of their refs so a re-import or a duplicate is still recognised.
@Model final class EntryExternalRefModel {
    #Index<EntryExternalRefModel>([\.provider, \.externalId])

    var provider: String
    var externalId: String
    var entry: SessionEntryModel?

    init(provider: String, externalId: String) {
        self.provider = provider
        self.externalId = externalId
    }
}

@Model final class ExerciseSetModel {
    #Index<ExerciseSetModel>([\.externalProvider, \.externalId])

    @Attribute(.unique) var id: UUID
    var externalProvider: String?
    var externalId: String?
    var order: Int
    var sourceRaw: String
    var reps: Int?
    var durationSeconds: Int?
    var distanceMeters: Double?
    var weightValue: Double?
    var weightUnitRaw: String?
    var rir: Int?
    var restSeconds: Int?
    var completedAt: Date?
    var superseded: Bool = false
    /// Format field `warmup`; the user's annotation on an imported set.
    var warmup: Bool = false
    var entry: SessionEntryModel?

    init(id: UUID, order: Int, sourceRaw: String) {
        self.id = id
        self.order = order
        self.sourceRaw = sourceRaw
    }
}
