import Foundation

/// One completed session of an exercise's history (fast-add-exercise S6).
public struct ExerciseHistoryItem: Hashable, Sendable, Identifiable {
    public var sessionId: UUID
    public var sessionName: String?
    public var completedAt: Date
    /// The counted sets (no warm-ups, no superseded sets), in the order they were done.
    public var sets: [SetValues]

    public var id: UUID {
        sessionId
    }

    public init(sessionId: UUID, sessionName: String?, completedAt: Date, sets: [SetValues]) {
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.completedAt = completedAt
        self.sets = sets
    }

    /// The best set of `items`: the heaviest, then the one with most reps.
    /// Nil when no set has a weight.
    public static func best(in items: [ExerciseHistoryItem]) -> SetValues? {
        items.flatMap(\.sets)
            .filter { ($0.weight?.kilograms ?? 0) > 0 }
            .max { lhs, rhs in
                let left = (lhs.weight?.kilograms ?? 0, lhs.reps ?? 0)
                let right = (rhs.weight?.kilograms ?? 0, rhs.reps ?? 0)
                return left < right
            }
    }
}
