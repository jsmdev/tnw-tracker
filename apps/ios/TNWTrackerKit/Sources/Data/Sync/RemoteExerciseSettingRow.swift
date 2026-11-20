import Foundation

// MARK: - exercise_settings

/// A user's settings for one exercise, catalogue or their own (not training
/// data). The server keys it by (`user_id`, `exercise_id`) and has no `id`
/// column: for its owner the exercise id is the key, so it is the row's `id`
/// here, the second half of the pull cursor and the `row_id` of its tombstone
/// (`RemoteTable.keyColumn`).
public struct RemoteExerciseSettingRow: RemoteRow {
    public static let table = RemoteTable.exerciseSettings

    /// The exercise id.
    public var id: UUID
    public var userId: UUID
    public var restEnabled: Bool
    public var restSeconds: Int
    public var updatedAt: String?

    public init(exerciseId: UUID, userId: UUID, restEnabled: Bool, restSeconds: Int, updatedAt: String? = nil) {
        id = exerciseId
        self.userId = userId
        self.restEnabled = restEnabled
        self.restSeconds = restSeconds
        self.updatedAt = updatedAt
    }

    public var exerciseId: UUID {
        id
    }

    enum CodingKeys: String, CodingKey {
        case id = "exercise_id"
        case userId = "user_id"
        case restEnabled = "rest_enabled"
        case restSeconds = "rest_seconds"
        case updatedAt = "updated_at"
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(userId, forKey: .userId)
        try values.encode(restEnabled, forKey: .restEnabled)
        try values.encode(restSeconds, forKey: .restSeconds)
    }
}
