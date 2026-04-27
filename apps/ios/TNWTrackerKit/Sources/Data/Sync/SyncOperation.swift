import Foundation
import SwiftData

@Model public final class SyncOperationRecord {
    @Attribute(.unique) public var id: UUID
    public var tableName: String
    public var recordId: UUID
    public var operationTypeRaw: String // "insert" | "update" | "delete"
    public var payload: Data? // JSON serializado del DTO
    public var enqueuedAt: Date
    public var attempts: Int
    public var lastAttemptAt: Date?

    public init(
        tableName: String,
        recordId: UUID,
        operationType: String,
        payload: Data? = nil
    ) {
        id = UUID()
        self.tableName = tableName
        self.recordId = recordId
        operationTypeRaw = operationType
        self.payload = payload
        enqueuedAt = Date()
        attempts = 0
    }
}
