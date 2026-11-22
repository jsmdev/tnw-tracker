import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

@Suite("ExerciseRepository")
@MainActor
struct ExerciseRepositoryTests {
    let store: TrainingStore

    init() throws {
        store = try TrainingStore.inMemory()
    }

    private var full: Exercise {
        Exercise(
            externalRef: ExternalRef(provider: "machines-atlas", id: "ex-7"),
            name: "Seated Row Machine",
            type: .strength,
            equipment: .connectedMachine,
            muscleGroups: [
                MuscleGroup(muscle: .back, role: .primary),
                MuscleGroup(muscle: .biceps, role: .secondary)
            ],
            instructions: ExerciseInstructions(
                setup: ["Adjust the seat."],
                execution: ["Pull.", "Release."],
                tips: ["Slow."]
            ),
            media: ExerciseMedia(imageURI: "exercises/row.jpg", videoURI: "https://media.example/row.mp4"),
            relatedVideos: [
                RelatedVideo(title: "Setup", url: "https://video.example/a", source: "Example"),
                RelatedVideo(title: "Range", url: "https://video.example/b", source: "Example")
            ]
        )
    }

    @Test("every format field survives a save and a fetch from a fresh context")
    func roundTripAllFields() throws {
        let exercise = full
        try store.exercises.save(exercise)

        let fresh = SwiftDataExerciseRepository(context: ModelContext(store.container))
        let loaded = try #require(try fresh.exercise(id: exercise.id))
        #expect(loaded == exercise)
    }

    @Test("an exercise with only the required fields keeps the optional ones unknown")
    func optionalFieldsStayUnknown() throws {
        let minimal = Exercise(name: "Unknown activity", type: .cardio)
        try store.exercises.save(minimal)
        let loaded = try #require(try store.exercises.exercise(id: minimal.id))
        #expect(loaded.equipment == nil)
        #expect(loaded.muscleGroups.isEmpty)
        #expect(loaded.instructions == nil)
        #expect(loaded.media == nil)
        #expect(loaded.relatedVideos == nil)
        #expect(loaded.externalRef == nil)
    }

    @Test("#182 S9 related videos are kept when a save does not state them, replaced or cleared when it does")
    func relatedVideosOptionalMeansUnknown() throws {
        let base = full
        try store.exercises.save(base)

        var unstated = base
        unstated.relatedVideos = nil
        unstated.name = "Row"
        try store.exercises.save(unstated)
        let kept = try #require(try store.exercises.exercise(id: base.id))
        #expect(kept.name == "Row")
        #expect(kept.relatedVideos == base.relatedVideos, "a save without the field keeps them")

        var replaced = base
        replaced.relatedVideos = [RelatedVideo(title: "Grip", url: "https://video.example/c", source: "Example")]
        try store.exercises.save(replaced)
        #expect(try store.exercises.exercise(id: base.id)?.relatedVideos == replaced.relatedVideos)

        var cleared = base
        cleared.relatedVideos = []
        try store.exercises.save(cleared)
        #expect(try store.exercises.exercise(id: base.id)?.relatedVideos == nil, "an empty list clears them")
    }

    @Test("saving an existing id replaces its values and muscle groups")
    func saveReplaces() throws {
        var exercise = full
        try store.exercises.save(exercise)
        exercise.name = "Row"
        exercise.muscleGroups = [MuscleGroup(muscle: .back, role: .primary)]
        try store.exercises.save(exercise)

        let all = try store.exercises.exercises()
        #expect(all.count == 1)
        #expect(all.first?.name == "Row")
        #expect(all.first?.muscleGroups == [MuscleGroup(muscle: .back, role: .primary)])
    }

    @Test("two exercises cannot share an externalRef")
    func externalRefIsUnique() throws {
        try store.exercises.save(full)
        let other = Exercise(externalRef: full.externalRef, name: "Copy", type: .strength)
        #expect(throws: TrainingDataError.duplicateExternalRef) {
            try store.exercises.save(other)
        }
    }

    @Test("an empty name is rejected")
    func emptyNameRejected() {
        #expect(throws: TrainingDataError.self) {
            try store.exercises.save(Exercise(name: "", type: .strength))
        }
    }

    @Test("an exercise is imported exactly when it has an externalRef")
    func isImportedFollowsExternalRef() {
        #expect(full.isImported == true)
        #expect(Exercise(name: "Plank", type: .bodyweight).isImported == false)
        #expect(Exercise(isCatalogue: true, name: "Plank", type: .bodyweight).isImported == false)
    }

    @Test("isCatalogue defaults to false and survives a save and a fetch from a fresh context")
    func isCataloguePersists() throws {
        #expect(Exercise(name: "Plank", type: .bodyweight).isCatalogue == false)
        let catalogue = Exercise(isCatalogue: true, name: "Back Squat", type: .strength, equipment: .freeWeights)
        let own = Exercise(name: "Plank", type: .bodyweight)
        try store.exercises.save(catalogue)
        try store.exercises.save(own)

        let fresh = SwiftDataExerciseRepository(context: ModelContext(store.container))
        #expect(try fresh.exercise(id: catalogue.id)?.isCatalogue == true)
        #expect(try fresh.exercise(id: own.id)?.isCatalogue == false)
        #expect(try fresh.exercise(id: catalogue.id) == catalogue)
    }

    @Test("a catalogue exercise with an externalRef is rejected and nothing is saved")
    func catalogueWithExternalRefRejected() throws {
        var invalid = full
        invalid.isCatalogue = true
        #expect(throws: TrainingDataError.invalidExercise("a catalogue exercise has no externalRef")) {
            try store.exercises.save(invalid)
        }
        let fresh = SwiftDataExerciseRepository(context: ModelContext(store.container))
        #expect(try fresh.exercises().isEmpty)
        #expect(try store.exercises.exercises().isEmpty)
    }

    @Test("exercises are listed by name")
    func listedByName() throws {
        try store.exercises.save(Exercise(name: "Plank", type: .bodyweight))
        try store.exercises.save(Exercise(name: "Bench Press", type: .strength))
        #expect(try store.exercises.exercises().map(\.name) == ["Bench Press", "Plank"])
    }
}
