import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

/// One test per rule of docs/training-data-format.md that the session repository keeps.
@Suite("SessionRepository")
@MainActor
struct SessionRepositoryTests {
    let fx: TrainingFixtures
    let t0 = TrainingFixtures.t0

    init() throws {
        fx = try TrainingFixtures()
    }

    private func start(_ routine: Routine? = nil) throws -> TrainingSession {
        try fx.sessions.startSession(routineId: routine?.id, name: "Morning", at: t0, timeZone: TrainingFixtures.zone)
    }

    private func reload(_ id: UUID) throws -> TrainingSession {
        try #require(try fx.sessions.session(id: id))
    }

    private func entry(_ session: TrainingSession, _ exercise: Exercise) throws -> SessionEntry {
        try #require(session.entries.first { $0.exerciseId == exercise.id && $0.status != .removed })
    }

    // MARK: - Starting

    @Test("a session started from a routine lists every item as a skipped entry, in routine order")
    func startFromRoutine() throws {
        let routine = try fx.makeRoutine()
        let session = try start(routine)
        #expect(session.routineId == routine.id)
        #expect(session.startedAt == t0)
        #expect(session.completedAt == nil)
        #expect(session.timeZone == "Europe/Madrid")
        #expect(session.entries.map(\.exerciseId) == [fx.squat.id, fx.press.id])
        #expect(session.entries.map(\.order) == [1, 2])
        #expect(session.entries.allSatisfy { $0.status == .skipped && $0.sets.isEmpty })
        #expect(try fx.sessions.activeSession()?.id == session.id)
    }

    @Test("a free session starts without entries")
    func freeSession() throws {
        let session = try start()
        #expect(session.routineId == nil)
        #expect(session.entries.isEmpty)
    }

    // MARK: - One entry per exercise

    @Test("logging the planned exercise turns its entry into done, with manual sets numbered from 1")
    func logPlannedExercise() throws {
        let session = try start(fx.makeRoutine())
        try fx.sessions.logManualSet(SetValues(reps: 10, weight: .kg(16)), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        try fx.sessions.logManualSet(SetValues(reps: 8, weight: .kg(16)), exerciseId: fx.squat.id, sessionId: session.id, at: t0)

        let squat = try entry(reload(session.id), fx.squat)
        #expect(squat.status == .done)
        #expect(squat.order == 1)
        #expect(squat.sets.map(\.order) == [1, 2])
        #expect(squat.sets.allSatisfy { $0.source == .manual && !$0.superseded })
        #expect(squat.reconciliation == nil)
    }

    @Test("coming back to an exercise adds sets to the same done entry")
    func oneDoneEntryPerExercise() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 10), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        try fx.sessions.logManualSet(SetValues(reps: 30), exerciseId: fx.plank.id, sessionId: session.id, at: t0)
        try fx.sessions.logManualSet(SetValues(reps: 9), exerciseId: fx.squat.id, sessionId: session.id, at: t0)

