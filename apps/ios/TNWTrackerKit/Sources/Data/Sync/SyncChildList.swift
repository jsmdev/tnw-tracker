import Foundation

// The child list of an aggregate root (an exercise's muscle groups, a routine's
// items) as the server last held it for this device, so a change of the parent
// alone never sends the list again over children another device added (L12).
// The decision is `SyncConflictRule.childListChanged`.
//
// Children are recreated on every save, so the fingerprint is built from their
// content only: the list order and every field the push sends, never a model
// identity or a row id. Saving the same list again is therefore no change.
// It is stamped when the server acknowledges a push that sent the list, and
// when a pull applies the server's list.

/// An aggregate root whose children the sync pushes and pulls as one list.
protocol SyncChildListOwner: SyncTrackedModel {
    /// The fingerprint of the list as it is now.
    var childrenFingerprint: String { get }
    /// The fingerprint of the list the server last held for this device.
    var syncedChildrenFingerprint: String? { get set }
}

extension SyncChildListOwner {
    /// True when the list changed on the device since the server last held it.
    var childListChanged: Bool {
        SyncConflictRule.childListChanged(
            parentPending: syncRevision > syncedRevision,
            synced: syncedChildrenFingerprint,
            current: childrenFingerprint
        )
    }

    /// The list as it is now is the one the server holds.
    func markChildrenSynced() {
        syncedChildrenFingerprint = childrenFingerprint
    }
}

extension ExerciseModel: SyncChildListOwner {
    /// The muscle groups in list order, as the push sends them.
    var childrenFingerprint: String {
        Self.fingerprint(snapshot.muscleGroups.map { [$0.muscle.rawValue, $0.role.rawValue] })
    }
}

extension RoutineModel: SyncChildListOwner {
    /// The items in position order, every field the push sends.
    var childrenFingerprint: String {
        Self.fingerprint(snapshot.items.map { item in
            [
                String(item.order), item.exerciseId.uuidString, item.targetSets.map(String.init),
                item.targetReps.map { "\($0.min)-\($0.max)" },
                item.targetWeight.map { "\($0.value) \($0.unit.rawValue)" },
                item.targetDurationSeconds.map(String.init), item.restSeconds.map(String.init), item.notes
            ]
        })
    }
}

private extension SyncChildListOwner {
    /// A canonical text of the fields, unambiguous for any field content (JSON
    /// arrays of strings and nulls, which always encode).
    static func fingerprint(_ rows: [[String?]]) -> String {
        let data = (try? JSONEncoder().encode(rows)) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
