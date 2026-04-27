import Foundation
import SwiftData

@Model public final class ExerciseVideo {
    @Attribute(.unique) public var id: UUID
    public var exerciseId: UUID
    public var sourceRaw: String
    public var url: String
    public var thumbnailUrl: String?
    public var durationSeconds: Int?
    public var isPrimary: Bool
    public var pendingSyncOp: String?
    public var remoteUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(exerciseId: UUID, source: String, url: String) {
        id = UUID()
        self.exerciseId = exerciseId
        sourceRaw = source
        self.url = url
        isPrimary = false
        createdAt = Date()
        updatedAt = Date()
    }
}
