import Foundation
import Testing
@testable import TNWTrackerKit

/// Exercise sheet actions, AC5: from an exercise's sheet the user adds it to one
/// of their routines, at the end and with no targets, never twice, or creates a
/// routine that holds it. Real in-memory store, invented data only.
@Suite("Add an exercise to a routine (AC5)")
@MainActor
struct AddToRoutineModelTests {
    private let store: TrainingStore
    private let squat = Exercise(name: "Goblet Squat", type: .strength)
    private let press = Exercise(name: "Chest Press Machine", type: .strength)
    private let row = Exercise(name: "Seated Row", type: .strength)

    init() throws {
        store = try TrainingStore.inMemory()
        for exercise in [squat, press, row] {
            try store.exercises.save(exercise)
        }
    }

    private func model(for exercise: Exercise) -> AddToRoutineModel {
        AddToRoutineModel(exerciseId: exercise.id, routines: store.routines)
    }

    @Test("AC5 the menu lists the user's routines, favourites first, then by name")
    func listsRoutines() throws {
        try store.routines.save(Routine(name: "Pull", items: [RoutineItem(order: 1, exerciseId: row.id)]))
        let push = Routine(name: "Push", items: [RoutineItem(order: 1, exerciseId: press.id)])
        try store.routines.save(push)
        try store.routines.save(Routine(name: "Legs", items: [RoutineItem(order: 1, exerciseId: squat.id)]))
        try store.routines.setFavorite(true, routineId: push.id)
        let model = model(for: squat)

        model.load()

        #expect(model.routines.map(\.name) == ["Push", "Legs", "Pull"])
        #expect(!model.loadFailed)
    }

    @Test("AC5 adding puts the exercise at the end, with no targets, and keeps the others as they were")
    func addsAtTheEnd() throws {
        let original = Routine(name: "Push", items: [
            RoutineItem(order: 1, exerciseId: press.id, targetSets: 3, targetReps: RepRange(min: 8, max: 12)),
            RoutineItem(order: 4, exerciseId: row.id, restSeconds: 90)
        ])
        try store.routines.save(original)
        let model = model(for: squat)
        model.load()

        let result = try model.add(to: original.id)

        #expect(result == .added(routineName: "Push"))
        let saved = try #require(try store.routines.routine(id: original.id))
        #expect(saved.items == original.items + [RoutineItem(order: 5, exerciseId: squat.id)])
        #expect(saved.name == "Push")
        #expect(model.routines.first?.items.last?.exerciseId == squat.id, "the menu shows the routine as saved")
    }

    @Test("AC5 a routine that already has the exercise is left as it was")
    func neverDuplicates() throws {
        let original = Routine(name: "Legs", items: [
            RoutineItem(order: 1, exerciseId: squat.id, targetSets: 4),
            RoutineItem(order: 2, exerciseId: row.id)
        ])
        try store.routines.save(original)
        let model = model(for: squat)

        let result = try model.add(to: original.id)

        #expect(result == .alreadyInRoutine(routineName: "Legs"))
        #expect(try store.routines.routine(id: original.id)?.items == original.items)
    }

    @Test("AC5 adding to a routine that no longer exists fails and creates nothing")
    func missingRoutine() throws {
        let model = model(for: squat)

        #expect(throws: TrainingDataError.notFound) {
            try model.add(to: UUID())
        }
        #expect(try store.routines.routines(RoutineQuery()).isEmpty)
    }

    @Test("AC5 a new routine is created with the name, trimmed, and only this exercise")
    func createsRoutine() throws {
        let model = model(for: press)

        let created = try model.createRoutine(named: "  Upper body  ")

        let saved = try #require(try store.routines.routine(id: created.id))
        #expect(saved.name == "Upper body")
        #expect(saved.items == [RoutineItem(order: 1, exerciseId: press.id)])
        #expect(!saved.isFavorite)
        #expect(try store.routines.routines(RoutineQuery()).count == 1)
        #expect(model.routines.map(\.name) == ["Upper body"], "the menu lists the new routine")
    }

    @Test("AC5 a blank name creates nothing")
    func blankNameCreatesNothing() throws {
        let model = model(for: press)

        #expect(!AddToRoutineModel.isValidName("   "))
        #expect(AddToRoutineModel.isValidName(" Upper "))
        #expect(throws: TrainingDataError.self) {
            try model.createRoutine(named: "   ")
        }
        #expect(try store.routines.routines(RoutineQuery()).isEmpty)
    }
}
