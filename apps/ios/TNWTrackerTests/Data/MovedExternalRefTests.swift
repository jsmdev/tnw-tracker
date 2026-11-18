import Foundation
import Testing
@testable import TNWTrackerKit

/// T7 (D8): a provider ref (entry or set) that already belongs to another session
/// moves to the session being imported, keeping the user's annotations. An
/// imported-only session left with no counted sets is removed. The import never
/// throws `duplicateExternalRef` for this case.
@Suite("Moved external refs (D8)")
@MainActor
struct MovedExternalRefTests {
    let fx: TrainingFixtures
    let t0 = TrainingFixtures.t0

    init() throws {
        fx = try TrainingFixtures()
    }

    private func reload(_ id: UUID) throws -> TrainingSession {
        try #require(try fx.sessions.session(id: id))
    }

    private var allSessions: [TrainingSession] {
        get throws { try fx.sessions.completedSessions(in: DateInterval(start: .distantPast, end: .distantFuture)) }
    }

    /// A completed session the user logged: one manual squat set and the
    /// imported press entry `entryRef`.
    private func userSession(importing entryRef: String, reps: [Int] = [10, 9]) throws -> TrainingSession {
        let session = try fx.sessions.startSession(routineId: nil, name: "Morning", at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        try fx.sessions.importEntry(fx.importedSets(entryRef, reps: reps, weight: 40), into: session.id)
        return try fx.sessions.finishSession(id: session.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
    }

    private func laterSession() throws -> TrainingSession {
        try fx.sessions.startSession(routineId: nil, name: "Evening", at: t0.addingTimeInterval(7200), timeZone: TrainingFixtures.zone)
    }

    // MARK: - Move

    @Test("AC7.1 an entry ref of another session moves, with its sets, to the session being imported")
    func entryRefMoves() throws {
        let first = try userSession(importing: "e-7")
        let movedIds = try #require(first.entries.first { $0.exerciseId == fx.press.id }).sets.map(\.id)
        let second = try laterSession()

        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [12, 11], weight: 45), into: second.id)

        let target = try #require(try reload(second.id).entries.first { $0.exerciseId == fx.press.id })
        #expect(target.externalRef == fx.ref("e-7"))
        #expect(target.sets.map(\.id) == movedIds, "the same sets move; nothing is duplicated")
        #expect(target.sets.map { $0.values.reps } == [12, 11])
        #expect(target.sets.map(\.order) == [1, 2])
        let source = try reload(first.id)
        #expect(source.entries.contains { $0.exerciseId == fx.press.id } == false, "the emptied imported entry is gone")
        #expect(source.entries.flatMap(\.sets).allSatisfy { $0.source == .manual })
    }

    @Test("AC7.1 a set ref of another session moves into the new entry and keeps its warm-up flag")
    func setRefMovesKeepingWarmup() throws {
        let first = try userSession(importing: "e-7")
        let warm = try #require(first.entries.first { $0.exerciseId == fx.press.id }?.sets.first)
        try fx.sessions.setWarmup(true, setId: warm.id)
        let second = try laterSession()
        // The provider regrouped the set under a new entry ref.
        let regrouped = ImportedEntry(
            exerciseId: fx.press.id, externalRef: fx.ref("e-8"),
            sets: [ImportedSet(externalRef: fx.ref("e-7#1"), order: 1, values: SetValues(reps: 10, weight: .kg(40)))]
        )

        try fx.sessions.importEntry(regrouped, into: second.id)

        let target = try #require(try reload(second.id).entries.first { $0.exerciseId == fx.press.id })
        let moved = try #require(target.sets.first)
        #expect(target.sets.count == 1)
        #expect(moved.id == warm.id)
        #expect(moved.warmup, "the user's warm-up flag survives the move")
        let source = try #require(try reload(first.id).entries.first { $0.exerciseId == fx.press.id })
        #expect(source.sets.map(\.externalRef) == [fx.ref("e-7#2")], "the other set stays where it was")
    }

