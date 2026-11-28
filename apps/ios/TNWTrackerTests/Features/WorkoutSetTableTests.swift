import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// The set table of the current exercise (fast-add-exercise S5), through the
/// real coordinator and store: rows ready from the last time, a check logs one.
@Suite("Workout set table", .serialized)
@MainActor
struct WorkoutSetTableTests {
    let fx: TrainingFixtures
    let t0 = TrainingFixtures.t0

    init() throws {
        fx = try TrainingFixtures()
    }

    private func makeCoordinator() -> ActiveWorkoutCoordinator {
        ActiveWorkoutCoordinator(
            sessions: fx.sessions,
            routines: fx.routines,
            exerciseSettings: fx.store.exerciseSettings,
            changeExerciseRest: { nil },
            requestSync: {},
            timerService: RestTimerService(),
            liveActivity: LiveActivitySpy(),
            now: { TrainingFixtures.t0 }
        )
    }

    /// A completed squat session a day before `t0`: 20 × 9, 15 × 10.1.
    private func squatYesterday() throws {
        let start = t0.addingTimeInterval(-86400)
        let session = try fx.sessions.startSession(
            routineId: nil,
            name: nil,
            at: start,
            timeZone: TrainingFixtures.zone
        )
        for (reps, kg) in [(20, 9.0), (15, 10.1)] {
            try fx.sessions.logManualSet(
                SetValues(reps: reps, weight: .kg(kg)), warmup: false,
                exerciseId: fx.squat.id, sessionId: session.id, at: start.addingTimeInterval(60)
            )
        }
        try fx.sessions.finishSession(id: session.id, at: start.addingTimeInterval(600), durationSeconds: nil)
    }

    private func started(_ exerciseId: UUID) async throws -> (ActiveWorkoutCoordinator, SessionEntry) {
        let coordinator = makeCoordinator()
        try await coordinator.startAdHoc(name: "Free")
        coordinator.addExercise(exerciseId)
        return try (coordinator, #require(coordinator.currentEntry))
    }

    private func savedSets(_ coordinator: ActiveWorkoutCoordinator) throws -> [SetValues] {
        let id = try #require(coordinator.activeWorkoutId)
        let session = try #require(try fx.sessions.session(id: id))
        return session.entries.flatMap(\.workingManualSets).map { SetValues(
            reps: $0.values.reps,
            weight: $0.values.weight
        ) }
    }

    @Test("an exercise done before shows last time's sets as rows at once (AC1)")
    func rowsFromLastTime() async throws {
        try squatYesterday()
        let (coordinator, entry) = try await started(fx.squat.id)
        #expect(coordinator.pendingSets(for: entry) == [
            SetValues(reps: 20, weight: .kg(9)), SetValues(reps: 15, weight: .kg(10.1))
        ])
    }

    @Test("an exercise never done shows 3 rows of 15 reps and 0 kg (AC2)")
    func defaultRows() async throws {
        let (coordinator, entry) = try await started(fx.press.id)
        #expect(coordinator.pendingSets(for: entry) == Array(repeating: SetValues(reps: 15, weight: .kg(0)), count: 3))
    }

    @Test("checking an edited row logs it with its values, and the row leaves the pending ones (AC4)")
    func checkLogsRow() async throws {
        try squatYesterday()
        var (coordinator, entry) = try await started(fx.squat.id)
        coordinator.updatePendingSet(SetValues(reps: 15, weight: .kg(11)), at: 1, of: entry)

        try await coordinator.logPendingSet(at: 1, of: entry)

        #expect(try savedSets(coordinator) == [SetValues(reps: 15, weight: .kg(11))])
        entry = try #require(coordinator.currentEntry)
        #expect(entry.workingManualSets.count == 1)
        #expect(coordinator.pendingSets(for: entry) == [SetValues(reps: 20, weight: .kg(9))])
        #expect(coordinator.phase == .restingBetweenSets, "as logging a set today: the rest starts")
    }

    @Test("0 kg logs no weight; a row without reps logs nothing")
    func zeroWeightAndNoReps() async throws {
        var (coordinator, entry) = try await started(fx.press.id)
        try await coordinator.logPendingSet(at: 0, of: entry)
        let id = try #require(coordinator.activeWorkoutId)
        let logged = try #require(try fx.sessions.session(id: id)?.entries.first?.manualSets.first)
        #expect(logged.values.reps == 15)
        #expect(logged.values.weight == nil)

        entry = try #require(coordinator.currentEntry)
        coordinator.updatePendingSet(SetValues(reps: nil, weight: .kg(5)), at: 0, of: entry)
        try await coordinator.logPendingSet(at: 0, of: entry)
        #expect(try savedSets(coordinator).count == 1)
        #expect(coordinator.pendingSets(for: entry).count == 2)
    }

    @Test("«Añadir serie» adds a row with the values of the row above, or the last logged set (AC5)")
    func addRow() async throws {
        var (coordinator, entry) = try await started(fx.press.id)
        coordinator.updatePendingSet(SetValues(reps: 9, weight: .kg(30)), at: 2, of: entry)
        coordinator.addPendingSet(to: entry)
        #expect(coordinator.pendingSets(for: entry).count == 4)
        #expect(coordinator.pendingSets(for: entry).last == SetValues(reps: 9, weight: .kg(30)))

        for _ in 0 ..< 4 {
            entry = try #require(coordinator.currentEntry)
            try await coordinator.logPendingSet(at: 0, of: entry)
            await coordinator.skipTimer()
        }
        entry = try #require(coordinator.currentEntry)
        #expect(coordinator.pendingSets(for: entry).isEmpty)
        coordinator.addPendingSet(to: entry)
        #expect(coordinator.pendingSets(for: entry) == [SetValues(reps: 9, weight: .kg(30))])
    }

    @Test("undoing a checked row puts its values back as the first row")
    func undoPutsRowBack() async throws {
        try squatYesterday()
        var (coordinator, entry) = try await started(fx.squat.id)
        coordinator.updatePendingSet(SetValues(reps: 18, weight: .kg(9)), at: 0, of: entry)
        try await coordinator.logPendingSet(at: 0, of: entry)

        try await coordinator.undoLastSet()

        entry = try #require(coordinator.currentEntry)
        #expect(entry.manualSets.isEmpty)
        #expect(coordinator.pendingSets(for: entry) == [
            SetValues(reps: 18, weight: .kg(9)), SetValues(reps: 15, weight: .kg(10.1))
        ])
    }

    @Test("a workout continued later rebuilds the rows still to do from the plan")
    func resumedRows() async throws {
        try squatYesterday()
        let (first, entry) = try await started(fx.squat.id)
        try await first.logPendingSet(at: 0, of: entry)

        let resumed = makeCoordinator()
        try await resumed.startAdHoc(name: "Free")
        let again = try #require(resumed.currentEntry)
        #expect(resumed.pendingSets(for: again) == [SetValues(reps: 15, weight: .kg(10.1))])
    }
}
