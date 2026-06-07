import Foundation

// MARK: - WorkoutPhase

/// Estados del FSM de un workout activo.
/// Vive en Kit porque es un value type puro compartido entre el coordinator
/// (que lo escribe) y las views (que lo observan).
public enum WorkoutPhase: Sendable, Equatable {
    case idle
    case active
    case restingBetweenSets
    case restingBetweenExercises
    case paused
    case finishing
}

// MARK: - TimerTriggerMode

/// Política de disparo del timer de descanso al registrar un set.
/// - auto: el coordinator dispara el timer automáticamente según el FSM.
/// - manual: el usuario decide cuándo arrancar el timer.
public enum TimerTriggerMode: String, Codable, Sendable {
    case auto
    case manual
}
