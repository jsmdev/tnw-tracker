import Foundation
import Testing
@testable import TNWTrackerKit

/// #137 S7: the exercise sheet shows the video, else the image, else a neutral
/// placeholder, then the name, the equipment, the muscles by role and how to
/// do it (setup steps, then execution steps), as stored. Invented data only.
@Suite("Exercise sheet (#137 S7)")
@MainActor
final class ExerciseSheetTests {
    let root: URL
    let user = UUID()

    init() throws {
        root = try InventedMedia.folder()
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func library(_ source: RecordingMediaSource) -> ExerciseMediaLibrary {
        ExerciseMediaLibrary(store: ExerciseMediaStore(folder: root, source: source))
    }

    private func exercise(image: String? = nil, video: String? = nil) -> Exercise {
        Exercise(
            name: "Cable Row", type: .strength, equipment: .machine,
            media: image == nil && video == nil ? nil : ExerciseMedia(imageURI: image, videoURI: video)
        )
    }

    // MARK: - Content

    @Test("S7 the sheet shows the steps and the muscles by role, as stored")
    func sheetShowsStepsAndMuscles() throws {
        let squat = try #require(
            SampleTrainingData.exercises.first { $0.id == SampleTrainingData.ExerciseID.gobletSquat }
        )

        let content = ExerciseSheetContent(squat)

        #expect(content.name == "Goblet Squat")
        #expect(content.type == .strength)
        #expect(content.equipment == .freeWeights)
        #expect(content.primaryMuscles == [.quadriceps])
        #expect(content.secondaryMuscles == [.glutes])
        #expect(content.setupSteps == ["Hold the weight close to the chest."])
        #expect(content.executionSteps == ["Sit down between the knees.", "Stand up tall."])
        #expect(!content.hasNoSteps)
        #expect(content.imagePath == nil && content.videoPath == nil)
    }

    @Test("S7 an exercise with no steps says so; its media paths are the stored object paths")
    func sheetWithoutSteps() {
        let image = InventedMedia.path(user: user, file: "photo.png")
        let video = InventedMedia.path(user: user, file: "clip.mp4")
        let content = ExerciseSheetContent(Exercise(
            name: "Cable Row", type: .strength,
            muscleGroups: [.init(muscle: .back, role: .primary), .init(muscle: .biceps, role: .primary)],
            media: ExerciseMedia(imageURI: image, videoURI: video)
        ))

        #expect(content.hasNoSteps)
        #expect(content.primaryMuscles == [.back, .biceps], "in their stored order")
        #expect(content.secondaryMuscles.isEmpty)
        #expect(content.imagePath == image)
        #expect(content.videoPath == video)
    }

    // MARK: - Hero

    @Test("S7 with a video and an image, the hero plays the video from its local file")
    func heroShowsTheVideo() async throws {
        let image = InventedMedia.path(user: user, file: "photo.png")
        let video = InventedMedia.path(user: user, file: "clip.mp4")
        let source = RecordingMediaSource([image: InventedMedia.png(), video: InventedMedia.mp4()])
        let hero = ExerciseHeroModel(
            content: ExerciseSheetContent(exercise(image: image, video: video)), library: library(source)
        )

        await hero.load()

        let file = try #require(hero.videoFile)
        #expect(try Data(contentsOf: file) == InventedMedia.mp4())
        #expect(hero.image != nil, "the image is there too")
        #expect(hero.placeholder == nil)
        #expect(hero.videoNotice == nil)
        #expect(!hero.isLoading)
        #expect(Set(source.requests) == [image, video])
    }

    @Test("S7 the video unavailable offline: the hero falls back to the image and says why the video is missing")
    func heroFallsBackToTheImage() async throws {
        let image = InventedMedia.path(user: user, file: "photo.png")
        let video = InventedMedia.path(user: user, file: "clip.mp4")
        let online = RecordingMediaSource([image: InventedMedia.png()])
        _ = try await library(online).image(path: image)
        let offline = RecordingMediaSource()
        offline.goOffline()
        let hero = ExerciseHeroModel(
            content: ExerciseSheetContent(exercise(image: image, video: video)), library: library(offline)
        )

        await hero.load()

        #expect(hero.videoFile == nil)
        #expect(hero.image != nil)
        #expect(hero.placeholder == nil)
        #expect(hero.videoNotice == .offline)
    }

    @Test("S7 the placeholder says why: no media, offline before the first download, or a failed download")
    func heroPlaceholder() async throws {
        let image = InventedMedia.path(user: user, file: "photo.png")
        let video = InventedMedia.path(user: user, file: "clip.mp4")

        let none = ExerciseHeroModel(
            content: ExerciseSheetContent(exercise()), library: library(RecordingMediaSource())
        )
        await none.load()
        #expect(none.placeholder == ExerciseMediaLibrary.Unavailable.none)
        #expect(none.image == nil && none.videoFile == nil)

        let offlineSource = RecordingMediaSource()
        offlineSource.goOffline()
        let offline = ExerciseHeroModel(
            content: ExerciseSheetContent(exercise(image: image, video: video)), library: library(offlineSource)
        )
        await offline.load()
        #expect(offline.placeholder == .offline)
        #expect(offline.videoNotice == nil)

        let refusing = RecordingMediaSource()
        refusing.fail(with: RemoteSessionError.notSignedInAsAccount)
        let failed = ExerciseHeroModel(
            content: ExerciseSheetContent(exercise(image: image)), library: library(refusing)
        )
        await failed.load()
        #expect(failed.placeholder == .failed)
        #expect(failed.imageUnavailable == .failed)
    }
}
