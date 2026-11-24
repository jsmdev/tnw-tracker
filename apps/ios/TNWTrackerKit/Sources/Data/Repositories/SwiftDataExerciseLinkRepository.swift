import Foundation
import SwiftData

/// SwiftData adapter of the personal related links (S10). It refuses what the
/// server would refuse (supabase/migrations/20261124120000_exercise_links.sql),
/// so a stored link never stays pending for good, and a second link with the
/// same address on the same exercise, which the server allows (two devices
/// adding it offline must not block each other's push).
@MainActor
final class SwiftDataExerciseLinkRepository: ExerciseLinkRepositoryProtocol {
    private let context: ModelContext
    /// The context does not keep its container alive; the adapter does.
    private let container: ModelContainer

    init(context: ModelContext) {
        self.context = context
        container = context.container
    }

    func links(exerciseId: UUID) throws -> [ExerciseLink] {
        try ordered(context.fetchExerciseLinks(exerciseId: exerciseId)).map(\.snapshot)
    }

    func add(exerciseId: UUID, title: String, url: String, source: String) throws -> ExerciseLink {
        let title = Self.trimmed(title)
        let url = Self.trimmed(url)
        let source = Self.trimmed(source)
        guard try context.fetchExercise(id: exerciseId) != nil else { throw TrainingDataError.notFound }
        try Self.validate(title: title, source: source)
        guard RelatedLink.isHTTPSAddress(url) else { throw TrainingDataError.invalidLink("the address is not https") }
        let others = try context.fetchExerciseLinks(exerciseId: exerciseId)
        guard !others.contains(where: { $0.url == url }) else { throw TrainingDataError.duplicateLink }
        let model = ExerciseLinkModel(
            id: UUID(), exerciseId: exerciseId, title: title, url: url, source: source,
            position: (others.map(\.position).max() ?? 0) + 1
        )
        context.insert(model)
        // The user's link, also on a catalogue exercise.
        try context.trackNew(model)
        try context.save()
        return model.snapshot
    }

    func rename(id: UUID, title: String) throws {
        guard let model = try context.fetchExerciseLink(id: id) else { throw TrainingDataError.notFound }
        let title = Self.trimmed(title)
        try Self.validate(title: title, source: model.source)
        guard model.title != title else { return }
        model.title = title
        model.markChanged()
        try context.save()
    }

    func delete(id: UUID) throws {
        guard let model = try context.fetchExerciseLink(id: id) else { throw TrainingDataError.notFound }
        try context.recordDeletion(of: model)
        context.delete(model)
        try context.save()
    }

    // MARK: - Rules

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func validate(title: String, source: String) throws {
        guard !title.isEmpty, !source.isEmpty else {
            throw TrainingDataError.invalidLink("a link needs a title and a source")
        }
    }

    /// By position, ties by id, as the server orders them.
    private func ordered(_ models: [ExerciseLinkModel]) -> [ExerciseLinkModel] {
        models.sorted { lhs, rhs in
            lhs.position == rhs.position
                ? lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
                : lhs.position < rhs.position
        }
    }
}
