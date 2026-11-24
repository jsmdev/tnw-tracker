import Foundation

// MARK: - exercise_links

/// A personal related link of an exercise, catalogue or the user's own
/// (supabase/migrations/20261124120000_exercise_links.sql): user data outside
/// the training data format, pushed and pulled on its own like the settings.
/// The push sends every column the client owns and never `created_at` or
/// `updated_at`, which the server writes.
public struct RemoteExerciseLinkRow: RemoteRow {
    public static let table = RemoteTable.exerciseLinks

    public var id: UUID
    public var userId: UUID
    public var exerciseId: UUID
    public var title: String
    /// An `https` address.
    public var url: String
    public var source: String
    /// From 1; ties keep id order.
    public var position: Int
    public var updatedAt: String?

    public init(
        id: UUID,
        userId: UUID,
        exerciseId: UUID,
        title: String,
        url: String,
        source: String,
        position: Int,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.exerciseId = exerciseId
        self.title = title
        self.url = url
        self.source = source
        self.position = position
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseId = "exercise_id"
        case title
        case url
        case source
        case position
        case updatedAt = "updated_at"
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(userId, forKey: .userId)
        try values.encode(exerciseId, forKey: .exerciseId)
        try values.encode(title, forKey: .title)
        try values.encode(url, forKey: .url)
        try values.encode(source, forKey: .source)
        try values.encode(position, forKey: .position)
    }
}
