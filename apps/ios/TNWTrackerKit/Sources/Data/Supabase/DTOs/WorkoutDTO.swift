import Foundation

public struct WorkoutDTO: Codable, Sendable {
    public let id: UUID
    public let userId: UUID
    public let sessionId: UUID?
    public let name: String
    public let status: String
    public let startedAt: Date
    public let completedAt: Date?
    public let durationSeconds: Int?
    public let notes: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        userId: UUID,
        sessionId: UUID?,
        name: String,
        status: String,
        startedAt: Date,
        completedAt: Date?,
        durationSeconds: Int?,
        notes: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.sessionId = sessionId
        self.name = name
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, status, notes
        case userId = "user_id"
        case sessionId = "session_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public extension WorkoutDTO {
    func toModel() -> Workout {
        let wkt = Workout(userId: userId, name: name)
        wkt.id = id
        wkt.sessionId = sessionId
        wkt.statusRaw = status
        wkt.startedAt = startedAt
        wkt.completedAt = completedAt
        wkt.durationSeconds = durationSeconds
        wkt.notes = notes
        wkt.remoteUpdatedAt = updatedAt
        return wkt
    }
}

public extension Workout {
    func toDTO() -> WorkoutDTO {
        WorkoutDTO(
            id: id,
            userId: userId,
            sessionId: sessionId,
            name: name,
            status: statusRaw,
            startedAt: startedAt,
            completedAt: completedAt,
            durationSeconds: durationSeconds,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
