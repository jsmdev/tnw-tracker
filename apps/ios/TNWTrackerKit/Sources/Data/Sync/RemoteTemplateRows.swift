import CryptoKit
import Foundation

// Rows of the exercise and routine tables, with the same encoding rules as
// `RemoteRows.swift`: every column the client owns is written, `null` included,
// and `created_at`/`updated_at` are never sent. The columns the app only reads
// (`related_links`) are never sent either, so an upsert keeps them.

// MARK: - exercises

public struct RemoteExerciseRow: RemoteRow {
    public static let table = RemoteTable.exercises

    public var id: UUID
    /// `nil` for a catalogue exercise, which the app reads but never writes.
    public var userId: UUID?
    public var name: String
    public var type: ExerciseType
    public var equipment: Equipment?
    /// `nil`, never empty: the server refuses an empty array.
    public var setupSteps: [String]?
    public var executionSteps: [String]?
    public var tips: [String]?
    public var imageURI: String?
    public var videoURI: String?
    /// Curated on the server (format 1.2): read, never sent.
    public var relatedLinks: [RelatedLink]?
    public var externalRef: ExternalRef?
    public var updatedAt: String?

    public init(
        id: UUID,
        userId: UUID?,
        name: String,
        type: ExerciseType,
        equipment: Equipment? = nil,
        setupSteps: [String]? = nil,
        executionSteps: [String]? = nil,
        tips: [String]? = nil,
        imageURI: String? = nil,
        videoURI: String? = nil,
        externalRef: ExternalRef? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.type = type
        self.equipment = equipment
        self.setupSteps = setupSteps
        self.executionSteps = executionSteps
        self.tips = tips
        self.imageURI = imageURI
        self.videoURI = videoURI
        self.externalRef = externalRef
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name, type, equipment
        case setupSteps = "setup_steps"
        case executionSteps = "execution_steps"
        case tips
        case imageURI = "image_uri"
        case videoURI = "video_uri"
        case relatedLinks = "related_links"
        case updatedAt = "updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        userId = try values.decodeIfPresent(UUID.self, forKey: .userId)
        name = try values.decode(String.self, forKey: .name)
        type = try values.decode(ExerciseType.self, forKey: .type)
        equipment = try values.decodeIfPresent(Equipment.self, forKey: .equipment)
        setupSteps = try values.decodeIfPresent([String].self, forKey: .setupSteps)
        executionSteps = try values.decodeIfPresent([String].self, forKey: .executionSteps)
        tips = try values.decodeIfPresent([String].self, forKey: .tips)
        imageURI = try values.decodeIfPresent(String.self, forKey: .imageURI)
        videoURI = try values.decodeIfPresent(String.self, forKey: .videoURI)
        relatedLinks = try values.decodeIfPresent([RelatedLink].self, forKey: .relatedLinks)
        externalRef = try ExternalRefColumns.decode(from: decoder)
        updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(userId, forKey: .userId)
        try values.encode(name, forKey: .name)
        try values.encode(type, forKey: .type)
        try values.encode(equipment, forKey: .equipment)
        try values.encode(setupSteps, forKey: .setupSteps)
        try values.encode(executionSteps, forKey: .executionSteps)
        try values.encode(tips, forKey: .tips)
        try values.encode(imageURI, forKey: .imageURI)
        try values.encode(videoURI, forKey: .videoURI)
        try ExternalRefColumns.encode(externalRef, to: encoder)
    }
}

// MARK: - exercise_muscle_groups

/// One muscle of an exercise. The table has no `user_id`: it follows its exercise.
public struct RemoteMuscleGroupRow: RemoteRow {
    public static let table = RemoteTable.exerciseMuscleGroups

    public var id: UUID
    public var exerciseId: UUID
    public var muscle: Muscle
    public var role: MuscleRole
    /// Order of the muscle in its exercise, from 1.
    public var position: Int
    public var updatedAt: String?

    public init(
        id: UUID,
        exerciseId: UUID,
        muscle: Muscle,
        role: MuscleRole,
        position: Int = 1,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.muscle = muscle
        self.role = role
        self.position = position
        self.updatedAt = updatedAt
    }

    /// The device keeps no id for a muscle group it created, so its row id is
    /// derived from its natural key (`exercise_muscle_groups_key`): pushing the
    /// same exercise again updates the same rows instead of colliding with them.
    public init(exerciseId: UUID, muscle: Muscle, role: MuscleRole, position: Int = 1) {
        self.init(
            id: Self.id(exerciseId: exerciseId, muscle: muscle.rawValue, role: role.rawValue),
            exerciseId: exerciseId,
            muscle: muscle,
            role: role,
            position: position
        )
    }

    /// The derived row id of a muscle group the device created.
    public static func id(exerciseId: UUID, muscle: String, role: String) -> UUID {
        .derived(from: exerciseId, key: "muscle-group/\(muscle)/\(role)")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case exerciseId = "exercise_id"
        case muscle, role, position
        case updatedAt = "updated_at"
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(exerciseId, forKey: .exerciseId)
        try values.encode(muscle, forKey: .muscle)
        try values.encode(role, forKey: .role)
        try values.encode(position, forKey: .position)
    }
}

