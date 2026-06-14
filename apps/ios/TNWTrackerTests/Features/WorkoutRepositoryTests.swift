import Foundation
import Supabase
import SwiftData
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - WorkoutRepositoryTests

// Cubre las mutaciones del histórico: updateSet (edición de series) y delete.
// Verifica el estado del store local + el encolado en SyncOperationRecord.
// Sigue la convención del repo: SyncEngineImpl real contra un host inválido
// (el push nunca corre en estos tests; solo se ejercita el enqueue local).

@Suite("WorkoutRepository", .serialized)
@MainActor
struct WorkoutRepositoryTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerFactory.makeContainer(inMemory: true)
    }

    private func makeRepo(_ context: ModelContext) -> (WorkoutRepository, SyncEngineImpl) {
        guard let invalidURL = URL(string: "https://test.invalid") else {
            preconditionFailure("URL de prueba inválido")
        }
        let supabase = SupabaseClient(supabaseURL: invalidURL, supabaseKey: "test-key")
        let engine = SyncEngineImpl(
            modelContext: context,
            supabase: supabase,
            networkMonitor: StubNetworkMonitor(isOnline: false)
        )
        return (WorkoutRepository(modelContext: context, syncEngine: engine), engine)
    }

    private func queuedOps(_ context: ModelContext) -> [SyncOperationRecord] {
        (try? context.fetch(FetchDescriptor<SyncOperationRecord>())) ?? []
    }

    // MARK: - updateSet

    @Test("updateSet persiste cambios y encola 'update' en exercise_sets con payload")
    func updateSetEnqueuesWithPayload() async throws {
        let context = ModelContext(container)
        let (repo, _) = makeRepo(context)

        let workout = Workout(userId: UUID(), name: "Push Day")
        workout.status = .completed
        context.insert(workout)
        let we = WorkoutExercise(workoutId: workout.id, exerciseId: UUID(), orderIndex: 0)
        context.insert(we)
        workout.workoutExercises.append(we)
        let set = ExerciseSet(workoutExerciseId: we.id, setNumber: 1)
        set.reps = 8
        set.weight = 80
        context.insert(set)
        we.exerciseSets.append(set)
        try context.save()

        set.reps = 10
        set.weight = 85
        try await repo.updateSet(set)

        // Persistencia local
        #expect(set.reps == 10)
        #expect(set.weight == 85)
        #expect(set.pendingSyncOp == "update")

        // Encolado para exercise_sets con payload no nil
        let ops = queuedOps(context).filter { $0.tableName == "exercise_sets" }
        #expect(ops.count == 1)
        let op = try #require(ops.first)
        #expect(op.operationTypeRaw == "update")
        #expect(op.recordId == set.id)
        #expect(op.payload != nil)

        // El payload es un DTO decodificable con los valores editados
        let payload = try #require(op.payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(ExerciseSetDTO.self, from: payload)
        #expect(dto.reps == 10)
        #expect(dto.weight == 85)
    }

    // MARK: - updateMetadata

    @Test("updateMetadata persiste cambios y encola 'update' en workouts con payload")
    func updateMetadataEnqueuesWithPayload() async throws {
        let context = ModelContext(container)
        let (repo, _) = makeRepo(context)

        let workout = Workout(userId: UUID(), name: "Old Name")
        workout.status = .completed
        context.insert(workout)
        try context.save()

        workout.name = "New Name"
        workout.notes = "Felt strong"
        try await repo.updateMetadata(workout)

        #expect(workout.name == "New Name")
        #expect(workout.pendingSyncOp == "update")

        let ops = queuedOps(context).filter { $0.tableName == "workouts" && $0.operationTypeRaw == "update" }
        #expect(ops.count == 1)
        let op = try #require(ops.first)
        #expect(op.payload != nil)

        let payload = try #require(op.payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(WorkoutDTO.self, from: payload)
        #expect(dto.name == "New Name")
        #expect(dto.notes == "Felt strong")
    }

    // MARK: - delete

    @Test("delete elimina el workout del store y encola 'delete' en workouts")
    func deleteRemovesWorkoutAndEnqueues() async throws {
        let context = ModelContext(container)
        let (repo, _) = makeRepo(context)

        let workout = Workout(userId: UUID(), name: "To Delete")
        workout.status = .completed
        context.insert(workout)
        try context.save()
        let workoutId = workout.id

        try await repo.delete(workout)

        // Ya no está en el store
        let remaining = try context.fetch(FetchDescriptor<Workout>())
        #expect(remaining.isEmpty)

        // Encolado delete sobre workouts
        let ops = queuedOps(context).filter { $0.tableName == "workouts" && $0.operationTypeRaw == "delete" }
        #expect(ops.count == 1)
        #expect(ops.first?.recordId == workoutId)
    }

    @Test("delete borra en cascada workoutExercises y exerciseSets locales")
    func deleteCascadesChildren() async throws {
        let context = ModelContext(container)
        let (repo, _) = makeRepo(context)

        let workout = Workout(userId: UUID(), name: "Cascade")
        workout.status = .completed
        context.insert(workout)
        let we = WorkoutExercise(workoutId: workout.id, exerciseId: UUID(), orderIndex: 0)
        context.insert(we)
        workout.workoutExercises.append(we)
        let set = ExerciseSet(workoutExerciseId: we.id, setNumber: 1)
        context.insert(set)
        we.exerciseSets.append(set)
        try context.save()

        try await repo.delete(workout)

        #expect(try context.fetch(FetchDescriptor<WorkoutExercise>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ExerciseSet>()).isEmpty)
    }
}
