import Foundation
import SwiftData

@MainActor
public protocol SessionRepositoryProtocol: AnyObject, Sendable {
    func fetchAll() async throws -> [Session]
    func fetch(id: UUID) async throws -> Session?
    func create(_ session: Session) async throws
    func update(_ session: Session) async throws
    func delete(_ session: Session) async throws
}

@MainActor
public final class SessionRepository: SessionRepositoryProtocol {
    private let modelContext: ModelContext
    private let syncEngine: any SyncEngine

    public init(modelContext: ModelContext, syncEngine: any SyncEngine) {
        self.modelContext = modelContext
        self.syncEngine = syncEngine
    }

    public func fetchAll() async throws -> [Session] {
        let descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    public func fetch(id: UUID) async throws -> Session? {
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    public func create(_ session: Session) async throws {
        modelContext.insert(session)
        try modelContext.save()
        session.pendingSyncOp = "insert"
        try await syncEngine.enqueueLocalChange(
            tableName: "sessions",
            recordId: session.id,
            operationType: "insert",
            payload: nil
        )
    }

    public func update(_ session: Session) async throws {
        session.updatedAt = Date()
        session.pendingSyncOp = "update"
        try modelContext.save()
        try await syncEngine.enqueueLocalChange(
            tableName: "sessions",
            recordId: session.id,
            operationType: "update",
            payload: nil
        )
    }

    public func delete(_ session: Session) async throws {
        let recordId = session.id
        modelContext.delete(session)
        try modelContext.save()
        try await syncEngine.enqueueLocalChange(
            tableName: "sessions",
            recordId: recordId,
            operationType: "delete",
            payload: nil
        )
    }
}
