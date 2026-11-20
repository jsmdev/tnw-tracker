import Foundation
import Testing
@testable import TNWTrackerKit

/// T9 (D13): an import is atomic per session, not per bundle. An invalid session
/// is skipped and reported in `ImportResult` with its reason; every valid session
/// of the bundle is saved; nothing of the invalid session is written.
@Suite("Per-session import (D13)")
@MainActor
struct PerSessionImportTests {
    let store: TrainingStore
    let provider = "machines-atlas"
    /// 2030-03-04T09:00:00Z
    let t0 = Date(timeIntervalSince1970: 1_898_845_200)
    let strengthId = UUID()
    let cardioId = UUID()

    init() throws {
        store = try TrainingStore.inMemory()
    }

    private func ref(_ id: String) -> ExternalRef {
        ExternalRef(provider: provider, id: id)
    }

    private var allSessions: [TrainingSession] {
        get throws { try store.sessions.completedSessions(in: DateInterval(start: .distantPast, end: .distantFuture)) }
    }

    private func session(_ name: String, day: Int, exerciseId: UUID, values: [SetValues]) -> BundleSession {
        BundleSession(
            id: UUID(),
            externalRef: ref(name),
            completedAt: t0.addingTimeInterval(Double(day) * 86400),
            timeZone: "UTC",
            entries: [
                ImportedEntry(
                    exerciseId: exerciseId,
                    externalRef: ref("\(name)-e"),
                    sets: values.enumerated().map { index, value in
                        ImportedSet(externalRef: ref("\(name)-e#\(index + 1)"), order: index + 1, values: value)
                    }
                )
            ]
        )
    }

    /// Day 1 and day 3 are valid. Day 2 is invalid only at its second set (a cardio
    /// set with reps), so a per-bundle check would have written its first set.
    private func bundle() -> TrainingBundle {
        let strength = Exercise(id: strengthId, externalRef: ref("st"), name: "Row", type: .strength)
        let cardio = Exercise(id: cardioId, externalRef: ref("ca"), name: "Bike", type: .cardio)
        return TrainingBundle(exercises: [strength, cardio], sessions: [
            session("day1", day: 0, exerciseId: strengthId, values: [SetValues(reps: 5)]),
            session(
                "day2",
                day: 1,
                exerciseId: cardioId,
                values: [SetValues(durationSeconds: 300), SetValues(reps: 5)]
            ),
            session("day3", day: 2, exerciseId: strengthId, values: [SetValues(reps: 6), SetValues(reps: 7)])
        ])
    }

    @Test("AC9.1 every valid session is saved and the result lists the skipped session with its reason")
    func validSessionsSavedInvalidReported() throws {
        let source = bundle()
        let result = try store.importer.importBundle(source)

        #expect(try allSessions.count == 2)
        #expect(Set(result.sessionIds.keys) == [source.sessions[0].id, source.sessions[2].id])
        #expect(result.skippedSessions == [SkippedSession(
            bundleId: source.sessions[1].id,
            externalRef: ref("day2"),
            reason: .invalidSet("cardio sets need a duration")
        )])
        #expect(try store.exercises.exercises().count == 2)
    }

    @Test("AC9.2 nothing of the invalid session is written: no session, entry or set")
    func invalidSessionWritesNothing() throws {
        try store.importer.importBundle(bundle())

        let sessions = try allSessions
        #expect(sessions.map(\.externalRef).contains(ref("day2")) == false)
        let refs = sessions.flatMap(\.entries).compactMap(\.externalRef)
        #expect(refs.contains(ref("day2-e")) == false)
        let setRefs = sessions.flatMap(\.entries).flatMap(\.sets).compactMap(\.externalRef)
        #expect(setRefs.contains(ref("day2-e#1")) == false)
        #expect(sessions.allSatisfy { $0.entries.allSatisfy { $0.exerciseId != cardioId } })
    }

    @Test("AC9.2 a session that fails while it is written (a time zone with no IANA name) is skipped the same way")
    func failureWhileWritingSkipsOnlyThatSession() throws {
        var source = bundle()
        // Passes validation (a known zone), fails when the new session is created.
        source.sessions[2].timeZone = "GMT+0530"
        let result = try store.importer.importBundle(source)

        #expect(try allSessions.map(\.externalRef) == [ref("day1")])
        #expect(result.skippedSessions.map(\.bundleId) == [source.sessions[1].id, source.sessions[2].id])
        #expect(result.skippedSessions.last?.reason == .invalidSession("time zone GMT+0530 has no IANA name"))
    }

    @Test("AC9.1 a session naming a routine outside the bundle is skipped; the others are saved")
    func unresolvedRoutineSkipsSession() throws {
        var source = bundle()
        source.sessions[2].routineId = UUID()
        let result = try store.importer.importBundle(source)

        #expect(try allSessions.map(\.externalRef) == [ref("day1")])
        #expect(result.skippedSessions.last?.reason == .invalidSession("session names a routine outside the bundle"))
    }

    @Test("AC9.3 importing the same bundle again duplicates no valid session and reports the invalid one again")
    func reimportSameBundle() throws {
        let source = bundle()
        let first = try store.importer.importBundle(source)
        let second = try store.importer.importBundle(source)

        let sessions = try allSessions
        #expect(sessions.count == 2)
        #expect(sessions.allSatisfy { session in session.entries.count == 1 })
        #expect(sessions.flatMap(\.entries).flatMap(\.sets).count == 3)
        #expect(second.sessionIds == first.sessionIds)
        #expect(second.skippedSessions == first.skippedSessions)
        #expect(second.skippedSessions.map(\.bundleId) == [source.sessions[1].id])
    }

    @Test("D13 a bundle-level error (an invalid exercise) still rejects the whole bundle and writes nothing")
    func bundleLevelErrorRejectsAll() throws {
        var source = bundle()
        source.exercises[0].isCatalogue = true
        #expect(throws: TrainingDataError.invalidExercise("a catalogue exercise has no externalRef")) {
            try store.importer.importBundle(source)
        }
        #expect(try allSessions.isEmpty)
        #expect(try store.exercises.exercises().isEmpty)
    }
}
