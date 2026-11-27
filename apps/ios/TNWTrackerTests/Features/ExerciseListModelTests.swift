import Foundation
import Testing
@testable import TNWTrackerKit

/// #137 S7, T2b: the exercises screen lists the exercises of the account's
/// local store, its own and the catalogue's, sorted by name, and each opens
/// its sheet. Invented data only.
@Suite("Exercise list (#137 S7)")
@MainActor
struct ExerciseListModelTests {
    @Test("S7 the list shows own and catalogue exercises sorted by name, whatever their case")
    func listIsSortedByName() throws {
        let store = try TrainingStore.inMemory()
        let names = ["rowing Machine", "Air Bike", "bench Press", "Calf Raise"]
        for (index, name) in names.enumerated() {
            try store.exercises.save(Exercise(isCatalogue: index.isMultiple(of: 2), name: name, type: .strength))
        }
        let model = ExerciseListModel(exercises: store.exercises)

        model.load()

        #expect(model.exercises.map(\.name) == ["Air Bike", "bench Press", "Calf Raise", "rowing Machine"])
        #expect(model.exercises.filter(\.isCatalogue).count == 2, "the catalogue's are listed too")
        #expect(!model.loadFailed)
    }

    @Test("S7 an empty store lists nothing")
    func emptyList() throws {
        let model = try ExerciseListModel(exercises: TrainingStore.inMemory().exercises)

        model.load()

        #expect(model.exercises.isEmpty)
        #expect(!model.loadFailed)
    }
}
