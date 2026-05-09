import Foundation
import SwiftData
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - WorkoutSummaryBuilderTests

//
// RED→GREEN tests for WorkoutSummaryBuilder pure value type.
// Covers: PR detection, duration FormatStyle locale-aware, volume calculation.
// Uses in-memory ModelContainer + explicit-append relationship pattern (per swiftdata bug).

@Suite("WorkoutSummaryBuilder", .serialized)
struct WorkoutSummaryBuilderTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerFactory.makeContainer(inMemory: true)
    }

    // MARK: - PR Detection

    @Test("PR detected when exercise hits new max weight")
    func prDetectedForNewMaxWeight() throws {
        let context = ModelContext(container)
        let userId = UUID()
        let exerciseId = UUID()

        // Insert exercise
        let exercise = Exercise(name: "Bench Press", category: "strength")
        exercise.id = exerciseId
        context.insert(exercise)

        // Insert a previous PersonalRecord at 80kg
        let prevPR = PersonalRecord(userId: userId, exerciseId: exerciseId, type: .maxWeight, value: 80.0)
        context.insert(prevPR)

        // Build a workout where the set reaches 100kg (new max)
        let workout = Workout(userId: userId, name: "Push Day")
        context.insert(workout)

        let we = WorkoutExercise(workoutId: workout.id, exerciseId: exerciseId, orderIndex: 0)
        context.insert(we)
        workout.workoutExercises.append(we)

        let set = ExerciseSet(workoutExerciseId: we.id, setNumber: 1)
        set.reps = 5
        set.weight = 100.0
        set.weightUnit = .kg
        set.isWarmup = false
        set.completedAt = Date()
        context.insert(set)
        we.exerciseSets.append(set)

        try context.save()

        let summary = WorkoutSummaryBuilder.build(from: workout, context: context)

        #expect(summary.personalRecords.count == 1)
        #expect(summary.personalRecords.first?.exerciseName == "Bench Press")
        #expect(summary.personalRecords.first?.newValue == 100.0)
    }

    @Test("No PR when exercise does not beat previous max weight")
    func noPRWhenNotBeatingPreviousMax() throws {
        let context = ModelContext(container)
        let userId = UUID()
        let exerciseId = UUID()

        let exercise = Exercise(name: "Squat", category: "strength")
        exercise.id = exerciseId
        context.insert(exercise)

        // Previous PR at 120kg
        let prevPR = PersonalRecord(userId: userId, exerciseId: exerciseId, type: .maxWeight, value: 120.0)
        context.insert(prevPR)

        // Workout with max set at 100kg (does NOT beat PR)
        let workout = Workout(userId: userId, name: "Leg Day")
        context.insert(workout)

        let we = WorkoutExercise(workoutId: workout.id, exerciseId: exerciseId, orderIndex: 0)
        context.insert(we)
        workout.workoutExercises.append(we)

        let set = ExerciseSet(workoutExerciseId: we.id, setNumber: 1)
        set.reps = 5
        set.weight = 100.0
        set.weightUnit = .kg
        set.isWarmup = false
        set.completedAt = Date()
        context.insert(set)
        we.exerciseSets.append(set)

        try context.save()

        let summary = WorkoutSummaryBuilder.build(from: workout, context: context)

        #expect(summary.personalRecords.isEmpty)
    }

    @Test("PR detected when no previous record exists for exercise")
    func prDetectedWhenNoPreviousRecord() throws {
        let context = ModelContext(container)
        let userId = UUID()
        let exerciseId = UUID()

        let exercise = Exercise(name: "Deadlift", category: "strength")
        exercise.id = exerciseId
        context.insert(exercise)

        // No previous PersonalRecord for this exercise

        let workout = Workout(userId: userId, name: "Pull Day")
        context.insert(workout)

        let we = WorkoutExercise(workoutId: workout.id, exerciseId: exerciseId, orderIndex: 0)
        context.insert(we)
        workout.workoutExercises.append(we)

        let set = ExerciseSet(workoutExerciseId: we.id, setNumber: 1)
        set.reps = 3
        set.weight = 150.0
        set.weightUnit = .kg
        set.isWarmup = false
        set.completedAt = Date()
        context.insert(set)
        we.exerciseSets.append(set)

        try context.save()

        let summary = WorkoutSummaryBuilder.build(from: workout, context: context)

        #expect(summary.personalRecords.count == 1)
        #expect(summary.personalRecords.first?.newValue == 150.0)
    }

    // MARK: - Volume Calculation

    @Test("Total volume = sum of weight × reps across all sets")
    func totalVolumeCalculation() throws {
        let context = ModelContext(container)
        let userId = UUID()

        let workout = Workout(userId: userId, name: "Volume Test")
        context.insert(workout)

        let we = WorkoutExercise(workoutId: workout.id, exerciseId: UUID(), orderIndex: 0)
        context.insert(we)
        workout.workoutExercises.append(we)

        // Set 1: 3 × 100kg = 300
        let s1 = ExerciseSet(workoutExerciseId: we.id, setNumber: 1)
        s1.reps = 3; s1.weight = 100.0; s1.weightUnit = .kg; s1.isWarmup = false
        context.insert(s1); we.exerciseSets.append(s1)

        // Set 2: 5 × 80kg = 400
        let s2 = ExerciseSet(workoutExerciseId: we.id, setNumber: 2)
        s2.reps = 5; s2.weight = 80.0; s2.weightUnit = .kg; s2.isWarmup = false
        context.insert(s2); we.exerciseSets.append(s2)

        // Warmup: should be excluded from volume
        let s3 = ExerciseSet(workoutExerciseId: we.id, setNumber: 3)
        s3.reps = 10; s3.weight = 40.0; s3.weightUnit = .kg; s3.isWarmup = true
        context.insert(s3); we.exerciseSets.append(s3)

        try context.save()

        let summary = WorkoutSummaryBuilder.build(from: workout, context: context)

        // 3×100 + 5×80 = 300 + 400 = 700 (warmup excluded)
        #expect(summary.totalVolumeKg == 700.0)
    }

    // MARK: - Duration FormatStyle (locale-aware)

    @Test("Duration FormatStyle formats correctly with es-ES locale")
    func durationFormatStyleEsES() throws {
        let context = ModelContext(container)
        let userId = UUID()

        // Workout started 75 minutes ago
        var workout = Workout(userId: userId, name: "Duration Test")
        let startTime = Date().addingTimeInterval(-75 * 60)
        workout.startedAt = startTime
        workout.completedAt = Date()
        context.insert(workout)
        try context.save()

        let summary = WorkoutSummaryBuilder.build(from: workout, context: context)

        // Duration should be approximately 75 minutes (4500 seconds)
        let durationSeconds = summary.durationSeconds
        #expect(durationSeconds >= 4490 && durationSeconds <= 4510)

        // Format with es-ES locale — Duration.TimeFormatStyle
        let duration = Duration.seconds(durationSeconds)
        let formatted = duration.formatted(
            .time(pattern: .hourMinuteSecond)
                .locale(Locale(identifier: "es-ES"))
        )
        // Should produce "1:15:00" or locale-equivalent (non-empty, no raw interpolation)
        #expect(!formatted.isEmpty)
        #expect(formatted.contains("1"))
        #expect(formatted.contains("15"))
    }

    @Test("Duration FormatStyle under one hour uses minuteSecond pattern")
    func durationFormatStyleUnderOneHour() throws {
        let context = ModelContext(container)
        let userId = UUID()

        var workout = Workout(userId: userId, name: "Short Workout")
        let startTime = Date().addingTimeInterval(-30 * 60) // 30 min ago
        workout.startedAt = startTime
        workout.completedAt = Date()
        context.insert(workout)
        try context.save()

        let summary = WorkoutSummaryBuilder.build(from: workout, context: context)

        let durationSeconds = summary.durationSeconds
        #expect(durationSeconds >= 1790 && durationSeconds <= 1810)

        // Verify the duration is under an hour — format with minuteSecond pattern
        let duration = Duration.seconds(durationSeconds)
        let formatted = duration.formatted(
            .time(pattern: .minuteSecond)
                .locale(Locale(identifier: "es-ES"))
        )
        #expect(!formatted.isEmpty)
        #expect(formatted.contains("30"))
    }

    // MARK: - Exercise listing

    @Test("Exercise rows include name and set count")
    func exerciseRowsIncludeNameAndSetCount() throws {
        let context = ModelContext(container)
        let userId = UUID()
        let exerciseId = UUID()

        let exercise = Exercise(name: "Overhead Press", category: "strength")
        exercise.id = exerciseId
        context.insert(exercise)

        let workout = Workout(userId: userId, name: "Push")
        context.insert(workout)

        let we = WorkoutExercise(workoutId: workout.id, exerciseId: exerciseId, orderIndex: 0)
        context.insert(we)
        workout.workoutExercises.append(we)

        for i in 1 ... 4 {
            let s = ExerciseSet(workoutExerciseId: we.id, setNumber: i)
            s.reps = 8; s.weight = 60.0; s.weightUnit = .kg; s.isWarmup = false
            context.insert(s); we.exerciseSets.append(s)
        }

        try context.save()

        let summary = WorkoutSummaryBuilder.build(from: workout, context: context)

        #expect(summary.exerciseRows.count == 1)
        #expect(summary.exerciseRows.first?.exerciseName == "Overhead Press")
        #expect(summary.exerciseRows.first?.setCount == 4)
    }
}
