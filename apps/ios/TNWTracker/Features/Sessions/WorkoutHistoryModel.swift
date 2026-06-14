import Foundation
import Observation
import SwiftData
import TNWTrackerKit

// MARK: - WorkoutHistoryModel

/// View model para `WorkoutHistoryListView`.
/// Lista las sesiones completadas (Workout con status `.completed`), paginadas
/// (50 por página), ordenadas por fecha de inicio descendente, con búsqueda por
/// nombre. La lectura usa `ModelContext` directo (igual que `SessionListModel`);
/// las mutaciones (editar/eliminar) las orquesta la vista vía `WorkoutRepository`.
@Observable
@MainActor
final class WorkoutHistoryModel {
    // MARK: - State

    private(set) var workouts: [Workout] = []
    private(set) var isLoading = false
    private(set) var hasNextPage = false

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
        workouts = []
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
        let fetched = fetchWorkouts(context: context, offset: offset)

        workouts.append(contentsOf: fetched)

        hasNextPage = fetched.count == pageSize
        if hasNextPage {
            currentPage += 1
        }
    }

    private func fetchWorkouts(context: ModelContext, offset: Int) -> [Workout] {
        let completedRaw = WorkoutStatus.completed.rawValue
        let query = searchQuery

        var descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = offset

        if query.isEmpty {
            descriptor.predicate = #Predicate<Workout> { workout in
                workout.statusRaw == completedRaw
            }
        } else {
            descriptor.predicate = #Predicate<Workout> { workout in
                workout.statusRaw == completedRaw &&
                    workout.name.localizedStandardContains(query)
            }
        }

        return (try? context.fetch(descriptor)) ?? []
    }
}
