import Foundation

public enum PRRecordType: String, Codable, CaseIterable, Sendable {
    case maxWeight = "max_weight"
    case maxReps = "max_reps"
    case maxVolume = "max_volume"
}
