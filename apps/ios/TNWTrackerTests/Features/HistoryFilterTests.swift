import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// Search, filters and month grouping of the Historial tab (#174 S8).
@Suite("HistoryFilter")
@MainActor
struct HistoryFilterTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .gmt
        return calendar
    }()

    let squat = UUID()
    let press = UUID()
    let rower = UUID()
    let ref = ExternalRef(provider: TrainingFixtures.provider, id: "x-1")

    /// 2030-03-20 12:00 Madrid.
    var now: Date { date(2030, 3, 20) }

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    func names(_ id: UUID) -> String? {
        [squat: "Sentadilla búlgara", press: "Chest Press Machine", rower: "Remo"][id]
    }

    func workout(
        _ name: String?,
        _ completedAt: Date,
        exercises: [UUID],
        status: EntryStatus = .done,
        imported: Bool = false
    ) -> TrainingSession {
        let entries = exercises.enumerated().map { index, id in
            SessionEntry(
                exerciseId: id, order: index + 1, status: status,
                sets: [ExerciseSet(order: 1, source: imported ? .imported : .manual, values: SetValues(reps: 5))]
            )
        }
        return TrainingSession(name: name, completedAt: completedAt, timeZone: "Europe/Madrid", entries: entries)
    }

    func apply(_ filter: HistoryFilter, _ sessions: [TrainingSession]) -> [String?] {
        filter.apply(to: sessions, exerciseName: names, now: now, calendar: calendar).map(\.name)
    }

    @Test("no filter keeps every workout, in order, and is not active")
    func noFilter() {
        let sessions = [
            workout("A", date(2030, 3, 19), exercises: [squat]),
            workout(nil, date(2029, 1, 2), exercises: [press])
        ]
        #expect(apply(HistoryFilter(), sessions) == ["A", nil])
        #expect(HistoryFilter().isActive == false)
    }

    @Test("the search matches a performed exercise ignoring case and accents, or the workout's name")
    func search() {
        let sessions = [
            workout("Piernas", date(2030, 3, 19), exercises: [squat]),
            workout("Pecho", date(2030, 3, 18), exercises: [press]),
            workout("Removed", date(2030, 3, 17), exercises: [squat], status: .removed),
            workout(nil, date(2030, 3, 16), exercises: [rower])
        ]
        #expect(apply(HistoryFilter(query: "BULGARA"), sessions) == ["Piernas"], "a removed exercise does not match")
        #expect(apply(HistoryFilter(query: "  press "), sessions) == ["Pecho"])
        #expect(apply(HistoryFilter(query: "pech"), sessions) == ["Pecho"], "the workout's name matches too")
        #expect(apply(HistoryFilter(query: "zzz"), sessions).isEmpty)
        #expect(HistoryFilter(query: "x").isActive)
    }

    @Test("the kind keeps one routine's workouts, or the free ones")
    func kind() {
        let sessions = [
            workout("Piernas", date(2030, 3, 19), exercises: [squat]),
            workout(nil, date(2030, 3, 18), exercises: [press]),
            workout("Pecho", date(2030, 3, 17), exercises: [press])
        ]
        #expect(apply(HistoryFilter(kind: .named("Pecho")), sessions) == ["Pecho"])
        #expect(apply(HistoryFilter(kind: .free), sessions) == [nil])
    }

    @Test("the periods: last 30 days, last 91 days, this year, everything")
    func period() {
        let sessions = [
            workout("d0", date(2030, 3, 20), exercises: [squat]),
            workout("d30", date(2030, 2, 18), exercises: [squat]),
            workout("d31", date(2030, 2, 17), exercises: [squat]),
            workout("jan1", date(2030, 1, 1), exercises: [squat]),
            workout("d91", date(2029, 12, 19), exercises: [squat]),
            workout("d92", date(2029, 12, 18), exercises: [squat])
        ]
        #expect(apply(HistoryFilter(period: .month), sessions) == ["d0", "d30"])
        #expect(apply(HistoryFilter(period: .year), sessions) == ["d0", "d30", "d31", "jan1"])
        #expect(apply(HistoryFilter(period: .quarter), sessions) == ["d0", "d30", "d31", "jan1", "d91"])
        #expect(apply(HistoryFilter(period: .all), sessions).count == 6)
    }

    @Test("a workout that ends exactly when the period starts is in it")
    func periodBoundary() throws {
        let newYear = try #require(calendar.date(from: DateComponents(year: 2030, month: 1, day: 1)))
        let sessions = [
            workout("start", newYear, exercises: [squat]),
            workout("before", newYear.addingTimeInterval(-1), exercises: [squat])
        ]
        #expect(apply(HistoryFilter(period: .year), sessions) == ["start"])
    }

    @Test("the source keeps workouts with machine data, or the manual ones")
    func source() {
        let sessions = [
            workout("manual", date(2030, 3, 19), exercises: [squat]),
            workout("machines", date(2030, 3, 18), exercises: [press], imported: true),
            TrainingSession(externalRef: ref, name: "imported", completedAt: date(2030, 3, 17), timeZone: "UTC")
        ]
        #expect(apply(HistoryFilter(source: .machines), sessions) == ["machines", "imported"])
        #expect(apply(HistoryFilter(source: .manual), sessions) == ["manual"])
    }

    @Test("filters combine")
    func combined() {
        let sessions = [
            workout("Pecho", date(2030, 3, 19), exercises: [press], imported: true),
            workout("Pecho", date(2030, 3, 18), exercises: [press]),
            workout("Pecho", date(2029, 3, 18), exercises: [press], imported: true)
        ]
        let filter = HistoryFilter(query: "chest", kind: .named("Pecho"), period: .month, source: .machines)
        #expect(filter.apply(to: sessions, exerciseName: names, now: now, calendar: calendar)
            .map(\.completedAt) == [date(2030, 3, 19)])
    }

    @Test("workouts group by the month they ended in, newest first")
    func months() {
        let sessions = [
            workout("a", date(2030, 3, 2), exercises: [squat]),
            workout("b", date(2030, 3, 1), exercises: [squat]),
            workout("c", date(2030, 2, 28), exercises: [squat]),
            workout("d", date(2029, 3, 5), exercises: [squat])
        ]
        let months = HistoryFilter.months(of: sessions, calendar: calendar)
        #expect(months.map(\.id) == [date(2030, 3, 1), date(2030, 2, 1), date(2029, 3, 1)].map {
            calendar.startOfDay(for: $0)
        })
        #expect(months.map { $0.sessions.map(\.name) } == [["a", "b"], ["c"], ["d"]])
    }

    @Test("kinds: every workout, then names by frequency and name, then free ones")
    func kinds() {
        let sessions = [
            workout("Pecho", date(2030, 3, 19), exercises: [press]),
            workout("Piernas", date(2030, 3, 18), exercises: [squat]),
            workout(nil, date(2030, 3, 17), exercises: [squat]),
            workout("Piernas", date(2030, 3, 16), exercises: [squat]),
            workout("Espalda", date(2030, 3, 15), exercises: [rower])
        ]
        #expect(
            HistoryFilter.kinds(of: sessions) == [.all, .named("Piernas"), .named("Espalda"), .named("Pecho"), .free]
        )
        #expect(HistoryFilter.kinds(of: [sessions[0]]) == [.all, .named("Pecho")])
    }
}
