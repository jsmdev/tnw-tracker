import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

// More rules of the session repository: warm-up sets, removed and swapped
// entries, undo, finishing and history.

extension SessionRepositoryTests {
    // MARK: - Warm-up sets

    @Test("a warm-up flag is stored for a manual set, and the user can change it on any set")
    func warmupRoundTrips() throws {
        let session = try start()
        let warm = try fx.sessions.logManualSet(
            SetValues(reps: 10, weight: .kg(20)), warmup: true, exerciseId: fx.squat.id, sessionId: session.id, at: t0
        )
        let work = try fx.sessions.logManualSet(
            SetValues(reps: 5, weight: .kg(60)), exerciseId: fx.squat.id, sessionId: session.id, at: t0
        )
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
        try fx.sessions.logManualSet(
            SetValues(reps: 3, weight: .kg(120)), warmup: true, exerciseId: fx.squat.id, sessionId: session.id, at: t0
        )
        try fx.sessions.logManualSet(
            SetValues(reps: 5, weight: .kg(80)), exerciseId: fx.squat.id, sessionId: session.id, at: t0
        )
        let finished = try fx.sessions.finishSession(
            id: session.id, at: t0.addingTimeInterval(600), durationSeconds: nil
        )

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
        try fx.sessions.logManualSet(
            SetValues(reps: 10, weight: .kg(20)), warmup: true, exerciseId: fx.press.id, sessionId: session.id, at: t0
        )
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
        try fx.sessions.logManualSet(
            SetValues(reps: 10, weight: .kg(20)), exerciseId: fx.squat.id, sessionId: session.id, at: t0
        )
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
        let set = try fx.sessions.logManualSet(
            SetValues(reps: 10), exerciseId: fx.squat.id, sessionId: session.id, at: t0
        )
        try fx.sessions.deleteManualSet(id: set.id)
        let squat = try entry(reload(session.id), fx.squat)
        #expect(squat.status == .skipped)
        #expect(squat.sets.isEmpty)
    }

    @Test("undoing the only set of an unplanned exercise drops its entry")
    func undoUnplannedSet() throws {
        let session = try start()
        let set = try fx.sessions.logManualSet(
            SetValues(reps: 10), exerciseId: fx.squat.id, sessionId: session.id, at: t0
        )
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
            let session = try fx.sessions.startSession(
                routineId: nil, name: nil, at: t0.addingTimeInterval(offset), timeZone: TrainingFixtures.zone
            )
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
        try fx.sessions.logManualSet(
            SetValues(reps: 5, weight: .kg(100)), exerciseId: fx.press.id, sessionId: session.id, at: t0
        )
        try fx.sessions.importEntry(fx.importedSets("e-6", reps: [5], weight: 50), into: session.id)
        try fx.sessions.logManualSet(
            SetValues(reps: 5, weight: Weight(value: 100, unit: .lb)),
            exerciseId: fx.squat.id,
            sessionId: session.id,
            at: t0
        )
        try fx.sessions.finishSession(id: session.id, at: t0.addingTimeInterval(600), durationSeconds: nil)

        let bests = try fx.sessions.bestWeights(completedBefore: t0.addingTimeInterval(601))
        #expect(bests[fx.press.id] == 50, "the superseded 100 kg manual set does not count")
        let best: Double = bests[fx.squat.id] ?? 0
        #expect(abs(best - 45.359_237) < 0.000_1)
        #expect(try fx.sessions.bestWeights(completedBefore: t0).isEmpty)
    }

    @Test("an externalRef set is never stored twice, even across sessions: it moves (D8)")
    func importedSetUniqueAcrossSessions() throws {
        let first = try start()
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: first.id)
        try fx.sessions.finishSession(id: first.id, at: t0.addingTimeInterval(600), durationSeconds: nil)
        let second = try fx.sessions.startSession(
            routineId: nil, name: nil, at: t0.addingTimeInterval(700), timeZone: TrainingFixtures.zone
        )
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: second.id)
        let sets = try reload(second.id).entries.flatMap(\.sets)
        #expect(sets.map(\.externalRef) == [fx.ref("e-7#1")])
        #expect(
            try fx.sessions.session(id: first.id) != nil,
            "D-T7f: a session the user logged is never removed by an import"
        )
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
