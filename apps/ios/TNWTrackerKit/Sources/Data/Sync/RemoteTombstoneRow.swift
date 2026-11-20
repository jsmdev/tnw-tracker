import Foundation

// MARK: - tombstones

/// A row of `tombstones` (supabase/migrations/20261119120000_sync_tombstones.sql):
/// a row the server deleted, recorded by its triggers whoever deleted it and
/// through whatever cascade. The app only reads them, with the same cursor as
/// the rows, and never writes one.
public struct RemoteTombstoneRow: RemoteRow {
    public static let table = RemoteTable.tombstones

    public var id: UUID
    /// The owner of the deleted row.
    public var userId: UUID
    /// The table the row was deleted from, as the server names it. Text, so a
    /// table this version of the app does not know does not fail the page.
    public var tableName: String
    /// The id the deleted row had.
    public var rowId: UUID
    public var updatedAt: String?

    public init(id: UUID = UUID(), userId: UUID, tableName: String, rowId: UUID, updatedAt: String? = nil) {
        self.id = id
        self.userId = userId
        self.tableName = tableName
        self.rowId = rowId
        self.updatedAt = updatedAt
    }

    /// The deleted row's table, when the app syncs it.
    public var deletedTable: RemoteTable? {
        RemoteTable(rawValue: tableName)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case tableName = "table_name"
        case rowId = "row_id"
        case updatedAt = "updated_at"
    }
}
