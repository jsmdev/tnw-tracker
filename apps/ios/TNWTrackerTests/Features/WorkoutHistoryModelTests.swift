import Foundation
import SwiftData
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - WorkoutHistoryModelTests

// Tests del histórico de sesiones completadas: paginación, orden, búsqueda y
// el filtrado por status .completed. Usa un ModelContainer in-memory.

@Suite("WorkoutHistoryModel", .serialized)
@MainActor
struct WorkoutHistoryModelTests {
    let container: ModelContainer
    let userId = UUID()

    init() throws {
        container = try ModelContainerFactory.makeContainer(inMemory: true)
    }

    private func insertCompleted(_ context: ModelContext, name: String, startedAt: Date = Date()) {
        let w = Workout(userId: userId, name: name)
        w.status = .completed
        w.startedAt = startedAt
        w.completedAt = startedAt
        context.insert(w)
    }

    // MARK: - Filtrado por status

    @Test("solo lista workouts completados, no activos ni cancelados")
    func onlyCompletedWorkouts() async throws {
        let context = ModelContext(container)
        insertCompleted(context, name: "Done")
        let active = Workout(userId: userId, name: "Active")
        active.status = .active
        context.insert(active)
        let cancelled = Workout(userId: userId, name: "Cancelled")
        cancelled.status = .cancelled
        context.insert(cancelled)
        try context.save()

        let model = WorkoutHistoryModel(container: container)
        await model.loadFirstPage()

        #expect(model.workouts.count == 1)
        #expect(model.workouts.first?.name == "Done")
    }

    // MARK: - Paginación

    @Test("loadFirstPage devuelve a lo sumo 50 cuando hay más")
    func paginationReturnsFirst50() async throws {
        let context = ModelContext(container)
        for i in 0 ..< 60 {
            insertCompleted(context, name: "W \(i)", startedAt: Date().addingTimeInterval(Double(i)))
        }
        try context.save()

        let model = WorkoutHistoryModel(container: container)
        await model.loadFirstPage()

        #expect(model.workouts.count == 50)
        #expect(model.hasNextPage)
    }

    @Test("loadMore agrega la página siguiente")
    func loadMoreAppendsNextPage() async throws {
        let context = ModelContext(container)
        for i in 0 ..< 60 {
            insertCompleted(context, name: "W \(i)", startedAt: Date().addingTimeInterval(Double(i)))
        }
        try context.save()

        let model = WorkoutHistoryModel(container: container)
        await model.loadFirstPage()
        await model.loadMore()

        #expect(model.workouts.count == 60)
        #expect(!model.hasNextPage)
    }

    // MARK: - Orden

    @Test("ordena por startedAt descendente (más reciente primero)")
    func orderedMostRecentFirst() async throws {
        let context = ModelContext(container)
        insertCompleted(context, name: "Older", startedAt: Date().addingTimeInterval(-100))
        insertCompleted(context, name: "Newer", startedAt: Date())
        try context.save()

        let model = WorkoutHistoryModel(container: container)
        await model.loadFirstPage()

        #expect(model.workouts.first?.name == "Newer")
    }

    // MARK: - Búsqueda

    @Test("búsqueda por nombre filtra resultados")
    func searchByName() async throws {
        let context = ModelContext(container)
        insertCompleted(context, name: "Push Day")
        insertCompleted(context, name: "Pull Day")
        insertCompleted(context, name: "Legs Day")
        try context.save()

        let model = WorkoutHistoryModel(container: container)
        model.searchQuery = "Push"
        await model.loadFirstPage()

        #expect(model.workouts.count == 1)
        #expect(model.workouts.first?.name == "Push Day")
    }
}
