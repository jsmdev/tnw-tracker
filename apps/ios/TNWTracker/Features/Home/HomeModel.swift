import Foundation
import Observation
import TNWTrackerKit

// MARK: - HomeModel

/// View model for HomeView. Computes weekly progress and the next routine.
/// REQ-HOME-01, REQ-HOME-02, REQ-HOME-03.
@Observable
@MainActor
final class HomeModel {
    // MARK: - Published State

    /// Number of sessions completed in the current week.
    private(set) var weeklyCompletedCount: Int = 0

    /// Total volume (weight × reps, kg) of the counted sets of this week's sessions.
    /// Superseded sets, warm-up sets and removed entries do not count.
    private(set) var weeklyVolume: Double = 0.0

    /// The routine proposed next (nil if none exist): favourites if any, the one
    /// never done or done longest ago (T5 AC5.2–AC5.3).
    private(set) var nextSession: Routine?

    /// "Otras rutinas" (T10 AC10.1): every routine but `nextSession`, in the
    /// routine list's order (favourites first, then by name).
    private(set) var otherRoutines: [Routine] = []

    /// True when a session is in progress or a routine exists to start.
    /// Drives the Quick Start button visibility (REQ-HOME-03).
    private(set) var hasSessionToday: Bool = false

    /// True while loading data.
    private(set) var isLoading: Bool = false

    // MARK: - Private

    private let sessions: any SessionRepositoryProtocol
    private let routines: any RoutineRepositoryProtocol
    private let calendar: Calendar
    private let now: () -> Date

    // MARK: - Init

    init(
        sessions: any SessionRepositoryProtocol,
        routines: any RoutineRepositoryProtocol,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.sessions = sessions
        self.routines = routines
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }

        if let week = calendar.dateInterval(of: .weekOfYear, for: now()) {
            let completed = (try? sessions.completedSessions(in: week)) ?? []
            weeklyCompletedCount = completed.count
            weeklyVolume = completed.reduce(0) { $0 + $1.volumeKg }
        } else {
            weeklyCompletedCount = 0
            weeklyVolume = 0
        }

        nextSession = try? routines.nextRoutine()
        // The routine list's own order (favourites first, then by name).
        let all = (try? routines.routines(RoutineQuery())) ?? []
        otherRoutines = all.filter { $0.id != nextSession?.id }
        let hasActive = ((try? sessions.activeSession()) ?? nil) != nil
        hasSessionToday = hasActive || nextSession != nil
    }
}
