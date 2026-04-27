import Foundation
import SwiftData

@Model public final class RoutineSession {
    @Attribute(.unique) public var id: UUID
    public var routineId: UUID
    public var sessionId: UUID
    public var orderIndex: Int
    public var pendingSyncOp: String?
    public var remoteUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(routineId: UUID, sessionId: UUID, orderIndex: Int) {
        id = UUID()
        self.routineId = routineId
        self.sessionId = sessionId
        self.orderIndex = orderIndex
        createdAt = Date()
        updatedAt = Date()
    }
}
