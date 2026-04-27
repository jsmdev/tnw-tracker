import Foundation
import SwiftData

@Model public final class User {
    @Attribute(.unique) public var id: UUID
    public var email: String
    public var weightUnitRaw: String
    public var timerTriggerModeRaw: String
    public var pendingSyncOp: String?
    public var remoteUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public var weightUnit: WeightUnit {
        get { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
        set { weightUnitRaw = newValue.rawValue }
    }

    public init(id: UUID, email: String) {
        self.id = id
        self.email = email
        weightUnitRaw = WeightUnit.kg.rawValue
        timerTriggerModeRaw = "auto"
        createdAt = Date()
        updatedAt = Date()
    }
}
