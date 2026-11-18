import Foundation

// Repository interfaces for the training data. Views and view models depend on
// these protocols only; the SwiftData adapters live next to them in this module.
// Every read returns value snapshots, every write goes through a command that
// keeps the rules of docs/training-data-format.md.

@MainActor
public protocol ExerciseRepositoryProtocol: AnyObject {
    /// Every exercise, sorted by name.
    func exercises() throws -> [Exercise]
    func exercise(id: UUID) throws -> Exercise?
    /// Inserts or replaces the exercise with the same `id`.
    /// Throws `duplicateExternalRef` when another exercise has the same `externalRef`.
    func save(_ exercise: Exercise) throws
}

@MainActor
public protocol RoutineRepositoryProtocol: AnyObject {
    /// Routines filtered and paged by `query`: favourites first, then the rest,
    /// each group sorted by name.
    func routines(_ query: RoutineQuery) throws -> [Routine]
    func routine(id: UUID) throws -> Routine?
    /// The routine proposed for the next session ("Próxima sesión"), or nil
    /// without routines. Same rule as the widget's `NextSessionQuery`.
    func nextRoutine() throws -> Routine?
    /// Marks or unmarks the routine as a favourite. Throws `notFound`.
    func setFavorite(_ favorite: Bool, routineId: UUID) throws
    /// Inserts or replaces the routine with the same `id`, items included.
    /// Never changes `isFavorite`.
    /// Throws `invalidRoutine` without items, with repeated or non-positive
    /// `order`, or with an exercise that does not exist.
    func save(_ routine: Routine) throws
}

@MainActor
public protocol SessionRepositoryProtocol: AnyObject {
    /// The session in progress (not completed yet), if any.
    func activeSession() throws -> TrainingSession?
    func session(id: UUID) throws -> TrainingSession?
    /// Completed sessions whose `completedAt` falls in `interval`, most recent first.
    func completedSessions(in interval: DateInterval) throws -> [TrainingSession]

    /// Starts a session in progress. With a routine, every routine item becomes a
    /// `skipped` entry in routine order until a set is logged for it.
    func startSession(routineId: UUID?, name: String?, at date: Date, timeZone: TimeZone) throws -> TrainingSession

    /// Logs a manual set. The session keeps one `done` entry per exercise: the set
    /// joins that entry, or the planned entry for the exercise, or a new entry.
    /// If the entry also holds imported sets, the reconciliation in force decides
    /// whether the new set is superseded.
    /// `warmup` marks a warm-up set; it never changes whether the set is superseded.
    @discardableResult
    func logManualSet(_ values: SetValues, warmup: Bool, exerciseId: UUID, sessionId: UUID, at date: Date) throws -> ExerciseSet

    /// The user's warm-up annotation on any set, manual or imported.
    /// Re-imports keep it. Never changes reconciliation or `superseded`.
    func setWarmup(_ warmup: Bool, setId: UUID) throws

    /// Replaces the values of a manual set, with the same rules as logging it.
    /// Used for the rest taken after the set (`restSeconds`). Throws `notFound`
    /// for an unknown set and `invalidSet` for an imported one.
    func updateManualSet(_ values: SetValues, setId: UUID) throws

    /// Deletes a manual set (undo). A planned entry left without sets goes back to
    /// `skipped`; an unplanned one is removed from the session.
    func deleteManualSet(id: UUID) throws

    /// Swaps the exercise of an entry that has no sets yet, recording the
    /// planned exercise in `replacedExerciseId`.
    func replaceExercise(entryId: UUID, with exerciseId: UUID) throws

    /// Marks an entry `removed`. Its sets stay stored and stop counting.
    func removeEntry(id: UUID) throws

    /// Merges imported sets into the session's `done` entry for the exercise
    /// (one entry per exercise), upserting each set on its `externalRef`.
    /// Never changes manual sets. The first time an entry mixes sources it gets
    /// the default reconciliation (keep imported); an existing reconciliation is
    /// kept, and new imported sets follow it.
    func importEntry(_ imported: ImportedEntry, into sessionId: UUID) throws

    /// The user's reconciliation choice for an entry that mixes sources.
    func chooseReconciliation(entryId: UUID, keep: SetSource, at date: Date) throws

    /// Deletes a session that is still in progress, for example one ended
    /// without any entry (the format needs at least one).
    func discardSession(id: UUID) throws

    /// Completes the session. `durationSeconds` is clamped to the time between
    /// start and end; an entry `completedAt` later than the end is dropped
    /// (rule `range`). Throws for an end before the start or a session without entries.
    @discardableResult
    func finishSession(id: UUID, at date: Date, durationSeconds: Int?) throws -> TrainingSession

    /// Best counted weight per exercise, in kilograms, over sessions completed before `date`.
    func bestWeights(completedBefore date: Date) throws -> [UUID: Double]
}

public extension SessionRepositoryProtocol {
    /// Logs a manual working set (not a warm-up).
    @discardableResult
    func logManualSet(_ values: SetValues, exerciseId: UUID, sessionId: UUID, at date: Date) throws -> ExerciseSet {
        try logManualSet(values, warmup: false, exerciseId: exerciseId, sessionId: sessionId, at: date)
    }
}

/// The user's per-exercise settings (app-local; not imported or exported).
@MainActor
public protocol ExerciseSettingRepositoryProtocol: AnyObject {
    /// The saved setting of the exercise, or nil when the user never changed it.
    func setting(exerciseId: UUID) throws -> ExerciseSetting?
    /// Inserts or replaces the exercise's setting. Throws `notFound` for an
    /// exercise that does not exist and `invalidExercise` for a negative rest.
    func save(_ setting: ExerciseSetting) throws
}

/// Imports an importer's bundle (format decision B: receivers own their keys).
@MainActor
public protocol TrainingImporterProtocol: AnyObject {
    /// Every item is looked up by its `externalRef` (an exercise without one by
    /// its name and type); a new item gets a fresh local id. Bundle ids are only
    /// used to resolve the bundle's own references. Re-importing the same data,
    /// even with different bundle ids, updates in place and never duplicates.
    /// Imported sessions join the session completed on the same local date (O1),
    /// or become a new completed session.
    @discardableResult
    func importBundle(_ bundle: TrainingBundle) throws -> ImportResult
}

/// Placeholder for the remote sync (#135). The app only calls `fullSync()`.
@MainActor
public protocol SyncEngine: AnyObject {
    func fullSync() async throws
}

/// Sync that does nothing until #135 builds the real one on the new schema.
@MainActor
public final class NoopSyncEngine: SyncEngine {
    public init() {}
    public func fullSync() async throws {}
}
