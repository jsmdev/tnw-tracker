import Foundation
import SwiftData

@MainActor
public final class SyncQueue {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func enqueue(
        tableName: String,
        recordId: UUID,
        operationType: String,
        payload: Data? = nil
    ) throws {
        // Evitar duplicados: mismo tableName + recordId + operationType
        let descriptor = FetchDescriptor<SyncOperationRecord>(
            predicate: #Predicate { op in
                op.tableName == tableName &&
                    op.recordId == recordId &&
                    op.operationTypeRaw == operationType
            }
        )
        let existing = try modelContext.fetch(descriptor)
        guard existing.isEmpty else { return }

        let record = SyncOperationRecord(
            tableName: tableName,
            recordId: recordId,
            operationType: operationType,
            payload: payload
        )
        modelContext.insert(record)
        try modelContext.save()
    }

    public func drain() throws -> [SyncOperationRecord] {
        // Orden por dependencias FK: workouts primero, luego workout_exercises, luego exercise_sets
        let tableOrder = ["workouts", "workout_exercises", "exercise_sets", "rest_timers", "personal_records"]
        var result: [SyncOperationRecord] = []

        for table in tableOrder {
            let tableName = table
            let descriptor = FetchDescriptor<SyncOperationRecord>(
                predicate: #Predicate { op in op.tableName == tableName },
                sortBy: [SortDescriptor(\.enqueuedAt)]
            )
            result += (try? modelContext.fetch(descriptor)) ?? []
        }

        // Añadir el resto de tablas no en tableOrder
        let othersDescriptor = FetchDescriptor<SyncOperationRecord>(
            sortBy: [SortDescriptor(\.enqueuedAt)]
        )
        let allOps = (try? modelContext.fetch(othersDescriptor)) ?? []
        let inResult = Set(result.map(\.id))
        result += allOps.filter { !inResult.contains($0.id) }

        return result
    }

    public func remove(_ record: SyncOperationRecord) throws {
        modelContext.delete(record)
        try modelContext.save()
    }
}