// MARK: - routines

public struct RemoteRoutineRow: RemoteRow {
    public static let table = RemoteTable.routines

    public var id: UUID
    public var userId: UUID
    public var name: String
    public var description: String?
    public var isFavorite: Bool
    public var externalRef: ExternalRef?
    public var updatedAt: String?

    public init(
        id: UUID,
        userId: UUID,
        name: String,
        description: String? = nil,
        isFavorite: Bool = false,
        externalRef: ExternalRef? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.description = description
        self.isFavorite = isFavorite
        self.externalRef = externalRef
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name, description
        case isFavorite = "is_favorite"
        case updatedAt = "updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        userId = try values.decode(UUID.self, forKey: .userId)
        name = try values.decode(String.self, forKey: .name)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        isFavorite = try values.decode(Bool.self, forKey: .isFavorite)
        externalRef = try ExternalRefColumns.decode(from: decoder)
        updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(userId, forKey: .userId)
        try values.encode(name, forKey: .name)
        try values.encode(description, forKey: .description)
        try values.encode(isFavorite, forKey: .isFavorite)
        try ExternalRefColumns.encode(externalRef, to: encoder)
    }
}

// MARK: - routine_items

public struct RemoteRoutineItemRow: RemoteRow {
    public static let table = RemoteTable.routineItems

    public var id: UUID
    public var userId: UUID
    public var routineId: UUID
    public var position: Int
    public var exerciseId: UUID
    public var targetSets: Int?
    public var targetReps: RepRange?
    public var targetWeight: Weight?
    public var targetDurationSeconds: Int?
    public var restSeconds: Int?
    public var notes: String?
    public var updatedAt: String?

    public init(
        id: UUID,
        userId: UUID,
        routineId: UUID,
        position: Int,
        exerciseId: UUID,
        targetSets: Int? = nil,
        targetReps: RepRange? = nil,
        targetWeight: Weight? = nil,
        targetDurationSeconds: Int? = nil,
        restSeconds: Int? = nil,
        notes: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.routineId = routineId
        self.position = position
        self.exerciseId = exerciseId
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetDurationSeconds = targetDurationSeconds
        self.restSeconds = restSeconds
        self.notes = notes
        self.updatedAt = updatedAt
    }

    /// The device keeps no id for a routine item, so its row id is derived from
    /// its natural key (`routine_items_position_key`): the item at a position
    /// keeps its row when the routine is pushed again.
    public static func id(routineId: UUID, position: Int) -> UUID {
        .derived(from: routineId, key: "routine-item/\(position)")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case routineId = "routine_id"
        case position
        case exerciseId = "exercise_id"
        case targetSets = "target_sets"
        case targetRepsMin = "target_reps_min"
        case targetRepsMax = "target_reps_max"
        case targetWeight = "target_weight"
        case targetWeightUnit = "target_weight_unit"
        case targetDurationSeconds = "target_duration_seconds"
        case restSeconds = "rest_seconds"
        case notes
        case updatedAt = "updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        userId = try values.decode(UUID.self, forKey: .userId)
        routineId = try values.decode(UUID.self, forKey: .routineId)
        position = try values.decode(Int.self, forKey: .position)
        exerciseId = try values.decode(UUID.self, forKey: .exerciseId)
        targetSets = try values.decodeIfPresent(Int.self, forKey: .targetSets)
        if let min = try values.decodeIfPresent(Int.self, forKey: .targetRepsMin),
           let max = try values.decodeIfPresent(Int.self, forKey: .targetRepsMax) {
            targetReps = RepRange(min: min, max: max)
        } else {
            targetReps = nil
        }
        if let value = try values.decodeIfPresent(Double.self, forKey: .targetWeight) {
            targetWeight = try Weight(value: value, unit: values.decode(WeightUnit.self, forKey: .targetWeightUnit))
        } else {
            targetWeight = nil
        }
        targetDurationSeconds = try values.decodeIfPresent(Int.self, forKey: .targetDurationSeconds)
        restSeconds = try values.decodeIfPresent(Int.self, forKey: .restSeconds)
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(userId, forKey: .userId)
        try values.encode(routineId, forKey: .routineId)
        try values.encode(position, forKey: .position)
        try values.encode(exerciseId, forKey: .exerciseId)
        try values.encode(targetSets, forKey: .targetSets)
        try values.encode(targetReps?.min, forKey: .targetRepsMin)
        try values.encode(targetReps?.max, forKey: .targetRepsMax)
        try values.encode(targetWeight?.value, forKey: .targetWeight)
        try values.encode(targetWeight?.unit, forKey: .targetWeightUnit)
        try values.encode(targetDurationSeconds, forKey: .targetDurationSeconds)
        try values.encode(restSeconds, forKey: .restSeconds)
        try values.encode(notes, forKey: .notes)
    }
}

// MARK: - Derived ids

extension UUID {
    /// A stable UUID (version 5 layout) for a child row the device keeps no id
    /// for: the same parent and key always give the same id.
    static func derived(from parent: UUID, key: String) -> UUID {
        var data = withUnsafeBytes(of: parent.uuid) { Data($0) }
        data.append(Data(key.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
