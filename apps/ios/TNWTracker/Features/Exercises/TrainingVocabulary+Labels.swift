import Foundation
import TNWTrackerKit

// Display names of the format's vocabulary (S6): every one in the string
// catalog, in English and Spanish.

extension ExerciseType {
    var label: LocalizedStringResource {
        switch self {
        case .strength: "exercise-type.strength"
        case .bodyweight: "exercise-type.bodyweight"
        case .cardio: "exercise-type.cardio"
        }
    }
}

extension Equipment {
    var label: LocalizedStringResource {
        switch self {
        case .none: "equipment.none"
        case .freeWeights: "equipment.free-weights"
        case .machine: "equipment.machine"
        case .connectedMachine: "equipment.connected-machine"
        case .cardioMachine: "equipment.cardio-machine"
        case .other: "equipment.other"
        }
    }
}

extension Muscle {
    var label: LocalizedStringResource {
        switch self {
        case .chest: "muscle.chest"
        case .back: "muscle.back"
        case .shoulders: "muscle.shoulders"
        case .biceps: "muscle.biceps"
        case .triceps: "muscle.triceps"
        case .forearms: "muscle.forearms"
        case .core: "muscle.core"
        case .glutes: "muscle.glutes"
        case .quadriceps: "muscle.quadriceps"
        case .hamstrings: "muscle.hamstrings"
        case .calves: "muscle.calves"
        case .hips: "muscle.hips"
        case .neck: "muscle.neck"
        }
    }
}
