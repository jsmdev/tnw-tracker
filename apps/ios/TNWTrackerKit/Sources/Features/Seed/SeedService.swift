#if DEBUG
    import Foundation
    import SwiftData

    /// Inserta datos canónicos de desarrollo en el store.
    /// Solo existe en builds DEBUG. Nunca llames esto en producción.
    public enum SeedService {
        // MARK: - Public API

        /// Inserta datos solo si el store está vacío (idempotente).
        public static func seedIfNeeded(context: ModelContext) throws {
            let existing = try context.fetch(FetchDescriptor<Plan>())
            guard existing.isEmpty else { return }
            try seed(context: context)
        }

        /// Borra todos los datos de entrenamiento y re-siembra desde cero.
        public static func reseed(context: ModelContext) throws {
            try deleteAll(context: context)
            try seed(context: context)
        }

        // MARK: - Private

        private static func seed(context: ModelContext) throws {
            // Dummy userId para seed data — no se sincroniza con backend en DEBUG
            let devUserId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

            // Ejercicios canónicos (7)
            let squat = Exercise(name: "Squat", category: "strength")
            let deadlift = Exercise(name: "Deadlift", category: "strength")
            let bench = Exercise(name: "Bench Press", category: "strength")
            let ohp = Exercise(name: "Overhead Press", category: "strength")
            let row = Exercise(name: "Bent-Over Row", category: "strength")
            let pullUp = Exercise(name: "Pull-Up", category: "strength")
            let rdl = Exercise(name: "Romanian Deadlift", category: "strength")

            for ex in [squat, deadlift, bench, ohp, row, pullUp, rdl] {
                context.insert(ex)
            }

            // Plan
            let plan = Plan(userId: devUserId, name: "Push Pull Legs")
            context.insert(plan)

            // Rutinas
            let push = Routine(userId: devUserId, name: "Push Day")
            let pull = Routine(userId: devUserId, name: "Pull Day")
            let legs = Routine(userId: devUserId, name: "Legs Day")

            for routine in [push, pull, legs] {
                context.insert(routine)
            }

            // PlanRoutines — vinculan plan ↔ rutinas
            for (idx, routine) in [push, pull, legs].enumerated() {
                let pr = PlanRoutine(planId: plan.id, routineId: routine.id, orderIndex: idx)
                context.insert(pr)
            }

            // Sessions (templates) y RoutineSessions
            let pushSession = makeSession(
                userId: devUserId,
                name: "Push Day",
                exercises: [(bench, 0), (ohp, 1)],
                context: context
            )
            let pullSession = makeSession(
                userId: devUserId,
                name: "Pull Day",
                exercises: [(row, 0), (pullUp, 1)],
                context: context
            )
            let legsSession = makeSession(
                userId: devUserId,
                name: "Legs Day",
                exercises: [(squat, 0), (deadlift, 1), (rdl, 2)],
                context: context
            )

            for (idx, (routine, session)) in [(push, pushSession), (pull, pullSession), (legs, legsSession)]
                .enumerated()
            {
                let rs = RoutineSession(routineId: routine.id, sessionId: session.id, orderIndex: idx)
                context.insert(rs)
            }

            try context.save()
        }

        private static func makeSession(
            userId: UUID,
            name: String,
            exercises: [(Exercise, Int)],
            context: ModelContext
        ) -> Session {
            let session = Session(userId: userId, name: name)
            context.insert(session)
            for (exercise, idx) in exercises {
                let se = SessionExercise(sessionId: session.id, exerciseId: exercise.id, orderIndex: idx)
                se.targetSets = 3
                se.targetReps = 10
                se.restBetweenSetsSeconds = 90
                context.insert(se)
            }
            return session
        }

        private static func deleteAll(context: ModelContext) throws {
            try context.delete(model: RoutineSession.self)
            try context.delete(model: SessionExercise.self)
            try context.delete(model: Session.self)
            try context.delete(model: PlanRoutine.self)
            try context.delete(model: Routine.self)
            try context.delete(model: Plan.self)
            try context.delete(model: Exercise.self)
            try context.save()
        }
    }
#endif
