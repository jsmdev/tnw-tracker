import Foundation

/// A personal related link of an exercise (S10): an external link (a video, an
/// article…) the user added to a catalogue or own exercise. Only its owner sees
/// it. User data outside the training data format, like `ExerciseSetting`; the
/// curated links of the catalogue are `Exercise.relatedLinks` and are not
/// editable. Shown by its `title` and `source`, never by its address.
public struct ExerciseLink: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let exerciseId: UUID
    public var title: String
    /// An `https` address (`RelatedLink.isHTTPSAddress`).
    public var url: String
    /// The name of the site, shown to the user.
    public var source: String
    /// Order among the user's links of the exercise, from 1; ties keep id order.
    public var position: Int

    public init(id: UUID = UUID(), exerciseId: UUID, title: String, url: String, source: String, position: Int) {
        self.id = id
        self.exerciseId = exerciseId
        self.title = title
        self.url = url
        self.source = source
        self.position = position
    }
}
