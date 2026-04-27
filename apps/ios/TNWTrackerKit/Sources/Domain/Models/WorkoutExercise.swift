import Foundation
import SwiftData

@Model public final class WorkoutExercise {
    @Attribute(.unique) public var id: UUID
    public var workoutId: UUID
    public var exerciseId: UUID
    public var orderIndex: Int
    public var notes: String?
    public var statusRaw: String
    public var pendingSyncOp: String?
    public var remoteUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    @Relationship(deleteRule: .cascade) public var exerciseSets: [ExerciseSet]

    public init(workoutId: UUID, exerciseId: UUID, orderIndex: Int) {
        id = UUID()
        self.workoutId = workoutId
        self.exerciseId = exerciseId
        self.orderIndex = orderIndex
        statusRaw = "pending"
        exerciseSets = []
        createdAt = Date()
        updatedAt = Date()
    }
}
