import Foundation
import SwiftData

// SwiftData adapters of the training repositories. They own every rule of the
// format that a single write can break; see docs/training-data-format.md.

// MARK: - Session

@MainActor
final class SwiftDataSessionRepository: SessionRepositoryProtocol {
    /// Internal so the import merge (`SwiftDataSessionRepository+Merge.swift`) can reach it.
    let context: ModelContext
    /// The context does not keep its container alive; the adapter does.
    private let container: ModelContainer

    init(context: ModelContext) {
        self.context = context
        container = context.container
    }

    // MARK: Reads

    func activeSession() throws -> TrainingSession? {
        var descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.completedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.snapshot
    }

    func session(id: UUID) throws -> TrainingSession? {
        try context.fetchSession(id: id)?.snapshot
    }

    func completedSessions(in interval: DateInterval) throws -> [TrainingSession] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { session in
                session.completedAt.flatMap { $0 >= start && $0 <= end } == true
            },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.snapshot)
    }

    func bestWeights(completedBefore date: Date) throws -> [UUID: Double] {
        let sessions = try completedSessions(in: DateInterval(start: .distantPast, end: date))
            .filter { ($0.completedAt ?? date) < date }
        var bests: [UUID: Double] = [:]
        for entry in sessions.flatMap(\.entries) {
            for set in entry.countedSets {
                guard let kilograms = set.values.weight?.kilograms else { continue }
                bests[entry.exerciseId] = max(bests[entry.exerciseId] ?? 0, kilograms)
            }
        }
        return bests
    }

    // MARK: Writes

    func startSession(routineId: UUID?, name: String?, at date: Date, timeZone: TimeZone) throws -> TrainingSession {
        let session = try SessionModel(id: UUID(), timeZone: Self.formatTimeZone(timeZone))
        session.name = name
        session.startedAt = date
        context.insert(session)
        if let routineId {
            guard let routine = try context.fetchRoutine(id: routineId) else { throw TrainingDataError.notFound }
            session.routine = routine
            for (index, item) in routine.items.sorted(by: { $0.order < $1.order }).enumerated() {
                let entry = SessionEntryModel(id: UUID(), order: index + 1, statusRaw: EntryStatus.skipped.rawValue)
                context.insert(entry)
                entry.exercise = item.exercise
                session.entries.append(entry)
            }
        }
        try context.save()
        return session.snapshot
    }

    func logManualSet(
        _ values: SetValues,
        warmup: Bool,
        exerciseId: UUID,
        sessionId: UUID,
        at date: Date
    ) throws -> ExerciseSet {
        let session = try openSession(sessionId)
        guard let exercise = try context.fetchExercise(id: exerciseId) else { throw TrainingDataError.notFound }
        try Self.validate(values, for: exercise)

        let entry = doneEntry(in: session, for: exercise)
        let set = ExerciseSetModel(
            id: UUID(),
            order: nextOrder(in: entry, source: .manual),
            sourceRaw: SetSource.manual.rawValue
        )
        context.insert(set)
        set.apply(values)
        set.completedAt = date
        set.superseded = entry.reconciliationKeepRaw == SetSource.imported.rawValue
        set.warmup = warmup
        entry.sets.append(set)
        entry.completedAt = date
        applyReconciliationOnMerge(entry, at: date)
        try context.save()
        return set.snapshot
    }

    func setWarmup(_ warmup: Bool, setId: UUID) throws {
        let descriptor = FetchDescriptor<ExerciseSetModel>(predicate: #Predicate { $0.id == setId })
        guard let set = try context.fetch(descriptor).first else { throw TrainingDataError.notFound }
        set.warmup = warmup
        try context.save()
    }

    func updateManualSet(_ values: SetValues, setId: UUID) throws {
        let descriptor = FetchDescriptor<ExerciseSetModel>(predicate: #Predicate { $0.id == setId })
        guard let set = try context.fetch(descriptor).first, let exercise = set.entry?.exercise else {
            throw TrainingDataError.notFound
        }
        guard set.sourceRaw == SetSource.manual.rawValue else {
            throw TrainingDataError.invalidSet("only manual sets can be updated")
        }
        try Self.validate(values, for: exercise)
        set.apply(values)
        try context.save()
    }

    func deleteManualSet(id: UUID) throws {
        let descriptor = FetchDescriptor<ExerciseSetModel>(predicate: #Predicate { $0.id == id })
        guard let set = try context.fetch(descriptor).first, let entry = set.entry else {
            throw TrainingDataError.notFound
        }
        guard set.sourceRaw == SetSource.manual.rawValue else {
            throw TrainingDataError.invalidSet("only manual sets can be deleted")
        }
        entry.sets.removeAll { $0.id == set.id }
        context.delete(set)

        if entry.sets.isEmpty, entry.statusRaw == EntryStatus.done.rawValue {
            if let session = entry.session, isPlanned(entry, in: session) {
                entry.statusRaw = EntryStatus.skipped.rawValue
                entry.completedAt = nil
            } else {
                entry.session?.entries.removeAll { $0.id == entry.id }
                context.delete(entry)
            }
        } else if !entry.hasBothSources {
            entry.clearReconciliation()
        }
        try context.save()
    }

    func replaceExercise(entryId: UUID, with exerciseId: UUID) throws {
        let entry = try fetchEntry(entryId)
        guard entry.sets.isEmpty else { throw TrainingDataError.entryHasSets }
        guard let exercise = try context.fetchExercise(id: exerciseId) else { throw TrainingDataError.notFound }
        if entry.replacedExercise == nil {
            entry.replacedExercise = entry.exercise
        }
        entry.exercise = exercise
        try context.save()
    }

    func removeEntry(id: UUID) throws {
        let entry = try fetchEntry(id)
        entry.statusRaw = EntryStatus.removed.rawValue
        try context.save()
    }

    func importEntry(_ imported: ImportedEntry, into sessionId: UUID) throws {
        guard let session = try context.fetchSession(id: sessionId) else { throw TrainingDataError.notFound }
        guard let exercise = try context.fetchExercise(id: imported.exerciseId) else {
            throw TrainingDataError.notFound
        }
        let vacated = try merge(imported, exercise: exercise, into: session)
        removeEmptiedImportedSessions(vacated)
        try context.save()
    }

    func chooseReconciliation(entryId: UUID, keep: SetSource, at date: Date) throws {
        let entry = try fetchEntry(entryId)
        guard entry.hasBothSources else { throw TrainingDataError.entryNotMixed }
        entry.setReconciliation(keep: keep, decidedBy: .user, at: date)
        try context.save()
    }

    func discardSession(id: UUID) throws {
        let session = try openSession(id)
        context.delete(session)
        try context.save()
    }

    func finishSession(id: UUID, at date: Date, durationSeconds: Int?) throws -> TrainingSession {
        let session = try openSession(id)
        if let startedAt = session.startedAt, date < startedAt {
            throw TrainingDataError.invalidSession("a session cannot end before it started")
        }
        guard !session.entries.isEmpty else {
            throw TrainingDataError.invalidSession("a session needs at least one entry")
        }
        session.completedAt = date
        if let durationSeconds {
            let elapsed = session.startedAt.map { max(0, Int(date.timeIntervalSince($0))) } ?? durationSeconds
            session.durationSeconds = max(0, min(durationSeconds, elapsed))
        }
        // Rule `range`: no entry ends after its session. A later time is unknown, not invented.
        for entry in session.entries where (entry.completedAt ?? date) > date {
            entry.completedAt = nil
        }
        try context.save()
        return session.snapshot
    }

    // MARK: Rules

    /// Fields a set may carry for the exercise's type (format rule `exercise-type`).
    static func validate(_ values: SetValues, for exercise: ExerciseModel) throws {
        try validate(values, typeRaw: exercise.typeRaw)
    }

    /// Fields a set may carry for an exercise type (format rule `exercise-type`).
    static func validate(_ values: SetValues, typeRaw: String) throws {
        guard values.reps != nil || values.durationSeconds != nil else {
            throw TrainingDataError.invalidSet("a set needs reps or a duration")
        }
        try validateRanges(values)
        let isCardio = typeRaw == ExerciseType.cardio.rawValue
        if isCardio {
            guard values.durationSeconds != nil else {
                throw TrainingDataError.invalidSet("cardio sets need a duration")
            }
            guard values.reps == nil, values.weight == nil else {
                throw TrainingDataError.invalidSet("cardio sets have neither reps nor weight")
            }
        } else if values.distanceMeters != nil {
            throw TrainingDataError.invalidSet("only cardio sets have a distance")
        }
        if let distance = values.distanceMeters, distance < 0 {
            throw TrainingDataError.invalidSet("distance must not be negative")
        }
    }

    /// Ranges of a set's rir, reps, duration, weight and rest.
    private static func validateRanges(_ values: SetValues) throws {
        if let rir = values.rir, !(0 ... 10).contains(rir) {
            throw TrainingDataError.invalidSet("rir must be between 0 and 10")
        }
        if let reps = values.reps, reps < 0 { throw TrainingDataError.invalidSet("reps must not be negative") }
        if let seconds = values.durationSeconds, seconds < 0 {
            throw TrainingDataError.invalidSet("duration must not be negative")
        }
        if let weight = values.weight, weight.value < 0 {
            throw TrainingDataError.invalidSet("weight must not be negative")
        }
        if let rest = values.restSeconds, rest < 0 { throw TrainingDataError.invalidSet("rest must not be negative") }
    }

    /// The format's `timeZone`: an IANA name or `UTC`. Fixed-offset zones
    /// (identifier `GMT+0100`) become the equivalent `Etc/GMT` zone.
    static func formatTimeZone(_ zone: TimeZone) throws -> String {
        let identifier = zone.identifier
        if identifier == "UTC" || identifier == "GMT" { return "UTC" }
        if identifier.wholeMatch(of: /[A-Za-z_]+(\/[A-Za-z0-9_+\-]+)+/) != nil { return identifier }
        let seconds = zone.secondsFromGMT()
        if seconds == 0 { return "UTC" }
        guard seconds % 3600 == 0 else {
            throw TrainingDataError.invalidSession("time zone \(identifier) has no IANA name")
        }
        let hours = seconds / 3600
        // Etc/GMT signs are inverted: UTC+1 is Etc/GMT-1.
        return hours > 0 ? "Etc/GMT-\(hours)" : "Etc/GMT+\(-hours)"
    }

    /// The one `done` entry for the exercise in the session (rule `one-entry-per-exercise`):
    /// the existing done entry, else the planned (skipped) entry, else a new one at the end.
    func doneEntry(in session: SessionModel, for exercise: ExerciseModel) -> SessionEntryModel {
        let ofExercise = session.entries.filter { $0.exercise?.id == exercise.id }
        if let done = ofExercise.first(where: { $0.statusRaw == EntryStatus.done.rawValue }) {
            return done
        }
        if let planned = ofExercise.first(where: { $0.statusRaw == EntryStatus.skipped.rawValue }) {
            planned.statusRaw = EntryStatus.done.rawValue
            return planned
        }
        let order = (session.entries.map(\.order).max() ?? 0) + 1
        let entry = SessionEntryModel(id: UUID(), order: order, statusRaw: EntryStatus.done.rawValue)
        context.insert(entry)
        entry.exercise = exercise
        session.entries.append(entry)
        return entry
    }

    /// Reconciliation rules 3 and 4: an entry that starts mixing sources gets the
    /// default decision (keep imported). An existing decision is never changed here;
    /// sets added later are marked when they are created.
    func applyReconciliationOnMerge(_ entry: SessionEntryModel, at date: Date) {
        guard entry.hasBothSources, entry.reconciliationKeepRaw == nil else { return }
        entry.setReconciliation(keep: .imported, decidedBy: .default, at: date)
    }

    func nextOrder(in entry: SessionEntryModel, source: SetSource) -> Int {
        (entry.sets.filter { $0.sourceRaw == source.rawValue }.map(\.order).max() ?? 0) + 1
    }

    func isPlanned(_ entry: SessionEntryModel, in session: SessionModel) -> Bool {
        guard let routine = session.routine, let exerciseId = entry.exercise?.id else { return false }
        return routine.items.contains { $0.exercise?.id == exerciseId || $0.exercise?.id == entry.replacedExercise?.id }
    }

    private func openSession(_ id: UUID) throws -> SessionModel {
        guard let session = try context.fetchSession(id: id) else { throw TrainingDataError.notFound }
        guard session.completedAt == nil else { throw TrainingDataError.sessionAlreadyCompleted }
        return session
    }

    private func fetchEntry(_ id: UUID) throws -> SessionEntryModel {
        let descriptor = FetchDescriptor<SessionEntryModel>(predicate: #Predicate { $0.id == id })
        guard let entry = try context.fetch(descriptor).first else { throw TrainingDataError.notFound }
        return entry
    }
}
