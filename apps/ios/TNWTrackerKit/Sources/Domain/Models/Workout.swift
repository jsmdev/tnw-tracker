import Foundation
import SwiftData

@Model public final class Workout {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var sessionId: UUID?
    public var name: String
    public var statusRaw: String
    public var startedAt: Date
    public var completedAt: Date?
    public var durationSeconds: Int?
    public var notes: String?
    public var pendingSyncOp: String?
    public var remoteUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    @Relationship(deleteRule: .cascade) public var workoutExercises: [WorkoutExercise]

    public var status: WorkoutStatus {
        get { WorkoutStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    public init(userId: UUID, name: String) {
        id = UUID()
        self.userId = userId
        self.name = name
        statusRaw = WorkoutStatus.active.rawValue
        startedAt = Date()
        workoutExercises = []
        createdAt = Date()
        updatedAt = Date()
    }
}
