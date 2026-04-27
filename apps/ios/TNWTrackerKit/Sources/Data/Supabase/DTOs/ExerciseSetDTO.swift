import Foundation

public struct ExerciseSetDTO: Codable, Sendable {
    public let id: UUID
    public let workoutExerciseId: UUID
    public let setNumber: Int
    public let reps: Int?
    public let weight: Double?
    public let weightUnit: String
    public let rpe: Int?
    public let notes: String?
    public let isWarmup: Bool
    public let completedAt: Date?
    public let isPersonalRecord: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        workoutExerciseId: UUID,
        setNumber: Int,
        reps: Int?,
        weight: Double?,
        weightUnit: String,
        rpe: Int?,
        notes: String?,
        isWarmup: Bool,
        completedAt: Date?,
        isPersonalRecord: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.workoutExerciseId = workoutExerciseId
        self.setNumber = setNumber
        self.reps = reps
        self.weight = weight
        self.weightUnit = weightUnit
        self.rpe = rpe
        self.notes = notes
        self.isWarmup = isWarmup
        self.completedAt = completedAt
        self.isPersonalRecord = isPersonalRecord
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, reps, weight, rpe, notes
        case workoutExerciseId = "workout_exercise_id"
        case setNumber = "set_number"
        case weightUnit = "weight_unit"
        case isWarmup = "is_warmup"
        case completedAt = "completed_at"
        case isPersonalRecord = "is_personal_record"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public extension ExerciseSetDTO {
    func toModel() -> ExerciseSet {
        let exerciseSet = ExerciseSet(workoutExerciseId: workoutExerciseId, setNumber: setNumber)
        exerciseSet.id = id
        exerciseSet.reps = reps
        exerciseSet.weight = weight
        exerciseSet.weightUnitRaw = weightUnit
        exerciseSet.rpe = rpe
        exerciseSet.notes = notes
        exerciseSet.isWarmup = isWarmup
        exerciseSet.completedAt = completedAt
        exerciseSet.isPersonalRecord = isPersonalRecord
        exerciseSet.remoteUpdatedAt = updatedAt
        return exerciseSet
    }
}

public extension ExerciseSet {
    func toDTO() -> ExerciseSetDTO {
        ExerciseSetDTO(
            id: id,
            workoutExerciseId: workoutExerciseId,
            setNumber: setNumber,
            reps: reps,
            weight: weight,
            weightUnit: weightUnitRaw,
            rpe: rpe,
            notes: notes,
            isWarmup: isWarmup,
            completedAt: completedAt,
            isPersonalRecord: isPersonalRecord,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
