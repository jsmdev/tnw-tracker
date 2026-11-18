import Foundation

// Value snapshots of the training data, shaped like the format's JSON.
// Repositories return these; views and view models never see a `@Model`.

// MARK: - Exercise

public struct MuscleGroup: Hashable, Codable, Sendable {
    public var muscle: Muscle
    public var role: MuscleRole

    public init(muscle: Muscle, role: MuscleRole) {
        self.muscle = muscle
        self.role = role
    }
}

/// Format field `exercise.instructions`: each part is a list of steps.
public struct ExerciseInstructions: Hashable, Codable, Sendable {
    public var setup: [String]
    public var execution: [String]
    public var tips: [String]

    public init(setup: [String] = [], execution: [String] = [], tips: [String] = []) {
        self.setup = setup
        self.execution = execution
        self.tips = tips
    }

    public var isEmpty: Bool {
        setup.isEmpty && execution.isEmpty && tips.isEmpty
    }
}

/// Format field `exercise.media`: URIs, absolute or relative to the agreed media root (O7).
public struct ExerciseMedia: Hashable, Codable, Sendable {
    public var imageURI: String?
    public var videoURI: String?

    public init(imageURI: String? = nil, videoURI: String? = nil) {
        self.imageURI = imageURI
        self.videoURI = videoURI
    }

    public var isEmpty: Bool {
        imageURI == nil && videoURI == nil
    }
}

public struct Exercise: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var externalRef: ExternalRef?
    public var name: String
    public var type: ExerciseType
    public var equipment: Equipment?
    public var muscleGroups: [MuscleGroup]
    public var instructions: ExerciseInstructions?
    public var media: ExerciseMedia?
    /// True for a catalogue exercise: a curated app exercise shared with every user.
    /// A catalogue exercise never has an `externalRef`.
    public var isCatalogue: Bool

    public init(
        id: UUID = UUID(),
        externalRef: ExternalRef? = nil,
        isCatalogue: Bool = false,
        name: String,
        type: ExerciseType,
        equipment: Equipment? = nil,
        muscleGroups: [MuscleGroup] = [],
        instructions: ExerciseInstructions? = nil,
        media: ExerciseMedia? = nil
    ) {
        self.id = id
        self.externalRef = externalRef
        self.isCatalogue = isCatalogue
        self.name = name
        self.type = type
        self.equipment = equipment
        self.muscleGroups = muscleGroups
        self.instructions = instructions
        self.media = media
    }

    /// True for an exercise imported from a provider: it has an `externalRef`.
    /// An imported exercise belongs to the user who imported it.
    public var isImported: Bool {
        externalRef != nil
    }
}

// MARK: - Routine

public struct RoutineItem: Hashable, Sendable {
    public var order: Int
    public var exerciseId: UUID
    public var targetSets: Int?
    public var targetReps: RepRange?
    public var targetWeight: Weight?
    public var targetDurationSeconds: Int?
    public var restSeconds: Int?
    public var notes: String?

    public init(
        order: Int,
        exerciseId: UUID,
        targetSets: Int? = nil,
        targetReps: RepRange? = nil,
        targetWeight: Weight? = nil,
        targetDurationSeconds: Int? = nil,
        restSeconds: Int? = nil,
        notes: String? = nil
    ) {
        self.order = order
        self.exerciseId = exerciseId
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetDurationSeconds = targetDurationSeconds
        self.restSeconds = restSeconds
        self.notes = notes
    }
}

/// A session template: an ordered list of exercises with targets.
public struct Routine: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var externalRef: ExternalRef?
    public var name: String
    /// Format field `routine.description`.
    public var description: String?
    /// Sorted by `order`.
    public var items: [RoutineItem]
    /// The user's favourite mark. App state, not a format field: `save` and
    /// imports never write it; `RoutineRepositoryProtocol.setFavorite` does.
    public var isFavorite: Bool

    public init(
        id: UUID = UUID(),
        externalRef: ExternalRef? = nil,
        name: String,
        description: String? = nil,
        items: [RoutineItem],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.externalRef = externalRef
        self.name = name
        self.description = description
        self.items = items
        self.isFavorite = isFavorite
    }
}

/// Filters for listing routines.
public struct RoutineQuery: Sendable {
    /// Matches the routine name; empty matches every routine.
    public var search: String
    /// Only routines that at least one completed session was started from.
    public var onlyPerformed: Bool
    public var offset: Int
    public var limit: Int?

    public init(search: String = "", onlyPerformed: Bool = false, offset: Int = 0, limit: Int? = nil) {
        self.search = search
        self.onlyPerformed = onlyPerformed
        self.offset = offset
        self.limit = limit
    }
}

// MARK: - Session

/// The measured values of a set. Which ones apply depends on the exercise type.
public struct SetValues: Hashable, Sendable {
    public var reps: Int?
    public var weight: Weight?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    /// Reps in reserve, 0 to 10.
    public var rir: Int?
    public var restSeconds: Int?

    public init(
        reps: Int? = nil,
        weight: Weight? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        rir: Int? = nil,
        restSeconds: Int? = nil
    ) {
        self.reps = reps
        self.weight = weight
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.rir = rir
        self.restSeconds = restSeconds
    }
}

