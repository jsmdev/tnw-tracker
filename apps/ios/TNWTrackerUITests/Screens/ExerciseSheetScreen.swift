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
