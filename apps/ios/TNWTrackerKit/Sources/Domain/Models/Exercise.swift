import Foundation
import SwiftData

@Model public final class Exercise {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID?
    public var name: String
    public var exerciseDescription: String?
    public var categoryRaw: String
    public var muscleGroups: [String]
    public var isPublic: Bool
    public var isActive: Bool
    public var pendingSyncOp: String?
    public var remoteUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    @Relationship(deleteRule: .cascade) public var videos: [ExerciseVideo]

    public init(name: String, category: String) {
        id = UUID()
        self.name = name
        categoryRaw = category
        muscleGroups = []
        isPublic = false
        isActive = true
        videos = []
        createdAt = Date()
        updatedAt = Date()
    }
}
