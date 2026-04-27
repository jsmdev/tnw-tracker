import Foundation
import SwiftData

@Model public final class ExerciseSet {
    @Attribute(.unique) public var id: UUID
    public var workoutExerciseId: UUID
    public var setNumber: Int
    public var reps: Int?
    public var weight: Double?
    public var weightUnitRaw: String
    public var rpe: Int?
    public var notes: String?
    public var isWarmup: Bool
    public var completedAt: Date?
    public var isPersonalRecord: Bool
    public var pendingSyncOp: String?
    public var remoteUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public var weightUnit: WeightUnit {
        get { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
        set { weightUnitRaw = newValue.rawValue }
    }

    public func validateRPE() -> Bool {
        guard let rpe else { return true }
        return (1 ... 10).contains(rpe)
    }

    public init(workoutExerciseId: UUID, setNumber: Int) {
        id = UUID()
        self.workoutExerciseId = workoutExerciseId
        self.setNumber = setNumber
        weightUnitRaw = WeightUnit.kg.rawValue
        isWarmup = false
        isPersonalRecord = false
        createdAt = Date()
        updatedAt = Date()
    }
}
