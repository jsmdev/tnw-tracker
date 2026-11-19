import Foundation
import Testing
@testable import TNWTrackerKit

/// Probes from the independent verifier of T7 (B1, B2, P3), kept as regression tests.
@Suite("Verifier probes")
@MainActor
struct VerifierProbeTests {
    let fx: TrainingFixtures
    let t0 = TrainingFixtures.t0

    init() throws { fx = try TrainingFixtures() }

    private func reload(_ id: UUID) throws -> TrainingSession { try #require(try fx.sessions.session(id: id)) }

    @Test("P1 a copied keep-imported choice supersedes the target's manual sets")
    func copiedKeepImportedRecomputes() throws {
        let s1 = try fx.sessions.startSession(routineId: nil, name: "A", at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(
            SetValues(reps: 6, weight: .kg(40)),
            exerciseId: fx.press.id,
            sessionId: s1.id,
            at: t0
        )
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: s1.id)
        let mixed = try #require(try reload(s1.id).entries.first { $0.exerciseId == fx.press.id })
        try fx.sessions.chooseReconciliation(entryId: mixed.id, keep: .imported, at: t0)
        try fx.sessions.finishSession(id: s1.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
        let s2 = try fx.sessions.startSession(
            routineId: nil,
            name: "B",
            at: t0.addingTimeInterval(7200),
            timeZone: TrainingFixtures.zone
        )
        try fx.sessions.logManualSet(
            SetValues(reps: 7, weight: .kg(40)),
            exerciseId: fx.press.id,
            sessionId: s2.id,
            at: t0.addingTimeInterval(7300)
        )

        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: s2.id)

        let target = try #require(try reload(s2.id).entries.first { $0.exerciseId == fx.press.id })
        #expect(target.reconciliation?.keep == .imported)
        #expect(
            target.sets.filter { $0.source == .manual }.allSatisfy { $0.superseded },
            "keep imported: manual superseded"
        )
        #expect(target.sets.filter { $0.source == .imported }.allSatisfy { !$0.superseded })
    }

