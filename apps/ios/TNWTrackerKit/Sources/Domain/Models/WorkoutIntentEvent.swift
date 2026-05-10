import Foundation
import SwiftData

/// Persistent mailbox event written by an AppIntent in the widget process.
/// Consumed by the app process via Darwin notification drain.
/// kind values: "skip" | "pause" | "resume" | "end"
@Model public final class WorkoutIntentEvent {
    @Attribute(.unique) public var id: UUID
    public var workoutId: UUID
    public var kind: String
    public var createdAt: Date
    public var consumedAt: Date?

    public init(workoutId: UUID, kind: String) {
        id = UUID()
        self.workoutId = workoutId
        self.kind = kind
        createdAt = Date()
        consumedAt = nil
    }
}
