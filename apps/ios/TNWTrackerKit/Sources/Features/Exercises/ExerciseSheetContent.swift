import Foundation

/// What the exercise sheet shows (#137 S7): the exercise's own text as
/// stored, its muscles by role and its media's object paths.
public struct ExerciseSheetContent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let type: ExerciseType
    public let equipment: Equipment?
    public let primaryMuscles: [Muscle]
    public let secondaryMuscles: [Muscle]
    public let setupSteps: [String]
    public let executionSteps: [String]
    public let imagePath: String?
    public let videoPath: String?
    /// External videos that explain it (#182 S9), in their stored order.
    public let relatedVideos: [RelatedVideoLink]

    public init(_ exercise: Exercise) {
        id = exercise.id
        name = exercise.name
        type = exercise.type
        equipment = exercise.equipment
        primaryMuscles = exercise.muscleGroups.filter { $0.role == .primary }.map(\.muscle)
        secondaryMuscles = exercise.muscleGroups.filter { $0.role == .secondary }.map(\.muscle)
        setupSteps = exercise.instructions?.setup ?? []
        executionSteps = exercise.instructions?.execution ?? []
        imagePath = exercise.media?.imageURI
        videoPath = exercise.media?.videoURI
        relatedVideos = (exercise.relatedVideos ?? []).map(RelatedVideoLink.init)
    }

    /// True when the exercise has neither setup nor execution steps.
    public var hasNoSteps: Bool {
        setupSteps.isEmpty && executionSteps.isEmpty
    }
}
