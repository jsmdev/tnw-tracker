import Foundation

/// The user's own settings for one exercise (app-local, not part of the
/// training data format). Saved once and used in every session that has the
/// exercise, routine or free.
public struct ExerciseSetting: Sendable, Equatable {
    public let exerciseId: UUID
    /// "Descanso entre series" on or off. Turning it off keeps `restSeconds`.
    public var restEnabled: Bool
    /// Rest between working sets, in seconds.
    public var restSeconds: Int

    public init(exerciseId: UUID, restEnabled: Bool = true, restSeconds: Int) {
        self.exerciseId = exerciseId
        self.restEnabled = restEnabled
        self.restSeconds = restSeconds
    }
}

/// Which rest starts after a working set.
public enum RestPolicy {
    /// Rest between sets when neither the exercise nor the routine item sets one.
    public static let defaultBetweenSetsSeconds = 90
    /// Step of the −15 s / +15 s controls.
    public static let stepSeconds = 15
    /// Durations the rest editors offer.
    public static let allowedSeconds = 15 ... 600

    /// The exercise's setting in force: the saved one, else rest on with the
    /// routine item's `restSeconds`, else 90 s.
    public static func setting(
        exerciseId: UUID,
        saved: ExerciseSetting?,
        routineRestSeconds: Int?
    ) -> ExerciseSetting {
        saved ?? ExerciseSetting(
            exerciseId: exerciseId,
            restEnabled: true,
            restSeconds: routineRestSeconds ?? defaultBetweenSetsSeconds
        )
    }

    /// Rest between sets in seconds, or nil when the exercise's rest is off.
    public static func restBetweenSets(_ setting: ExerciseSetting) -> Int? {
        setting.restEnabled ? setting.restSeconds : nil
    }
}
