import Foundation
import SwiftData

// SwiftData adapters of the training repositories. They own every rule of the
// format that a single write can break; see docs/training-data-format.md.

// MARK: - Exercise

@MainActor
final class SwiftDataExerciseRepository: ExerciseRepositoryProtocol {
    private let context: ModelContext
    /// The context does not keep its container alive; the adapter does.
    private let container: ModelContainer

    init(context: ModelContext) {
        self.context = context
        container = context.container
    }

    func exercises() throws -> [Exercise] {
        try context.fetch(FetchDescriptor<ExerciseModel>(sortBy: [SortDescriptor(\.name)])).map(\.snapshot)
    }

    func exercise(id: UUID) throws -> Exercise? {
        try context.fetchExercise(id: id)?.snapshot
    }

    func save(_ exercise: Exercise) throws {
        try write(exercise)
        try context.save()
    }

    /// Validates and writes the exercise without saving the context.
    func write(_ exercise: Exercise) throws {
        try Self.validate(exercise)
        if let ref = exercise.externalRef,
           let owner = try context.fetchExercise(ref: ref), owner.id != exercise.id {
            throw TrainingDataError.duplicateExternalRef
        }
        let model = try context.fetchExercise(id: exercise.id)
            ?? ExerciseModel(id: exercise.id, name: exercise.name, typeRaw: exercise.type.rawValue)
        if model.modelContext == nil { context.insert(model) }

        model.name = exercise.name
        model.typeRaw = exercise.type.rawValue
        model.externalProvider = exercise.externalRef?.provider
        model.externalId = exercise.externalRef?.id
        model.isCatalogue = exercise.isCatalogue
        model.equipmentRaw = exercise.equipment?.rawValue
        let instructions = exercise.instructions.flatMap { $0.isEmpty ? nil : $0 }
        model.instructionsSetup = instructions.map(\.setup).flatMap { $0.isEmpty ? nil : $0 }
        model.instructionsExecution = instructions.map(\.execution).flatMap { $0.isEmpty ? nil : $0 }
        model.instructionsTips = instructions.map(\.tips).flatMap { $0.isEmpty ? nil : $0 }
        model.mediaImageURI = exercise.media?.imageURI
        model.mediaVideoURI = exercise.media?.videoURI

        for old in model.muscleGroups {
            context.delete(old)
        }
        model.muscleGroups = []
        for (position, group) in exercise.muscleGroups.enumerated() {
            let row = MuscleGroupModel(muscleRaw: group.muscle.rawValue, roleRaw: group.role.rawValue, position: position)
            context.insert(row)
            model.muscleGroups.append(row)
        }

    }

    /// Field rules of the format's `exercise` that a JSON Schema states.
    static func validate(_ exercise: Exercise) throws {
        guard !exercise.name.isEmpty else { throw TrainingDataError.invalidExercise("name is empty") }
        if let ref = exercise.externalRef, !ref.isValid { throw TrainingDataError.invalidExternalRef }
        if exercise.isCatalogue, exercise.externalRef != nil {
            throw TrainingDataError.invalidExercise("a catalogue exercise has no externalRef")
        }
        guard Set(exercise.muscleGroups).count == exercise.muscleGroups.count else {
            throw TrainingDataError.invalidExercise("muscle groups must be unique")
        }
        if let media = exercise.media, media.imageURI == "" || media.videoURI == "" {
            throw TrainingDataError.invalidExercise("a media uri is empty")
        }
        if let steps = exercise.instructions, (steps.setup + steps.execution + steps.tips).contains(where: \.isEmpty) {
            throw TrainingDataError.invalidExercise("an instruction step is empty")
        }
    }
}

// MARK: - Routine

@MainActor
final class SwiftDataRoutineRepository: RoutineRepositoryProtocol {
    private let context: ModelContext
    /// The context does not keep its container alive; the adapter does.
    private let container: ModelContainer

