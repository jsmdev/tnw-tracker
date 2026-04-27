import Foundation
import SwiftData

@Model public final class RestTimer {
    @Attribute(.unique) public var id: UUID
    public var workoutId: UUID
    public var timerTypeRaw: String
    public var durationSeconds: Int
    public var startedAt: Date
    public var endsAt: Date
    public var isActive: Bool
    public var pendingSyncOp: String?
    public var remoteUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public var timerType: TimerType {
        get { TimerType(rawValue: timerTypeRaw) ?? .betweenSets }
        set { timerTypeRaw = newValue.rawValue }
    }

    public init(workoutId: UUID, type: TimerType, durationSeconds: Int) {
        id = UUID()
        self.workoutId = workoutId
        timerTypeRaw = type.rawValue
        self.durationSeconds = durationSeconds
        startedAt = Date()
        endsAt = Date().addingTimeInterval(TimeInterval(durationSeconds))
        isActive = true
        createdAt = Date()
        updatedAt = Date()
    }
}
