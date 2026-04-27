import Foundation

public struct WorkoutExerciseDTO: Codable, Sendable {
    public let id: UUID
    public let workoutId: UUID
    public let exerciseId: UUID
    public let orderIndex: Int
    public let notes: String?
    public let status: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        workoutId: UUID,
        exerciseId: UUID,
        orderIndex: Int,
        notes: String?,
        status: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.workoutId = workoutId
        self.exerciseId = exerciseId
        self.orderIndex = orderIndex
        self.notes = notes
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, notes, status
        case workoutId = "workout_id"
        case exerciseId = "exercise_id"
        case orderIndex = "order_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public extension WorkoutExerciseDTO {
    func toModel() -> WorkoutExercise {
        let we = WorkoutExercise(workoutId: workoutId, exerciseId: exerciseId, orderIndex: orderIndex)
        we.id = id
        we.notes = notes
        we.statusRaw = status
        we.remoteUpdatedAt = updatedAt
        return we
    }
}

public extension WorkoutExercise {
    func toDTO() -> WorkoutExerciseDTO {
        WorkoutExerciseDTO(
            id: id,
            workoutId: workoutId,
            exerciseId: exerciseId,
            orderIndex: orderIndex,
            notes: notes,
            status: statusRaw,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