    init(context: ModelContext) {
        self.context = context
        container = context.container
    }

    func routines(_ query: RoutineQuery) throws -> [Routine] {
        var descriptor = FetchDescriptor<RoutineModel>(sortBy: [SortDescriptor(\.name)])
        if !query.search.isEmpty {
            let search = query.search
            descriptor.predicate = #Predicate { $0.name.localizedStandardContains(search) }
        }
        var models = try context.fetch(descriptor)
        if query.onlyPerformed {
            models = models.filter { routine in routine.sessions.contains { $0.completedAt != nil } }
        }
        let page = models.dropFirst(query.offset).prefix(query.limit ?? Int.max)
        return page.map(\.snapshot)
    }

    func routine(id: UUID) throws -> Routine? {
        try context.fetchRoutine(id: id)?.snapshot
    }

    func save(_ routine: Routine) throws {
        try write(routine)
        try context.save()
    }

    /// Validates and writes the routine without saving the context.
    func write(_ routine: Routine) throws {
        guard !routine.name.isEmpty else { throw TrainingDataError.invalidRoutine("name is empty") }
        guard !routine.items.isEmpty else { throw TrainingDataError.invalidRoutine("a routine needs at least one item") }
        let orders = routine.items.map(\.order)
        guard orders.allSatisfy({ $0 >= 1 }), Set(orders).count == orders.count else {
            throw TrainingDataError.invalidRoutine("item positions must be unique and start at 1")
        }
        if let ref = routine.externalRef, !ref.isValid { throw TrainingDataError.invalidExternalRef }
        if let ref = routine.externalRef,
           let owner = try context.fetchRoutine(ref: ref), owner.id != routine.id {
            throw TrainingDataError.duplicateExternalRef
        }
        var exercises: [UUID: ExerciseModel] = [:]
        for item in routine.items {
            if let range = item.targetReps, range.min < 1 || range.min > range.max {
                throw TrainingDataError.invalidRoutine("targetReps needs 1 ≤ min ≤ max")
            }
            if let sets = item.targetSets, sets < 1 { throw TrainingDataError.invalidRoutine("targetSets must be at least 1") }
            if [item.targetDurationSeconds, item.restSeconds].contains(where: { ($0 ?? 0) < 0 }) {
                throw TrainingDataError.invalidRoutine("durations must not be negative")
            }
            if let weight = item.targetWeight, weight.value < 0 {
                throw TrainingDataError.invalidRoutine("targetWeight must not be negative")
            }
            guard let exercise = try context.fetchExercise(id: item.exerciseId) else {
                throw TrainingDataError.invalidRoutine("unknown exercise \(item.exerciseId)")
            }
            exercises[item.exerciseId] = exercise
        }

        let model = try context.fetchRoutine(id: routine.id) ?? RoutineModel(id: routine.id, name: routine.name)
        if model.modelContext == nil { context.insert(model) }
        model.name = routine.name
        model.routineDescription = routine.description
        model.externalProvider = routine.externalRef?.provider
        model.externalId = routine.externalRef?.id

        for old in model.items {
            context.delete(old)
        }
        model.items = []
        for item in routine.items.sorted(by: { $0.order < $1.order }) {
            let row = RoutineItemModel(order: item.order)
            context.insert(row)
            row.exercise = exercises[item.exerciseId]
            row.targetSets = item.targetSets
            row.targetRepsMin = item.targetReps?.min
            row.targetRepsMax = item.targetReps?.max
            row.targetWeightValue = item.targetWeight?.value
            row.targetWeightUnitRaw = item.targetWeight?.unit.rawValue
            row.targetDurationSeconds = item.targetDurationSeconds
            row.restSeconds = item.restSeconds
            row.notes = item.notes
            model.items.append(row)
        }

    }
}

// MARK: - Session

@MainActor
final class SwiftDataSessionRepository: SessionRepositoryProtocol {
    private let context: ModelContext
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

