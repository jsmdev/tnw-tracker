import Foundation
import Testing
@testable import TNWTrackerKit

/// Exercise settings both ways (S1, S2, S11, S13): keyed by their exercise,
/// pushed after it, pulled and deleted like the other aggregates. Real store
/// and repositories, in-memory server. Invented data only.
@Suite("Sync engine exercise settings")
@MainActor
struct TrainingSyncEngineSettingsTests {
    let world: PushWorld

    init() throws {
        world = try PushWorld()
    }

    private var store: TrainingStore { world.store }
    private var server: InMemoryTrainingRemoteStore { world.server }

    private func save(_ exerciseId: UUID, enabled: Bool = true, seconds: Int, on device: PushWorld? = nil) throws {
        try (device ?? world).store.exerciseSettings.save(
            ExerciseSetting(exerciseId: exerciseId, restEnabled: enabled, restSeconds: seconds)
        )
    }

    private func row(_ exerciseId: UUID, enabled: Bool = true, seconds: Int) -> RemoteExerciseSettingRow {
        RemoteExerciseSettingRow(
            exerciseId: exerciseId, userId: world.userId, restEnabled: enabled, restSeconds: seconds
        )
    }

    // MARK: - Push

    @Test("settings go up after their exercise, one row per exercise, and a new value updates that row")
    func settingsGoUp() async throws {
        try save(world.squat.id, enabled: false, seconds: 120)
        try save(world.bench.id, seconds: 60)

        let report = try await world.engine.push()

        let squatSetting = SyncAggregateRef(.exerciseSetting, id: world.squat.id)
        #expect(report.rejected.isEmpty)
        #expect(report.skipped.isEmpty)
        #expect(Set(report.pushed) == [
            SyncAggregateRef(.exercise, id: world.squat.id), squatSetting,
            SyncAggregateRef(.exerciseSetting, id: world.bench.id)
        ])
        let exerciseFirst = report.pushed.firstIndex(of: SyncAggregateRef(.exercise, id: world.squat.id))
        #expect(try #require(exerciseFirst) < #require(report.pushed.firstIndex(of: squatSetting)))
        #expect(await world.stored(RemoteExerciseSettingRow.self) == PushWorld.byId([
            row(world.squat.id, enabled: false, seconds: 120), row(world.bench.id, seconds: 60)
        ]))
        try world.expectNothingPending()

        try save(world.squat.id, seconds: 30)
        try await world.engine.push()

        #expect(await world.stored(RemoteExerciseSettingRow.self) == PushWorld.byId([
            row(world.squat.id, seconds: 30), row(world.bench.id, seconds: 60)
        ]))
        try world.expectNothingPending()
    }

    @Test("a setting of an exercise the server refused waits for it; the others go up")
    func settingWaitsForItsExercise() async throws {
        try save(world.squat.id, seconds: 120)
        try save(world.bench.id, seconds: 60)
        await server.failNext(.upsert, with: InMemoryTrainingRemoteStore.foreignKeyViolation("refused"))

        let report = try await world.engine.push()

        let squatExercise = SyncAggregateRef(.exercise, id: world.squat.id)
        #expect(report.rejected.map(\.aggregate) == [squatExercise])
        #expect(report.skipped == [
            .init(aggregate: SyncAggregateRef(.exerciseSetting, id: world.squat.id), reason: .waitsFor(squatExercise))
        ])
        #expect(await world.stored(RemoteExerciseSettingRow.self) == [row(world.bench.id, seconds: 60)])
        #expect(try store.syncState.pending(.exerciseSetting).map(\.id) == [world.squat.id])
    }

    // MARK: - Pull

    @Test("a setting saved on another device arrives clean; one with a local change keeps the device's value")
    func settingsArrive() async throws {
        let tablet = try PushWorld(sharing: world)
        try await tablet.engine.sync()
        try save(world.squat.id, enabled: false, seconds: 120)
        try save(world.bench.id, seconds: 60)
        try await world.engine.push()
        try save(world.bench.id, seconds: 45, on: tablet)

        let report = try await tablet.engine.pull()

        let squat = SyncAggregateRef(.exerciseSetting, id: world.squat.id)
        let bench = SyncAggregateRef(.exerciseSetting, id: world.bench.id)
        #expect(report.created == [squat])
        #expect(report.resolved.contains(.init(aggregate: bench, rule: .localKept)))
        #expect(try tablet.store.exerciseSettings.setting(exerciseId: world.squat.id) == ExerciseSetting(
            exerciseId: world.squat.id, restEnabled: false, restSeconds: 120
        ))
        #expect(try tablet.store.exerciseSettings.setting(exerciseId: world.bench.id)?.restSeconds == 45)
        #expect(try tablet.store.syncState.pending(.exerciseSetting).map(\.id) == [world.bench.id])
        let last = try #require(await server.stored(RemoteExerciseSettingRow.self).last)
        #expect(try tablet.store.pulled.cursor(.exerciseSettings, userId: world.userId)
            == RemoteCursor(updatedAt: try #require(last.updatedAt), id: last.id))

        // The device's value goes up with the next sync, and both devices settle on it.
        try await tablet.engine.sync()
        try await world.engine.sync()
        #expect(try store.exerciseSettings.setting(exerciseId: world.bench.id)?.restSeconds == 45)
        try world.expectNothingPending()
        try tablet.expectNothingPending()
    }

    @Test("a setting of an exercise the device does not hold waits for it")
    func settingWithoutExerciseWaits() throws {
        var orphan = row(UUID(), seconds: 50)
        orphan.updatedAt = InMemoryTrainingRemoteStore.timestamp(1)

        let report = try store.pulled.apply(PulledBatch(exerciseSettings: [orphan]), userId: world.userId)

        #expect(report.skipped == [.init(table: .exerciseSettings, id: orphan.id, reason: .missingParent)])
        #expect(try store.pulled.cursor(.exerciseSettings, userId: world.userId) == nil)
        #expect(try store.exerciseSettings.setting(exerciseId: orphan.id) == nil)
    }

    @Test("a setting of an exercise the device deleted is passed over, and its cursor moves on")
    func settingOfDeletedExerciseIsPassedOver() throws {
        let gone = UUID()
        store.context.insert(SyncTombstoneModel(
            kindRaw: SyncTombstoneKind.exercise.rawValue, rowId: gone, sessionId: nil, revision: 1, deletedAt: world.t0
        ))
        try store.context.save()
        var orphan = row(gone, seconds: 50)
        orphan.updatedAt = InMemoryTrainingRemoteStore.timestamp(1)

        let report = try store.pulled.apply(PulledBatch(exerciseSettings: [orphan]), userId: world.userId)

        #expect(report.skipped == [.init(table: .exerciseSettings, id: gone, reason: .deletedOnDevice)])
        #expect(try store.pulled.cursor(.exerciseSettings, userId: world.userId)?.id == gone)
        #expect(try store.exerciseSettings.setting(exerciseId: gone) == nil)
    }

    @Test("a setting deleted on the server goes from the device, unless it has a local change (S13)")
    func deletedSettingGoes() async throws {
        try save(world.squat.id, seconds: 120)
        try save(world.bench.id, seconds: 60)
        try await world.engine.push()
        try await server.deleteOnServer(.exerciseSettings, ids: [world.squat.id, world.bench.id])
        try save(world.bench.id, seconds: 45)

        let report = try await world.engine.pull()

        #expect(report.deletions.sorted { $0.id.uuidString < $1.id.uuidString } == [
            SyncPullReport.Deletion(table: .exerciseSettings, id: world.squat.id, rule: .serverApplied),
            SyncPullReport.Deletion(table: .exerciseSettings, id: world.bench.id, rule: .localKept)
        ].sorted { $0.id.uuidString < $1.id.uuidString })
        #expect(try store.exerciseSettings.setting(exerciseId: world.squat.id) == nil)
        #expect(try store.exerciseSettings.setting(exerciseId: world.bench.id)?.restSeconds == 45)
        #expect(try store.syncState.pending(.exerciseSetting).map(\.id) == [world.bench.id])

        // The kept setting goes back up and clears its server tombstone.
        try await world.engine.sync()
        #expect(await world.stored(RemoteExerciseSettingRow.self) == [row(world.bench.id, seconds: 45)])
        #expect(await server.stored(RemoteTombstoneRow.self).map(\.rowId) == [world.squat.id])
        try world.expectNothingPending()
    }
}
