import Foundation
import Supabase
import SwiftData

public protocol SyncEngine: AnyObject, Sendable {
    func enqueueLocalChange(tableName: String, recordId: UUID, operationType: String, payload: Data?) async throws
    func pushPendingChanges() async throws
    func pullRemoteChanges(for tableName: String) async throws
    func fullSync() async throws
}

@MainActor
public final class SyncEngineImpl: SyncEngine {
    private let syncQueue: SyncQueue
    private let supabase: SupabaseClient
    private let conflictResolver: ConflictResolver
    private let modelContext: ModelContext

    /// Claves para cursor en UserDefaults
    private func cursorKey(for tableName: String) -> String {
        "sync_cursor_\(tableName)"
    }

    private var isOnline: Bool {
        // Simplificado — en producción usar NWPathMonitor
        true
    }

    public init(modelContext: ModelContext, supabase: SupabaseClient) {
        self.modelContext = modelContext
        syncQueue = SyncQueue(modelContext: modelContext)
        self.supabase = supabase
        conflictResolver = ConflictResolver()
    }

    public func enqueueLocalChange(
        tableName: String,
        recordId: UUID,
        operationType: String,
        payload: Data?
    ) async throws {
        try await syncQueue.enqueue(
            tableName: tableName,
            recordId: recordId,
            operationType: operationType,
            payload: payload
        )
    }

    public func pushPendingChanges() async throws {
        guard isOnline else { return }
        let ops = try await syncQueue.drain()

        for op in ops {
            op.attempts += 1
            op.lastAttemptAt = Date()

            do {
                try await pushOperation(op)
                try await syncQueue.remove(op)
            } catch {
                // Backoff exponencial: 1s, 2s, 4s ... max 60s
                let delay = min(pow(2.0, Double(op.attempts - 1)), 60.0)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func pushOperation(_ op: SyncOperationRecord) async throws {
        guard let payload = op.payload else { return }
        switch op.operationTypeRaw {
        case "insert", "update":
            // upsert genérico — en producción usar typed endpoints
            let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any] ?? [:]
            try await supabase.from(op.tableName).upsert(json).execute()
        case "delete":
            try await supabase.from(op.tableName).delete().eq("id", value: op.recordId.uuidString).execute()
        default:
            break
        }
    }

    public func pullRemoteChanges(for tableName: String) async throws {
        guard isOnline else { return }
        let key = cursorKey(for: tableName)
        let lastCursor = UserDefaults.standard.string(forKey: key) ?? "1970-01-01T00:00:00Z"

        try await supabase
            .from(tableName)
            .select()
            .gt("updated_at", value: lastCursor)
            .order("updated_at")
            .execute()

        // Actualizar cursor con el updated_at más reciente
        // (en producción parsear el array de resultados y aplicar conflictos)
        let newCursor = ISO8601DateFormatter().string(from: Date())
        UserDefaults.standard.set(newCursor, forKey: key)
    }

    public func fullSync() async throws {
        let tables = [
            "workouts", "workout_exercises", "exercise_sets",
            "exercises", "plans", "routines", "sessions",
        ]
        for table in tables {
            try await pullRemoteChanges(for: table)
        }
        try await pushPendingChanges()
    }
}
