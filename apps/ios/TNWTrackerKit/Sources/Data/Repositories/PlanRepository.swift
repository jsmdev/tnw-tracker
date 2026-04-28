import Foundation
import SwiftData

@MainActor
public protocol PlanRepositoryProtocol: AnyObject, Sendable {
    func fetchAll() async throws -> [Plan]
    func fetch(id: UUID) async throws -> Plan?
    func create(_ plan: Plan) async throws
    func update(_ plan: Plan) async throws
    func delete(_ plan: Plan) async throws
}

@MainActor
public final class PlanRepository: PlanRepositoryProtocol {
    private let modelContext: ModelContext
    private let syncEngine: any SyncEngine

    public init(modelContext: ModelContext, syncEngine: any SyncEngine) {
        self.modelContext = modelContext
        self.syncEngine = syncEngine
    }

    public func fetchAll() async throws -> [Plan] {
        let descriptor = FetchDescriptor<Plan>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    public func fetch(id: UUID) async throws -> Plan? {
        let descriptor = FetchDescriptor<Plan>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    public func create(_ plan: Plan) async throws {
        modelContext.insert(plan)
        try modelContext.save()
        plan.pendingSyncOp = "insert"
        try await syncEngine.enqueueLocalChange(
            tableName: "plans",
            recordId: plan.id,
            operationType: "insert",
            payload: nil
        )
    }

    public func update(_ plan: Plan) async throws {
        plan.updatedAt = Date()
        plan.pendingSyncOp = "update"
        try modelContext.save()
        try await syncEngine.enqueueLocalChange(
            tableName: "plans",
            recordId: plan.id,
            operationType: "update",
            payload: nil
        )
    }

    public func delete(_ plan: Plan) async throws {
        let recordId = plan.id
        modelContext.delete(plan)
        try modelContext.save()
        try await syncEngine.enqueueLocalChange(
            tableName: "plans",
            recordId: recordId,
            operationType: "delete",
            payload: nil
        )
    }
}
