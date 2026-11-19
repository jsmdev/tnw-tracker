import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

@Suite("RoutineRepository")
@MainActor
struct RoutineRepositoryTests {
    let fx: TrainingFixtures

    init() throws {
        fx = try TrainingFixtures()
    }

    @Test("items and their targets survive a save and a fetch from a fresh context, in order")
    func roundTripItems() throws {
        let routine = Routine(
            externalRef: fx.ref("r-1"),
            name: "Full Body A",
            description: "Squat and press.",
            items: [
                RoutineItem(order: 2, exerciseId: fx.press.id, targetSets: 3, targetReps: RepRange(min: 8, max: 12),
                            targetWeight: Weight(value: 90, unit: .lb), restSeconds: 90, notes: "Seat 4"),
                RoutineItem(order: 1, exerciseId: fx.plank.id, targetSets: 2, targetDurationSeconds: 45)
            ]
        )
        try fx.routines.save(routine)

        let fresh = SwiftDataRoutineRepository(context: ModelContext(fx.store.container))
        let loaded = try #require(try fresh.routine(id: routine.id))
        #expect(loaded.items.map(\.order) == [1, 2])
        #expect(loaded.items[1] == routine.items[0])
        #expect(loaded.items[0] == routine.items[1])
        #expect(loaded.description == "Squat and press.")
        #expect(loaded.externalRef == fx.ref("r-1"))
    }

    @Test("a routine needs at least one item")
    func needsItems() {
        #expect(throws: TrainingDataError.self) {
            try fx.routines.save(Routine(name: "Empty", items: []))
        }
    }

    @Test("item positions are unique and start at 1")
    func positionsUnique() {
        let repeated = Routine(name: "R", items: [
            RoutineItem(order: 1, exerciseId: fx.squat.id),
            RoutineItem(order: 1, exerciseId: fx.press.id)
        ])
        #expect(throws: TrainingDataError.self) { try fx.routines.save(repeated) }
        let zero = Routine(name: "R", items: [RoutineItem(order: 0, exerciseId: fx.squat.id)])
        #expect(throws: TrainingDataError.self) { try fx.routines.save(zero) }
    }

    @Test("every item must name an exercise that exists")
    func exerciseMustExist() {
        let routine = Routine(name: "R", items: [RoutineItem(order: 1, exerciseId: UUID())])
        #expect(throws: TrainingDataError.self) { try fx.routines.save(routine) }
    }

    @Test("a target rep range needs min ≤ max")
    func repRangeOrdered() {
        let routine = Routine(name: "R", items: [
            RoutineItem(order: 1, exerciseId: fx.squat.id, targetReps: RepRange(min: 12, max: 8))
        ])
        #expect(throws: TrainingDataError.self) { try fx.routines.save(routine) }
    }

    @Test("saving an existing routine replaces its items")
    func saveReplacesItems() throws {
        var routine = try fx.makeRoutine()
        routine.items = [RoutineItem(order: 1, exerciseId: fx.plank.id)]
        try fx.routines.save(routine)
        let loaded = try #require(try fx.routines.routine(id: routine.id))
        #expect(loaded.items == [RoutineItem(order: 1, exerciseId: fx.plank.id)])
    }

    @Test("routines are listed by name, searched by name and paged")
    func queryListsSearchesAndPages() throws {
        for name in ["Pull Day", "Push Day", "Legs Day"] {
            _ = try fx.makeRoutine(name: name)
        }
        #expect(try fx.routines.routines(RoutineQuery()).map(\.name) == ["Legs Day", "Pull Day", "Push Day"])
        #expect(try fx.routines.routines(RoutineQuery(search: "pu")).map(\.name) == ["Pull Day", "Push Day"])
        #expect(try fx.routines.routines(RoutineQuery(offset: 1, limit: 1)).map(\.name) == ["Pull Day"])
    }

    @Test("onlyPerformed keeps routines with a completed session")
    func onlyPerformed() throws {
        let performed = try fx.makeRoutine(name: "Performed")
        _ = try fx.makeRoutine(name: "Never")
        let inProgress = try fx.makeRoutine(name: "In progress only")

        let done = try fx.sessions.startSession(
            routineId: performed.id,
            name: nil,
            at: TrainingFixtures.t0,
            timeZone: TrainingFixtures.zone
        )
        try fx.sessions.logManualSet(
            SetValues(reps: 5),
            exerciseId: fx.squat.id,
            sessionId: done.id,
            at: TrainingFixtures.t0
        )
        try fx.sessions.finishSession(
            id: done.id,
            at: TrainingFixtures.t0.addingTimeInterval(600),
            durationSeconds: nil
        )
        _ = try fx.sessions.startSession(
            routineId: inProgress.id,
            name: nil,
            at: TrainingFixtures.t0,
            timeZone: TrainingFixtures.zone
        )

        #expect(try fx.routines.routines(RoutineQuery(onlyPerformed: true)).map(\.name) == ["Performed"])
    }
}
