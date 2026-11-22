import Foundation
import TNWTrackerKit

// MARK: - HistoryFilter

/// The search and filters of the Historial tab (#174 S8): a text that matches
/// an exercise or the workout's name, the kind of workout, a period and where
/// the data came from.
struct HistoryFilter: Equatable {
    /// The kind of workout: every one, one name (a routine's), or the free ones.
    enum Kind: Hashable {
        case all
        case named(String)
        case free
    }

    enum Period: CaseIterable, Hashable {
        /// The last 30 days.
        case month
        /// The last 91 days.
        case quarter
        /// Since 1 January of the current year.
        case year
        case all
    }

    enum Source: CaseIterable, Hashable {
        case all
        /// Workouts with machine data (`TrainingSession.hasImportedData`).
        case machines
        /// Workouts logged by hand only.
        case manual
    }

    var query = ""
    var kind = Kind.all
    var period = Period.all
    var source = Source.all

    /// True when anything narrows the list, so "Quitar filtros" has something to do.
    var isActive: Bool {
        self != HistoryFilter()
    }

    /// The sessions that pass every filter, in their original order.
    /// `exerciseName` resolves an entry's exercise for the text search.
    func apply(
        to sessions: [TrainingSession],
        exerciseName: (UUID) -> String?,
        now: Date,
        calendar: Calendar
    ) -> [TrainingSession] {
        let start = periodStart(now: now, calendar: calendar)
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessions.filter { session in
            matchesKind(session)
                && matchesSource(session)
                && (start.map { (session.completedAt ?? .distantPast) >= $0 } ?? true)
                && (text.isEmpty || matches(text, session, exerciseName: exerciseName))
        }
    }

    /// The first instant the period includes, or nil for every workout.
    func periodStart(now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch period {
        case .month: return calendar.date(byAdding: .day, value: -30, to: today)
        case .quarter: return calendar.date(byAdding: .day, value: -91, to: today)
        case .year: return calendar.dateInterval(of: .year, for: now)?.start
        case .all: return nil
        }
    }

    private func matchesKind(_ session: TrainingSession) -> Bool {
        switch kind {
        case .all: true
        case let .named(name): session.name == name
        case .free: session.name == nil
        }
    }

    private func matchesSource(_ session: TrainingSession) -> Bool {
        switch source {
        case .all: true
        case .machines: session.hasImportedData
        case .manual: !session.hasImportedData
        }
    }

    /// Case- and diacritic-insensitive, on the exercises performed (not removed
    /// or skipped) and on the workout's name.
    private func matches(_ text: String, _ session: TrainingSession, exerciseName: (UUID) -> String?) -> Bool {
        if session.name?.localizedStandardContains(text) == true { return true }
        return session.entries
            .filter { $0.status == .done }
            .contains { exerciseName($0.exerciseId)?.localizedStandardContains(text) == true }
    }
}

// MARK: - Grouping

/// The workouts of one calendar month, newest first.
struct HistoryMonth: Identifiable, Equatable {
    /// The first instant of the month.
    let id: Date
    let sessions: [TrainingSession]
}

extension HistoryFilter {
    /// Groups workouts already sorted newest first by the month they ended in.
    static func months(of sessions: [TrainingSession], calendar: Calendar) -> [HistoryMonth] {
        var months: [HistoryMonth] = []
        for session in sessions {
            guard let completedAt = session.completedAt,
                  let start = calendar.dateInterval(of: .month, for: completedAt)?.start else { continue }
            if let last = months.last, last.id == start {
                months[months.count - 1] = HistoryMonth(id: start, sessions: last.sessions + [session])
            } else {
                months.append(HistoryMonth(id: start, sessions: [session]))
            }
        }
        return months
    }

    /// The workout names to offer as kinds, most frequent first, then by name.
    static func kinds(of sessions: [TrainingSession]) -> [Kind] {
        var counts: [String: Int] = [:]
        for name in sessions.compactMap(\.name) {
            counts[name, default: 0] += 1
        }
        let named = counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map { Kind.named($0.key) }
        return [.all] + named + (sessions.contains { $0.name == nil } ? [.free] : [])
    }
}
