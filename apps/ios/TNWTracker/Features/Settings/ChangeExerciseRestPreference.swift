import Foundation
import TNWTrackerKit

/// "Descanso al cambiar de ejercicio": one general app preference (not part of
/// the training data format). It starts after the last working set of an
/// exercise that is not the last one.
struct ChangeExerciseRestPreference {
    static let enabledKey = "settings.changeExerciseRestEnabled"
    static let secondsKey = "settings.changeExerciseRestSeconds"
    static let defaultEnabled = true
    static let defaultSeconds = 120

    let defaults: UserDefaults

    /// On unless the user turned it off. A missing key means the default.
    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? Self.defaultEnabled
    }

    /// The duration, kept while the rest is off.
    var seconds: Int {
        let stored = defaults.object(forKey: Self.secondsKey) as? Int ?? Self.defaultSeconds
        return min(max(stored, RestPolicy.allowedSeconds.lowerBound), RestPolicy.allowedSeconds.upperBound)
    }

    /// The rest that starts when changing exercise, or nil when it is off.
    var restSeconds: Int? {
        isEnabled ? seconds : nil
    }
}
