import TNWTrackerKit
import XCTest

/// Page Object for the Home screen.
/// Convention: properties are element queries; functions fire actions and return the next validated screen.
@MainActor
struct HomeScreen {
    let app: XCUIApplication

    // MARK: - Queries

    var quickStartButton: XCUIElement {
        app.buttons[AXID.Home.quickStartButton]
    }

    var settingsButton: XCUIElement {
        app.buttons[AXID.Home.settingsButton]
    }

    // MARK: - Landing

    /// Waits for the Home landing element. Fails the test with a descriptive message if it times out.
    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> Self {
        XCTAssertTrue(
            quickStartButton.waitForExistence(timeout: timeout),
            "HomeScreen did not load: quickStartButton not found within \(timeout)s. "
                + "Possible: auth bypass not active, seed not applied, or router did not pop to root."
        )
        return self
    }

    // MARK: - Transitions

    /// Taps the quick-start button and returns an already-validated ActiveWorkoutScreen.
    func tapQuickStart() -> ActiveWorkoutScreen {
        quickStartButton.tap()
        return ActiveWorkoutScreen(app: app).waitUntilLoaded()
    }
}
