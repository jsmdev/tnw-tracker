import Foundation
import TNWTrackerKit

extension ActiveWorkoutCoordinator {
    /// The exercise's "Descanso entre series" in force: the saved setting, else
    /// on with the routine item's rest, else 90 s.
    public func restSetting(for exerciseId: UUID) -> ExerciseSetting {
        let saved = try? exerciseSettings.setting(exerciseId: exerciseId)
        let routineRest = targets[exerciseId]?.restSeconds
            ?? entries.first { $0.exerciseId == exerciseId }.flatMap { target(for: $0)?.restSeconds }
        return RestPolicy.setting(exerciseId: exerciseId, saved: saved, routineRestSeconds: routineRest)
    }

    /// Saves the exercise's "Descanso entre series" for this and every later session.
    public func saveRestSetting(_ setting: ExerciseSetting) throws {
        try exerciseSettings.save(setting)
    }

    /// −15 s / +15 s on the running rest, the same for both timers.
    public func adjustTimer(by seconds: Int) async {
        await timerService.extend(by: seconds)
        publishLiveActivity()
    }

    /// The user's warm-up annotation on a logged set of the session.
    public func setWarmup(_ warmup: Bool, setId: UUID) throws {
        try sessions.setWarmup(warmup, setId: setId)
        try refreshSession()
        publishLiveActivity()
    }
}
