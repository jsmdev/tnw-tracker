import Foundation
import SwiftData

/// Refuses the user's writes while the signed-in user does not own the store
/// (S10): their changes would become the owner's data and later be pushed to the
/// owner's account. Shared by every repository of one `TrainingStore`; the sync's
/// own writes (the pull) do not pass through it.
@MainActor
final class UserWriteGate {
    private(set) var isBlocked = false

    func setBlocked(_ blocked: Bool) {
        isBlocked = blocked
    }
}

@MainActor
extension ModelContext {
    /// Saves a user command's changes, or discards them and throws
    /// `TrainingDataError.storeNotOwned` while `gate` is blocked.
    func saveUserChange(_ gate: UserWriteGate) throws {
        guard !gate.isBlocked else {
            rollback()
            throw TrainingDataError.storeNotOwned
        }
        try save()
    }
}
