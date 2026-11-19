import Foundation
import Supabase

/// `TrainingRemoteStore` over PostgREST for one account. Every request runs as
/// the signed-in user of `client`, so row-level security limits it to that
/// user's rows and the read-only catalogue; it is sent only while that user is
/// `userId`, and its answer is used only if they still are once it arrives
/// (S10). Deletes and pulls also name the user (`user_id`), so a request made
/// with another account's token reaches none of its rows. The client is shared
/// by every account of the device: once another account signs in, the store of
/// the previous one sends nothing more.
///
/// A push is several requests, not one transaction. The order documented on
/// `TrainingRemoteStore.pushSession` keeps every intermediate state valid for
/// the server's constraints and triggers, and every write is idempotent
/// (client ids, upsert by id), so retrying the whole aggregate converges.
public struct SupabaseTrainingRemoteStore: TrainingRemoteStore {
    private let client: SupabaseClient
    private let userId: UUID
    /// The user the client is signed in as now.
    private let signedInUser: @Sendable () -> UUID?

    public init(client: SupabaseClient, userId: UUID) {
        self.init(client: client, userId: userId) { client.auth.currentSession?.user.id }
    }

    /// `signedInUser` stands in for the client's session, for tests.
    init(client: SupabaseClient, userId: UUID, signedInUser: @escaping @Sendable () -> UUID?) {
        self.client = client
        self.userId = userId
        self.signedInUser = signedInUser
    }

    private var user: String {
        userId.uuidString.lowercased()
    }

    /// Every request starts here: it throws `RemoteSessionError` and sends
    /// nothing unless the client is signed in as this store's account.
    private func from(_ table: String) throws -> PostgrestQueryBuilder {
        try requireAccount()
        return client.from(table)
    }

    private func requireAccount() throws {
        guard signedInUser() == userId else { throw RemoteSessionError.notSignedInAsAccount }
    }

    /// Runs one request. Its answer, or its error, counts only if the client is
    /// still signed in as this account when it arrives: otherwise it throws
    /// `RemoteSessionError.notSignedInAsAccount`, so a delete made while another
    /// account signed in never clears the device's tombstones, and a page read
    /// then is never applied.
    private func answer<Value>(_ request: () async throws -> Value) async throws -> Value {
        let value: Value
        do {
            value = try await request()
        } catch {
            try requireAccount()
            throw Self.classified(error)
        }
        try requireAccount()
        return value
    }

    public func pushSession(_ aggregate: RemoteSessionAggregate) async throws {
        try aggregate.validate()
        try await write(aggregate)
    }

