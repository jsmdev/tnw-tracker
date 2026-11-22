import Foundation
import Observation
import TNWTrackerKit

// MARK: - HistoryListModel

/// View model for the Historial tab: the finished workouts, newest first (#174 S6),
/// searched, filtered and grouped by month (#174 S8).
@Observable
@MainActor
final class HistoryListModel {
    private(set) var sessions: [TrainingSession] = []
    private(set) var isLoading = false
    var filter = HistoryFilter()

    private var exerciseNames: [UUID: String] = [:]
    private let repository: any SessionRepositoryProtocol
    private let exercises: any ExerciseRepositoryProtocol
    private let now: () -> Date
    let calendar: Calendar

    init(
        sessions: any SessionRepositoryProtocol,
        exercises: any ExerciseRepositoryProtocol,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        repository = sessions
        self.exercises = exercises
        self.now = now
        self.calendar = calendar
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let everything = DateInterval(start: .distantPast, end: now())
        sessions = (try? repository.completedSessions(in: everything)) ?? []
        let catalogue = (try? exercises.exercises()) ?? []
        exerciseNames = Dictionary(catalogue.map { ($0.id, $0.name) }) { first, _ in first }
    }

    /// The workouts that pass the search and the filters, newest first.
    var filteredSessions: [TrainingSession] {
        filter.apply(to: sessions, exerciseName: { exerciseNames[$0] }, now: now(), calendar: calendar)
    }

    /// `filteredSessions` by month.
    var months: [HistoryMonth] {
        HistoryFilter.months(of: filteredSessions, calendar: calendar)
    }

    /// The kinds of workout to offer, from every finished workout.
    var kinds: [HistoryFilter.Kind] {
        HistoryFilter.kinds(of: sessions)
    }

    /// When the oldest finished workout ended, for "N sesiones · desde junio".
    var firstWorkoutDate: Date? {
        sessions.last?.completedAt
    }

    func clearFilters() {
        filter = HistoryFilter()
    }

    /// Only a workout without machine data can be deleted: the next import would bring it back.
    static func canDelete(_ session: TrainingSession) -> Bool {
        session.isCompleted && !session.hasImportedData
    }

    /// Deletes a finished workout and drops it from the list.
    /// See `SessionRepositoryProtocol.deleteCompletedSession(id:)`.
    func delete(_ sessionId: UUID) throws {
        try repository.deleteCompletedSession(id: sessionId)
        sessions.removeAll { $0.id == sessionId }
    }

    /// The exercises of a workout, leaving out the ones removed from it.
    static func exerciseCount(_ session: TrainingSession) -> Int {
        session.entries.filter { $0.status != .removed && !$0.sets.isEmpty }.count
    }
}
