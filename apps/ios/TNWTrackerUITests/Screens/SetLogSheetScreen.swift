import TNWTrackerKit
import XCTest

/// Page Object for the Set Log sheet.
@MainActor
struct SetLogSheetScreen {
    let app: XCUIApplication

    // MARK: - Queries

    var repsField: XCUIElement {
        app.textFields[AXID.SetLog.repsField]
    }

    var weightField: XCUIElement {
        app.textFields[AXID.SetLog.weightField]
    }

    var saveButton: XCUIElement {
        app.buttons[AXID.SetLog.saveButton]
    }

    var cancelButton: XCUIElement {
        app.buttons[AXID.SetLog.cancelButton]
    }

    // MARK: - Landing

    /// Waits for repsField — the first interactive element when the sheet is fully presented.
    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 3) -> Self {
        XCTAssertTrue(
            repsField.waitForExistence(timeout: timeout),
            "SetLogSheetScreen did not load: repsField not found within \(timeout)s."
        )
        return self
    }

    // MARK: - Interaction helpers

    /// Taps the reps field and types the given value over any prefill. Returns self for chaining.
    @discardableResult
    func enterReps(_ value: Int) -> Self {
        replaceText(of: repsField, with: String(value))
        return self
    }

    /// Taps the weight field and types the given value over any prefill. Returns self for chaining.
    @discardableResult
    func enterWeight(_ value: Double) -> Self {
        replaceText(of: weightField, with: String(value))
        return self
    }

    /// The field's text, empty while it shows its placeholder.
    func value(of field: XCUIElement) -> String {
        let text = field.value as? String ?? ""
        return text == field.placeholderValue ? "" : text
    }

    /// Types over a field that may come prefilled (fast-add-exercise S3).
    /// Focusing a prefilled field selects its text, so typing replaces it.
    private func replaceText(of field: XCUIElement, with text: String) {
        field.tap()
        field.typeText(text)
        XCTAssertEqual(value(of: field), text, "typing did not replace the field's value")
    }

    // MARK: - Transitions

    /// Taps the save button and returns an already-validated ActiveWorkoutScreen.
    func save() -> ActiveWorkoutScreen {
        saveButton.tap()
        return ActiveWorkoutScreen(app: app).waitUntilLoaded()
    }

    /// Taps the save button when the set starts a rest; returns the validated RestTimerScreen.
    func saveStartingRest() -> RestTimerScreen {
        saveButton.tap()
        return RestTimerScreen(app: app).waitUntilLoaded()
    }

    /// Taps the cancel button and returns an already-validated ActiveWorkoutScreen.
    func cancel() -> ActiveWorkoutScreen {
        cancelButton.tap()
        return ActiveWorkoutScreen(app: app).waitUntilLoaded()
    }
}
