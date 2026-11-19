import Foundation
import Testing
@testable import TNWTrackerKit

/// Format decision B: receivers own their keys. Bundle ids only link the parts of a
/// bundle; the app looks imported items up by `externalRef` and gives new ones its own id.
@Suite("Import identity (decision B)")
@MainActor
struct ImportIdentityTests {
    let store: TrainingStore
    let provider = "machines-atlas"
    /// 2030-03-04T09:00:00Z
    let t0 = Date(timeIntervalSince1970: 1_898_845_200)

    init() throws {
        store = try TrainingStore(inMemory: true)
    }

    private func ref(_ id: String) -> ExternalRef {
        ExternalRef(provider: provider, id: id)
    }

    /// The same provider data; every call uses fresh bundle ids unless given.
    private func bundle(
        exerciseName: String = "Chest Press Machine",
        routineName: String = "Machine Circuit",
        reps: [Int] = [10, 9],
        exerciseBundleId: UUID = UUID(),
        sessionBundleId: UUID = UUID()
    ) -> TrainingBundle {
        let routineBundleId = UUID()
        let press = Exercise(
            id: exerciseBundleId, externalRef: ref("ex-1"), name: exerciseName,
            type: .strength, equipment: .connectedMachine
        )
        let routine = Routine(
            id: routineBundleId, externalRef: ref("r-1"), name: routineName,
            items: [RoutineItem(order: 1, exerciseId: exerciseBundleId, targetSets: 2)]
        )
        let session = BundleSession(
            id: sessionBundleId, externalRef: ref("2030-03-04"),
            completedAt: t0.addingTimeInterval(3600), timeZone: "Europe/Madrid",
            routineId: routineBundleId,
            entries: [ImportedEntry(
                exerciseId: exerciseBundleId, externalRef: ref("e-5001"),
                sets: reps.enumerated().map { index, value in
                    ImportedSet(externalRef: ref("e-5001#\(index + 1)"), order: index + 1,
                                values: SetValues(reps: value, weight: .kg(40)))
                }
            )]
        )
        return TrainingBundle(exercises: [press], routines: [routine], sessions: [session])
    }

    private var allSessions: [TrainingSession] {
        get throws { try store.sessions.completedSessions(in: DateInterval(start: .distantPast, end: .distantFuture)) }
    }

    @Test("re-importing the same data with different bundle ids updates in place without duplicates")
    func reimportWithNewBundleIds() throws {
        let first = try store.importer.importBundle(bundle())
        let second = try store.importer.importBundle(bundle(
            exerciseName: "Chest Press", routineName: "Circuit", reps: [12, 11]
        ))

        let exercises = try store.exercises.exercises()
        #expect(exercises.count == 1)
        #expect(exercises.first?.name == "Chest Press")
        let routines = try store.routines.routines(RoutineQuery())
        #expect(routines.count == 1)
        #expect(routines.first?.name == "Circuit")
        let sessions = try allSessions
        #expect(sessions.count == 1)
        let entry = try #require(sessions.first?.entries.first)
        #expect(sessions.first?.entries.count == 1)
        #expect(entry.sets.map { $0.values.reps } == [12, 11])

        #expect(Set(first.exerciseIds.values) == Set(second.exerciseIds.values))
        #expect(Set(first.routineIds.values) == Set(second.routineIds.values))
        #expect(Set(first.sessionIds.values) == Set(second.sessionIds.values))
    }

    @Test("bundle ids are never adopted as local ids, and internal references resolve to local items")
    func bundleIdsAreNotAdopted() throws {
        let exerciseBundleId = UUID()
        let sessionBundleId = UUID()
        let result = try store.importer.importBundle(
            bundle(exerciseBundleId: exerciseBundleId, sessionBundleId: sessionBundleId)
        )

        let localExercise = try #require(result.exerciseIds[exerciseBundleId])
        #expect(localExercise != exerciseBundleId)
        #expect(try store.exercises.exercise(id: exerciseBundleId) == nil)
        #expect(try store.exercises.exercise(id: localExercise)?.isImported == true)
        #expect(try store.exercises.exercise(id: localExercise)?.isCatalogue == false)

        let localSession = try #require(result.sessionIds[sessionBundleId])
        #expect(localSession != sessionBundleId)
        let session = try #require(try store.sessions.session(id: localSession))
        let routine = try #require(try store.routines.routines(RoutineQuery()).first)
        #expect(session.routineId == routine.id)
        #expect(routine.items.first?.exerciseId == localExercise)
        #expect(session.entries.first?.exerciseId == localExercise)
        #expect(session.externalRef == ref("2030-03-04"))
        #expect(session.isCompleted)
    }

