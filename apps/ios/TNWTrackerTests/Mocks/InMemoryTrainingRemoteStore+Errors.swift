import Foundation
@testable import TNWTrackerKit

/// What the in-memory server answers when it refuses a request, as Postgres does.
extension InMemoryTrainingRemoteStore {
    static let networkDown = URLError(.notConnectedToInternet)

    /// What the server answers for a broken foreign key or check.
    static func foreignKeyViolation(_ constraint: String) -> RemoteStoreError {
        .rejected(code: "23503", message: constraint)
    }

    /// What the server answers for a row whose policy names an exercise the user cannot see.
    static func rowLevelSecurity(_ table: RemoteTable) -> RemoteStoreError {
        .rejected(code: "42501", message: "new row violates row-level security policy for table \"\(table.rawValue)\"")
    }

    static let skippedEntryWithSets = RemoteStoreError.rejected(code: "23514", message: "a skipped entry has no sets")

    /// What the server answers for a second row of the user with the same external ref.
    static func duplicateExternalRef(_ table: RemoteTable) -> RemoteStoreError {
        .rejected(code: "23505", message: "\(table.rawValue)_external_ref_key")
    }
}
