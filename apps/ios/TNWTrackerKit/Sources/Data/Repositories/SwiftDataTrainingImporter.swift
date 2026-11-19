import Foundation
import SwiftData

/// Imports an importer's bundle under format decision B: the app owns its keys.
/// Bundle ids only resolve references inside the bundle (bundle id → local model);
/// every item is found by its `externalRef` or created with a fresh UUID.
@MainActor
final class SwiftDataTrainingImporter: TrainingImporterProtocol {
    private let context: ModelContext
    private let container: ModelContainer
    private let sessions: SwiftDataSessionRepository
    private let exercises: SwiftDataExerciseRepository
    private let routines: SwiftDataRoutineRepository

    init(context: ModelContext, sessions: SwiftDataSessionRepository) {
        self.context = context
        container = context.container
        self.sessions = sessions
        exercises = SwiftDataExerciseRepository(context: context)
        routines = SwiftDataRoutineRepository(context: context)
    }

    /// Atomic per session (D13). Bundle-level rules (exercises, routines and their
    /// references) are checked before any write and reject the whole bundle.
    /// Exercises and routines are then saved, and each session is validated and
    /// written on its own: an invalid session is rolled back, skipped and listed in
    /// `ImportResult.skippedSessions` with its reason; every valid one is saved.
    func importBundle(_ bundle: TrainingBundle) throws -> ImportResult {
        try validateBundleLevel(bundle)
        var result = ImportResult()
        do {
            for exercise in bundle.exercises {
                result.exerciseIds[exercise.id] = try importExercise(exercise)
            }
            for routine in bundle.routines {
                result.routineIds[routine.id] = try importRoutine(routine, exerciseIds: result.exerciseIds)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        let types = Dictionary(
            bundle.exercises.map { ($0.id, $0.type.rawValue) },
            uniquingKeysWith: { first, _ in first }
        )
        let bundleRoutineIds = Set(bundle.routines.map(\.id))
        for session in bundle.sessions {
            do {
                try validate(session, types: types, routineIds: bundleRoutineIds)
                let localId = try importSession(session, result: result)
                try context.save()
                result.sessionIds[session.id] = localId
            } catch let error as TrainingDataError {
                context.rollback()
                result.skippedSessions.append(
                    SkippedSession(bundleId: session.id, externalRef: session.externalRef, reason: error)
                )
            } catch {
                // Not a rule of the format (a storage failure): stop the import.
                // Sessions already saved stay saved.
                context.rollback()
                throw error
            }
        }
        return result
    }

    // MARK: - Items

    /// An imported exercise (with `externalRef`) is found by it and its values are
    /// replaced. An exercise without provider data is matched by name and type and
    /// left as it is, so a user's own exercise is never overwritten. Exercises the
    /// importer creates are never catalogue exercises.
    private func importExercise(_ exercise: Exercise) throws -> UUID {
        if let ref = exercise.externalRef {
            var local = exercise
            local.isCatalogue = false
            local.id = try context.fetchExercise(ref: ref)?.id ?? UUID()
            try exercises.write(local)
            return local.id
        }
        if let existing = try context.fetchExerciseWithoutRef(name: exercise.name, typeRaw: exercise.type.rawValue) {
            return existing.id
        }
        var local = exercise
        local.id = UUID()
        local.isCatalogue = false
        try exercises.write(local)
        return local.id
    }

    private func importRoutine(_ routine: Routine, exerciseIds: [UUID: UUID]) throws -> UUID {
        guard let ref = routine.externalRef else {
            throw TrainingDataError.invalidRoutine("an imported routine needs an externalRef")
        }
        var local = routine
        local.id = try context.fetchRoutine(ref: ref)?.id ?? UUID()
        local.items = try routine.items.map { item in
            var mapped = item
            mapped.exerciseId = try resolve(item.exerciseId, in: exerciseIds)
            return mapped
        }
        try routines.write(local)
        return local.id
    }

    /// The session an imported session lands in: the one already holding its
    /// entries, the one with its `externalRef`, the session completed on the same
    /// local date (O1), or a new completed session.
    private func importSession(_ incoming: BundleSession, result: ImportResult) throws -> UUID {
        guard incoming.externalRef.isValid else { throw TrainingDataError.invalidExternalRef }
        let zone = TimeZone(identifier: incoming.timeZone) ?? .gmt
        let session = try knownSession(of: incoming)
            ?? context.fetchSession(ref: incoming.externalRef)
            ?? sameDaySession(as: incoming.completedAt, in: zone)
            ?? newSession(from: incoming, zone: zone)

        // Only a session the import created carries the import's `externalRef`,
        // and only that one takes the import's values. A session the user logged
        // keeps every user field; it only gains the imported entries and sets,
        // whose refs find it again on a re-import.
        let ownedByImport = session.externalProvider == incoming.externalRef.provider
            && session.externalId == incoming.externalRef.id
        if ownedByImport {
            session.name = incoming.name
            session.notes = incoming.notes
            session.durationSeconds = incoming.durationSeconds
            if let routineId = incoming.routineId {
                session.routine = try context.fetchRoutine(id: resolve(routineId, in: result.routineIds))
            }
        }
        var vacated: [SessionModel] = []
        for entry in incoming.entries {
            let exerciseId = try resolve(entry.exerciseId, in: result.exerciseIds)
            guard let exercise = try context.fetchExercise(id: exerciseId) else { throw TrainingDataError.notFound }
            vacated += try sessions.merge(entry, exercise: exercise, into: session)
        }
        // D8: a session whose refs all moved here is removed once every entry is in.
        try sessions.removeEmptiedImportedSessions(vacated.filter { $0.id != session.id })
        return session.id
    }

    private func knownSession(of incoming: BundleSession) throws -> SessionModel? {
        for entry in incoming.entries {
            if let session = try context.fetchEntry(ref: entry.externalRef)?.session {
                return session
            }
        }
        return nil
    }

    private func sameDaySession(as date: Date, in zone: TimeZone) throws -> SessionModel? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let day = calendar.dateInterval(of: .day, for: date) else { return nil }
        let start = day.start
        let end = day.end
        var descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { session in
                session.completedAt.flatMap { $0 >= start && $0 < end } == true
            },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func newSession(from incoming: BundleSession, zone: TimeZone) throws -> SessionModel {
        let session = try SessionModel(id: UUID(), timeZone: SwiftDataSessionRepository.formatTimeZone(zone))
        session.externalProvider = incoming.externalRef.provider
        session.externalId = incoming.externalRef.id
        session.startedAt = incoming.startedAt
        session.completedAt = incoming.completedAt
        context.insert(session)
        try context.trackNew(session)
        return session
    }

    // MARK: - References

    private func resolve(_ bundleId: UUID, in map: [UUID: UUID]) throws -> UUID {
        guard let local = map[bundleId] else {
            throw TrainingDataError.invalidSession("bundle reference \(bundleId) is not in the bundle")
        }
        return local
    }

    /// Bundle-level rules, checked before any write: a failure rejects the whole
    /// bundle (exercises, routines and the routines' exercise references).
    private func validateBundleLevel(_ bundle: TrainingBundle) throws {
        for exercise in bundle.exercises {
            try SwiftDataExerciseRepository.validate(exercise)
        }
        for routine in bundle.routines where routine.externalRef?.isValid != true {
            throw TrainingDataError.invalidRoutine("an imported routine needs a valid externalRef")
        }
        let exerciseIds = Set(bundle.exercises.map(\.id))
        for routine in bundle.routines where routine.items.contains(where: { !exerciseIds.contains($0.exerciseId) }) {
            throw TrainingDataError.invalidRoutine("routine \(routine.name) names an exercise outside the bundle")
        }
    }

    /// Every rule one bundle session can break (rules `exercise-reference`,
    /// `routine-reference`, `range`, `exercise-type`), checked before it is written.
    private func validate(_ session: BundleSession, types: [UUID: String], routineIds: Set<UUID>) throws {
        guard session.externalRef.isValid else { throw TrainingDataError.invalidExternalRef }
        if let startedAt = session.startedAt, startedAt > session.completedAt {
            throw TrainingDataError.invalidSession("a session cannot end before it started")
        }
        guard TimeZone(identifier: session.timeZone) != nil || session.timeZone == "UTC" else {
            throw TrainingDataError.invalidSession("unknown time zone \(session.timeZone)")
        }
        if let routineId = session.routineId, !routineIds.contains(routineId) {
            throw TrainingDataError.invalidSession("session names a routine outside the bundle")
        }
        if session.entries.contains(where: { types[$0.exerciseId] == nil }) {
            throw TrainingDataError.invalidSession("entry names an exercise outside the bundle")
        }
        guard !session.entries.isEmpty else {
            throw TrainingDataError.invalidSession("a session needs at least one entry")
        }
        for entry in session.entries {
            try validate(entry, typeRaw: types[entry.exerciseId])
        }
    }

    /// Rules one entry of a bundle session and its sets can break.
    private func validate(_ entry: ImportedEntry, typeRaw: String?) throws {
        guard entry.externalRef.isValid else { throw TrainingDataError.invalidExternalRef }
        guard !entry.sets.isEmpty else {
            throw TrainingDataError.invalidSet("an imported entry needs at least one set")
        }
        for set in entry.sets {
            guard set.externalRef.isValid else { throw TrainingDataError.invalidExternalRef }
            guard set.order >= 1 else { throw TrainingDataError.invalidSet("set order starts at 1") }
            if let typeRaw {
                try SwiftDataSessionRepository.validate(set.values, typeRaw: typeRaw)
            }
        }
    }
}
