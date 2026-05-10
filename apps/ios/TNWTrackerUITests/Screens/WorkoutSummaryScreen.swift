import TNWTrackerKit
import XCTest

/// Page Object for the Workout Summary screen.
/// BUG-2 coverage: if the nested fullScreenCover chain is broken, waitUntilLoaded times out.
/// BUG-4 coverage: assertWorkoutNameVisible verifies the workout name is not empty/fallback.
@MainActor
struct WorkoutSummaryScreen {
    let app: XCUIApplication

    // MARK: - Queries

    /// Maps to AXID.Summary.workoutNameLabel (W1: use workoutNameLabel, not title).
    var workoutNameLabel: XCUIElement {
        app.staticTexts[AXID.Summary.workoutNameLabel]
    }

    var closeButton: XCUIElement {
        app.buttons[AXID.Summary.closeButton]
    }

    // MARK: - Landing

    /// Waits for closeButton — BUG-2: if summary cover never mounts, this fails within timeout.
    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> Self {
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: timeout),
            "WorkoutSummaryScreen did not load: closeButton not found within \(timeout)s. "
                + "BUG-2: nested fullScreenCover chain may be broken (cover not mounted on ActiveWorkoutCover)."
        )
        return self
    }

    // MARK: - Bug coverage assertions

    /// BUG-4 (direct): if the lifecycle gap causes workoutId to be nil, the workout name is empty.
    /// Reverts: change WorkoutSummaryView to read from appEnv.activeCoordinator instead of captured workoutId.
    @discardableResult
    func assertWorkoutNameVisible() -> Self {
        XCTAssertTrue(
            workoutNameLabel.exists,
            "BUG-4: workoutNameLabel element not found in the view hierarchy."
        )
        XCTAssertFalse(
            workoutNameLabel.label.isEmpty,
            "BUG-4 detected: workoutNameLabel.label is empty — workout name not rendered. "
                + "Possible lifecycle gap: activeCoordinator=nil before Summary reads workoutId."
        )
        return self
    }

    // MARK: - Transitions

    /// Taps the close button and returns the Home screen (not yet validated — caller validates).
    func tapClose() -> HomeScreen {
        closeButton.tap()
        return HomeScreen(app: app)
    }
}
