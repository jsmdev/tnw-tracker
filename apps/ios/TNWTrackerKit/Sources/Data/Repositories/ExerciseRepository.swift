import Foundation
import SwiftData

public protocol ExerciseRepositoryProtocol: AnyObject, Sendable {
    func fetchAll() async throws -> [Exercise]
    func fetch(id: UUID) async throws -> Exercise?
    func create(_ exercise: Exercise) async throws
    func update(_ exercise: Exercise) async throws
    func softDelete(_ exercise: Exercise) async throws
}

@MainActor
public final class ExerciseRepository: ExerciseRepositoryProtocol {
    private let modelContext: ModelContext
    private let syncEngine: any SyncEngine

    public init(modelContext: ModelContext, syncEngine: any SyncEngine) {
        self.modelContext = modelContext
        self.syncEngine = syncEngine
    }

    public func fetchAll() async throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    public func fetch(id: UUID) async throws -> Exercise? {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    public func create(_ exercise: Exercise) async throws {
        modelContext.insert(exercise)
        try modelContext.save()
        exercise.pendingSyncOp = "insert"
        try await syncEngine.enqueueLocalChange(
            tableName: "exercises",
            recordId: exercise.id,
            operationType: "insert",
            payload: nil
        )
    }

    public func update(_ exercise: Exercise) async throws {
        exercise.updatedAt = Date()
        exercise.pendingSyncOp = "update"
        try modelContext.save()
        try await syncEngine.enqueueLocalChange(
            tableName: "exercises",
            recordId: exercise.id,
            operationType: "update",
            payload: nil
        )
    }

    public func softDelete(_ exercise: Exercise) async throws {
        exercise.isActive = false
        exercise.updatedAt = Date()
        exercise.pendingSyncOp = "update"
        try modelContext.save()
        try await syncEngine.enqueueLocalChange(
            tableName: "exercises",
            recordId: exercise.id,
            operationType: "update",
            payload: nil
        )
    }
}