    @Test("an imported item whose bundle id equals an unrelated local id does not overwrite it")
    func bundleIdCollisionDoesNotOverwrite() throws {
        let manual = Exercise(name: "Goblet Squat", type: .strength, equipment: .freeWeights)
        try store.exercises.save(manual)
        let manualSession = try store.sessions.startSession(
            routineId: nil,
            name: "Manual",
            at: t0.addingTimeInterval(-86400 * 3),
            timeZone: .gmt
        )
        try store.sessions.logManualSet(
            SetValues(reps: 8),
            exerciseId: manual.id,
            sessionId: manualSession.id,
            at: manualSession.startedAt ?? t0
        )
        try store.sessions.finishSession(
            id: manualSession.id,
            at: t0.addingTimeInterval(-86400 * 3 + 600),
            durationSeconds: nil
        )

        let result = try store.importer.importBundle(
            bundle(exerciseBundleId: manual.id, sessionBundleId: manualSession.id)
        )

        #expect(try store.exercises.exercise(id: manual.id) == manual)
        #expect(result.exerciseIds[manual.id] != manual.id)
        #expect(try store.exercises.exercises().count == 2)
        let untouched = try #require(try store.sessions.session(id: manualSession.id))
        #expect(untouched.name == "Manual")
        #expect(untouched.entries.map(\.exerciseId) == [manual.id])
        #expect(result.sessionIds[manualSession.id] != manualSession.id)
        #expect(try allSessions.count == 2)
    }

    @Test("an imported session joins the manual session completed on the same local date (O1)")
    func importJoinsSameDaySession() throws {
        let manual = Exercise(name: "Goblet Squat", type: .strength)
        try store.exercises.save(manual)
        let morning = try store.sessions.startSession(
            routineId: nil,
            name: "Morning",
            at: t0,
            timeZone: TimeZone(identifier: "Europe/Madrid") ?? .gmt
        )
        try store.sessions.logManualSet(SetValues(reps: 8), exerciseId: manual.id, sessionId: morning.id, at: t0)
        try store.sessions.finishSession(id: morning.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)

        let result = try store.importer.importBundle(bundle())

        #expect(Set(result.sessionIds.values) == [morning.id])
        let joined = try #require(try store.sessions.session(id: morning.id))
        #expect(joined.entries.count == 2)
        #expect(try allSessions.count == 1)
    }

    @Test("a manual exercise keeps the id the app gave it")
    func manualKeepsId() throws {
        let manual = Exercise(name: "Plank", type: .bodyweight)
        try store.exercises.save(manual)
        #expect(try store.exercises.exercise(id: manual.id)?.id == manual.id)
        #expect(manual.isImported == false)
    }

    @Test("an exercise without catalogue data is matched by name and type on re-import")
    func exerciseWithoutRefMatchedByName() throws {
        let unknown = Exercise(name: "Treadmill Walk", type: .cardio)
        var first = TrainingBundle(exercises: [unknown])
        first.sessions = [BundleSession(
            id: UUID(), externalRef: ref("2030-03-05"), completedAt: t0.addingTimeInterval(86400), timeZone: "UTC",
            entries: [ImportedEntry(exerciseId: unknown.id, externalRef: ref("e-9"), sets: [
                ImportedSet(externalRef: ref("e-9#1"), order: 1, values: SetValues(durationSeconds: 900))
            ])]
        )]
        try store.importer.importBundle(first)
        var second = first
        let renamedBundleId = UUID()
        second.exercises = [Exercise(id: renamedBundleId, name: "Treadmill Walk", type: .cardio)]
        second.sessions[0].entries[0].exerciseId = renamedBundleId
        try store.importer.importBundle(second)

        #expect(try store.exercises.exercises().count == 1)
        #expect(try store.exercises.exercises().first?.isImported == false)
    }

    @Test("an imported exercise is never a catalogue exercise")
    func importedExerciseIsNeverCatalogue() throws {
        var unknown = Exercise(name: "Rowing Erg", type: .cardio)
        unknown.isCatalogue = true
        var source = TrainingBundle(exercises: [unknown])
        source.sessions = [BundleSession(
            id: UUID(), externalRef: ref("2030-03-06"), completedAt: t0.addingTimeInterval(86400 * 2), timeZone: "UTC",
            entries: [ImportedEntry(exerciseId: unknown.id, externalRef: ref("e-10"), sets: [
                ImportedSet(externalRef: ref("e-10#1"), order: 1, values: SetValues(durationSeconds: 600))
            ])]
        )]
        let result = try store.importer.importBundle(source)
        try store.importer.importBundle(bundle())

        let local = try #require(result.exerciseIds[unknown.id])
        #expect(try store.exercises.exercise(id: local)?.isCatalogue == false)
        #expect(try store.exercises.exercises().count == 2)
        #expect(try store.exercises.exercises().allSatisfy { !$0.isCatalogue })
    }

