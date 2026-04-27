import Foundation

public struct ExerciseDTO: Codable, Sendable {
    public let id: UUID
    public let userId: UUID?
    public let name: String
    public let description: String?
    public let category: String
    public let muscleGroups: [String]
    public let isPublic: Bool
    public let isActive: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        userId: UUID?,
        name: String,
        description: String?,
        category: String,
        muscleGroups: [String],
        isPublic: Bool,
        isActive: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.description = description
        self.category = category
        self.muscleGroups = muscleGroups
        self.isPublic = isPublic
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, category
        case userId = "user_id"
        case muscleGroups = "muscle_groups"
        case isPublic = "is_public"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public extension ExerciseDTO {
    func toModel() -> Exercise {
        let e = Exercise(name: name, category: category)
        e.id = id
        e.userId = userId
        e.exerciseDescription = description
        e.muscleGroups = muscleGroups
        e.isPublic = isPublic
        e.isActive = isActive
        e.remoteUpdatedAt = updatedAt
        return e
    }
}

public extension Exercise {
    func toDTO() -> ExerciseDTO {
        ExerciseDTO(
            id: id,
            userId: userId,
            name: name,
            description: exerciseDescription,
            category: categoryRaw,
            muscleGroups: muscleGroups,
            isPublic: isPublic,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
