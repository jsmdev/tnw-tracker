import Foundation
import SwiftData

@MainActor
public protocol WorkoutRepositoryProtocol: AnyObject, Sendable {
    func fetchActive() async throws -> Workout?
    func fetchHistory(limit: Int) async throws -> [Workout]
    func fetch(id: UUID) async throws -> Workout?
    func create(_ workout: Workout) async throws
    func update(_ workout: Workout) async throws
    func complete(_ workout: Workout) async throws
    func updateMetadata(_ workout: Workout) async throws
    func updateSet(_ set: ExerciseSet) async throws
    func delete(_ workout: Workout) async throws
}

@MainActor
public final class WorkoutRepository: WorkoutRepositoryProtocol {
    private let modelContext: ModelContext
    private let syncEngine: any SyncEngine

    public init(modelContext: ModelContext, syncEngine: any SyncEngine) {
        self.modelContext = modelContext
        self.syncEngine = syncEngine
    }

    public func fetchActive() async throws -> Workout? {
        let activeRaw = WorkoutStatus.active.rawValue
        let pausedRaw = WorkoutStatus.paused.rawValue
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { workout in
                workout.statusRaw == activeRaw || workout.statusRaw == pausedRaw
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    public func fetchHistory(limit: Int) async throws -> [Workout] {
        let completedRaw = WorkoutStatus.completed.rawValue
        let cancelledRaw = WorkoutStatus.cancelled.rawValue
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { workout in
                workout.statusRaw == completedRaw || workout.statusRaw == cancelledRaw
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    public func fetch(id: UUID) async throws -> Workout? {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    public func create(_ workout: Workout) async throws {
        modelContext.insert(workout)
        try modelContext.save()
        workout.pendingSyncOp = "insert"
        try await syncEngine.enqueueLocalChange(
            tableName: "workouts",
            recordId: workout.id,
            operationType: "insert",
            payload: nil
        )
    }

    public func update(_ workout: Workout) async throws {
        workout.updatedAt = Date()
        workout.pendingSyncOp = "update"
        try modelContext.save()
        try await syncEngine.enqueueLocalChange(
            tableName: "workouts",
            recordId: workout.id,
            operationType: "update",
            payload: nil
        )
    }

    public func complete(_ workout: Workout) async throws {
        workout.completedAt = Date()
        workout.statusRaw = WorkoutStatus.completed.rawValue
        workout.updatedAt = Date()
        workout.pendingSyncOp = "update"
        try modelContext.save()
        try await syncEngine.enqueueLocalChange(
            tableName: "workouts",
            recordId: workout.id,
            operationType: "update",
            payload: nil
        )
    }

    /// Persiste la edición de los metadatos de un workout del histórico (nombre,
    /// fecha, notas) y encola el cambio para `workouts` con el DTO serializado —
    /// como `updateSet`, evita el `payload: nil` que el push descartaría.
    public func updateMetadata(_ workout: Workout) async throws {
        workout.updatedAt = Date()
        workout.pendingSyncOp = "update"
        try modelContext.save()

        let payload = try Self.dtoEncoder.encode(workout.toDTO())
        try await syncEngine.enqueueLocalChange(
            tableName: "workouts",
            recordId: workout.id,
            operationType: "update",
            payload: payload
        )
    }

    /// Persiste la edición de una serie de un workout del histórico y encola el
    /// cambio para `exercise_sets`. A diferencia de los demás métodos de este
    /// repositorio, encola el DTO serializado como payload: el push genérico de
    /// `SyncEngineImpl` descarta las operaciones `update` sin payload, así que un
    /// `payload: nil` nunca llegaría a Supabase.
    public func updateSet(_ set: ExerciseSet) async throws {
        set.updatedAt = Date()
        set.pendingSyncOp = "update"
        try modelContext.save()

        let payload = try Self.dtoEncoder.encode(set.toDTO())
        try await syncEngine.enqueueLocalChange(
            tableName: "exercise_sets",
            recordId: set.id,
            operationType: "update",
            payload: payload
        )
    }

    /// Elimina un workout del histórico. SwiftData borra en cascada sus
    /// `WorkoutExercise`/`ExerciseSet` localmente (`deleteRule: .cascade`); en
    /// Supabase el borrado se propaga vía los FK `ON DELETE CASCADE` de
    /// `workout_exercises` y `exercise_sets`, por eso basta encolar el delete del
    /// workout raíz.
    public func delete(_ workout: Workout) async throws {
        let recordId = workout.id
        modelContext.delete(workout)
        try modelContext.save()
        try await syncEngine.enqueueLocalChange(
            tableName: "workouts",
            recordId: recordId,
            operationType: "delete",
            payload: nil
        )
    }

    /// Encoder dedicado al payload de sync: fechas en ISO-8601 para que el
    /// upsert genérico las envíe como `timestamptz` válidos. Las `CodingKeys`
    /// snake_case viven en cada DTO, así que no se necesita key strategy.
    private static let dtoEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