public struct ExerciseSet: Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Position among the sets of the same `source` in the entry, starting at 1.
    public var order: Int
    public var source: SetSource
    public var externalRef: ExternalRef?
    public var values: SetValues
    public var completedAt: Date?
    /// True when reconciliation kept the other source. Superseded sets do not count.
    public var superseded: Bool
    /// Format field `warmup`. A warm-up set stays stored but does not count. On an
    /// imported set it is the user's annotation: re-imports never change it.
    public var warmup: Bool

    public init(
        id: UUID = UUID(),
        order: Int,
        source: SetSource,
        externalRef: ExternalRef? = nil,
        values: SetValues,
        completedAt: Date? = nil,
        superseded: Bool = false,
        warmup: Bool = false
    ) {
        self.id = id
        self.order = order
        self.source = source
        self.externalRef = externalRef
        self.values = values
        self.completedAt = completedAt
        self.superseded = superseded
        self.warmup = warmup
    }

    /// Whether the set counts for volume, records and summaries:
    /// neither superseded nor a warm-up set.
    public var countsForStats: Bool {
        !superseded && !warmup
    }
}

/// Format type `reconciliation`. Present only on entries that mix sources.
public struct Reconciliation: Hashable, Sendable {
    public var keep: SetSource
    public var decidedBy: ReconciliationDecider
    public var decidedAt: Date?

    public init(keep: SetSource, decidedBy: ReconciliationDecider, decidedAt: Date? = nil) {
        self.keep = keep
        self.decidedBy = decidedBy
        self.decidedAt = decidedAt
    }
}

/// One exercise inside a session.
public struct SessionEntry: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var externalRef: ExternalRef?
    public var exerciseId: UUID
    public var order: Int
    public var status: EntryStatus
    public var replacedExerciseId: UUID?
    public var completedAt: Date?
    /// Manual sets first, then imported, each by `order`.
    public var sets: [ExerciseSet]
    public var reconciliation: Reconciliation?
    public var notes: String?

    public init(
        id: UUID = UUID(),
        externalRef: ExternalRef? = nil,
        exerciseId: UUID,
        order: Int,
        status: EntryStatus,
        replacedExerciseId: UUID? = nil,
        completedAt: Date? = nil,
        sets: [ExerciseSet] = [],
        reconciliation: Reconciliation? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.externalRef = externalRef
        self.exerciseId = exerciseId
        self.order = order
        self.status = status
        self.replacedExerciseId = replacedExerciseId
        self.completedAt = completedAt
        self.sets = sets
        self.reconciliation = reconciliation
        self.notes = notes
    }

    /// The sets that count for history, totals and records: only `done`
    /// entries, and only sets that `countsForStats` (not superseded, not warm-up).
    public var countedSets: [ExerciseSet] {
        guard status == .done else { return [] }
        return sets.filter(\.countsForStats)
    }

    public var manualSets: [ExerciseSet] {
        sets.filter { $0.source == .manual }.sorted { $0.order < $1.order }
    }

    /// Manual sets that count toward a routine's target sets: warm-ups do not.
    public var workingManualSets: [ExerciseSet] {
        manualSets.filter { !$0.warmup }
    }

    /// Sum of weight × reps over the counted sets, in kilograms.
    public var volumeKg: Double {
        countedSets.reduce(0) { total, set in
            guard let weight = set.values.weight, let reps = set.values.reps else { return total }
            return total + weight.kilograms * Double(reps)
        }
    }
}

/// A performed session. `completedAt == nil` means it is still in progress in
/// this app; the format only describes completed sessions.
public struct TrainingSession: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var externalRef: ExternalRef?
    public var name: String?
    public var notes: String?
    public var startedAt: Date?
    public var completedAt: Date?
    /// IANA time zone identifier, for example `Europe/Madrid`.
    public var timeZone: String
    public var durationSeconds: Int?
    public var routineId: UUID?
    /// Sorted by `order`.
    public var entries: [SessionEntry]

    public init(
        id: UUID = UUID(),
        externalRef: ExternalRef? = nil,
        name: String? = nil,
        notes: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        timeZone: String,
        durationSeconds: Int? = nil,
        routineId: UUID? = nil,
        entries: [SessionEntry] = []
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

    public var isCompleted: Bool {
        completedAt != nil
    }

    /// Sum of the entries' counted volume, in kilograms.
    public var volumeKg: Double {
        entries.reduce(0) { $0 + $1.volumeKg }
    }

    public func entry(id: UUID) -> SessionEntry? {
        entries.first { $0.id == id }
    }
}

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

extension TrainingSession {
    /// Whether the session has a working set (T6, D-T6a, M14): a set that is not
    /// a warm-up, imported or manual, strength or cardio, of an entry that was not
    /// removed. Warm-ups never count, an imported warm-up included. A session
    /// without one is never saved: ending it discards it.
    public var hasWorkingSets: Bool {
        entries.contains { entry in
            entry.status != .removed && entry.sets.contains { !$0.warmup }
        }
    }
}
