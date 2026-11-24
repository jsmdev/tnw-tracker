import Foundation
import SwiftData

// App user data of schema V1 (`TrainingSchemaV1.models`): the user's own data
// about an exercise that is not in the training data format, synced on its own
// (docs/database-schema.md, "User settings and links").

// MARK: - App-local settings

/// The user's settings for one exercise (app-local, not in the training data
/// format). Keyed by the exercise id; it outlives no exercise, see
/// `TrainingStore.deleteAllTrainingData`.
@Model final class ExerciseSettingModel {
    @Attribute(.unique) var exerciseId: UUID
    var restEnabled: Bool = true
    var restSeconds: Int

    // Sync state (app-local, see `ModelContext+SyncTracking.swift`): the revision
    // grows with every local change, `syncedRevision` is the last one the server
    // acknowledged, `syncSent` means it may exist on the server, and
    // `isSyncable` (fixed at creation) keeps unowned and catalogue data local.
    // None of them is user data: changing them never raises the revision.
    var syncRevision: Int = 0
    var syncedRevision: Int = 0
    var syncSent: Bool = false
    var isSyncable: Bool = false
    /// Pushes the server refused since the last acknowledged one, and why the last did.
    var syncFailureCount: Int = 0
    var syncLastError: String?

    init(exerciseId: UUID, restEnabled: Bool, restSeconds: Int) {
        self.exerciseId = exerciseId
        self.restEnabled = restEnabled
        self.restSeconds = restSeconds
    }
}

// MARK: - Personal links

/// A personal related link of an exercise (S10): the user's, on a catalogue or
/// own exercise, and seen only by them. Its own aggregate for the sync, keyed
/// by `id`; it outlives no exercise (the pull deletes it with its exercise, and
/// `TrainingStore.deleteAllTrainingData` with the rest).
@Model final class ExerciseLinkModel {
    #Index<ExerciseLinkModel>([\.exerciseId])

    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    var title: String
    /// An `https` address.
    var url: String
    /// The name of the site, shown to the user.
    var source: String
    /// Order among the user's links of the exercise, from 1; ties keep id order.
    var position: Int

    // Sync state, as on `ExerciseSettingModel`.
    var syncRevision: Int = 0
    var syncedRevision: Int = 0
    var syncSent: Bool = false
    var isSyncable: Bool = false
    var syncFailureCount: Int = 0
    var syncLastError: String?

    init(id: UUID, exerciseId: UUID, title: String, url: String, source: String, position: Int) {
        self.id = id
        self.exerciseId = exerciseId
        self.title = title
        self.url = url
        self.source = source
        self.position = position
    }

    var snapshot: ExerciseLink {
        ExerciseLink(id: id, exerciseId: exerciseId, title: title, url: url, source: source, position: position)
    }
}
