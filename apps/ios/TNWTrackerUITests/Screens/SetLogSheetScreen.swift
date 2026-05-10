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

    /// Taps the reps field and types the given value. Returns self for chaining.
    @discardableResult
    func enterReps(_ value: Int) -> Self {
        repsField.tap()
        repsField.typeText(String(value))
        return self
    }

    /// Taps the weight field and types the given value. Returns self for chaining.
    @discardableResult
    func enterWeight(_ value: Double) -> Self {
        weightField.tap()
        weightField.typeText(String(value))
        return self
    }

    // MARK: - Transitions

    /// Taps the save button and returns an already-validated ActiveWorkoutScreen.
    func save() -> ActiveWorkoutScreen {
        saveButton.tap()
        return ActiveWorkoutScreen(app: app).waitUntilLoaded()
    }

    /// Taps the cancel button and returns an already-validated ActiveWorkoutScreen.
    func cancel() -> ActiveWorkoutScreen {
        cancelButton.tap()
        return ActiveWorkoutScreen(app: app).waitUntilLoaded()
    }
}
