import Foundation
@testable import TNWTrackerKit

/// Invented fixtures for the training data tests. Generic names only.
@MainActor
struct TrainingFixtures {
    let store: TrainingStore

    static let provider = "machines-atlas"
    static let zone = TimeZone(identifier: "Europe/Madrid") ?? .gmt
    /// 2030-03-04T09:00:00Z — a fixed instant keeps the tests deterministic.
    static let t0 = Date(timeIntervalSince1970: 1_898_845_200)

    let squat = Exercise(name: "Goblet Squat", type: .strength, equipment: .freeWeights)
    let press = Exercise(
        externalRef: ExternalRef(provider: provider, id: "ex-1"),
        name: "Chest Press Machine", type: .strength, equipment: .connectedMachine
    )
    let plank = Exercise(name: "Plank", type: .bodyweight, equipment: Equipment.none)
    let rower = Exercise(name: "Rowing Machine", type: .cardio, equipment: .cardioMachine)

    init() throws {
        store = try TrainingStore(inMemory: true)
        for exercise in [squat, press, plank, rower] {
            try store.exercises.save(exercise)
        }
    }

    var sessions: any SessionRepositoryProtocol { store.sessions }
    var routines: any RoutineRepositoryProtocol { store.routines }
    var exercises: any ExerciseRepositoryProtocol { store.exercises }

    /// Routine with squat (3 sets, 90 s rest) then press (2 sets).
    func makeRoutine(name: String = "Full Body A") throws -> Routine {
        let routine = Routine(
            name: name,
            items: [
                RoutineItem(order: 1, exerciseId: squat.id, targetSets: 3, restSeconds: 90),
                RoutineItem(order: 2, exerciseId: press.id, targetSets: 2, restSeconds: 60)
            ]
        )
        try routines.save(routine)
        return routine
    }

    func ref(_ id: String) -> ExternalRef {
        ExternalRef(provider: Self.provider, id: id)
    }

    func importedSets(_ entryRef: String, reps: [Int], weight: Double) -> ImportedEntry {
        ImportedEntry(
            exerciseId: press.id,
            externalRef: ref(entryRef),
            sets: reps.enumerated().map { index, value in
                ImportedSet(
                    externalRef: ref("\(entryRef)#\(index + 1)"),
                    order: index + 1,
                    values: SetValues(reps: value, weight: .kg(weight))
                )
            }
        )
    }
}
