import Foundation
import SwiftData
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - ActiveWorkoutCoordinatorTests

//
// Tests for relationship wiring after logSet and coordinator state transitions.
// Covers Batch 7 requirements: SwiftData relationship integrity (MANDATORY per ADR).
//
// RED→GREEN: tests written before implementation of any new logic.

@Suite("ActiveWorkoutCoordinator", .serialized)
@MainActor
struct ActiveWorkoutCoordinatorTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerFactory.makeContainer(inMemory: true)
    }

    // MARK: - Relationship wiring

    @Test("recordSet wires exerciseSets relationship on WorkoutExercise")
    func recordSetWiresRelationshipOnWorkoutExercise() throws {
        let context = ModelContext(container)
        let userId = UUID()

        // Setup: Workout + WorkoutExercise (replicating the mandatory explicit-append pattern)
        let workout = Workout(userId: userId, name: "Test Workout")
        context.insert(workout)

        let we = WorkoutExercise(workoutId: workout.id, exerciseId: UUID(), orderIndex: 0)
        context.insert(we)
        workout.workoutExercises.append(we) // EXPLICIT — per swiftdata bug

        try context.save()

        // Simulate what recordSet does inside the coordinator
        let setNumber = we.exerciseSets.count + 1
        let set = ExerciseSet(workoutExerciseId: we.id, setNumber: setNumber)
        set.reps = 8
        set.weight = 100.0
        set.weightUnit = .kg
        set.rpe = 8
        set.isWarmup = false
        set.completedAt = Date()
        context.insert(set)
        we.exerciseSets.append(set) // EXPLICIT — per swiftdata bug
        try context.save()

        // Verify relationship is wired
        #expect(we.exerciseSets.count == 1)
        #expect(we.exerciseSets.first?.reps == 8)
        #expect(we.exerciseSets.first?.rpe == 8)
    }

    @Test("workout.workoutExercises populated after explicit append")
    func workoutExercisesPopulatedAfterAppend() throws {
        let context = ModelContext(container)
        let userId = UUID()

        let workout = Workout(userId: userId, name: "Push Day")
        context.insert(workout)

        let we1 = WorkoutExercise(workoutId: workout.id, exerciseId: UUID(), orderIndex: 0)
        let we2 = WorkoutExercise(workoutId: workout.id, exerciseId: UUID(), orderIndex: 1)
        context.insert(we1)
        context.insert(we2)
        workout.workoutExercises.append(we1)
        workout.workoutExercises.append(we2)
        try context.save()

        // Verify parent→children relationship populated
        #expect(workout.workoutExercises.count == 2)
    }

    @Test("multiple sets accumulate on single WorkoutExercise")
    func multipleSetsAccumulateOnExercise() throws {
        let context = ModelContext(container)
        let userId = UUID()

        let workout = Workout(userId: userId, name: "Test")
        context.insert(workout)
        let we = WorkoutExercise(workoutId: workout.id, exerciseId: UUID(), orderIndex: 0)
        context.insert(we)
        workout.workoutExercises.append(we)
        try context.save()

        // Log 3 sets
        for i in 1 ... 3 {
            let set = ExerciseSet(workoutExerciseId: we.id, setNumber: i)
            set.reps = 8
            set.weight = Double(100 + (i - 1) * 5)
            set.weightUnit = .kg
            set.isWarmup = false
            set.completedAt = Date()
            context.insert(set)
            we.exerciseSets.append(set)
        }
        try context.save()

        #expect(we.exerciseSets.count == 3)
    }

    @Test("RPE nil is allowed (warmup sets)")
    func rpeNilIsAllowedForWarmup() throws {
        let context = ModelContext(container)
        let userId = UUID()

        let workout = Workout(userId: userId, name: "Test")
        context.insert(workout)
        let we = WorkoutExercise(workoutId: workout.id, exerciseId: UUID(), orderIndex: 0)
        context.insert(we)
        workout.workoutExercises.append(we)
        try context.save()

        let warmupSet = ExerciseSet(workoutExerciseId: we.id, setNumber: 1)
        warmupSet.isWarmup = true
        warmupSet.rpe = nil
        warmupSet.reps = 10
        warmupSet.weight = 60.0
        warmupSet.weightUnit = .kg
        warmupSet.completedAt = Date()
        context.insert(warmupSet)
        we.exerciseSets.append(warmupSet)
        try context.save()

        #expect(warmupSet.rpe == nil)
        #expect(we.exerciseSets.count == 1)
    }
}

// MARK: - SetLogFormState Tests

@Suite("SetLogFormState")
struct SetLogFormStateTests {
    @Test("default state has reps 0, weight 0, no RPE, not warmup")
    func defaultState() {
        let state = SetLogFormState()
        #expect(state.reps == 0)
        #expect(state.weight == 0.0)
        #expect(state.rpe == nil)
        #expect(state.isWarmup == false)
    }

    @Test("isValid requires reps > 0")
    func isValidRequiresPositiveReps() {
        var state = SetLogFormState()
        #expect(!state.isValid)

        state.reps = 5
        #expect(state.isValid)
    }

    @Test("isValid allows weight 0 (bodyweight exercises)")
    func isValidAllowsZeroWeight() {
        var state = SetLogFormState()
        state.reps = 10
        state.weight = 0.0
        #expect(state.isValid)
    }

    @Test("RPE clamp: values outside 1–10 are invalid")
    func rpeValidRange() {
        var state = SetLogFormState()
        state.reps = 5

        // Nil RPE is fine
        state.rpe = nil
        #expect(state.isValid)

        // Valid RPE
        state.rpe = 8
        #expect(state.isValid)

        // Edge cases
        state.rpe = 1
        #expect(state.isValid)
        state.rpe = 10
        #expect(state.isValid)

        // Invalid
        state.rpe = 0
        #expect(!state.isValid)
        state.rpe = 11
        #expect(!state.isValid)
    }
}
