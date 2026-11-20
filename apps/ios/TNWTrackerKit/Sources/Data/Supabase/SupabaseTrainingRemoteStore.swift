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
        try await Self.reportingRejections {
            try await write(aggregate)
        }
    }

    private func write(_ aggregate: RemoteSessionAggregate) async throws {
        if !aggregate.removedSetIds.isEmpty {
            try await client.from(RemoteTable.sets.rawValue)
                .delete(returning: .minimal)
                .in("id", values: Self.text(aggregate.removedSetIds))
                .in("entry_id", values: Self.text(aggregate.entries.map(\.id) + aggregate.removedEntryIds))
                .execute()
        }
        if !aggregate.removedEntryIds.isEmpty {
            try await deleteEntries(of: aggregate)
        }
        try await upsertRows([aggregate.session])
        try await upsertRows(aggregate.entries)
        try await upsertRows(aggregate.sets)
    }

    /// The removed entries go, except one still holding a set the aggregate
    /// does not list: an importer added it after the device's last pull, and
    /// deleting the entry would delete it too. That entry and its sets are
    /// written again unchanged (the server moves their `updated_at`), so the
    /// next pull brings them back to the device. A set an importer adds between
    /// the read and the delete is not seen; the window is one request long.
    private func deleteEntries(of aggregate: RemoteSessionAggregate) async throws {
        let session = aggregate.session.id.uuidString.lowercased()
        let removed = Self.text(aggregate.removedEntryIds)
        let held: [HeldSet] = try await client.from(RemoteTable.sets.rawValue)
            .select("id,entry_id")
            .in("entry_id", values: removed)
            .execute()
            .value
        let listed = Set(aggregate.sets.map(\.id))
        let kept = Set(held.filter { !listed.contains($0.id) }.map(\.entryId))
        let deletable = aggregate.removedEntryIds.filter { !kept.contains($0) }
        if !deletable.isEmpty {
            try await client.from(RemoteTable.entries.rawValue)
                .delete(returning: .minimal)
                .in("id", values: Self.text(deletable))
                .eq("session_id", value: session)
                .execute()
        }
        guard !kept.isEmpty else { return }
        let owner = ["user_id": aggregate.session.userId.uuidString.lowercased()]
        try await client.from(RemoteTable.entries.rawValue)
            .update(owner, returning: .minimal)
            .in("id", values: Self.text(Array(kept)))
            .eq("session_id", value: session)
            .execute()
        try await client.from(RemoteTable.sets.rawValue)
            .update(owner, returning: .minimal)
            .in("entry_id", values: Self.text(Array(kept)))
            .execute()
    }

    /// One request, so one statement: the rows are written together or not at
    /// all, and position swaps pass the deferrable position keys.
    public func upsert<Row: RemoteRow>(_ rows: [Row]) async throws {
        try await Self.reportingRejections {
            try await upsertRows(rows)
        }
    }

    private func upsertRows<Row: RemoteRow>(_ rows: [Row]) async throws {
        guard !rows.isEmpty else { return }
        try await client.from(Row.table.rawValue)
            .upsert(rows, onConflict: Row.table.conflictTarget, returning: .minimal)
            .execute()
    }

    public func deleteChildren(_ table: RemoteTable, of parentId: UUID, keeping ids: [UUID]) async throws {
        guard let parent = table.parentColumn else {
            throw RemoteStoreError.invalidAggregate("\(table.rawValue) has no parent to delete children of")
        }
        try await Self.reportingRejections {
            var query = client.from(table.rawValue)
                .delete(returning: .minimal)
                .eq(parent, value: parentId.uuidString.lowercased())
            // An empty list keeps nothing: every child of the parent goes.
            if !ids.isEmpty { query = query.notIn("id", values: Self.text(ids)) }
            try await query.execute()
        }
    }

    public func delete(_ table: RemoteTable, ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await Self.reportingRejections {
            try await client.from(table.rawValue)
                .delete(returning: .minimal)
                .in(table.keyColumn, values: Self.text(ids))
                .execute()
        }
    }

    public func pull<Row: RemoteRow>(
        _ type: Row.Type,
        after cursor: RemoteCursor?,
        limit: Int
    ) async throws -> RemotePage<Row> {
        let key = Row.table.keyColumn
        var query = client.from(Row.table.rawValue).select()
        if let cursor {
            // Keyset: (updated_at, key) > cursor. The timestamp is quoted, as it
            // holds reserved characters of the filter grammar (":", ".", "+").
            let time = "\"\(cursor.updatedAt)\""
            let id = cursor.id.uuidString.lowercased()
            query = query.or("updated_at.gt.\(time),and(updated_at.eq.\(time),\(key).gt.\(id))")
        }
        let rows: [Row] = try await query
            .order("updated_at", ascending: true)
            .order(key, ascending: true)
            .limit(limit)
            .execute()
            .value
        return RemotePage(rows: rows, limit: limit)
    }

    /// Turns a refusal of the data (SQLSTATE class 22 data exception or 23
    /// integrity constraint, which the validation triggers also raise) into
    /// `RemoteStoreError.rejected`. Every other error passes through unchanged:
    /// it says nothing about the data.
    private static func reportingRejections(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch let error as PostgrestError {
            guard let code = error.code, code.hasPrefix("22") || code.hasPrefix("23") else { throw error }
            throw RemoteStoreError.rejected(code: code, message: error.message)
        }
    }

    private static func text(_ ids: [UUID]) -> [String] {
        ids.map { $0.uuidString.lowercased() }
    }
}

/// A set's id and entry, to tell the sets the device knows from late imports.
private struct HeldSet: Decodable {
    let id: UUID
    let entryId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case entryId = "entry_id"
    }
}