        let loaded = try reload(session.id)
        #expect(loaded.entries.count == 2)
        #expect(loaded.entries.map(\.order) == [1, 2])
        #expect(try entry(loaded, fx.squat).sets.count == 2)
    }

    @Test("an unplanned exercise gets a new entry after the routine's ones")
    func unplannedExerciseAppends() throws {
        let session = try start(fx.makeRoutine())
        try fx.sessions.logManualSet(SetValues(durationSeconds: 45), exerciseId: fx.plank.id, sessionId: session.id, at: t0)
        let plank = try entry(reload(session.id), fx.plank)
        #expect(plank.order == 3)
        #expect(plank.status == .done)
    }

    // MARK: - Set fields by exercise type

    @Test("cardio sets need a duration and take neither reps nor weight")
    func cardioRules() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(durationSeconds: 600, distanceMeters: 2000), exerciseId: fx.rower.id, sessionId: session.id, at: t0)
        #expect(throws: TrainingDataError.self) {
            try fx.sessions.logManualSet(SetValues(reps: 10, durationSeconds: 60), exerciseId: fx.rower.id, sessionId: session.id, at: t0)
        }
        #expect(throws: TrainingDataError.self) {
            try fx.sessions.logManualSet(SetValues(weight: .kg(10), durationSeconds: 60), exerciseId: fx.rower.id, sessionId: session.id, at: t0)
        }
        #expect(throws: TrainingDataError.self) {
            try fx.sessions.logManualSet(SetValues(distanceMeters: 100), exerciseId: fx.rower.id, sessionId: session.id, at: t0)
        }
    }

    @Test("only cardio sets have a distance; every set has reps or a duration; rir is 0 to 10")
    func setFieldRules() throws {
        let session = try start()
        #expect(throws: TrainingDataError.self) {
            try fx.sessions.logManualSet(SetValues(reps: 5, durationSeconds: 30, distanceMeters: 5), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        }
        #expect(throws: TrainingDataError.self) {
            try fx.sessions.logManualSet(SetValues(weight: .kg(20)), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        }
        #expect(throws: TrainingDataError.self) {
            try fx.sessions.logManualSet(SetValues(reps: 5, rir: 11), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        }
        let timedHold = try fx.sessions.logManualSet(SetValues(durationSeconds: 40), exerciseId: fx.plank.id, sessionId: session.id, at: t0)
        #expect(timedHold.values.durationSeconds == 40)
        #expect(timedHold.values.weight == nil)
    }

    @Test("a weight of zero is stored as a real load of zero, distinct from no weight")
    func zeroWeightIsReal() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 5, weight: .kg(0)), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        let sets = try entry(reload(session.id), fx.squat).sets
        #expect(sets[0].values.weight == .kg(0))
        #expect(sets[1].values.weight == nil)
    }

    // MARK: - Reconciliation

    @Test("imported sets merge into the done entry: same id, gains externalRef, default keeps imported")
    func importMergesWithDefault() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 10, weight: .kg(40)), exerciseId: fx.press.id, sessionId: session.id, at: t0)
        try fx.sessions.logManualSet(SetValues(reps: 9, weight: .kg(40)), exerciseId: fx.press.id, sessionId: session.id, at: t0)
        let manualEntryId = try entry(reload(session.id), fx.press).id

        try fx.sessions.importEntry(fx.importedSets("e-1", reps: [10, 10, 9], weight: 42.5), into: session.id)

        let loaded = try reload(session.id)
        #expect(loaded.entries.count == 1)
        let press = try entry(loaded, fx.press)
        #expect(press.id == manualEntryId)
        #expect(press.externalRef == fx.ref("e-1"))
        #expect(press.reconciliation?.keep == .imported)
        #expect(press.reconciliation?.decidedBy == .default)
        #expect(press.reconciliation?.decidedAt != nil)
        let manual = press.sets.filter { $0.source == .manual }
        let imported = press.sets.filter { $0.source == .imported }
        #expect(manual.map(\.order) == [1, 2])
        #expect(imported.map(\.order) == [1, 2, 3])
        #expect(manual.allSatisfy { $0.superseded })
        #expect(imported.allSatisfy { !$0.superseded })
        #expect(imported.map(\.externalRef) == [fx.ref("e-1#1"), fx.ref("e-1#2"), fx.ref("e-1#3")])
        #expect(press.countedSets.count == 3)
    }

    @Test("an entry with a single source has no reconciliation")
    func singleSourceHasNoReconciliation() throws {
        let session = try start()
        try fx.sessions.importEntry(fx.importedSets("e-2", reps: [10, 8], weight: 40), into: session.id)
        let press = try entry(reload(session.id), fx.press)
        #expect(press.status == .done)
        #expect(press.reconciliation == nil)
        #expect(press.sets.allSatisfy { $0.source == .imported && !$0.superseded })
    }

    @Test("the user can keep manual sets, and go back to imported; both are user decisions")
    func userChoice() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 10, weight: .kg(40)), exerciseId: fx.press.id, sessionId: session.id, at: t0)
        try fx.sessions.importEntry(fx.importedSets("e-3", reps: [10], weight: 42.5), into: session.id)
        let entryId = try entry(reload(session.id), fx.press).id

        try fx.sessions.chooseReconciliation(entryId: entryId, keep: .manual, at: t0)
        var press = try entry(reload(session.id), fx.press)
        #expect(press.reconciliation == Reconciliation(keep: .manual, decidedBy: .user, decidedAt: t0))
        #expect(press.sets.filter { $0.source == .imported }.allSatisfy { $0.superseded })
        #expect(press.sets.filter { $0.source == .manual }.allSatisfy { !$0.superseded })

        try fx.sessions.chooseReconciliation(entryId: entryId, keep: .imported, at: t0)
        press = try entry(reload(session.id), fx.press)
        #expect(press.reconciliation?.keep == .imported)
        #expect(press.reconciliation?.decidedBy == .user)
        #expect(press.sets.filter { $0.source == .manual }.allSatisfy { $0.superseded })
    }

    @Test("reconciliation can only be chosen on an entry that mixes sources")
    func choiceNeedsMixedEntry() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 10), exerciseId: fx.press.id, sessionId: session.id, at: t0)
        let entryId = try entry(reload(session.id), fx.press).id
        #expect(throws: TrainingDataError.entryNotMixed) {
            try fx.sessions.chooseReconciliation(entryId: entryId, keep: .manual, at: t0)
        }
    }

    @Test("a re-import updates imported values without duplicates and respects the user's choice")
    func reimportRespectsChoice() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 10, weight: .kg(40)), exerciseId: fx.press.id, sessionId: session.id, at: t0)
        try fx.sessions.importEntry(fx.importedSets("e-4", reps: [10, 10], weight: 42.5), into: session.id)
        let first = try entry(reload(session.id), fx.press)
        let storedIds = first.sets.filter { $0.source == .imported }.map(\.id)
        try fx.sessions.chooseReconciliation(entryId: first.id, keep: .manual, at: t0)

        // Same two sets with corrected reps, plus a third one.
        try fx.sessions.importEntry(fx.importedSets("e-4", reps: [12, 11, 9], weight: 42.5), into: session.id)

        let press = try entry(reload(session.id), fx.press)
        let imported = press.sets.filter { $0.source == .imported }
        #expect(imported.count == 3)
        #expect(imported.map { $0.values.reps } == [12, 11, 9])
        #expect(Array(imported.prefix(2).map(\.id)) == storedIds)
        #expect(press.reconciliation?.keep == .manual)
        #expect(press.reconciliation?.decidedBy == .user)
        #expect(imported.allSatisfy { $0.superseded }, "new imported sets follow keep = manual")
        let manual = press.sets.filter { $0.source == .manual }
        #expect(manual.count == 1)
        #expect(manual.first?.values.reps == 10)
        #expect(manual.allSatisfy { !$0.superseded })
    }

    @Test("a manual set logged after the default decision is superseded too")
    func manualAfterDefaultIsSuperseded() throws {
        let session = try start()
        try fx.sessions.importEntry(fx.importedSets("e-5", reps: [10], weight: 40), into: session.id)
        let late = try fx.sessions.logManualSet(SetValues(reps: 10, weight: .kg(40)), exerciseId: fx.press.id, sessionId: session.id, at: t0)
        #expect(late.superseded)
        let press = try entry(reload(session.id), fx.press)
        #expect(press.reconciliation?.keep == .imported)
        #expect(press.reconciliation?.decidedBy == .default)
    }

    // MARK: - Warm-up sets

    @Test("a warm-up flag is stored for a manual set, and the user can change it on any set")
    func warmupRoundTrips() throws {
        let session = try start()
        let warm = try fx.sessions.logManualSet(SetValues(reps: 10, weight: .kg(20)), warmup: true, exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        let work = try fx.sessions.logManualSet(SetValues(reps: 5, weight: .kg(60)), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        #expect(warm.warmup)
        var squat = try entry(reload(session.id), fx.squat)
        #expect(squat.sets.map(\.warmup) == [true, false])

        try fx.sessions.setWarmup(false, setId: warm.id)
        try fx.sessions.setWarmup(true, setId: work.id)
        squat = try entry(reload(session.id), fx.squat)
        #expect(squat.sets.map(\.warmup) == [false, true])
        #expect(throws: TrainingDataError.notFound) { try fx.sessions.setWarmup(true, setId: UUID()) }
    }

    @Test("a new imported set takes the format's warmup; a re-import keeps the user's flag")
    func reimportKeepsWarmup() throws {
        let session = try start()
        var bundle = fx.importedSets("e-w", reps: [12, 5, 5], weight: 40)
        bundle.sets[0].warmup = true
        try fx.sessions.importEntry(bundle, into: session.id)
        var imported = try entry(reload(session.id), fx.press).sets
        #expect(imported.map(\.warmup) == [true, false, false])

        // The user marks the second set as warm-up too, then the provider sends it again unmarked.
        try fx.sessions.setWarmup(true, setId: imported[1].id)
        let again = fx.importedSets("e-w", reps: [12, 6, 5], weight: 40)
        try fx.sessions.importEntry(again, into: session.id)

        imported = try entry(reload(session.id), fx.press).sets
        #expect(imported.map { $0.values.reps } == [12, 6, 5], "values are updated")
        #expect(imported.map(\.warmup) == [true, true, false], "warmup belongs to the app")
    }

    @Test("warm-up sets count for neither volume nor best weights")
    func warmupDoesNotCount() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 3, weight: .kg(120)), warmup: true, exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        try fx.sessions.logManualSet(SetValues(reps: 5, weight: .kg(80)), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        let finished = try fx.sessions.finishSession(id: session.id, at: t0.addingTimeInterval(600), durationSeconds: nil)

        let squat = try entry(finished, fx.squat)
        #expect(squat.countedSets.count == 1)
        #expect(squat.volumeKg == 5 * 80)
        #expect(finished.volumeKg == 5 * 80)
        let bests = try fx.sessions.bestWeights(completedBefore: t0.addingTimeInterval(601))
        #expect(bests[fx.squat.id] == 80, "the 120 kg warm-up set is not a record")
    }

    @Test("a warm-up set does not change the reconciliation trigger")
    func warmupKeepsTrigger() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 10, weight: .kg(20)), warmup: true, exerciseId: fx.press.id, sessionId: session.id, at: t0)
        try fx.sessions.importEntry(fx.importedSets("e-t", reps: [10], weight: 40), into: session.id)
        let press = try entry(reload(session.id), fx.press)
        #expect(press.reconciliation?.keep == .imported)
        #expect(press.reconciliation?.decidedBy == .default)
        #expect(press.sets.filter { $0.source == .manual }.allSatisfy { $0.superseded && $0.warmup })
    }

    // MARK: - Removed, swapped, undo

    @Test("a removed entry keeps its sets stored and they stop counting")
    func removedEntryKeepsSets() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 10, weight: .kg(20)), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        let entryId = try entry(reload(session.id), fx.squat).id
        try fx.sessions.removeEntry(id: entryId)

        let loaded = try reload(session.id)
        let removed = try #require(loaded.entry(id: entryId))
        #expect(removed.status == .removed)
        #expect(removed.sets.count == 1)
        #expect(removed.countedSets.isEmpty)
        #expect(loaded.volumeKg == 0)
    }

    @Test("swapping an exercise records the planned one, and both survive a fresh context")
    func swapRecordsReplacedExercise() throws {
        let session = try start(fx.makeRoutine())
        let planned = try entry(session, fx.press)
        try fx.sessions.replaceExercise(entryId: planned.id, with: fx.plank.id)

        let fresh = SwiftDataSessionRepository(context: ModelContext(fx.store.container))
        let swapped = try #require(try fresh.session(id: session.id)?.entry(id: planned.id))
        #expect(swapped.exerciseId == fx.plank.id)
        #expect(swapped.replacedExerciseId == fx.press.id)
        #expect(swapped.order == planned.order)
    }

    @Test("an entry with sets cannot be swapped")
    func swapNeedsEmptyEntry() throws {
        let session = try start(fx.makeRoutine())
        try fx.sessions.logManualSet(SetValues(reps: 10), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        let squat = try entry(reload(session.id), fx.squat)
        #expect(throws: TrainingDataError.entryHasSets) {
            try fx.sessions.replaceExercise(entryId: squat.id, with: fx.plank.id)
        }
    }

    @Test("undoing the only set of a planned exercise sets its entry back to skipped")
    func undoPlannedSet() throws {
        let session = try start(fx.makeRoutine())
        let set = try fx.sessions.logManualSet(SetValues(reps: 10), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        try fx.sessions.deleteManualSet(id: set.id)
        let squat = try entry(reload(session.id), fx.squat)
        #expect(squat.status == .skipped)
        #expect(squat.sets.isEmpty)
    }

    @Test("undoing the only set of an unplanned exercise drops its entry")
    func undoUnplannedSet() throws {
        let session = try start()
        let set = try fx.sessions.logManualSet(SetValues(reps: 10), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        try fx.sessions.deleteManualSet(id: set.id)
        #expect(try reload(session.id).entries.isEmpty)
    }

    // MARK: - Finishing and history

    @Test("finishing completes the session and clamps the duration to the time between start and end")
    func finishClampsDuration() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 10), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        let end = t0.addingTimeInterval(1200)
        let finished = try fx.sessions.finishSession(id: session.id, at: end, durationSeconds: 5000)
        #expect(finished.completedAt == end)
        #expect(finished.durationSeconds == 1200)
        #expect(try fx.sessions.activeSession() == nil)
        #expect(throws: TrainingDataError.sessionAlreadyCompleted) {
            try fx.sessions.logManualSet(SetValues(reps: 1), exerciseId: fx.squat.id, sessionId: session.id, at: end)
        }
    }

    @Test("completed sessions are listed by interval, most recent first, without the one in progress")
    func completedSessionsInInterval() throws {
        for offset: TimeInterval in [0, 86400, 10 * 86400] {
            let session = try fx.sessions.startSession(routineId: nil, name: nil, at: t0.addingTimeInterval(offset), timeZone: TrainingFixtures.zone)
            try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
            try fx.sessions.finishSession(id: session.id, at: t0.addingTimeInterval(offset + 600), durationSeconds: nil)
        }
        _ = try start()
        let week = DateInterval(start: t0, duration: 7 * 86400)
        let listed = try fx.sessions.completedSessions(in: week)
        #expect(listed.count == 2)
        #expect(listed.map(\.completedAt) == [t0.addingTimeInterval(86400 + 600), t0.addingTimeInterval(600)])
    }

    @Test("best weights read only counted sets of sessions completed before the date, in kg")
    func bestWeightsUseCountedSets() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 5, weight: .kg(100)), exerciseId: fx.press.id, sessionId: session.id, at: t0)
        try fx.sessions.importEntry(fx.importedSets("e-6", reps: [5], weight: 50), into: session.id)
        try fx.sessions.logManualSet(SetValues(reps: 5, weight: Weight(value: 100, unit: .lb)), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        try fx.sessions.finishSession(id: session.id, at: t0.addingTimeInterval(600), durationSeconds: nil)

        let bests = try fx.sessions.bestWeights(completedBefore: t0.addingTimeInterval(601))
        #expect(bests[fx.press.id] == 50, "the superseded 100 kg manual set does not count")
        #expect(abs((bests[fx.squat.id] ?? 0) - 45.359_237) < 0.000_1)
        #expect(try fx.sessions.bestWeights(completedBefore: t0).isEmpty)
    }

    @Test("an externalRef set is never stored twice, even across sessions: it moves (D8)")
    func importedSetUniqueAcrossSessions() throws {
        let first = try start()
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: first.id)
        try fx.sessions.finishSession(id: first.id, at: t0.addingTimeInterval(600), durationSeconds: nil)
        let second = try fx.sessions.startSession(routineId: nil, name: nil, at: t0.addingTimeInterval(700), timeZone: TrainingFixtures.zone)
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: second.id)
        let sets = try reload(second.id).entries.flatMap(\.sets)
        #expect(sets.map(\.externalRef) == [fx.ref("e-7#1")])
        #expect(try fx.sessions.session(id: first.id) != nil, "D-T7f: a session the user logged is never removed by an import")
    }

    @Test("an imported entry never ends after its completed session (rule range)")
    func importedEntryEndsWithinSession() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        let end = t0.addingTimeInterval(1800)
        try fx.sessions.finishSession(id: session.id, at: end, durationSeconds: nil)

        var late = fx.importedSets("e-8", reps: [10], weight: 40)
        late.completedAt = end.addingTimeInterval(3600)
        try fx.sessions.importEntry(late, into: session.id)

        let press = try entry(reload(session.id), fx.press)
        #expect(press.completedAt == nil)
    }
}
