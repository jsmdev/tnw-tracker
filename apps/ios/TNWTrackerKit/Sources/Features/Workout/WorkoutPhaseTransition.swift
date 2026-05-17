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

    /// Evalúa la transición tras registrar un set.
    ///
    /// - Parameters:
    ///   - setNumber: número 1-indexed del set recién registrado.
    ///   - target: cantidad de sets objetivo para el ejercicio actual.
    ///   - restSeconds: duración del descanso configurado para el ejercicio.
    ///   - currentExerciseIndex: índice 0-indexed del ejercicio actual.
    ///   - totalExercises: cantidad total de ejercicios en el workout.
    ///   - isWarmup: si el set registrado es de calentamiento.
    ///   - triggerMode: política de disparo del timer.
    /// - Returns: `Outcome` con la siguiente fase y el timer opcional,
    ///   o `nil` si no corresponde transicionar (warmup / modo manual).
    public static func evaluate(
        setNumber: Int,
        target: Int,
        restSeconds: Int,
        currentExerciseIndex: Int,
        totalExercises: Int,
        isWarmup: Bool,
        triggerMode: TimerTriggerMode
    ) -> Outcome? {
        guard triggerMode == .auto, !isWarmup else { return nil }

        let isLastSet = setNumber >= target
        let isLastExercise = currentExerciseIndex >= totalExercises - 1

        if isLastSet, isLastExercise {
            return Outcome(nextPhase: .finishing, restTimer: nil)
        }

        if isLastSet {
            return Outcome(
                nextPhase: .restingBetweenExercises,
                restTimer: RestSpec(type: .betweenExercises, durationSeconds: restSeconds)
            )
        }

        return Outcome(
            nextPhase: .restingBetweenSets,
            restTimer: RestSpec(type: .betweenSets, durationSeconds: restSeconds)
        )
    }
}
