import Foundation

// Neutral vocabulary of the training data format (docs/training-data-format.md).
// Raw values are the exact strings of docs/training-data/schema.json, so the
// app, the database (#133) and any importer share one spelling.

/// How an exercise is logged. Format field `exercise.type`.
public enum ExerciseType: String, Codable, CaseIterable, Sendable {
    case strength
    case bodyweight
    case cardio
}

/// Format field `exercise.equipment`.
public enum Equipment: String, Codable, CaseIterable, Sendable {
    case none
    case freeWeights = "free_weights"
    case machine
    case connectedMachine = "connected_machine"
    case cardioMachine = "cardio_machine"
    case other
}

/// Format field `exercise.muscleGroups[].muscle` (O14: thirteen groups).
public enum Muscle: String, Codable, CaseIterable, Sendable {
    case chest, back, shoulders, biceps, triceps, forearms, core
    case glutes, quadriceps, hamstrings, calves, hips, neck
}

/// Format field `exercise.muscleGroups[].role`.
public enum MuscleRole: String, Codable, CaseIterable, Sendable {
    case primary
    case secondary
}

/// Format field `entry.status`.
public enum EntryStatus: String, Codable, CaseIterable, Sendable {
    /// Performed. Has at least one set once the session is completed.
    case done
    /// In the session but not performed. Has no sets.
    case skipped
    /// Taken out of the session by the user. Its sets stay stored and do not count.
    case removed
}

/// Format field `set.source` and `reconciliation.keep`.
public enum SetSource: String, Codable, CaseIterable, Sendable {
    /// Logged by hand in this app.
    case manual
    /// Arrived through an import.
    case imported
}

/// Format field `reconciliation.decidedBy`.
public enum ReconciliationDecider: String, Codable, CaseIterable, Sendable {
    case `default`
    case user
}

/// Format type `externalRef`: identity of an item in the system it was imported from.
public struct ExternalRef: Hashable, Codable, Sendable {
    /// Format pattern of `provider`: a lower-case slug such as `machines-atlas`.
    public var isValid: Bool {
        !id.isEmpty && provider.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil
    }

    /// Opaque provider slug, for example `machines-atlas`.
    public var provider: String
    public var id: String

    public init(provider: String, id: String) {
        self.provider = provider
        self.id = id
    }
}

/// Format type `weight`. A value of zero is a real load of zero.
public struct Weight: Hashable, Codable, Sendable {
    public var value: Double
    public var unit: WeightUnit

    public init(value: Double, unit: WeightUnit) {
        self.value = value
        self.unit = unit
    }

    public static func kg(_ value: Double) -> Weight {
        Weight(value: value, unit: .kg)
    }

    /// The load in kilograms, for totals that mix units.
    public var kilograms: Double {
        switch unit {
        case .kg: value
        case .lb: value * 0.453_592_37
        }
    }
}

/// Format type `routineItem.targetReps`.
public struct RepRange: Hashable, Codable, Sendable {
    public var min: Int
    public var max: Int

    public init(min: Int, max: Int) {
        self.min = min
        self.max = max
    }
}

/// Errors raised when a write would break a rule of the format.
public enum TrainingDataError: Error, Equatable, Sendable {
    case notFound
    case invalidExercise(String)
    case invalidRoutine(String)
    case invalidSet(String)
    case invalidSession(String)
    case invalidExternalRef
    case duplicateExternalRef
    case sessionAlreadyCompleted
    case entryNotMixed
    case entryHasSets
}