    @Test("a bundle with a catalogue exercise that has an externalRef is rejected and writes nothing")
    func catalogueExerciseWithRefInBundleRejected() throws {
        var source = bundle()
        source.exercises[0].isCatalogue = true
        #expect(throws: TrainingDataError.invalidExercise("a catalogue exercise has no externalRef")) {
            try store.importer.importBundle(source)
        }
        #expect(try store.exercises.exercises().isEmpty)
        #expect(try store.routines.routines(RoutineQuery()).isEmpty)
        #expect(try allSessions.isEmpty)
    }

    @Test("a session naming an exercise the bundle does not contain is skipped and reported (D13)")
    func unresolvedReferenceRejected() throws {
        var broken = bundle()
        broken.sessions[0].entries[0].exerciseId = UUID()
        let result = try store.importer.importBundle(broken)
        #expect(result.skippedSessions.map(\.reason) == [.invalidSession("entry names an exercise outside the bundle")])
        #expect(try allSessions.isEmpty)
    }

    // MARK: - Verifier regressions (B3, B4)

    @Test("""
        B3: a failing session writes nothing, even after an unrelated save, \
        and a corrected retry imports cleanly (D13: per session)
        """)
    func failingImportIsAtomic() throws {
        let strengthId = UUID(), cardioId = UUID()
        let strength = Exercise(id: strengthId, externalRef: ref("st"), name: "Row", type: .strength)
        let cardio = Exercise(id: cardioId, externalRef: ref("ca"), name: "Bike", type: .cardio)
        let good = BundleSession(
            id: UUID(), externalRef: ref("day1"), completedAt: t0, timeZone: "UTC",
            entries: [ImportedEntry(exerciseId: strengthId, externalRef: ref("g"), sets: [
                ImportedSet(externalRef: ref("g#1"), order: 1, values: SetValues(reps: 5))
            ])]
        )
        let bad = BundleSession(
            id: UUID(), externalRef: ref("day2"), completedAt: t0.addingTimeInterval(2 * 86400), timeZone: "UTC",
            entries: [ImportedEntry(exerciseId: cardioId, externalRef: ref("b"), sets: [
                ImportedSet(externalRef: ref("b#1"), order: 1, values: SetValues(reps: 5)) // cardio with reps
            ])]
        )
        let invalid = TrainingBundle(exercises: [strength, cardio], sessions: [good, bad])

        let skipped = try store.importer.importBundle(invalid)
        #expect(skipped.skippedSessions.map(\.bundleId) == [bad.id])
        try store.exercises.save(Exercise(name: "Unrelated", type: .bodyweight))
        #expect(try allSessions.map(\.externalRef) == [ref("day1")], "only the valid session")
        #expect(try store.exercises.exercises().map(\.name).sorted() == ["Bike", "Row", "Unrelated"])

        var fixed = invalid
        fixed.sessions[1].entries[0].sets[0].values = SetValues(durationSeconds: 300)
        try store.importer.importBundle(fixed)
        let sessions = try allSessions
        #expect(sessions.count == 2)
        #expect(sessions.allSatisfy { $0.entries.count == 1 && $0.entries[0].sets.count == 1 })
    }

    @Test("B4: joining a session the user logged never changes its user fields, and a re-import does not duplicate")
    func joinKeepsUserFields() throws {
        let mine = Exercise(name: "Squat", type: .strength)
        try store.exercises.save(mine)
        let utc = try #require(TimeZone(identifier: "UTC"))
        let started = try store.sessions.startSession(routineId: nil, name: "Leg day", at: t0, timeZone: utc)
        try store.sessions.logManualSet(
            SetValues(reps: 5),
            exerciseId: mine.id,
            sessionId: started.id,
            at: t0.addingTimeInterval(60)
        )
        try store.sessions.finishSession(id: started.id, at: t0.addingTimeInterval(1800), durationSeconds: 1800)

        func providerBundle() -> TrainingBundle {
            let bundleId = UUID()
            return TrainingBundle(
                exercises: [Exercise(id: bundleId, externalRef: ref("rw"), name: "Row", type: .strength)],
                sessions: [BundleSession(
                    id: UUID(), externalRef: ref("prov-s"), name: "Provider workout", notes: "from provider",
                    completedAt: t0.addingTimeInterval(7200), timeZone: "UTC", durationSeconds: 600,
                    entries: [ImportedEntry(exerciseId: bundleId, externalRef: ref("pe"), sets: [
                        ImportedSet(externalRef: ref("pe#1"), order: 1, values: SetValues(reps: 8))
                    ])]
                )]
            )
        }
        let result = try store.importer.importBundle(providerBundle())
        try store.importer.importBundle(providerBundle())

        #expect(Set(result.sessionIds.values) == [started.id])
        let joined = try #require(try store.sessions.session(id: started.id))
        #expect(joined.name == "Leg day")
        #expect(joined.notes == nil)
        #expect(joined.durationSeconds == 1800)
        #expect(joined.externalRef == nil)
        #expect(joined.completedAt == t0.addingTimeInterval(1800))
        #expect(joined.entries.count == 2)
        #expect(joined.entries.flatMap(\.sets).count == 2)
        #expect(try allSessions.count == 1)
    }
}
