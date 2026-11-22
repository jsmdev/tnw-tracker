import Foundation
import Observation
import TNWTrackerKit

// MARK: - HistoryListModel

/// View model for the Historial tab: the finished workouts, newest first (#174 S6).
@Observable
@MainActor
final class HistoryListModel {
    private(set) var sessions: [TrainingSession] = []
    private(set) var isLoading = false

    private let repository: any SessionRepositoryProtocol
    private let now: () -> Date

    init(sessions: any SessionRepositoryProtocol, now: @escaping () -> Date = Date.init) {
        repository = sessions
        self.now = now
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let everything = DateInterval(start: .distantPast, end: now())
        sessions = (try? repository.completedSessions(in: everything)) ?? []
    }

    /// The exercises of a workout, leaving out the ones removed from it.
    static func exerciseCount(_ session: TrainingSession) -> Int {
        session.entries.filter { $0.status != .removed && !$0.sets.isEmpty }.count
    }
}
