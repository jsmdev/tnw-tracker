import Foundation
import SwiftData

@Model public final class PlanRoutine {
    @Attribute(.unique) public var id: UUID
    public var planId: UUID
    public var routineId: UUID
    public var orderIndex: Int
    public var pendingSyncOp: String?
    public var remoteUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(planId: UUID, routineId: UUID, orderIndex: Int) {
        id = UUID()
        self.planId = planId
        self.routineId = routineId
        self.orderIndex = orderIndex
        createdAt = Date()
        updatedAt = Date()
    }
}
