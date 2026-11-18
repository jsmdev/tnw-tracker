import Foundation
import SwiftData

/// The app's local training store: one SwiftData container and the repositories
/// built on it. It is the only thing the app target needs to know about
/// persistence; nothing outside this module touches `ModelContext`.
@MainActor
public final class TrainingStore {
    public let container: ModelContainer
    public let exercises: any ExerciseRepositoryProtocol
    public let routines: any RoutineRepositoryProtocol
    public let sessions: any SessionRepositoryProtocol
    public let importer: any TrainingImporterProtocol
    public let intentInbox: IntentInbox

    let context: ModelContext

    public convenience init(inMemory: Bool = false) throws {
        try self.init(container: ModelContainerFactory.makeContainer(inMemory: inMemory))
    }

    public init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
        exercises = SwiftDataExerciseRepository(context: context)
        routines = SwiftDataRoutineRepository(context: context)
        let sessionRepository = SwiftDataSessionRepository(context: context)
        sessions = sessionRepository
        importer = SwiftDataTrainingImporter(context: context, sessions: sessionRepository)
        intentInbox = IntentInbox(context: context)
    }

    /// Deletes every exercise, routine and session. Intent events are kept.
    /// Rows are deleted one by one: batch deletes do not support the `deny` rules.
    public func deleteAllTrainingData() throws {
        for session in try context.fetch(FetchDescriptor<SessionModel>()) {
            context.delete(session)
        }
        for routine in try context.fetch(FetchDescriptor<RoutineModel>()) {
            context.delete(routine)
        }
        try context.save()
        for exercise in try context.fetch(FetchDescriptor<ExerciseModel>()) {
            context.delete(exercise)
        }
        try context.save()
    }

    /// True when the store holds no exercise.
    public func isEmpty() throws -> Bool {
        try context.fetchCount(FetchDescriptor<ExerciseModel>()) == 0
    }
}

/// Reads the intent events the widget process writes through `IntentMailbox`.
@MainActor
public final class IntentInbox {
    private let context: ModelContext
    private let container: ModelContainer

    init(context: ModelContext) {
        self.context = context
        container = context.container
    }

    public convenience init(container: ModelContainer) {
        self.init(context: container.mainContext)
    }

    /// Hands every unconsumed event of `workoutId` to `handle`, oldest first,
    /// and marks each one consumed. Events of other workouts are left untouched.
    /// Safe to call repeatedly.
    public func drain(workoutId: UUID, handle: (String) async throws -> Void) async throws {
        var descriptor = FetchDescriptor<WorkoutIntentEvent>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.predicate = #Predicate { $0.consumedAt == nil }
        let events = try context.fetch(descriptor)
        for event in events where event.workoutId == workoutId {
            try await handle(event.kind)
            event.consumedAt = Date()
        }
        try context.save()
    }
}