    private func write(_ aggregate: RemoteSessionAggregate) async throws {
        if !aggregate.removedSetIds.isEmpty {
            try await answer {
                try await from(RemoteTable.sets.rawValue)
                    .delete(returning: .minimal)
                    .in("id", values: Self.text(aggregate.removedSetIds))
                    .in("entry_id", values: Self.text(aggregate.entries.map(\.id) + aggregate.removedEntryIds))
                    .eq("user_id", value: user)
                    .execute()
            }
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
        let held: [HeldSet] = try await answer {
            try await from(RemoteTable.sets.rawValue)
                .select("id,entry_id")
                .in("entry_id", values: removed)
                .eq("user_id", value: user)
                .execute()
                .value
        }
        let listed = Set(aggregate.sets.map(\.id))
        let kept = Set(held.filter { !listed.contains($0.id) }.map(\.entryId))
        let deletable = aggregate.removedEntryIds.filter { !kept.contains($0) }
        if !deletable.isEmpty {
            try await answer {
                try await from(RemoteTable.entries.rawValue)
                    .delete(returning: .minimal)
                    .in("id", values: Self.text(deletable))
                    .eq("session_id", value: session)
                    .eq("user_id", value: user)
                    .execute()
            }
        }
        guard !kept.isEmpty else { return }
        let owner = ["user_id": aggregate.session.userId.uuidString.lowercased()]
        try await answer {
            try await from(RemoteTable.entries.rawValue)
                .update(owner, returning: .minimal)
                .in("id", values: Self.text(Array(kept)))
                .eq("session_id", value: session)
                .eq("user_id", value: user)
                .execute()
        }
        try await answer {
            try await from(RemoteTable.sets.rawValue)
                .update(owner, returning: .minimal)
                .in("entry_id", values: Self.text(Array(kept)))
                .eq("user_id", value: user)
                .execute()
        }
    }

    /// One request, so one statement: the rows are written together or not at
    /// all, and position swaps pass the deferrable position keys.
    public func upsert<Row: RemoteRow>(_ rows: [Row]) async throws {
        try await upsertRows(rows)
    }

    private func upsertRows<Row: RemoteRow>(_ rows: [Row]) async throws {
        guard !rows.isEmpty else { return }
        try await answer {
            try await from(Row.table.rawValue)
                .upsert(rows, onConflict: Row.table.conflictTarget, returning: .minimal)
                .execute()
        }
    }

    public func deleteChildren(_ table: RemoteTable, of parentId: UUID, keeping ids: [UUID]) async throws {
        guard let parent = table.parentColumn else {
            throw RemoteStoreError.invalidAggregate("\(table.rawValue) has no parent to delete children of")
        }
        try await answer {
            var query = try from(table.rawValue)
                .delete(returning: .minimal)
                .eq(parent, value: parentId.uuidString.lowercased())
            // Muscle groups have no owner column: row-level security limits them to the user's exercises.
            if table != .exerciseMuscleGroups { query = query.eq("user_id", value: user) }
            // An empty list keeps nothing: every child of the parent goes.
            if !ids.isEmpty { query = query.notIn("id", values: Self.text(ids)) }
            try await query.execute()
        }
    }

    public func delete(_ table: RemoteTable, ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await answer {
            try await from(table.rawValue)
                .delete(returning: .minimal)
                .in(table.keyColumn, values: Self.text(ids))
                .eq("user_id", value: user)
                .execute()
        }
    }

    public func pull<Row: RemoteRow>(
        _ type: Row.Type,
        after cursor: RemoteCursor?,
        limit: Int
    ) async throws -> RemotePage<Row> {
        let key = Row.table.keyColumn
        var query = try from(Row.table.rawValue).select()
        switch Row.table {
        // No owner column: row-level security returns the groups of the exercises the user can see.
        case .exerciseMuscleGroups: break
        // The catalogue belongs to nobody.
        case .exercises: query = query.or("user_id.is.null,user_id.eq.\(user)")
        default: query = query.eq("user_id", value: user)
        }
        if let cursor {
            // Keyset: (updated_at, key) > cursor. The timestamp is quoted, as it
            // holds reserved characters of the filter grammar (":", ".", "+").
            let time = "\"\(cursor.updatedAt)\""
            let id = cursor.id.uuidString.lowercased()
            query = query.or("updated_at.gt.\(time),and(updated_at.eq.\(time),\(key).gt.\(id))")
        }
        let ordered = query
        let rows: [Row] = try await answer {
            try await ordered
                .order("updated_at", ascending: true)
                .order(key, ascending: true)
                .limit(limit)
                .execute()
                .value
        }
        return RemotePage(rows: rows, limit: limit)
    }

    /// What a PostgREST error says, for the sync:
    /// - a refusal of the data: SQLSTATE class 22 (data exception) or 23
    ///   (integrity constraint, which the validation triggers also raise), or a
    ///   row-level security check a written row failed (`42501`, "new row
    ///   violates row-level security policy"), as when it names an exercise the
    ///   user cannot see. That check only runs for a signed-in user: a request
    ///   without a valid token runs as `anon`, which has no privileges at all,
    ///   and fails "permission denied" first;
    /// - a refused session: any other `42501` (permission denied) and the JWT
    ///   errors (`PGRST3xx`);
    /// - otherwise a server fault (`RemoteServerError`).
    /// Errors without an answer from PostgREST (no network) pass through.
    static func classified(_ error: any Error) -> any Error {
        guard let error = error as? PostgrestError else { return error }
        let code = error.code ?? ""
        if code.hasPrefix("22") || code.hasPrefix("23")
            || code == "42501" && error.message.contains("row-level security policy") {
            return RemoteStoreError.rejected(code: code, message: error.message)
        }
        if code == "42501" || code.hasPrefix("PGRST3") { return RemoteSessionError.sessionRefused }
        return RemoteServerError(code: error.code, message: error.message)
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
