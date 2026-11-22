import Foundation
import Observation
import TNWTrackerKit

// MARK: - WorkoutDetailModel

/// View model for a finished workout of the history: its summary, the sets of
/// each exercise, and deleting it (#174 S7).
@Observable
@MainActor
final class WorkoutDetailModel {
    /// One exercise of the workout with the sets shown for it.
    struct ExerciseSection: Identifiable, Equatable {
        /// The entry's id.
        let id: UUID
        let exerciseName: String?
        let sets: [ShownSet]
    }

    /// A set as the detail shows it. `number` counts working sets only; a
    /// warm-up set has none.
    struct ShownSet: Identifiable, Equatable {
        let value: ExerciseSet
        let number: Int?

        var id: UUID { value.id }
    }

    let sessionID: UUID
    private(set) var session: TrainingSession?
    private(set) var sections: [ExerciseSection] = []
    private(set) var isLoaded = false

    private let sessions: any SessionRepositoryProtocol
    private let exercises: any ExerciseRepositoryProtocol

    init(
        sessionID: UUID,
        sessions: any SessionRepositoryProtocol,
        exercises: any ExerciseRepositoryProtocol
    ) {
        self.sessionID = sessionID
        self.sessions = sessions
        self.exercises = exercises
    }

    /// A workout with machine data cannot be deleted: the next import would bring it back.
    var canDelete: Bool {
        session.map { $0.isCompleted && !$0.hasImportedData } ?? false
    }

    func load() {
        defer { isLoaded = true }
        guard let found = try? sessions.session(id: sessionID), found.isCompleted else {
            session = nil
            sections = []
            return
        }
        session = found
        sections = Self.sections(of: found) { [exercises] id in
            (try? exercises.exercise(id: id))?.name
        }
    }

    /// Deletes the workout. See `SessionRepositoryProtocol.deleteCompletedSession(id:)`.
    func delete() throws {
        try sessions.deleteCompletedSession(id: sessionID)
        session = nil
        sections = []
    }

    /// The performed exercises in session order, each with its sets that are not
    /// superseded: imported ones first, then manual, each in its own order.
    /// Entries that were skipped or removed, or that have no shown set, are left out.
    static func sections(
        of session: TrainingSession,
        exerciseName: (UUID) -> String?
    ) -> [ExerciseSection] {
        session.entries
            .filter { $0.status == .done }
            .sorted { $0.order < $1.order }
            .compactMap { entry in
                let shown = entry.sets
                    .filter { !$0.superseded }
                    .sorted { ($0.source.sortRank, $0.order) < ($1.source.sortRank, $1.order) }
                guard !shown.isEmpty else { return nil }
                var number = 0
                let sets = shown.map { set -> ShownSet in
                    guard !set.warmup else { return ShownSet(value: set, number: nil) }
                    number += 1
                    return ShownSet(value: set, number: number)
                }
                return ExerciseSection(id: entry.id, exerciseName: exerciseName(entry.exerciseId), sets: sets)
            }
    }
}

private extension SetSource {
    var sortRank: Int {
        switch self {
        case .imported: 0
        case .manual: 1
        }
    }
}
