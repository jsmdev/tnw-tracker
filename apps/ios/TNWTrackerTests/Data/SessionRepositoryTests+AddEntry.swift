import Foundation
import Testing
@testable import TNWTrackerKit

/// Adding an exercise before any set saves it at once (fast-add-exercise S4).
extension SessionRepositoryTests {
    @Test("adding an exercise saves a skipped entry at the end at once, and never twice")
    func addEntrySavesItAtOnce() throws {
        let session = try start(fx.makeRoutine())
        let added = try fx.sessions.addEntry(exerciseId: fx.plank.id, sessionId: session.id)
        #expect(added.exerciseId == fx.plank.id)
        #expect(added.status == .skipped)
        #expect(added.order == 3)
        #expect(added.sets.isEmpty)
        let loaded = try reload(session.id)
        #expect(loaded.entries.map(\.exerciseId) == [fx.squat.id, fx.press.id, fx.plank.id])

        let again = try fx.sessions.addEntry(exerciseId: fx.plank.id, sessionId: session.id)
        #expect(again.id == added.id)
        let planned = try fx.sessions.addEntry(exerciseId: fx.squat.id, sessionId: session.id)
        #expect(planned.id == loaded.entries[0].id)
        #expect(try reload(session.id).entries.count == 3)
    }

    @Test("an added exercise's first set fills its entry; a removed one is added anew")
    func addEntryThenLogAndRemove() throws {
        let session = try start()
        let added = try fx.sessions.addEntry(exerciseId: fx.squat.id, sessionId: session.id)
        try fx.sessions.logManualSet(SetValues(reps: 8), exerciseId: fx.squat.id, sessionId: session.id, at: t0)
        let done = try entry(reload(session.id), fx.squat)
        #expect(done.id == added.id)
        #expect(done.status == .done)
        #expect(done.sets.count == 1)

        try fx.sessions.removeEntry(id: added.id)
        let readded = try fx.sessions.addEntry(exerciseId: fx.squat.id, sessionId: session.id)
        #expect(readded.id != added.id)
        #expect(readded.status == .skipped)
        #expect(try reload(session.id).entries.map(\.status) == [.removed, .skipped])
    }

    @Test("adding an exercise to an unknown or completed session throws")
    func addEntryNeedsOpenSession() throws {
        #expect(throws: TrainingDataError.notFound) {
            try fx.sessions.addEntry(exerciseId: fx.squat.id, sessionId: UUID())
        }
        let session = try start()
        #expect(throws: TrainingDataError.notFound) {
            try fx.sessions.addEntry(exerciseId: UUID(), sessionId: session.id)
        }
    }
}
