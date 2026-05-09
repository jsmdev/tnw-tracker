import Foundation
import Observation
import SwiftData
import TNWTrackerKit

// MARK: - HomeModel

/// View model for HomeView. Computes weekly progress and next session.
/// REQ-HOME-01, REQ-HOME-02, REQ-HOME-03.
@Observable
@MainActor
final class HomeModel {
    // MARK: - Published State

    /// Number of completed workouts in the current ISO week.
    private(set) var weeklyCompletedCount: Int = 0

    /// Total volume (weight × reps) of completed workouts in the current ISO week.
    private(set) var weeklyVolume: Double = 0.0

    /// The next session template from SwiftData (nil if none exist).
    private(set) var nextSession: Session?

    /// True when there is an active workout today or a session template exists for today.
    /// Drives the Quick Start button visibility (REQ-HOME-03).
    private(set) var hasSessionToday: Bool = false

    /// True while loading data.
    private(set) var isLoading: Bool = false

    // MARK: - Private

    private let container: ModelContainer

    // MARK: - Init

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Load

    /// Fetch all required data from SwiftData and compute derived properties.
    func load() async {
        isLoading = true
        defer { isLoading = false }

        let context = ModelContext(container)

        // Weekly progress
        let (count, volume) = weeklyProgressFromContext(context)
        weeklyCompletedCount = count
        weeklyVolume = volume

        // Next session (first template in store)
        nextSession = nextSessionFromContext(context)

        // Quick-start: today if any active workout OR at least one session template
        hasSessionToday = hasActiveTodayFromContext(context)
    }

    // MARK: - Private helpers

    private func weeklyProgressFromContext(_ context: ModelContext) -> (Int, Double) {
        // Fetch all completed workouts
        var descriptor = FetchDescriptor<Workout>()
        descriptor.predicate = #Predicate { $0.statusRaw == "completed" }
        let workouts = (try? context.fetch(descriptor)) ?? []

        // Filter to current ISO week in Swift (Calendar)
        let calendar = Calendar.current
        let now = Date()
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return (0, 0.0)
        }

        let thisWeekWorkouts = workouts.filter { workout in
            guard let completedAt = workout.completedAt else { return false }
            return weekInterval.contains(completedAt)
        }

        let count = thisWeekWorkouts.count

        // Volume: sum weight × reps for all sets in this week's workouts
        let volume = thisWeekWorkouts.reduce(0.0) { total, workout in
            total + workout.workoutExercises.reduce(0.0) { exerciseTotal, we in
                exerciseTotal + we.exerciseSets.reduce(0.0) { setTotal, set in
                    guard let weight = set.weight, let reps = set.reps else { return setTotal }
                    return setTotal + weight * Double(reps)
                }
            }
        }

        return (count, volume)
    }

    private func nextSessionFromContext(_ context: ModelContext) -> Session? {
        var descriptor = FetchDescriptor<Session>()
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func hasActiveTodayFromContext(_ context: ModelContext) -> Bool {
        // Active workout counts as "session today"
        var activeDescriptor = FetchDescriptor<Workout>()
        activeDescriptor.predicate = #Predicate { $0.statusRaw == "active" }
        activeDescriptor.fetchLimit = 1
        let activeWorkouts = (try? context.fetch(activeDescriptor)) ?? []
        if !activeWorkouts.isEmpty { return true }

        // Any session template means there's something to start
        var sessionDescriptor = FetchDescriptor<Session>()
        sessionDescriptor.fetchLimit = 1
        let sessions = (try? context.fetch(sessionDescriptor)) ?? []
        return !sessions.isEmpty
    }
}
