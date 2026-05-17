import Foundation

// MARK: - WorkoutPhaseTransition

/// Función pura que decide la transición de fase tras registrar un set.
///
/// Aislar esta decisión del coordinator nos da dos ganancias:
/// 1. La lógica del FSM se puede testear exhaustivamente sin mocks de
///    Supabase, SwiftData, Live Activity, ni timer service.
/// 2. El coordinator queda enfocado en orquestar IO y observar estado.
///
/// El coordinator es responsable de aplicar el `Outcome` (asignar `phase`
/// y disparar el timer si corresponde). Este tipo NO hace IO.
public enum WorkoutPhaseTransition {
    /// Resultado de evaluar la transición. `nil` significa "sin transición"
    /// (caso típico: set de calentamiento o modo manual de timer).
    public struct Outcome: Sendable, Equatable {
        public let nextPhase: WorkoutPhase
        public let restTimer: RestSpec?

        public init(nextPhase: WorkoutPhase, restTimer: RestSpec?) {
            self.nextPhase = nextPhase
            self.restTimer = restTimer
        }
    }

    /// Especificación del descanso que debe arrancar el coordinator.
    public struct RestSpec: Sendable, Equatable {
        public let type: TimerType
        public let durationSeconds: Int

        public init(type: TimerType, durationSeconds: Int) {
            self.type = type
            self.durationSeconds = durationSeconds
        }
    }

    /// Información del set recién registrado.
    public struct SetContext: Sendable, Equatable {
        public let number: Int
        public let isWarmup: Bool

        public init(number: Int, isWarmup: Bool) {
            self.number = number
            self.isWarmup = isWarmup
        }
    }

    /// Contexto del ejercicio actual dentro del workout.
    public struct ExerciseContext: Sendable, Equatable {
        public let target: Int
        public let restSeconds: Int
        public let index: Int
        public let total: Int

        public init(target: Int, restSeconds: Int, index: Int, total: Int) {
            self.target = target
            self.restSeconds = restSeconds
            self.index = index
            self.total = total
        }
    }

    /// Evalúa la transición tras registrar un set.
    ///
    /// - Parameters:
    ///   - set: información del set recién registrado.
    ///   - exercise: contexto del ejercicio actual dentro del workout.
    ///   - triggerMode: política de disparo del timer.
    /// - Returns: `Outcome` con la siguiente fase y el timer opcional,
    ///   o `nil` si no corresponde transicionar (warmup / modo manual).
    public static func evaluate(
        set: SetContext,
        exercise: ExerciseContext,
        triggerMode: TimerTriggerMode
    ) -> Outcome? {
        guard triggerMode == .auto, !set.isWarmup else { return nil }

        let isLastSet = set.number >= exercise.target
        let isLastExercise = exercise.index >= exercise.total - 1

        if isLastSet, isLastExercise {
            return Outcome(nextPhase: .finishing, restTimer: nil)
        }

        if isLastSet {
            return Outcome(
                nextPhase: .restingBetweenExercises,
                restTimer: RestSpec(type: .betweenExercises, durationSeconds: exercise.restSeconds)
            )
        }

        return Outcome(
            nextPhase: .restingBetweenSets,
            restTimer: RestSpec(type: .betweenSets, durationSeconds: exercise.restSeconds)
        )
    }
}
