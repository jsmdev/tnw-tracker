import Foundation
import Observation
import TNWTrackerKit

// MARK: - SessionListModel

/// View model for SessionListView: the routines the user can start.
/// Manages pagination (50 per page), filter (.all / .withWorkouts), ordering (favourites first, then by name),
/// and search-by-name. Covers REQ-SESSLIST-01, REQ-SESSLIST-02, REQ-SESSLIST-03.
@Observable
@MainActor
final class SessionListModel {
    // MARK: - Nested Types

    enum Filter: String, CaseIterable {
        case all
        /// Routines with at least one completed session.
        case withWorkouts
    }

    // MARK: - State

    private(set) var sessions: [Routine] = []
    private(set) var isLoading = false
    private(set) var hasNextPage = false

    var filter: Filter = .all {
        didSet { if oldValue != filter { Task { await loadFirstPage() } } }
    }

    var searchQuery: String = "" {
        didSet { if oldValue != searchQuery { Task { await loadFirstPage() } } }
    }

    // MARK: - Private

    private let routines: any RoutineRepositoryProtocol
    private let pageSize = 50
    private var currentPage = 0

    // MARK: - Init

    init(routines: any RoutineRepositoryProtocol) {
        self.routines = routines
    }

    // MARK: - Public API

    func loadFirstPage() async {
        currentPage = 0
        sessions = []
        await loadPage()
    }

    /// Marks or unmarks `routine` as a favourite and reloads the list, so it
    /// moves into or out of the favourites group (AC5.1, AC5.4).
    func setFavorite(_ favorite: Bool, for routine: Routine) async {
        try? routines.setFavorite(favorite, routineId: routine.id)
        await loadFirstPage()
    }

    func loadMore() async {
        guard hasNextPage, !isLoading else { return }
        await loadPage()
    }

    // MARK: - Private

    private func loadPage() async {
        isLoading = true
        defer { isLoading = false }

        let query = RoutineQuery(
            search: searchQuery,
            onlyPerformed: filter == .withWorkouts,
            offset: currentPage * pageSize,
            limit: pageSize
        )
        let fetched = (try? routines.routines(query)) ?? []
        sessions.append(contentsOf: fetched)

        // If we got a full page, there may be more
        hasNextPage = fetched.count == pageSize
        if hasNextPage {
            currentPage += 1
        }
    }
}
