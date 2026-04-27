import Foundation
import SwiftData

@Model public final class PersonalRecord {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var exerciseId: UUID
    public var recordTypeRaw: String
    public var value: Double
    public var weightUnitRaw: String
    public var achievedAt: Date
    public var exerciseSetId: UUID?
    public var pendingSyncOp: String?
    public var remoteUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public var recordType: PRRecordType {
        get { PRRecordType(rawValue: recordTypeRaw) ?? .maxWeight }
        set { recordTypeRaw = newValue.rawValue }
    }

    public init(userId: UUID, exerciseId: UUID, type: PRRecordType, value: Double) {
        id = UUID()
        self.userId = userId
        self.exerciseId = exerciseId
        recordTypeRaw = type.rawValue
        self.value = value
        weightUnitRaw = WeightUnit.kg.rawValue
        achievedAt = Date()
        createdAt = Date()
        updatedAt = Date()
    }
}