    func logManualSet(_ values: SetValues, warmup: Bool, exerciseId: UUID, sessionId: UUID, at date: Date) throws -> ExerciseSet {
        let session = try openSession(sessionId)
        guard let exercise = try context.fetchExercise(id: exerciseId) else { throw TrainingDataError.notFound }
        try Self.validate(values, for: exercise)

        let entry = doneEntry(in: session, for: exercise)
        let set = ExerciseSetModel(id: UUID(), order: nextOrder(in: entry, source: .manual), sourceRaw: SetSource.manual.rawValue)
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
        guard let exercise = try context.fetchExercise(id: imported.exerciseId) else { throw TrainingDataError.notFound }
        try merge(imported, exercise: exercise, into: session)
        try context.save()
    }

    /// Merges one imported entry into `session` without saving. `imported.exerciseId`
    /// is ignored: `exercise` is the local exercise it resolved to.
    func merge(_ imported: ImportedEntry, exercise: ExerciseModel, into session: SessionModel) throws {
        // Validate everything before writing anything.
        guard !imported.sets.isEmpty else { throw TrainingDataError.invalidSet("an imported entry needs at least one set") }
        guard imported.externalRef.isValid else { throw TrainingDataError.invalidExternalRef }
        for incoming in imported.sets {
            guard incoming.externalRef.isValid else { throw TrainingDataError.invalidExternalRef }
            guard incoming.order >= 1 else { throw TrainingDataError.invalidSet("set order starts at 1") }
            try Self.validate(incoming.values, for: exercise)
        }
        let known = try context.fetchEntry(ref: imported.externalRef)
        if let known, known.session?.id != session.id { throw TrainingDataError.duplicateExternalRef }
        for incoming in imported.sets {
            if let stored = try context.fetchSet(ref: incoming.externalRef), stored.entry?.session?.id != session.id {
                throw TrainingDataError.duplicateExternalRef
            }
        }

        // One entry per exercise: a second provider entry merges into the same entry.
        let entry = known ?? doneEntry(in: session, for: exercise)
        if entry.externalId == nil {
            entry.externalProvider = imported.externalRef.provider
            entry.externalId = imported.externalRef.id
        }
        if known == nil {
            let alias = EntryExternalRefModel(provider: imported.externalRef.provider, externalId: imported.externalRef.id)
            context.insert(alias)
            entry.mergedRefs.append(alias)
        }
        // Rule `range`: no entry ends after its session.
        if let completedAt = imported.completedAt, session.completedAt.map({ completedAt <= $0 }) ?? true {
            entry.completedAt = completedAt
        }

        let keep = entry.reconciliationKeepRaw.flatMap(SetSource.init(rawValue:))
        for incoming in imported.sets.sorted(by: { $0.order < $1.order }) {
            if let stored = try context.fetchSet(ref: incoming.externalRef) {
                // Re-import: values replace the stored ones. The set keeps its
                // position in the merged entry; `superseded` and `warmup` belong to the app.
                stored.apply(incoming.values)
                stored.completedAt = incoming.completedAt
            } else {
                // Imported sets are numbered within the merged entry, so sets of
                // several provider entries never share an order.
                let set = ExerciseSetModel(id: UUID(), order: nextOrder(in: entry, source: .imported), sourceRaw: SetSource.imported.rawValue)
                context.insert(set)
                set.externalProvider = incoming.externalRef.provider
                set.externalId = incoming.externalRef.id
                set.apply(incoming.values)
                set.completedAt = incoming.completedAt
                set.superseded = keep == .manual
                set.warmup = incoming.warmup
                entry.sets.append(set)
            }
        }
        applyReconciliationOnMerge(entry, at: Date())
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
    private static func validate(_ values: SetValues, for exercise: ExerciseModel) throws {
        try validate(values, typeRaw: exercise.typeRaw)
    }

    /// Fields a set may carry for an exercise type (format rule `exercise-type`).
    static func validate(_ values: SetValues, typeRaw: String) throws {
        guard values.reps != nil || values.durationSeconds != nil else {
            throw TrainingDataError.invalidSet("a set needs reps or a duration")
        }
        if let rir = values.rir, !(0 ... 10).contains(rir) {
            throw TrainingDataError.invalidSet("rir must be between 0 and 10")
        }
        if let reps = values.reps, reps < 0 { throw TrainingDataError.invalidSet("reps must not be negative") }
        if let seconds = values.durationSeconds, seconds < 0 {
            throw TrainingDataError.invalidSet("duration must not be negative")
        }
        if let weight = values.weight, weight.value < 0 { throw TrainingDataError.invalidSet("weight must not be negative") }
        if let rest = values.restSeconds, rest < 0 { throw TrainingDataError.invalidSet("rest must not be negative") }
        let isCardio = typeRaw == ExerciseType.cardio.rawValue
        if isCardio {
            guard values.durationSeconds != nil else { throw TrainingDataError.invalidSet("cardio sets need a duration") }
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
    private func doneEntry(in session: SessionModel, for exercise: ExerciseModel) -> SessionEntryModel {
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
    private func applyReconciliationOnMerge(_ entry: SessionEntryModel, at date: Date) {
        guard entry.hasBothSources, entry.reconciliationKeepRaw == nil else { return }
        entry.setReconciliation(keep: .imported, decidedBy: .default, at: date)
    }

    private func nextOrder(in entry: SessionEntryModel, source: SetSource) -> Int {
        (entry.sets.filter { $0.sourceRaw == source.rawValue }.map(\.order).max() ?? 0) + 1
    }

    private func isPlanned(_ entry: SessionEntryModel, in session: SessionModel) -> Bool {
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

// MARK: - Lookups

extension ModelContext {
    func fetchExercise(id: UUID) throws -> ExerciseModel? {
        var descriptor = FetchDescriptor<ExerciseModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func fetchExercise(ref: ExternalRef) throws -> ExerciseModel? {
        let provider: String? = ref.provider
        let externalId: String? = ref.id
        var descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate { $0.externalProvider == provider && $0.externalId == externalId }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    /// An exercise without provider data, matched by its name and type.
    func fetchExerciseWithoutRef(name: String, typeRaw: String) throws -> ExerciseModel? {
        var descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate { $0.externalProvider == nil && $0.name == name && $0.typeRaw == typeRaw }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func fetchSession(ref: ExternalRef) throws -> SessionModel? {
        let provider: String? = ref.provider
        let externalId: String? = ref.id
        var descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.externalProvider == provider && $0.externalId == externalId }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func fetchRoutine(id: UUID) throws -> RoutineModel? {
        var descriptor = FetchDescriptor<RoutineModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func fetchRoutine(ref: ExternalRef) throws -> RoutineModel? {
        let provider: String? = ref.provider
        let externalId: String? = ref.id
        var descriptor = FetchDescriptor<RoutineModel>(
            predicate: #Predicate { $0.externalProvider == provider && $0.externalId == externalId }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func fetchSession(id: UUID) throws -> SessionModel? {
        var descriptor = FetchDescriptor<SessionModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    /// The entry an external entry ref was merged into.
    func fetchEntry(ref: ExternalRef) throws -> SessionEntryModel? {
        let provider = ref.provider
        let externalId = ref.id
        var descriptor = FetchDescriptor<EntryExternalRefModel>(
            predicate: #Predicate { $0.provider == provider && $0.externalId == externalId }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first?.entry
    }

    func fetchSet(ref: ExternalRef) throws -> ExerciseSetModel? {
        let provider: String? = ref.provider
        let externalId: String? = ref.id
        var descriptor = FetchDescriptor<ExerciseSetModel>(
            predicate: #Predicate { $0.externalProvider == provider && $0.externalId == externalId }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }
}
