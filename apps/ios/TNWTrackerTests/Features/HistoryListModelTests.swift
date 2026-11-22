import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// The Historial tab lists finished workouts (#174 S6).
@Suite("HistoryListModel", .serialized)
@MainActor
struct HistoryListModelTests {
    let fx: TrainingFixtures

    init() throws {
        fx = try TrainingFixtures()
    }

    /// A finished session `days` after t0 with one set of `reps` squats.
    @discardableResult
    private func finishedSession(name: String, days: Double, reps: Int = 8) throws -> TrainingSession {
        let start = TrainingFixtures.t0.addingTimeInterval(days * 86_400)
        let session = try fx.sessions.startSession(
            routineId: nil, name: name, at: start, timeZone: TrainingFixtures.zone
        )
        _ = try fx.sessions.logManualSet(
            SetValues(reps: reps, weight: .kg(20)), exerciseId: fx.squat.id, sessionId: session.id,
            at: start.addingTimeInterval(60)
        )
        return try fx.sessions.finishSession(
            id: session.id, at: start.addingTimeInterval(1_800), durationSeconds: 1_800
        )
    }

    @Test("lists finished workouts newest first and leaves out the one in progress")
    func newestFirstWithoutInProgress() async throws {
        try finishedSession(name: "Older", days: 0)
        try finishedSession(name: "Newer", days: 2)
        _ = try fx.sessions.startSession(
            routineId: nil, name: "Open", at: TrainingFixtures.t0.addingTimeInterval(3 * 86_400),
            timeZone: TrainingFixtures.zone
        )
        let model = HistoryListModel(sessions: fx.sessions, now: { TrainingFixtures.t0.addingTimeInterval(4 * 86_400) })

        await model.load()

        #expect(model.sessions.map(\.name) == ["Newer", "Older"])
    }

    @Test("with no finished workout the list is empty")
    func emptyHistory() async {
        let model = HistoryListModel(sessions: fx.sessions, now: { TrainingFixtures.t0 })
        await model.load()
        #expect(model.sessions.isEmpty)
        #expect(!model.isLoading)
    }

    @Test("a row counts the exercises that were not removed")
    func exerciseCount() throws {
        let session = try finishedSession(name: "One", days: 0)
        #expect(HistoryListModel.exerciseCount(session) == 1)
    }

    @Test("deleting a workout drops it from the list and from the store (#174 S7)")
    func deleteDropsTheWorkout() async throws {
        let kept = try finishedSession(name: "Kept", days: 0)
        let deleted = try finishedSession(name: "Deleted", days: 1)
        let model = HistoryListModel(sessions: fx.sessions, now: { TrainingFixtures.t0.addingTimeInterval(4 * 86_400) })
        await model.load()
        #expect(HistoryListModel.canDelete(deleted))

        try model.delete(deleted.id)

        #expect(model.sessions.map(\.id) == [kept.id])
        #expect(try fx.sessions.session(id: deleted.id) == nil)
        await model.load()
        #expect(model.sessions.map(\.id) == [kept.id])
    }

    @Test("a workout with machine data offers no delete, and stays when asked to (#174 S7)")
    func importedWorkoutIsKept() async throws {
        let workout = try finishedSession(name: "Mixed", days: 0)
        let open = try fx.sessions.startSession(
            routineId: nil, name: "Open", at: TrainingFixtures.t0.addingTimeInterval(86_400),
            timeZone: TrainingFixtures.zone
        )
        try fx.sessions.importEntry(
            ImportedEntry(exerciseId: fx.press.id, externalRef: fx.ref("e-1"), sets: [
                ImportedSet(externalRef: fx.ref("e-1#1"), order: 1, values: SetValues(reps: 10, weight: .kg(40)))
            ]),
            into: open.id
        )
        let mixed = try fx.sessions.finishSession(
            id: open.id, at: TrainingFixtures.t0.addingTimeInterval(86_400 + 900), durationSeconds: nil
        )
        let model = HistoryListModel(sessions: fx.sessions, now: { TrainingFixtures.t0.addingTimeInterval(4 * 86_400) })
        await model.load()

        #expect(HistoryListModel.canDelete(workout))
        #expect(HistoryListModel.canDelete(mixed) == false)
        #expect(throws: TrainingDataError.sessionHasImportedData) { try model.delete(mixed.id) }
        #expect(model.sessions.map(\.id) == [mixed.id, workout.id])
    }
}
