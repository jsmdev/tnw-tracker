import Foundation
import SwiftData

@Model public final class SessionExercise {
    @Attribute(.unique) public var id: UUID
    public var sessionId: UUID
    public var exerciseId: UUID
    public var orderIndex: Int
    public var targetSets: Int?
    public var targetReps: Int?
    public var targetWeight: Double?
    public var restBetweenSetsSeconds: Int?
    public var notes: String?
    public var pendingSyncOp: String?
    public var remoteUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(sessionId: UUID, exerciseId: UUID, orderIndex: Int) {
        id = UUID()
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.orderIndex = orderIndex
        createdAt = Date()
        updatedAt = Date()
    }
}