    @Test("AC7.1 the user's reconciliation choice moves with the entry")
    func reconciliationChoiceMoves() throws {
        let session = try fx.sessions.startSession(routineId: nil, name: "Morning", at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        try fx.sessions.logManualSet(SetValues(reps: 6, weight: .kg(40)), exerciseId: fx.press.id, sessionId: session.id, at: t0)
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: session.id)
        let mixed = try #require(try reload(session.id).entries.first { $0.exerciseId == fx.press.id })
        try fx.sessions.chooseReconciliation(entryId: mixed.id, keep: .manual, at: t0)
        try fx.sessions.finishSession(id: session.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
        let second = try laterSession()
        try fx.sessions.logManualSet(SetValues(reps: 7, weight: .kg(40)), exerciseId: fx.press.id, sessionId: second.id, at: t0.addingTimeInterval(7300))

        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: second.id)

        let target = try #require(try reload(second.id).entries.first { $0.exerciseId == fx.press.id })
        #expect(target.reconciliation?.keep == .manual)
        #expect(target.reconciliation?.decidedBy == .user)
        #expect(target.sets.filter { $0.source == .imported }.allSatisfy { $0.superseded })
        #expect(target.sets.filter { $0.source == .manual }.allSatisfy { !$0.superseded })
        let source = try #require(try reload(session.id).entries.first { $0.exerciseId == fx.press.id })
        #expect(source.reconciliation == nil, "back to manual sets only, nothing to reconcile")
        #expect(source.sets.allSatisfy { $0.source == .manual && !$0.superseded })
    }

    // MARK: - Removal

    @Test("AC7.2 an imported-only session left with no counted sets is removed")
    func emptiedImportedSessionRemoved() throws {
        let exerciseId = UUID()
        let press = Exercise(id: exerciseId, externalRef: fx.ref("ex-1"), name: "Chest Press Machine", type: .strength, equipment: .connectedMachine)
        func entry(_ ref: String) -> ImportedEntry {
            ImportedEntry(exerciseId: exerciseId, externalRef: fx.ref(ref), sets: [
                ImportedSet(externalRef: fx.ref("\(ref)#1"), order: 1, values: SetValues(reps: 10, weight: .kg(40)))
            ])
        }
        // First grouping: two provider workouts on different days.
        let monday = BundleSession(id: UUID(), externalRef: fx.ref("w-1"), completedAt: t0, timeZone: "UTC", entries: [entry("e-1")])
        let wednesday = BundleSession(
            id: UUID(), externalRef: fx.ref("w-2"), completedAt: t0.addingTimeInterval(2 * 86400), timeZone: "UTC", entries: [entry("e-2")]
        )
        let first = try fx.store.importer.importBundle(TrainingBundle(exercises: [press], sessions: [monday, wednesday]))
        let mondayId = try #require(first.sessionIds[monday.id])
        let wednesdayId = try #require(first.sessionIds[wednesday.id])

        // Regrouped: both entries belong to Monday's workout.
        let regrouped = BundleSession(id: UUID(), externalRef: fx.ref("w-1"), completedAt: t0, timeZone: "UTC", entries: [entry("e-1"), entry("e-2")])
        let second = try fx.store.importer.importBundle(TrainingBundle(exercises: [press], sessions: [regrouped]))

        #expect(second.sessionIds[regrouped.id] == mondayId)
        #expect(try fx.sessions.session(id: wednesdayId) == nil, "Wednesday lost its only sets and was imported-only")
        let joined = try reload(mondayId)
        #expect(joined.entries.count == 1)
        #expect(joined.entries.flatMap(\.sets).map(\.externalRef) == [fx.ref("e-1#1"), fx.ref("e-2#1")])
        #expect(try allSessions.map(\.id) == [mondayId])
    }

    @Test("AC7.3 a session with manual sets is kept after its imported data moves")
    func sessionWithManualSetsKept() throws {
        let first = try fx.sessions.startSession(routineId: nil, name: "Morning", at: t0, timeZone: TrainingFixtures.zone)
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: first.id, at: t0)
        try fx.sessions.setWarmup(true, setId: try #require(try reload(first.id).entries.first?.sets.first).id)
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: first.id)
        try fx.sessions.finishSession(id: first.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
        let second = try laterSession()

        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [10], weight: 40), into: second.id)

        let kept = try reload(first.id)
        #expect(kept.name == "Morning", "a manual (warm-up) set keeps the session, even with no counted sets")
        #expect(kept.entries.flatMap(\.sets).map(\.source) == [.manual])
    }

    @Test("AC7.1 a re-import into the session that already holds the ref is unchanged (no move)")
    func sameSessionReimportUnchanged() throws {
        let first = try userSession(importing: "e-7")
        try fx.sessions.importEntry(fx.importedSets("e-7", reps: [8, 7], weight: 40), into: first.id)
        let entry = try #require(try reload(first.id).entries.first { $0.exerciseId == fx.press.id })
        #expect(entry.sets.map { $0.values.reps } == [8, 7])
        #expect(try allSessions.count == 1)
    }
}
