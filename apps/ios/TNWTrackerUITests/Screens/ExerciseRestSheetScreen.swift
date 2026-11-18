import TNWTrackerKit
import XCTest

/// Page Object for the "Descanso entre series" sheet of the current exercise.
@MainActor
struct ExerciseRestSheetScreen {
    let app: XCUIApplication

    // MARK: - Queries

    var enabledToggle: XCUIElement {
        app.switches[AXID.ExerciseRest.enabledToggle]
    }

    var durationLabel: XCUIElement {
        app.staticTexts[AXID.ExerciseRest.durationLabel]
    }

    var decreaseButton: XCUIElement {
        app.buttons[AXID.ExerciseRest.decreaseButton]
    }

    var increaseButton: XCUIElement {
        app.buttons[AXID.ExerciseRest.increaseButton]
    }

    var doneButton: XCUIElement {
        app.buttons[AXID.ExerciseRest.doneButton]
    }

    /// The shown duration in seconds. The element's label reads it in words
    /// ("90 segundos" / "90 seconds"), so only its number is compared.
    var seconds: Int? {
        Int(durationLabel.label.filter(\.isNumber))
    }

    /// True when the toggle is on.
    var isEnabled: Bool {
        (enabledToggle.value as? String) == "1"
    }

    // MARK: - Landing

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 3) -> Self {
        XCTAssertTrue(
            durationLabel.waitForExistence(timeout: timeout),
            "ExerciseRestSheetScreen did not load: durationLabel not found within \(timeout)s."
        )
        return self
    }

    // MARK: - Interaction helpers

    @discardableResult
    func increase() -> Self {
        increaseButton.tap()
        return self
    }

    @discardableResult
    func decrease() -> Self {
        decreaseButton.tap()
        return self
    }

    /// Flips "Descanso entre series".
    @discardableResult
    func toggle() -> Self {
        // Tapping the switch itself, not its row label.
        enabledToggle.switches.firstMatch.tap()
        return self
    }

    // MARK: - Transitions

    func done() -> ActiveWorkoutScreen {
        doneButton.tap()
        return ActiveWorkoutScreen(app: app).waitUntilLoaded()
    }
}
