import Foundation

// Value snapshots an importer delivers: imported entries and sets, and the
// import bundle with its result. Shaped like the format's JSON.

/// Imported data for one exercise of one session, as an importer delivers it.
/// In `SessionRepositoryProtocol.importEntry` `exerciseId` is a local id; inside a
/// `TrainingBundle` it is the bundle's id of the exercise.
public struct ImportedEntry: Sendable {
    public var exerciseId: UUID
    public var externalRef: ExternalRef
    public var completedAt: Date?
    public var sets: [ImportedSet]

    public init(exerciseId: UUID, externalRef: ExternalRef, completedAt: Date? = nil, sets: [ImportedSet]) {
        self.exerciseId = exerciseId
        self.externalRef = externalRef
        self.completedAt = completedAt
        self.sets = sets
    }
}

/// An imported set. It has no id: the app keys imported sets by `externalRef`
/// and gives new ones an id of its own (format decision B).
public struct ImportedSet: Sendable {
    public var externalRef: ExternalRef
    public var order: Int
    public var values: SetValues
    public var completedAt: Date?
    /// Format field `warmup`. Read only when the set is new: on a re-import the
    /// stored flag is the user's and is kept.
    public var warmup: Bool

    public init(
        externalRef: ExternalRef,
        order: Int,
        values: SetValues,
        completedAt: Date? = nil,
        warmup: Bool = false
    ) {
        self.externalRef = externalRef
        self.order = order
        self.values = values
        self.completedAt = completedAt
        self.warmup = warmup
    }
}

// MARK: - Import bundle

/// A provider's data as an importer delivers it (an importer's bundle).
/// Every `id` here is a bundle id: it only links the parts of the bundle.
/// The app never stores a bundle id as its own key (format decision B).
public struct TrainingBundle: Sendable {
    public var exercises: [Exercise]
    public var routines: [Routine]
    public var sessions: [BundleSession]

    public init(exercises: [Exercise], routines: [Routine] = [], sessions: [BundleSession] = []) {
        self.exercises = exercises
        self.routines = routines
        self.sessions = sessions
    }
}

/// A performed session in a bundle. Its entries' `exerciseId` are bundle ids.
public struct BundleSession: Sendable {
    public var id: UUID
    public var externalRef: ExternalRef
    public var name: String?
    public var notes: String?
    public var startedAt: Date?
    public var completedAt: Date
    public var timeZone: String
    public var durationSeconds: Int?
    public var routineId: UUID?
    public var entries: [ImportedEntry]

    public init(
        id: UUID,
        externalRef: ExternalRef,
        name: String? = nil,
        notes: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date,
        timeZone: String,
        durationSeconds: Int? = nil,
        routineId: UUID? = nil,
        entries: [ImportedEntry]
    ) {
        self.id = id
        self.externalRef = externalRef
        self.name = name
        self.notes = notes
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.timeZone = timeZone
        self.durationSeconds = durationSeconds
        self.routineId = routineId
        self.entries = entries
    }
}

/// Where each bundle item landed: bundle id → local id. Sessions that could not
/// be imported are listed in `skippedSessions`, in bundle order (D13).
public struct ImportResult: Sendable, Equatable {
    public var exerciseIds: [UUID: UUID] = [:]
    public var routineIds: [UUID: UUID] = [:]
    public var sessionIds: [UUID: UUID] = [:]
    public var skippedSessions: [SkippedSession] = []

    public init() {}
}

/// A bundle session the import skipped, and why; nothing of it was written (D13).
public struct SkippedSession: Sendable, Equatable {
    public var bundleId: UUID
    public var externalRef: ExternalRef
    public var reason: TrainingDataError

    public init(bundleId: UUID, externalRef: ExternalRef, reason: TrainingDataError) {
        self.bundleId = bundleId
        self.externalRef = externalRef
        self.reason = reason
    }
}
