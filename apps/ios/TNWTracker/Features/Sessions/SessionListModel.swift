import Foundation
import Observation
import SwiftData
import TNWTrackerKit

// MARK: - SessionListModel

/// View model for SessionListView.
/// Manages pagination (50 per page), filter (.all / .withWorkouts), ordering (most recent first),
/// and search-by-name. Covers REQ-SESSLIST-01, REQ-SESSLIST-02, REQ-SESSLIST-03.
@Observable
@MainActor
final class SessionListModel {
    // MARK: - Nested Types

    enum Filter: String, CaseIterable {
        case all
        case withWorkouts
    }

    // MARK: - State

    private(set) var sessions: [Session] = []
    private(set) var isLoading = false
    private(set) var hasNextPage = false

    var filter: Filter = .all {
        didSet { if oldValue != filter { Task { await loadFirstPage() } } }
    }

    var searchQuery: String = "" {
        didSet { if oldValue != searchQuery { Task { await loadFirstPage() } } }
    }

    // MARK: - Private

    private let container: ModelContainer
    private let pageSize = 50
    private var currentPage = 0

    // MARK: - Init

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Public API

    func loadFirstPage() async {
        currentPage = 0
        sessions = []
        await loadPage()
    }

    func loadMore() async {
        guard hasNextPage, !isLoading else { return }
        await loadPage()
    }

    // MARK: - Private

    private func loadPage() async {
        isLoading = true
        defer { isLoading = false }

        let context = ModelContext(container)
        let offset = currentPage * pageSize

        let fetched = fetchSessions(context: context, offset: offset)

        if filter == .withWorkouts {
            let filtered = applyWithWorkoutsFilter(fetched, context: context)
            sessions.append(contentsOf: filtered)
        } else {
            sessions.append(contentsOf: fetched)
        }

        // If we got a full page, there may be more
        hasNextPage = fetched.count == pageSize
        if hasNextPage {
            currentPage += 1
        }
    }

    private func fetchSessions(context: ModelContext, offset: Int) -> [Session] {
        var descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = offset

        if !searchQuery.isEmpty {
            let query = searchQuery
            descriptor.predicate = #Predicate<Session> { session in
                session.name.localizedStandardContains(query)
            }
        }

        return (try? context.fetch(descriptor)) ?? []
    }

    /// Filters sessions to those that have at least one completed Workout referencing them by sessionId.
    private func applyWithWorkoutsFilter(_ sessions: [Session], context: ModelContext) -> [Session] {
        guard !sessions.isEmpty else { return [] }

        // Fetch all completed workouts that have a sessionId set
        var workoutDescriptor = FetchDescriptor<Workout>()
        workoutDescriptor.predicate = #Predicate<Workout> { workout in
            workout.statusRaw == "completed"
        }
        let completedWorkouts = (try? context.fetch(workoutDescriptor)) ?? []

        // Build set of sessionIds that have at least one completed workout
        let sessionIdsWithWorkouts = Set(completedWorkouts.compactMap(\.sessionId))

        return sessions.filter { sessionIdsWithWorkouts.contains($0.id) }
    }
}
