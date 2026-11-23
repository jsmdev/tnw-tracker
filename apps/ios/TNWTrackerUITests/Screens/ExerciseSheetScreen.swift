import TNWTrackerKit
import XCTest

/// Page Object for the exercise sheet (`ExerciseSheetView`, #137 S7).
@MainActor
struct ExerciseSheetScreen {
    let app: XCUIApplication

    var name: XCUIElement {
        app.staticTexts[AXID.ExerciseSheet.name]
    }

    var closeButton: XCUIElement {
        app.buttons[AXID.ExerciseSheet.closeButton]
    }

    var image: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.image]
    }

    var placeholder: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.placeholder]
    }

    var videoToggle: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.videoToggle].firstMatch
    }

    var video: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.video]
    }

    /// Opens or closes the "Watch video" section.
    func toggleVideo() {
        let button = app.buttons.matching(
            NSPredicate(format: "identifier == %@", AXID.ExerciseSheet.videoToggle)
        ).firstMatch
        (button.exists ? button : videoToggle).tap()
    }

    var relatedVideos: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.relatedVideos].firstMatch
    }

    /// The `number`th related video's row, from 1.
    func relatedVideo(_ number: Int) -> XCUIElement {
        app.buttons[AXID.ExerciseSheet.relatedVideo(number)]
    }

    /// "Abrir en YouTube" under the `number`th related video, from 1.
    func openInYouTube(_ number: Int) -> XCUIElement {
        app.buttons[AXID.ExerciseSheet.relatedVideoOpen(number)]
    }

    var relatedVideoPlayer: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.relatedVideoPlayer].firstMatch
    }

    var primaryMuscles: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.primaryMuscles]
    }

    func setupStep(_ number: Int) -> XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.setupStep(number)]
    }

    func executionStep(_ number: Int) -> XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.executionStep(number)]
    }

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> Self {
        XCTAssertTrue(
            name.waitForExistence(timeout: timeout),
            "ExerciseSheetScreen did not load: the exercise name was not found within \(timeout)s."
        )
        return self
    }

    func close() -> ExerciseListScreen {
        closeButton.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5), "The exercise sheet did not close.")
        return ExerciseListScreen(app: app)
    }
}
