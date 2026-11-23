import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

/// Regression tests for format rules found by the independent verifier of #134.
@Suite("Format rules")
@MainActor
struct FormatRuleTests {
    let fx: TrainingFixtures
    let t0 = TrainingFixtures.t0

    init() throws {
        fx = try TrainingFixtures()
    }

    private func start(zone: TimeZone = TrainingFixtures.zone) throws -> TrainingSession {
        try fx.sessions.startSession(routineId: nil, name: nil, at: t0, timeZone: zone)
    }

    private func reload(_ id: UUID) throws -> TrainingSession {
        try #require(try fx.sessions.session(id: id))
    }

    // MARK: - B1, B2: imports

    @Test("B1: an imported entry without sets is rejected and creates no entry")
    func importWithoutSetsRejected() throws {
        let session = try start()
        let empty = ImportedEntry(exerciseId: fx.press.id, externalRef: fx.ref("e0"), sets: [])
        #expect(throws: TrainingDataError.self) { try fx.sessions.importEntry(empty, into: session.id) }
        #expect(try reload(session.id).entries.isEmpty)
    }

    @Test("B2: two imported entries of one exercise merge with unique imported orders and both refs kept")
    func twoImportsMergeUniquely() throws {
        let session = try start()
        try fx.sessions.importEntry(fx.importedSets("a", reps: [10, 9], weight: 40), into: session.id)
        try fx.sessions.importEntry(fx.importedSets("b", reps: [8, 7], weight: 40), into: session.id)

        let loaded = try reload(session.id)
        #expect(loaded.entries.count == 1)
        let entry = try #require(loaded.entries.first)
        #expect(entry.externalRef == fx.ref("a"), "the first ref stays the entry's format externalRef")
        let imported = entry.sets.filter { $0.source == .imported }
        #expect(imported.map(\.order) == [1, 2, 3, 4])
        #expect(imported.map(\.values.reps) == [10, 9, 8, 7])

        // A re-import of "b" updates in place: no duplicates, orders unchanged.
        try fx.sessions.importEntry(fx.importedSets("b", reps: [6, 5], weight: 40), into: session.id)
        let again = try #require(try reload(session.id).entries.first).sets.filter { $0.source == .imported }
        #expect(again.map(\.order) == [1, 2, 3, 4])
        #expect(again.map(\.values.reps) == [10, 9, 6, 5])
    }

    @Test("B2: the merged second ref is still found in another session, and moves from it (D8)")
    func mergedRefDetectedAcrossSessions() throws {
        let first = try start()
        try fx.sessions.importEntry(fx.importedSets("a", reps: [10], weight: 40), into: first.id)
        try fx.sessions.importEntry(fx.importedSets("b", reps: [8], weight: 40), into: first.id)
        try fx.sessions.finishSession(id: first.id, at: t0.addingTimeInterval(600), durationSeconds: nil)
        let second = try fx.sessions.startSession(
            routineId: nil,
            name: nil,
            at: t0.addingTimeInterval(700),
            timeZone: TrainingFixtures.zone
        )
        let reshaped = ImportedEntry(
            exerciseId: fx.press.id, externalRef: fx.ref("b"),
            sets: [ImportedSet(externalRef: fx.ref("b#9"), order: 1, values: SetValues(reps: 1, weight: .kg(40)))]
        )
        try fx.sessions.importEntry(reshaped, into: second.id)

        let moved = try #require(try reload(second.id).entries.first)
        #expect(moved.externalRef == fx.ref("b"))
        #expect(moved.sets.map(\.externalRef) == [fx.ref("b#9")], "only the incoming set; b#1 stays behind")
        let kept = try #require(try reload(first.id).entries.first)
        #expect(kept.externalRef == fx.ref("a"), "the first session keeps ref a")
        #expect(kept.sets.map(\.externalRef) == [fx.ref("a#1"), fx.ref("b#1")])
    }

