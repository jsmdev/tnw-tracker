import Foundation
import Observation

/// «Añadir a rutina» in the exercise sheet: the user's routines to add the
/// exercise to, and a new routine that holds it. The exercise goes at the end of
/// the routine with no targets, and never twice in the same routine.
@Observable
@MainActor
public final class AddToRoutineModel {
    /// What adding did.
    public enum Result: Equatable, Sendable {
        case added(routineName: String)
        /// The routine already had the exercise; nothing changed.
        case alreadyInRoutine(routineName: String)
    }

    /// The user's routines, favourites first, then by name.
    public private(set) var routines: [Routine] = []
    /// True when the routines could not be read.
    public private(set) var loadFailed = false

    private let exerciseId: UUID
    private let repository: any RoutineRepositoryProtocol

    public init(exerciseId: UUID, routines: any RoutineRepositoryProtocol) {
        self.exerciseId = exerciseId
        repository = routines
    }

    public func load() {
        do {
            routines = try repository.routines(RoutineQuery())
            loadFailed = false
        } catch {
            routines = []
            loadFailed = true
        }
    }

    /// Adds the exercise at the end of the routine with `routineId`, unless it
    /// already has it. Throws `notFound` when the routine does not exist.
    @discardableResult
    public func add(to routineId: UUID) throws -> Result {
        guard var routine = try repository.routine(id: routineId) else {
            throw TrainingDataError.notFound
        }
        if routine.items.contains(where: { $0.exerciseId == exerciseId }) {
            return .alreadyInRoutine(routineName: routine.name)
        }
        let next = (routine.items.map(\.order).max() ?? 0) + 1
        routine.items.append(RoutineItem(order: next, exerciseId: exerciseId))
        try repository.save(routine)
        load()
        return .added(routineName: routine.name)
    }

    /// Creates a routine named `name` (trimmed) that holds only the exercise.
    /// Throws `invalidRoutine` for a blank name.
    @discardableResult
    public func createRoutine(named name: String) throws -> Routine {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TrainingDataError.invalidRoutine("name is empty")
        }
        let routine = Routine(name: trimmed, items: [RoutineItem(order: 1, exerciseId: exerciseId)])
        try repository.save(routine)
        load()
        return routine
    }

    /// True when `name` can name a new routine.
    public static func isValidName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
