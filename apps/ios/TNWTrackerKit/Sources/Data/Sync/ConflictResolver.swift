import Foundation

public enum ConflictResolution: Sendable {
    case useLocal
    case useRemote
    case manual(localUpdatedAt: Date, remoteUpdatedAt: Date)
}

public struct ConflictEvent: Sendable {
    public let tableName: String
    public let recordId: UUID
    public let resolution: ConflictResolution
}

public struct ConflictResolver: Sendable {
    public init() {}

    public func resolve(
        tableName: String,
        recordId: UUID,
        localUpdatedAt: Date,
        remoteUpdatedAt: Date,
        hasCompletedAt: Bool = false
    ) -> ConflictResolution {
        // ExerciseSet con completedAt es inmutable — siempre gana local
        if hasCompletedAt {
            return .useLocal
        }

        // LWW — Last Write Wins
        if remoteUpdatedAt > localUpdatedAt {
            return .useRemote
        } else if localUpdatedAt > remoteUpdatedAt {
            return .useLocal
        } else {
            // Mismo timestamp — evento manual
            return .manual(localUpdatedAt: localUpdatedAt, remoteUpdatedAt: remoteUpdatedAt)
        }
    }
}
