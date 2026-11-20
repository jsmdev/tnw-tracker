import Foundation
import Supabase

/// `TrainingRemoteStore` over PostgREST. Every request runs as the signed-in
/// user of `client`, so row-level security limits it to that user's rows and
/// the read-only catalogue.
///
/// A push is several requests, not one transaction. The order documented on
/// `TrainingRemoteStore.pushSession` keeps every intermediate state valid for
/// the server's constraints and triggers, and every write is idempotent
/// (client ids, upsert by id), so retrying the whole aggregate converges.
public struct SupabaseTrainingRemoteStore: TrainingRemoteStore {
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func pushSession(_ aggregate: RemoteSessionAggregate) async throws {
        try aggregate.validate()
        if !aggregate.removedSetIds.isEmpty {
            try await client.from(RemoteTable.sets.rawValue)
                .delete(returning: .minimal)
                .in("id", values: Self.text(aggregate.removedSetIds))
                .in("entry_id", values: Self.text(aggregate.entries.map(\.id) + aggregate.removedEntryIds))
                .execute()
        }
        if !aggregate.removedEntryIds.isEmpty {
            try await client.from(RemoteTable.entries.rawValue)
                .delete(returning: .minimal)
                .in("id", values: Self.text(aggregate.removedEntryIds))
                .eq("session_id", value: aggregate.session.id.uuidString.lowercased())
                .execute()
        }
        try await upsert([aggregate.session])
        try await upsert(aggregate.entries)
        try await upsert(aggregate.sets)
    }

    /// One request, so one statement: the rows are written together or not at
    /// all, and position swaps pass the deferrable position keys.
    public func upsert<Row: RemoteRow>(_ rows: [Row]) async throws {
        guard !rows.isEmpty else { return }
        try await client.from(Row.table.rawValue)
            .upsert(rows, onConflict: "id", returning: .minimal)
            .execute()
    }

    public func pull<Row: RemoteRow>(
        _ type: Row.Type,
        after cursor: RemoteCursor?,
        limit: Int
    ) async throws -> RemotePage<Row> {
        var query = client.from(Row.table.rawValue).select()
        if let cursor {
            // Keyset: (updated_at, id) > cursor. The timestamp is quoted, as it
            // holds reserved characters of the filter grammar (":", ".", "+").
            let time = "\"\(cursor.updatedAt)\""
            let id = cursor.id.uuidString.lowercased()
            query = query.or("updated_at.gt.\(time),and(updated_at.eq.\(time),id.gt.\(id))")
        }
        let rows: [Row] = try await query
            .order("updated_at", ascending: true)
            .order("id", ascending: true)
            .limit(limit)
            .execute()
            .value
        return RemotePage(rows: rows, limit: limit)
    }

    private static func text(_ ids: [UUID]) -> [String] {
        ids.map { $0.uuidString.lowercased() }
    }
}
