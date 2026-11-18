import Foundation

/// The target of a routine item as the routine detail shows it (T8, D9).
enum TargetRepsFormat {
    /// "3 × 8–12" for a range, "3 × 10" when both bounds are equal or only one is
    /// set; nil without reps. The same in every language: numbers and symbols only.
    static func setsReps(sets: Int, minReps: Int?, maxReps: Int?) -> String? {
        guard let reps = minReps ?? maxReps else { return nil }
        guard let minReps, let maxReps, minReps != maxReps else { return "\(sets) × \(reps)" }
        return "\(sets) × \(minReps)–\(maxReps)"
    }

    /// What VoiceOver reads for `setsReps`: words instead of "×" and "–".
    static func accessibilityLabel(sets: Int, minReps: Int?, maxReps: Int?) -> String? {
        guard let reps = minReps ?? maxReps else { return nil }
        guard let minReps, let maxReps, minReps != maxReps else {
            return String(format: String(localized: "session-detail.sets-reps"), sets, reps)
        }
        return String(format: String(localized: "session-detail.sets-reps-range"), sets, minReps, maxReps)
    }
}
