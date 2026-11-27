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
    /// The first tap only focuses the field; a second tap on its right edge puts
    /// the cursor after the right-aligned text, so deleting its characters clears it.
    private func replaceText(of field: XCUIElement, with text: String) {
        field.tap()
        let current = value(of: field)
        if !current.isEmpty {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        }
        if !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
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
