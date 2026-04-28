import Foundation
import SwiftData

@MainActor
public protocol RoutineRepositoryProtocol: AnyObject, Sendable {
    func fetchAll() async throws -> [Routine]
    func fetch(id: UUID) async throws -> Routine?
    func create(_ routine: Routine) async throws
    func update(_ routine: Routine) async throws
    func delete(_ routine: Routine) async throws
}

@MainActor
public final class RoutineRepository: RoutineRepositoryProtocol {
    private let modelContext: ModelContext
    private let syncEngine: any SyncEngine

    public init(modelContext: ModelContext, syncEngine: any SyncEngine) {
        self.modelContext = modelContext
        self.syncEngine = syncEngine
    }

    public func fetchAll() async throws -> [Routine] {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    public func fetch(id: UUID) async throws -> Routine? {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    public func create(_ routine: Routine) async throws {
        modelContext.insert(routine)
        try modelContext.save()
        routine.pendingSyncOp = "insert"
        try await syncEngine.enqueueLocalChange(
            tableName: "routines",
            recordId: routine.id,
            operationType: "insert",
            payload: nil
        )
    }

    public func update(_ routine: Routine) async throws {
        routine.updatedAt = Date()
        routine.pendingSyncOp = "update"
        try modelContext.save()
        try await syncEngine.enqueueLocalChange(
            tableName: "routines",
            recordId: routine.id,
            operationType: "update",
            payload: nil
        )
    }

    public func delete(_ routine: Routine) async throws {
        let recordId = routine.id
        modelContext.delete(routine)
        try modelContext.save()
        try await syncEngine.enqueueLocalChange(
            tableName: "routines",
            recordId: recordId,
            operationType: "delete",
            payload: nil
        )
    }
}
