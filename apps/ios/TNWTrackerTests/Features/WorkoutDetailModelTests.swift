import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// A finished workout of the history: its sets and deleting it (#174 S7).
@Suite("WorkoutDetailModel", .serialized)
@MainActor
struct WorkoutDetailModelTests {
    let fx: TrainingFixtures
    let t0 = TrainingFixtures.t0

    init() throws {
        fx = try TrainingFixtures()
    }

    private func model(_ id: UUID) -> WorkoutDetailModel {
        WorkoutDetailModel(sessionID: id, sessions: fx.sessions, exercises: fx.exercises)
    }

    /// Squat: a warm-up then two working sets. Plank: planned but skipped.
    /// Press: one set, then removed from the workout.
    private func finishedWorkout(importing: Bool = false) throws -> TrainingSession {
        let routine = Routine(name: "Legs", items: [
            RoutineItem(order: 1, exerciseId: fx.squat.id, targetSets: 2),
            RoutineItem(order: 2, exerciseId: fx.plank.id, targetSets: 1)
        ])
        try fx.routines.save(routine)
        let open = try fx.sessions.startSession(
            routineId: routine.id, name: "Legs", at: t0, timeZone: TrainingFixtures.zone
        )
        try fx.sessions.logManualSet(
            SetValues(reps: 12, weight: .kg(8)),
            warmup: true,
            exerciseId: fx.squat.id,
            sessionId: open.id,
            at: t0
        )
        for reps in [10, 9] {
            try fx.sessions.logManualSet(
                SetValues(reps: reps, weight: .kg(16)),
                exerciseId: fx.squat.id,
                sessionId: open.id,
                at: t0
            )
        }
        let pressSet = try fx.sessions.logManualSet(
            SetValues(reps: 5, weight: .kg(30)),
            exerciseId: fx.press.id,
            sessionId: open.id,
            at: t0
        )
        let pressEntry = try #require(try fx.sessions.session(id: open.id)?.entries
            .first { $0.sets.contains { $0.id == pressSet.id } })
        try fx.sessions.removeEntry(id: pressEntry.id)
        if importing {
            try fx.sessions.importEntry(
                ImportedEntry(exerciseId: fx.rower.id, externalRef: fx.ref("e-1"), sets: [
                    ImportedSet(externalRef: fx.ref("e-1#1"), order: 1, values: SetValues(durationSeconds: 600))
                ]),
                into: open.id
            )
        }
        return try fx.sessions.finishSession(id: open.id, at: t0.addingTimeInterval(2400), durationSeconds: 2400)
    }

    @Test("shows the performed exercises in order with their sets; warm-ups are not numbered")
    func sections() throws {
        let workout = try finishedWorkout()
        let detail = model(workout.id)

        detail.load()

        #expect(detail.session == workout)
        #expect(detail.sections.map(\.exerciseName) == ["Goblet Squat"], "skipped and removed entries are left out")
        #expect(detail.sections.map(\.exerciseId) == [fx.squat.id], "a row opens its exercise's sheet (AC1)")
        let squat = try #require(detail.sections.first)
        #expect(squat.sets.map(\.value.values.reps) == [12, 10, 9])
        #expect(squat.sets.map(\.number) == [nil, 1, 2])
        #expect(detail.canDelete)
    }

    @Test("imported sets come before manual ones, and superseded sets are left out")
    func importedFirstWithoutSuperseded() throws {
        let open = try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(
            SetValues(reps: 6, weight: .kg(30)), exerciseId: fx.press.id, sessionId: open.id, at: t0
        )
        try fx.sessions.importEntry(
            ImportedEntry(exerciseId: fx.press.id, externalRef: fx.ref("e-2"), sets: [
                ImportedSet(externalRef: fx.ref("e-2#2"), order: 2, values: SetValues(reps: 8, weight: .kg(40))),
                ImportedSet(externalRef: fx.ref("e-2#1"), order: 1, values: SetValues(reps: 10, weight: .kg(40)))
            ]),
            into: open.id
        )
        let workout = try fx.sessions.finishSession(id: open.id, at: t0.addingTimeInterval(900), durationSeconds: nil)
        let detail = model(workout.id)

        detail.load()

        // The default reconciliation keeps the imported sets: the manual one is superseded.
        let press = try #require(detail.sections.first)
        #expect(press.sets.map(\.value.source) == [.imported, .imported])
        #expect(press.sets.map(\.value.values.reps) == [10, 8])
        #expect(detail.canDelete == false)
    }

    @Test("a workout with machine data cannot be deleted")
    func importedCannotBeDeleted() throws {
        let workout = try finishedWorkout(importing: true)
        let detail = model(workout.id)

        detail.load()

        #expect(detail.sections.map(\.exerciseName) == ["Goblet Squat", "Rowing Machine"])
        #expect(detail.canDelete == false)
        #expect(throws: TrainingDataError.sessionHasImportedData) { try detail.delete() }
        #expect(try fx.sessions.session(id: workout.id) != nil)
    }

    @Test("deleting removes the workout from the store and from the detail")
    func delete() throws {
        let workout = try finishedWorkout()
        let detail = model(workout.id)
        detail.load()

        try detail.delete()

        #expect(try fx.sessions.session(id: workout.id) == nil)
        #expect(detail.session == nil)
        #expect(detail.sections.isEmpty)
        #expect(detail.canDelete == false)
    }

    @Test("an unknown workout, or one in progress, shows nothing and cannot be deleted")
    func notFound() throws {
        let open = try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: TrainingFixtures.zone)
        for id in [UUID(), open.id] {
            let detail = model(id)
            detail.load()
            #expect(detail.isLoaded)
            #expect(detail.session == nil)
            #expect(detail.canDelete == false)
        }
    }
}
