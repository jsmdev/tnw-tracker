import TNWTrackerKit
import XCTest

/// Page Object for the Settings screen.
@MainActor
struct SettingsScreen {
    let app: XCUIApplication

    // MARK: - Queries

    var changeExerciseRestToggle: XCUIElement {
        app.switches[AXID.Settings.changeExerciseRestToggle]
    }

    var changeExerciseRestDuration: XCUIElement {
        app.staticTexts[AXID.Settings.changeExerciseRestDurationLabel]
    }

    /// Shown only while the store holds another account's data.
    var syncStatusMessage: XCUIElement {
        app.staticTexts[AXID.Settings.syncStatusMessage]
    }

    var rirMaximumStepper: XCUIElement {
        app.steppers[AXID.Settings.rirMaximumStepper]
    }

    // MARK: - Landing

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 3) -> Self {
        XCTAssertTrue(
            changeExerciseRestToggle.waitForExistence(timeout: timeout),
            "SettingsScreen did not load: changeExerciseRestToggle not found within \(timeout)s."
        )
        return self
    }
}
