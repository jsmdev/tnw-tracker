import Foundation
import Testing
@testable import TNWTrackerKit

@Suite("SampleTrainingData")
@MainActor
struct SampleTrainingDataTests {
    let store: TrainingStore
    let now = Date(timeIntervalSince1970: 1_899_028_800)

    init() throws {
        store = try TrainingStore.inMemory()
    }

    @Test("loads invented exercises, routines and two completed sessions into an empty store")
    func loadsIntoEmptyStore() throws {
        try SampleTrainingData.loadIfEmpty(into: store, now: now)
        #expect(try store.exercises.exercises().count == SampleTrainingData.exercises.count)
        #expect(try store.routines.routines(RoutineQuery()).map(\.name) == ["Full Body A", "Full Body B"])
        let history = try store.sessions.completedSessions(in: DateInterval(start: .distantPast, end: now))
        #expect(history.count == 2)
        #expect(try store.sessions.activeSession() == nil)
    }

    @Test("T5 with the sample history, the next session is Full Body A (done longest ago), with no favourites")
    func sampleProposesFullBodyA() throws {
        try SampleTrainingData.loadIfEmpty(into: store, now: now)
        #expect(try store.routines.nextRoutine()?.id == SampleTrainingData.RoutineID.fullBodyA)
        #expect(try store.routines.routines(RoutineQuery()).allSatisfy { !$0.isFavorite })
    }

    @Test("loading twice does not duplicate data")
    func idempotent() throws {
        try SampleTrainingData.loadIfEmpty(into: store, now: now)
        try SampleTrainingData.loadIfEmpty(into: store, now: now)
        #expect(try store.exercises.exercises().count == SampleTrainingData.exercises.count)
        #expect(try store.sessions.completedSessions(in: DateInterval(start: .distantPast, end: now)).count == 2)
    }

    @Test("replaceAll resets the store to the sample data")
    func replaceAllResets() throws {
        try store.exercises.save(Exercise(name: "Extra", type: .strength))
        try SampleTrainingData.replaceAll(in: store, now: now)
        #expect(try store.exercises.exercises().contains { $0.name == "Extra" } == false)
        #expect(try store.exercises.exercises().count == SampleTrainingData.exercises.count)
    }

    @Test("the history shows every entry status, a swap and a default reconciliation")
    func historyCoversTheFormat() throws {
        try SampleTrainingData.loadIfEmpty(into: store, now: now)
        let history = try store.sessions.completedSessions(in: DateInterval(start: .distantPast, end: now))
        let entries = history.flatMap(\.entries)
        #expect(Set(entries.map(\.status)) == [.done, .skipped, .removed])
        #expect(entries.contains { $0.replacedExerciseId != nil })
        let reconciled = try #require(entries.first { $0.reconciliation != nil })
        #expect(reconciled.reconciliation?.keep == .imported)
        #expect(reconciled.reconciliation?.decidedBy == .default)
        let imported = entries.flatMap(\.sets).filter { $0.source == .imported }
        #expect(!imported.isEmpty)
        #expect(imported.allSatisfy { $0.externalRef?.provider == "machines-atlas" })
    }
}
