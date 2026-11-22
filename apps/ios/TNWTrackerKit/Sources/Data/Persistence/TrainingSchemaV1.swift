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
            ExerciseSettingModel.self,
            WorkoutIntentEvent.self,
            StoreOwnerModel.self,
            SyncTombstoneModel.self,
            SyncCursorModel.self
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
    /// `relatedVideos` (format 1.1) as JSON, `nil` when none; optional, so it migrates lightly.
    var relatedVideosData: Data?

    // Sync state (app-local, see `ModelContext+SyncTracking.swift`): the revision
    // grows with every local change, `syncedRevision` is the last one the server
    // acknowledged, `syncSent` means it may exist on the server, and
    // `isSyncable` (fixed at creation) keeps unowned and catalogue data local.
    // None of them is user data: changing them never raises the revision.
    var syncRevision: Int = 0
    var syncedRevision: Int = 0
    var syncSent: Bool = false
    var isSyncable: Bool = false
    /// Pushes the server refused since the last acknowledged one, and why the last did.
    var syncFailureCount: Int = 0
    var syncLastError: String?
    /// The muscle groups as the server last held them for this device (app-local,
    /// see `Data/Sync/SyncChildList.swift`); `nil` before the first sync.
    var syncedChildrenFingerprint: String?

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
    /// The server row's id when the pull brought this muscle group (app-local):
    /// another client may have written it under its own id. `nil` for one the
    /// device wrote, whose row id is derived from its natural key.
    var serverId: UUID?

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
    /// The user's favourite mark (app state, synced as `routines.is_favorite`).
    /// Not part of the training data format: imports never change it.
    var isFavorite: Bool = false

    // Sync state (app-local, see `ModelContext+SyncTracking.swift`): the revision
    // grows with every local change, `syncedRevision` is the last one the server
    // acknowledged, `syncSent` means it may exist on the server, and
    // `isSyncable` (fixed at creation) keeps unowned and catalogue data local.
    // None of them is user data: changing them never raises the revision.
    var syncRevision: Int = 0
    var syncedRevision: Int = 0
    var syncSent: Bool = false
    var isSyncable: Bool = false
    /// Pushes the server refused since the last acknowledged one, and why the last did.
    var syncFailureCount: Int = 0
    var syncLastError: String?
    /// The items as the server last held them for this device (app-local, see
    /// `Data/Sync/SyncChildList.swift`); `nil` before the first sync.
    var syncedChildrenFingerprint: String?

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
    /// The server row's id when the pull brought this item (app-local): another
    /// client may have written it under its own id. `nil` for one the device
    /// wrote, whose row id is derived from its routine and position.
    var serverId: UUID?
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

    // Sync state (app-local, see `ModelContext+SyncTracking.swift`): the revision
    // grows with every local change, `syncedRevision` is the last one the server
    // acknowledged, `syncSent` means it may exist on the server, and
    // `isSyncable` (fixed at creation) keeps unowned and catalogue data local.
    // None of them is user data: changing them never raises the revision.
    var syncRevision: Int = 0
    var syncedRevision: Int = 0
    var syncSent: Bool = false
    var isSyncable: Bool = false
    /// Pushes the server refused since the last acknowledged one, and why the last did.
    var syncFailureCount: Int = 0
    var syncLastError: String?

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
    /// The row was part of a session sent to the server (app-local).
    var syncSent: Bool = false

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
    /// The row was part of a session sent to the server (app-local).
    var syncSent: Bool = false

    init(id: UUID, order: Int, sourceRaw: String) {
        self.id = id
        self.order = order
        self.sourceRaw = sourceRaw
    }
}

// MARK: - App-local settings

/// The user's settings for one exercise (app-local, not in the training data
/// format). Keyed by the exercise id; it outlives no exercise, see
/// `TrainingStore.deleteAllTrainingData`.
@Model final class ExerciseSettingModel {
    @Attribute(.unique) var exerciseId: UUID
    var restEnabled: Bool = true
    var restSeconds: Int

    // Sync state (app-local, see `ModelContext+SyncTracking.swift`): the revision
    // grows with every local change, `syncedRevision` is the last one the server
    // acknowledged, `syncSent` means it may exist on the server, and
    // `isSyncable` (fixed at creation) keeps unowned and catalogue data local.
    // None of them is user data: changing them never raises the revision.
    var syncRevision: Int = 0
    var syncedRevision: Int = 0
    var syncSent: Bool = false
    var isSyncable: Bool = false
    /// Pushes the server refused since the last acknowledged one, and why the last did.
    var syncFailureCount: Int = 0
    var syncLastError: String?

    init(exerciseId: UUID, restEnabled: Bool, restSeconds: Int) {
        self.exerciseId = exerciseId
        self.restEnabled = restEnabled
        self.restSeconds = restSeconds
    }
}

// MARK: - Sync (app-local)

/// The user the store's user data belongs to (S10). At most one row.
@Model final class StoreOwnerModel {
    @Attribute(.unique) var userId: UUID
    var claimedAt: Date

    init(userId: UUID, claimedAt: Date) {
        self.userId = userId
        self.claimedAt = claimedAt
    }
}

/// A row deleted on the device that may exist on the server (S11). A set or
/// entry tombstone belongs to the session it was removed from (`sessionId`)
/// and travels with that session's push; the others are propagated on their own.
@Model final class SyncTombstoneModel {
    #Index<SyncTombstoneModel>([\.sessionId], [\.kindRaw, \.rowId])

    var kindRaw: String
    var rowId: UUID
    var sessionId: UUID?
    /// Revision of the owning aggregate when the row was removed.
    var revision: Int
    var deletedAt: Date

    init(kindRaw: String, rowId: UUID, sessionId: UUID?, revision: Int, deletedAt: Date) {
        self.kindRaw = kindRaw
        self.rowId = rowId
        self.sessionId = sessionId
        self.revision = revision
        self.deletedAt = deletedAt
    }
}

/// Where the pull of one server table stopped, for one user: the (`updated_at`,
/// `id`) of the last row applied. It lives in the store, so a store reset
/// (`TrainingStore.deleteAllTrainingData`) starts the pull again from the start.
@Model final class SyncCursorModel {
    /// `<user id>/<table>`, one cursor per user and table.
    @Attribute(.unique) var key: String
    var userId: UUID
    var tableRaw: String
    /// `updated_at` exactly as the server wrote it.
    var updatedAt: String
    var rowId: UUID

    init(userId: UUID, table: RemoteTable, cursor: RemoteCursor) {
        key = Self.key(userId: userId, table: table)
        self.userId = userId
        tableRaw = table.rawValue
        updatedAt = cursor.updatedAt
        rowId = cursor.id
    }

    static func key(userId: UUID, table: RemoteTable) -> String {
        "\(userId.uuidString.lowercased())/\(table.rawValue)"
    }
}
