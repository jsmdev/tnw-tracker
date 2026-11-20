import Foundation
import Testing
@testable import TNWTrackerKit

/// A signed-in user's device for the push tests: the real in-memory store
/// claimed by `userId`, the in-memory server and the engine between them.
/// Invented data only.
@MainActor
struct PushWorld {
    let store: TrainingStore
    let server: InMemoryTrainingRemoteStore
    let userId: UUID
    let engine: TrainingSyncEngine
    /// 2030-03-04T09:00:00Z, whole seconds so dates survive the round trip.
    let t0 = TrainingFixtures.t0

    /// A user exercise, with everything the server stores for one.
    let squat: Exercise
    static func makeSquat() -> Exercise {
        Exercise(
            externalRef: ExternalRef(provider: "machines-atlas", id: "squat-1"),
            name: "Goblet Squat",
            type: .strength,
            equipment: .freeWeights,
            muscleGroups: [
                MuscleGroup(muscle: .quadriceps, role: .primary),
                MuscleGroup(muscle: .glutes, role: .secondary)
            ],
            instructions: ExerciseInstructions(setup: ["Hold the bell"], execution: ["Sit down", "Stand up"], tips: []),
            media: ExerciseMedia(imageURI: "https://example.test/squat.png", videoURI: nil)
        )
    }

    /// A catalogue exercise the server already holds (supabase/seed.sql).
    let bench = Exercise(
        id: TrainingRemoteStoreContract.benchPress, isCatalogue: true, name: "Bench Press", type: .strength
    )

    /// Without `claimed`, everything written before `claim()` belongs to nobody (sample data).
    /// With `sharing`, another device of the same user: same server, user and exercises.
    init(claimed: Bool = true, userId: UUID = UUID(), sharing other: PushWorld? = nil) throws {
        self.userId = other?.userId ?? userId
        server = other?.server ?? InMemoryTrainingRemoteStore()
        squat = other?.squat ?? Self.makeSquat()
        store = try TrainingStore.inMemory()
        engine = TrainingSyncEngine(store: store, remote: server, userId: self.userId)
        if claimed { try claim() }
        try store.exercises.save(squat)
        try store.exercises.save(bench)
    }

    func claim() throws {
        _ = try store.ownership.claim(userId: userId, at: t0)
    }

    var squatRow: RemoteExerciseRow {
        RemoteExerciseRow(
            id: squat.id, userId: userId, name: "Goblet Squat", type: .strength, equipment: .freeWeights,
            setupSteps: ["Hold the bell"], executionSteps: ["Sit down", "Stand up"], tips: nil,
            imageURI: "https://example.test/squat.png", videoURI: nil,
            externalRef: ExternalRef(provider: "machines-atlas", id: "squat-1")
        )
    }

    // MARK: - Writing through the repositories

    /// A favourite routine: squat, then bench.
    func saveRoutine() throws -> Routine {
        let routine = Routine(
            name: "Legs",
            description: "Heavy",
            items: [
                RoutineItem(
                    order: 1, exerciseId: squat.id, targetSets: 3, targetReps: RepRange(min: 8, max: 12),
                    targetWeight: .kg(40), restSeconds: 90, notes: "Deep"
                ),
                RoutineItem(order: 2, exerciseId: bench.id, targetDurationSeconds: 60)
            ]
        )
        try store.routines.save(routine)
        try store.routines.setFavorite(true, routineId: routine.id)
        return routine
    }

    func itemRows(_ routine: Routine) -> [RemoteRoutineItemRow] {
        [
            RemoteRoutineItemRow(
                id: RemoteRoutineItemRow.id(routineId: routine.id, position: 1), userId: userId,
                routineId: routine.id, position: 1, exerciseId: squat.id, targetSets: 3,
                targetReps: RepRange(min: 8, max: 12), targetWeight: .kg(40), restSeconds: 90, notes: "Deep"
            ),
            RemoteRoutineItemRow(
                id: RemoteRoutineItemRow.id(routineId: routine.id, position: 2), userId: userId,
                routineId: routine.id, position: 2, exerciseId: bench.id, targetDurationSeconds: 60
            )
        ]
    }

