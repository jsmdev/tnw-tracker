import Foundation
import SwiftData

@Model public final class Session {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var name: String
    public var sessionDescription: String?
    public var restBetweenExercisesSeconds: Int?
    public var isPublic: Bool
    public var pendingSyncOp: String?
    public var remoteUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    @Relationship(deleteRule: .cascade) public var sessionExercises: [SessionExercise]

    public init(userId: UUID, name: String) {
        id = UUID()
        self.userId = userId
        self.name = name
        isPublic = false
        sessionExercises = []
        createdAt = Date()
        updatedAt = Date()
    }
}
