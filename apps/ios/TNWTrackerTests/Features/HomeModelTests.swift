import Foundation
import SwiftData
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - HomeModelTests

// Tests HomeModel logic: weekly progress calculation and next session derivation.
// Uses in-memory ModelContainer. Covers REQ-HOME-01 and REQ-HOME-02.

@Suite("HomeModel", .serialized)
@MainActor
struct HomeModelTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerFactory.makeContainer(inMemory: true)
    }

    // MARK: - Weekly Progress

    @Test("weeklyProgress returns zero when no workouts exist")
    func weeklyProgressReturnsZeroOnEmptyWorkouts() async {
        let model = HomeModel(container: container)
        await model.load()

        #expect(model.weeklyCompletedCount == 0)
        #expect(model.weeklyVolume == 0.0)
    }

    @Test("weeklyProgress counts only workouts completed in the current ISO week")
    func weeklyProgressCountsCurrentWeekOnly() async throws {
        let context = ModelContext(container)
        let userId = UUID()

        // Workout completed this week
        let thisWeek = Workout(userId: userId, name: "Push Day")
        thisWeek.status = .completed
        thisWeek.completedAt = Date()
        context.insert(thisWeek)

        // Workout completed last week (should NOT be counted)
        var comps = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekOfYear = (comps.weekOfYear ?? 1) - 1
        let lastWeekDate = Calendar.current.date(from: comps) ?? Date()
        let lastWeek = Workout(userId: userId, name: "Pull Day")
        lastWeek.status = .completed
        lastWeek.completedAt = lastWeekDate
        context.insert(lastWeek)

        try context.save()

        let model = HomeModel(container: container)
        await model.load()

        #expect(model.weeklyCompletedCount == 1)
    }

    @Test("weeklyVolume sums weight × reps for all sets in current week workouts")
    func weeklyVolumeSumsCurrentWeekSets() async throws {
        let context = ModelContext(container)
        let userId = UUID()

        let workout = Workout(userId: userId, name: "Push Day")
        workout.status = .completed
        workout.completedAt = Date()
        context.insert(workout)

        let we = WorkoutExercise(workoutId: workout.id, exerciseId: UUID(), orderIndex: 0)
        context.insert(we)

        // Set 1: 100kg × 5 reps = 500
        let set1 = ExerciseSet(workoutExerciseId: we.id, setNumber: 1)
        set1.weight = 100.0
        set1.reps = 5
        set1.completedAt = Date()
        context.insert(set1)

        // Set 2: 80kg × 10 reps = 800
        let set2 = ExerciseSet(workoutExerciseId: we.id, setNumber: 2)
        set2.weight = 80.0
        set2.reps = 10
        set2.completedAt = Date()
        context.insert(set2)

        we.exerciseSets = [set1, set2]
        workout.workoutExercises = [we]
        try context.save()

        let model = HomeModel(container: container)
        await model.load()

        #expect(model.weeklyVolume == 1300.0)
    }

    // MARK: - Next Session

    @Test("nextSession returns nil when no sessions exist")
    func nextSessionReturnsNilWhenNoSessions() async {
        let model = HomeModel(container: container)
        await model.load()

        #expect(model.nextSession == nil)
    }

    @Test("nextSession returns first session template when sessions exist")
    func nextSessionReturnsSomeSessionWhenSessionsExist() async throws {
        let context = ModelContext(container)
        let userId = UUID()
        let session = Session(userId: userId, name: "Push Day")
        context.insert(session)
        try context.save()

        let model = HomeModel(container: container)
        await model.load()

        #expect(model.nextSession != nil)
        #expect(model.nextSession?.name == "Push Day")
    }

    // MARK: - hasSessionToday

    @Test("hasSessionToday returns false when no workouts active or sessions scheduled today")
    func hasSessionTodayReturnsFalseWhenEmpty() async {
        let model = HomeModel(container: container)
        await model.load()

        #expect(model.hasSessionToday == false)
    }
}