    func startSession(routineId: UUID? = nil, at offset: TimeInterval = 0) throws -> TrainingSession {
        try store.sessions.startSession(
            routineId: routineId, name: "Morning", at: t0.addingTimeInterval(offset), timeZone: TrainingFixtures.zone
        )
    }

    /// A completed session: a heavy set and a warm-up of `exerciseId` (squat by default).
    func finishedSession(
        routineId: UUID? = nil,
        exerciseId: UUID? = nil,
        at offset: TimeInterval = 0
    ) throws -> TrainingSession {
        let session = try startSession(routineId: routineId, at: offset)
        let exercise = exerciseId ?? squat.id
        try store.sessions.logManualSet(
            SetValues(reps: 8, weight: Weight(value: 42.5, unit: .kg), rir: 2, restSeconds: 95),
            exerciseId: exercise, sessionId: session.id, at: t0.addingTimeInterval(offset + 300)
        )
        try store.sessions.logManualSet(
            SetValues(reps: 12, weight: .kg(20)), warmup: true,
            exerciseId: exercise, sessionId: session.id, at: t0.addingTimeInterval(offset + 600)
        )
        return try store.sessions.finishSession(
            id: session.id, at: t0.addingTimeInterval(offset + 1_800), durationSeconds: 1_500
        )
    }

    /// Pushes the user exercise first, so the next push only holds sessions.
    func uploadPrerequisites() async throws {
        try await engine.push()
    }

    func expectNothingPending() throws {
        for kind in SyncAggregateKind.allCases {
            #expect(try store.syncState.pending(kind).isEmpty, "\(kind) still pending")
        }
    }

    // MARK: - Expected server rows

    /// The rows the server should hold for `session`, written out field by field.
    static func rows(of session: TrainingSession, userId: UUID) -> RemoteSessionAggregate {
        let row = RemoteSessionRow(
            id: session.id, userId: userId, routineId: session.routineId, name: session.name, notes: session.notes,
            startedAt: session.startedAt, completedAt: session.completedAt ?? .distantPast, timeZone: session.timeZone,
            durationSeconds: session.durationSeconds, externalRef: session.externalRef
        )
        let entries = session.entries.map { entry in
            RemoteEntryRow(
                id: entry.id, userId: userId, sessionId: session.id, position: entry.order,
                exerciseId: entry.exerciseId, status: entry.status, replacedExerciseId: entry.replacedExerciseId,
                completedAt: entry.completedAt, notes: entry.notes, reconciliationKeep: entry.reconciliation?.keep,
                reconciliationDecidedBy: entry.reconciliation?.decidedBy,
                reconciliationDecidedAt: entry.reconciliation?.decidedAt, externalRef: entry.externalRef
            )
        }
        let sets = session.entries.flatMap { entry in
            entry.sets.map { set in
                RemoteSetRow(
                    id: set.id, userId: userId, entryId: entry.id, position: set.order, source: set.source,
                    reps: set.values.reps, weight: set.values.weight, durationSeconds: set.values.durationSeconds,
                    distanceMeters: set.values.distanceMeters, rir: set.values.rir,
                    restSeconds: set.values.restSeconds, completedAt: set.completedAt,
                    superseded: set.superseded, warmup: set.warmup, externalRef: set.externalRef
                )
            }
        }
        return RemoteSessionAggregate(session: row, entries: entries, sets: sets)
    }

    /// The rows of `type` the fake server holds, without `updated_at`, by id.
    func stored<Row: RemoteRow>(_ type: Row.Type) async -> [Row] {
        await Self.byId(server.stored(type).map(Self.plain))
    }

    /// Rows in a fixed order, to compare them as a set.
    static func byId<Row: RemoteRow>(_ rows: [Row]) -> [Row] {
        rows.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// A stored row without the server's `updated_at`.
    static func plain<Row: RemoteRow>(_ row: Row) -> Row {
        TrainingRemoteStoreContract.withoutServerFields(row)
    }
}
