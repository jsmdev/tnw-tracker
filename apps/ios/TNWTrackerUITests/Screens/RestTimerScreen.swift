import TNWTrackerKit
import XCTest

/// Page Object for the Rest Timer screen (SHOULD-level — appears between sets if rest timer is enabled).
@MainActor
struct RestTimerScreen {
    let app: XCUIApplication

    // MARK: - Queries

    var timerLabel: XCUIElement {
        app.staticTexts[AXID.RestTimer.timerLabel]
    }

    var skipButton: XCUIElement {
        app.buttons[AXID.RestTimer.skipButton]
    }

    // MARK: - Landing

    /// Waits for the timer label to confirm the rest timer sheet is fully presented.
    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 3) -> Self {
        XCTAssertTrue(
            timerLabel.waitForExistence(timeout: timeout),
            "RestTimerScreen did not load: timerLabel not found within \(timeout)s."
        )
        return self
    }

    // MARK: - Transitions

    /// Taps skip and returns an already-validated ActiveWorkoutScreen.
    func tapSkip() -> ActiveWorkoutScreen {
        skipButton.tap()
        return ActiveWorkoutScreen(app: app).waitUntilLoaded()
    }
}
