import Foundation
import SwiftData
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// Regression tests for the EXC_BREAKPOINT inside SwiftData seen on 2026-11-17
/// (crash reports TNWTracker-2026-11-17-062052 / -062109). `SessionListModel`
/// starts an unstructured Task from the `filter` and `searchQuery` didSet. That
/// Task can run after whoever created the store has released it. `ModelContext`
/// does not keep its `ModelContainer` alive, so a repository that held only the
/// context fetched from a freed container and SwiftData trapped.
@Suite("Routine search crash")
@MainActor
struct RoutineSearchCrashTests {
    @Test("the routine repository still searches after its store is released")
    func repositoryOutlivesStore() throws {
        var fx: TrainingFixtures? = try TrainingFixtures()
        _ = try fx?.makeRoutine(name: "Push Day")
        _ = try fx?.makeRoutine(name: "Legs Day")
        let routines = try #require(fx?.routines)
        fx = nil

        #expect(try routines.routines(RoutineQuery(search: "pu")).map(\.name) == ["Push Day"])
        #expect(try routines.routines(RoutineQuery(onlyPerformed: true)).isEmpty)
    }

    @Test("a search started by the session list still loads after the store is released")
    func pendingSearchTaskOutlivesStore() async throws {
        var fx: TrainingFixtures? = try TrainingFixtures()
        _ = try fx?.makeRoutine(name: "Push Day")
        _ = try fx?.makeRoutine(name: "Legs Day")
        let model = try SessionListModel(routines: #require(fx?.routines))

        // The didSet Task is queued on the main actor and has not run yet.
        model.searchQuery = "Pu"
        fx = nil

        await waitUntil { model.sessions.map(\.name) == ["Push Day"] }
        #expect(model.sessions.map(\.name) == ["Push Day"])
    }

    @Test("rapid searches and the performed filter work on an on-disk store")
    func rapidSearchOnDiskStore() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routine-search-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let schema = Schema(versionedSchema: TrainingSchemaV1.self)
        let config = ModelConfiguration(nil, schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema, migrationPlan: TrainingMigrationPlan.self, configurations: [config]
        )
        let store = TrainingStore(container: container)

        let squat = Exercise(name: "Goblet Squat", type: .strength, equipment: .freeWeights)
        try store.exercises.save(squat)
        var performed: Routine?
        for name in ["Push Day", "Pull Day", "Legs Day"] {
            let routine = Routine(name: name, items: [RoutineItem(order: 1, exerciseId: squat.id, targetSets: 3)])
            try store.routines.save(routine)
            if name == "Push Day" { performed = routine }
        }
        let routineId = try #require(performed?.id)
        let t0 = TrainingFixtures.t0
        let session = try store.sessions.startSession(routineId: routineId, name: nil, at: t0, timeZone: .gmt)
        try store.sessions.logManualSet(SetValues(reps: 5), exerciseId: squat.id, sessionId: session.id, at: t0)
        try store.sessions.finishSession(id: session.id, at: t0.addingTimeInterval(60), durationSeconds: nil)

        #expect(try store.routines.routines(RoutineQuery(search: "pu")).map(\.name) == ["Pull Day", "Push Day"])
        #expect(try store.routines.routines(RoutineQuery(search: "pu", onlyPerformed: true)).map(\.name) == ["Push Day"])

        // One didSet Task per keystroke, none awaited, as when typing in the field.
        let model = SessionListModel(routines: store.routines)
        model.filter = .withWorkouts
        for prefix in ["P", "Pu", "Pus", "Pu"] {
            model.searchQuery = prefix
        }
        await waitUntil { model.sessions.map(\.name) == ["Push Day"] }
        #expect(model.sessions.map(\.name) == ["Push Day"])
    }

    /// Lets the queued main-actor Tasks run until `condition` holds or a bound is reached.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 200 where !condition() {
            await Task.yield()
        }
    }
}
