import Foundation

/// The rule behind "Próxima sesión" (Home card and widget), T5 AC5.2–AC5.3:
/// - the candidates are the favourite routines, or every routine without favourites;
/// - a candidate never done comes first, by name;
/// - otherwise the candidate whose last completed session is the oldest
///   (name breaks a tie).
public enum NextRoutineRule {
    public struct Candidate: Hashable, Sendable {
        public var id: UUID
        public var name: String
        public var isFavorite: Bool
        /// Completion date of the routine's latest completed session; nil if never done.
        public var lastCompletedAt: Date?

        public init(id: UUID, name: String, isFavorite: Bool, lastCompletedAt: Date?) {
            self.id = id
            self.name = name
            self.isFavorite = isFavorite
            self.lastCompletedAt = lastCompletedAt
        }
    }

    /// The id of the routine to propose, or nil without candidates.
    public static func next(among candidates: [Candidate]) -> UUID? {
        let favourites = candidates.filter(\.isFavorite)
        let pool = favourites.isEmpty ? candidates : favourites
        return pool.min(by: precedes)?.id
    }

    private static func precedes(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        switch (lhs.lastCompletedAt, rhs.lastCompletedAt) {
        case (nil, .some): return true
        case (.some, nil): return false
        case let (.some(left), .some(right)) where left != right: return left < right
        default: return (lhs.name, lhs.id.uuidString) < (rhs.name, rhs.id.uuidString)
        }
    }
}