    @Test("imported set order starts at 1 and rest is not negative")
    func importedSetFieldRanges() throws {
        let session = try start()
        let zero = ImportedEntry(exerciseId: fx.press.id, externalRef: fx.ref("z"), sets: [
            ImportedSet(externalRef: fx.ref("z#0"), order: 0, values: SetValues(reps: 5, weight: .kg(10)))
        ])
        #expect(throws: TrainingDataError.self) { try fx.sessions.importEntry(zero, into: session.id) }
        let negativeRest = ImportedEntry(exerciseId: fx.press.id, externalRef: fx.ref("r"), sets: [
            ImportedSet(externalRef: fx.ref("r#1"), order: 1, values: SetValues(reps: 5, restSeconds: -5))
        ])
        #expect(throws: TrainingDataError.self) { try fx.sessions.importEntry(negativeRest, into: session.id) }
        #expect(throws: TrainingDataError.self) {
            try fx.sessions.logManualSet(
                SetValues(reps: 5, restSeconds: -1),
                exerciseId: fx.squat.id,
                sessionId: session.id,
                at: t0
            )
        }
        #expect(throws: TrainingDataError.self) {
            try fx.sessions.logManualSet(
                SetValues(durationSeconds: -1),
                exerciseId: fx.plank.id,
                sessionId: session.id,
                at: t0
            )
        }
        #expect(try reload(session.id).entries.isEmpty)
    }

    // MARK: - Session range

    @Test("a session cannot finish before it started")
    func finishBeforeStartRejected() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 10), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        #expect(throws: TrainingDataError.self) {
            try fx.sessions.finishSession(id: session.id, at: t0.addingTimeInterval(-60), durationSeconds: 100)
        }
        #expect(try reload(session.id).completedAt == nil)
    }

    @Test("finishing earlier than an entry's completedAt drops that entry time (rule range)")
    func finishDropsLaterEntryTimes() throws {
        let session = try start()
        var late = fx.importedSets("k", reps: [10], weight: 40)
        late.completedAt = t0.addingTimeInterval(3600)
        try fx.sessions.importEntry(late, into: session.id)
        try fx.sessions.logManualSet(
            SetValues(reps: 5),
            exerciseId: fx.squat.id,
            sessionId: session.id,
            at: t0.addingTimeInterval(4000)
        )
        let done = try fx.sessions.finishSession(id: session.id, at: t0.addingTimeInterval(1800), durationSeconds: nil)
        #expect(done.entries.allSatisfy { ($0.completedAt ?? .distantPast) <= t0.addingTimeInterval(1800) })
    }

    @Test("a session without entries cannot be finished, and can be discarded instead")
    func emptySessionCannotFinish() throws {
        let session = try start()
        #expect(throws: TrainingDataError.self) {
            try fx.sessions.finishSession(id: session.id, at: t0.addingTimeInterval(60), durationSeconds: 60)
        }
        try fx.sessions.discardSession(id: session.id)
        #expect(try fx.sessions.session(id: session.id) == nil)
        #expect(try fx.sessions.activeSession() == nil)
    }

    @Test("a completed session cannot be discarded")
    func completedSessionCannotBeDiscarded() throws {
        let session = try start()
        try fx.sessions.logManualSet(SetValues(reps: 5), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        try fx.sessions.finishSession(id: session.id, at: t0.addingTimeInterval(60), durationSeconds: nil)
        #expect(throws: TrainingDataError.sessionAlreadyCompleted) { try fx.sessions.discardSession(id: session.id) }
    }

    @Test("named time zones keep their IANA identifier; GMT is stored as UTC", arguments: [
        ("Europe/Madrid", "Europe/Madrid"), ("GMT", "UTC"), ("UTC", "UTC")
    ])
    func namedTimeZone(identifier: String, stored: String) throws {
        let zone = try #require(TimeZone(identifier: identifier))
        #expect(try start(zone: zone).timeZone == stored)
    }

    @Test("fixed-offset zones (identifier GMT+0100) are stored as Etc/GMT zones", arguments: [
        (0, "UTC"), (3600, "Etc/GMT-1"), (-5 * 3600, "Etc/GMT+5")
    ])
    func fixedOffsetTimeZone(seconds: Int, stored: String) throws {
        let zone = try #require(TimeZone(secondsFromGMT: seconds))
        #expect(try start(zone: zone).timeZone == stored)
    }

    @Test("a time zone with a non-whole-hour offset and no IANA name is rejected")
    func oddOffsetRejected() throws {
        let zone = try #require(TimeZone(secondsFromGMT: 5 * 3600 + 1800))
        #expect(throws: TrainingDataError.self) { try start(zone: zone) }
    }

    // MARK: - Routine targets

    @Test("routine targets: sets and reps are at least 1, durations and rest not negative")
    func routineTargetRanges() {
        let bad: [RoutineItem] = [
            RoutineItem(order: 1, exerciseId: fx.squat.id, targetSets: 0),
            RoutineItem(order: 1, exerciseId: fx.squat.id, targetReps: RepRange(min: 0, max: 5)),
            RoutineItem(order: 1, exerciseId: fx.squat.id, targetDurationSeconds: -1),
            RoutineItem(order: 1, exerciseId: fx.squat.id, restSeconds: -1),
            RoutineItem(order: 1, exerciseId: fx.squat.id, targetWeight: .kg(-1))
        ]
        for item in bad {
            #expect(throws: TrainingDataError.self) { try fx.routines.save(Routine(name: "R", items: [item])) }
        }
    }

    // MARK: - Exercise fields and external refs

    private func video(
        title: String = "Setup", url: String = "https://video.example/a", source: String = "Example"
    ) -> RelatedLink {
        RelatedLink(title: title, url: url, source: source)
    }

    @Test("""
    exercise: muscle groups are unique, media URIs and instruction steps are not empty; related links \
    have a title, an https url and a source, and are unique
    """)
    func exerciseFieldRules() {
        let invalid = [
            Exercise(name: "X", type: .strength, muscleGroups: [
                MuscleGroup(muscle: .chest, role: .primary), MuscleGroup(muscle: .chest, role: .primary)
            ]),
            Exercise(name: "X", type: .strength, media: ExerciseMedia(imageURI: "")),
            Exercise(name: "X", type: .strength, media: ExerciseMedia(videoURI: "")),
            Exercise(name: "X", type: .strength, instructions: ExerciseInstructions(setup: [""])),
            Exercise(name: "X", type: .strength, relatedLinks: [video(title: "")]),
            Exercise(name: "X", type: .strength, relatedLinks: [video(source: "")]),
            Exercise(name: "X", type: .strength, relatedLinks: [video(url: "http://video.example/a")]),
            Exercise(name: "X", type: .strength, relatedLinks: [video(url: "https://")]),
            Exercise(name: "X", type: .strength, relatedLinks: [video(url: "https://video.example/a b")]),
            Exercise(name: "X", type: .strength, relatedLinks: [video(), video()])
        ]
        for exercise in invalid {
            #expect(throws: TrainingDataError.self) { try fx.exercises.save(exercise) }
        }
    }

    @Test("an externalRef needs a slug provider and a non-empty id", arguments: [
        ("Machines Atlas", "1"), ("machines_atlas", "1"), ("-machines", "1"), ("machines-atlas", "")
    ])
    func externalRefRules(provider: String, id: String) throws {
        let ref = ExternalRef(provider: provider, id: id)
        #expect(throws: TrainingDataError.self) {
            try fx.exercises.save(Exercise(externalRef: ref, name: "X", type: .strength))
        }
        #expect(throws: TrainingDataError.self) {
            try fx.routines.save(
                Routine(externalRef: ref, name: "R", items: [RoutineItem(order: 1, exerciseId: fx.squat.id)])
            )
        }
        let session = try start()
        #expect(throws: TrainingDataError.self) {
            try fx.sessions.importEntry(ImportedEntry(exerciseId: fx.press.id, externalRef: ref, sets: [
                ImportedSet(externalRef: fx.ref("ok#1"), order: 1, values: SetValues(reps: 1))
            ]), into: session.id)
        }
        #expect(throws: TrainingDataError.self) {
            try fx.sessions.importEntry(ImportedEntry(exerciseId: fx.press.id, externalRef: fx.ref("ok"), sets: [
                ImportedSet(externalRef: ref, order: 1, values: SetValues(reps: 1))
            ]), into: session.id)
        }
    }
}