    @Test("P2 a set moved into an entry that keeps manual sets is superseded")
    func movedSetFollowsTargetChoice() throws {
        let s1 = try fx.sessions.startSession(routineId: nil, name: "A", at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: s1.id, at: t0)
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10, 9], weight: 40), into: s1.id)
        try fx.sessions.finishSession(id: s1.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
        let s2 = try fx.sessions.startSession(
            routineId: nil,
            name: "B",
            at: t0.addingTimeInterval(7200),
            timeZone: TrainingFixtures.zone
        )
        try fx.sessions.logManualSet(
            SetValues(reps: 7, weight: .kg(40)),
            exerciseId: fx.press.id,
            sessionId: s2.id,
            at: t0.addingTimeInterval(7300)
        )
        try fx.sessions.importEntry(fx.importedSets("e-9", reps: [8], weight: 40), into: s2.id)
        let mixed = try #require(try reload(s2.id).entries.first { $0.exerciseId == fx.press.id })
        try fx.sessions.chooseReconciliation(entryId: mixed.id, keep: .manual, at: t0)

        let regrouped = ImportedEntry(exerciseId: fx.press.id, externalRef: fx.ref("e-9"), sets: [
            ImportedSet(externalRef: fx.ref("e-9#1"), order: 1, values: SetValues(reps: 8, weight: .kg(40))),
            ImportedSet(externalRef: fx.ref("e-7#1"), order: 2, values: SetValues(reps: 10, weight: .kg(40)))
        ])
        try fx.sessions.importEntry(regrouped, into: s2.id)

        let target = try #require(try reload(s2.id).entries.first { $0.exerciseId == fx.press.id })
        #expect(target.reconciliation?.keep == .manual)
        #expect(target.sets.filter { $0.source == .imported }.count == 2)
        #expect(
            target.sets.filter { $0.source == .imported }.allSatisfy { $0.superseded },
            "keep manual: every imported set superseded"
        )
    }

    @Test("P3 a session the user logged with only imported sets is kept when they move")
    func userSessionWithoutManualSetsKept() throws {
        let routine = try fx.makeRoutine()
        let s1 = try fx.sessions.startSession(
            routineId: routine.id,
            name: "Mine",
            at: t0,
            timeZone: TrainingFixtures.zone
        )
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: s1.id)
        try fx.sessions.finishSession(id: s1.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
        let s2 = try fx.sessions.startSession(
            routineId: nil,
            name: "B",
            at: t0.addingTimeInterval(7200),
            timeZone: TrainingFixtures.zone
        )

        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: s2.id)

        #expect(try fx.sessions.session(id: s1.id) != nil, "D-T7f: an import never removes a session the user logged")
    }

    @Test("P4 an in-progress session that loses its imported data is kept")
    func inProgressKept() throws {
        let s1 = try fx.sessions.startSession(routineId: nil, name: "A", at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: s1.id)
        let s2Id = try fx.sessions.startSession(
            routineId: nil,
            name: "B",
            at: t0.addingTimeInterval(60),
            timeZone: TrainingFixtures.zone
        ).id
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: s2Id)
        #expect(try fx.sessions.session(id: s1.id) != nil)
    }

    @Test("P5 ties on the last date go by name; a never-done favourite wins")
    func ruleTies() {
        let date = Date(timeIntervalSince1970: 1000)
        let a = NextRoutineRule.Candidate(id: UUID(), name: "B", isFavorite: false, lastCompletedAt: date)
        let b = NextRoutineRule.Candidate(id: UUID(), name: "A", isFavorite: false, lastCompletedAt: date)
        #expect(NextRoutineRule.next(among: [a, b]) == b.id)
        let never1 = NextRoutineRule.Candidate(id: UUID(), name: "Z", isFavorite: false, lastCompletedAt: nil)
        let never2 = NextRoutineRule.Candidate(id: UUID(), name: "Y", isFavorite: false, lastCompletedAt: nil)
        #expect(NextRoutineRule.next(among: [a, never1, b, never2]) == never2.id)
        let fav = NextRoutineRule.Candidate(
            id: UUID(),
            name: "M",
            isFavorite: true,
            lastCompletedAt: Date(timeIntervalSince1970: 5000)
        )
        #expect(NextRoutineRule.next(among: [never1, fav, a]) == fav.id)
        #expect(NextRoutineRule.next(among: []) == nil)
    }

    @Test("P6 paging across the favourites boundary keeps one order with no repeats")
    func pagingAcrossBoundary() throws {
        var ids: [String: UUID] = [:]
        for name in ["E", "D", "C", "B", "A"] {
            let routine = try fx.makeRoutine(name: name)
            ids[name] = routine.id
        }
        try fx.routines.setFavorite(true, routineId: try #require(ids["D"]))
        try fx.routines.setFavorite(true, routineId: try #require(ids["B"]))
        let p1 = try fx.routines.routines(RoutineQuery(limit: 3)).map(\.name)
        let p2 = try fx.routines.routines(RoutineQuery(offset: 3, limit: 3)).map(\.name)
        #expect(p1 + p2 == ["B", "D", "A", "C", "E"])
    }

    @Test("P1b with the default choice, the target's manual sets are superseded after the move")
    func copiedDefaultRecomputes() throws {
        let s1 = try fx.sessions.startSession(routineId: nil, name: "A", at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(
            SetValues(reps: 6, weight: .kg(40)),
            exerciseId: fx.press.id,
            sessionId: s1.id,
            at: t0
        )
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: s1.id)
        try fx.sessions.finishSession(id: s1.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
        let s2 = try fx.sessions.startSession(
            routineId: nil,
            name: "B",
            at: t0.addingTimeInterval(7200),
            timeZone: TrainingFixtures.zone
        )
        try fx.sessions.logManualSet(
            SetValues(reps: 7, weight: .kg(40)),
            exerciseId: fx.press.id,
            sessionId: s2.id,
            at: t0.addingTimeInterval(7300)
        )

        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: s2.id)

        let target = try #require(try reload(s2.id).entries.first { $0.exerciseId == fx.press.id })
        #expect(target.reconciliation?.keep == .imported)
        #expect(target.sets.filter { $0.source == .manual }.allSatisfy { $0.superseded })
        #expect(target.sets.filter { !$0.superseded }.allSatisfy { $0.source == .imported }, "one source counts")
    }

    @Test("P7 an import-created session left with only an imported warm-up set is removed")
    func warmupOnlyLeftRemoved() throws {
        // D-T7f: only a session an import created can be removed, so it comes from a bundle.
        let exerciseId = UUID()
        let press = Exercise(
            id: exerciseId,
            externalRef: fx.ref("ex-1"),
            name: "Chest Press Machine",
            type: .strength,
            equipment: .connectedMachine
        )
        let day = BundleSession(id: UUID(), externalRef: fx.ref("w-1"), completedAt: t0, timeZone: "UTC", entries: [
            ImportedEntry(exerciseId: exerciseId, externalRef: fx.ref("e-7"), sets: [
                ImportedSet(externalRef: fx.ref("e-7#1"), order: 1, values: SetValues(reps: 10, weight: .kg(40))),
                ImportedSet(externalRef: fx.ref("e-7#2"), order: 2, values: SetValues(reps: 9, weight: .kg(40)))
            ])
        ])
        let s1Id = try #require(
            try fx.store.importer.importBundle(TrainingBundle(exercises: [press], sessions: [day])).sessionIds[day.id]
        )
        let second = try #require(try reload(s1Id).entries.first?.sets.first { $0.externalRef == fx.ref("e-7#2") })
        try fx.sessions.setWarmup(true, setId: second.id)
        let s2 = try fx.sessions.startSession(
            routineId: nil,
            name: "B",
            at: t0.addingTimeInterval(7200),
            timeZone: TrainingFixtures.zone
        )
        let regrouped = ImportedEntry(exerciseId: fx.press.id, externalRef: fx.ref("e-8"), sets: [
            ImportedSet(externalRef: fx.ref("e-7#1"), order: 1, values: SetValues(reps: 10, weight: .kg(40)))
        ])
        try fx.sessions.importEntry(regrouped, into: s2.id)
        #expect(try fx.sessions.session(id: s1Id) == nil, "no counted set left: warm-ups do not count")
    }

    @Test("P8 a planned entry emptied by a move goes back to skipped")
    func plannedEntryBackToSkipped() throws {
        let routine = try fx.makeRoutine()
        let s1 = try fx.sessions.startSession(
            routineId: routine.id,
            name: "Full Body A",
            at: t0,
            timeZone: TrainingFixtures.zone
        )
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: s1.id, at: t0)
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: s1.id)
        try fx.sessions.finishSession(id: s1.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
        let s2 = try fx.sessions.startSession(
            routineId: nil,
            name: "B",
            at: t0.addingTimeInterval(7200),
            timeZone: TrainingFixtures.zone
        )
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: s2.id)
        let press = try #require(try reload(s1.id).entries.first { $0.exerciseId == fx.press.id })
        #expect(press.status == .skipped)
        #expect(press.sets.isEmpty)
        #expect(press.externalRef == nil)
    }
}
