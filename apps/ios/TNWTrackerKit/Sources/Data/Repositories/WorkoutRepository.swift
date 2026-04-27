import Foundation
import SwiftData

public protocol WorkoutRepositoryProtocol: AnyObject, Sendable {
    func fetchActive() async throws -> Workout?
    func fetchHistory(limit: Int) async throws -> [Workout]
    func fetch(id: UUID) async throws -> Workout?
    func create(_ workout: Workout) async throws
    func update(_ workout: Workout) async throws
    func complete(_ workout: Workout) async throws
}

@MainActor
public final class WorkoutRepository: WorkoutRepositoryProtocol {
    private let modelContext: ModelContext
    private let syncEngine: any SyncEngine

    public init(modelContext: ModelContext, syncEngine: any SyncEngine) {
        self.modelContext = modelContext
        self.syncEngine = syncEngine
    }

    public func fetchActive() async throws -> Workout? {
        let activeRaw = WorkoutStatus.active.rawValue
        let pausedRaw = WorkoutStatus.paused.rawValue
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { workout in
                workout.statusRaw == activeRaw || workout.statusRaw == pausedRaw
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    public func fetchHistory(limit: Int) async throws -> [Workout] {
        let completedRaw = WorkoutStatus.completed.rawValue
        let cancelledRaw = WorkoutStatus.cancelled.rawValue
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { workout in
                workout.statusRaw == completedRaw || workout.statusRaw == cancelledRaw
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    public func fetch(id: UUID) async throws -> Workout? {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    public func create(_ workout: Workout) async throws {
        modelContext.insert(workout)
        try modelContext.save()
        workout.pendingSyncOp = "insert"
        try await syncEngine.enqueueLocalChange(
            tableName: "workouts",
            recordId: workout.id,
            operationType: "insert",
            payload: nil
        )
    }

    public func update(_ workout: Workout) async throws {
        workout.updatedAt = Date()
        workout.pendingSyncOp = "update"
        try modelContext.save()
        try await syncEngine.enqueueLocalChange(
            tableName: "workouts",
            recordId: workout.id,
            operationType: "update",
            payload: nil
        )
    }

    public func complete(_ workout: Workout) async throws {
        workout.completedAt = Date()
        workout.statusRaw = WorkoutStatus.completed.rawValue
        workout.updatedAt = Date()
        workout.pendingSyncOp = "update"
        try modelContext.save()
        try await syncEngine.enqueueLocalChange(
            tableName: "workouts",
            recordId: workout.id,
            operationType: "update",
            payload: nil
        )
    }
}
