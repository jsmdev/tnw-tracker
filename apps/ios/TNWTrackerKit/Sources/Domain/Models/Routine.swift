import Foundation
import SwiftData

@Model public final class Routine {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var name: String
    public var routineDescription: String?
    public var isActive: Bool
    public var isPublic: Bool
    public var pendingSyncOp: String?
    public var remoteUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    @Relationship(deleteRule: .cascade) public var routineSessions: [RoutineSession]

    public init(userId: UUID, name: String) {
        id = UUID()
        self.userId = userId
        self.name = name
        isActive = true
        isPublic = false
        routineSessions = []
        createdAt = Date()
        updatedAt = Date()
    }
}
