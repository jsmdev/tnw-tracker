import TNWTrackerKit
import XCTest

/// Page Object for the Active Workout screen.
/// Carries bug-coverage assertions for BUG-1, BUG-3, and BUG-4.
@MainActor
struct ActiveWorkoutScreen {
    let app: XCUIApplication

    // MARK: - Queries

    var endButton: XCUIElement {
        app.buttons[AXID.ActiveWorkout.endButton]
    }

    var logSetButton: XCUIElement {
        app.buttons[AXID.ActiveWorkout.logSetButton]
    }

    /// Query (not element) — used to assert count == 1 for BUG-1 coverage.
    var elapsedTimer: XCUIElementQuery {
        app.staticTexts.matching(identifier: AXID.ActiveWorkout.elapsedTimer)
    }

    var exerciseTitle: XCUIElement {
        app.staticTexts[AXID.ActiveWorkout.exerciseTitle]
    }

    var progressIndicator: XCUIElement {
        app.activityIndicators[AXID.ActiveWorkout.progressIndicator]
    }

    // MARK: - Landing

    /// Waits for endButton — guaranteed visible when coordinator phase != .idle.
    /// Descriptive failure message references BUG-1 and BUG-3 as likely causes.
    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> Self {
        XCTAssertTrue(
            endButton.waitForExistence(timeout: timeout),
            "ActiveWorkoutScreen did not load: endButton not found within \(timeout)s. "
                + "Possible causes: BUG-1 (double coordinator start race) or BUG-3 (phase guard dismissed cover)."
        )
        return self
    }

    // MARK: - Bug coverage assertions

    /// BUG-1: If the coordinator starts twice, two elapsed timers appear (count > 1).
    /// Revert `guard coordinator == nil else { return }` in ActiveWorkoutCover.task to reproduce failure.
    @discardableResult
    func assertSingleElapsedTimer() -> Self {
        XCTAssertEqual(
            elapsedTimer.count, 1,
            "BUG-1 detected: \(elapsedTimer.count) elapsed timer(s) visible, expected exactly 1. "
                + "Race in ActiveWorkoutCover.task (double-start coordinator)."
        )
        return self
    }

    /// BUG-3: The phase guard race-prone implementation dismissed the cover unexpectedly.
    /// If endButton is gone or progressIndicator is still visible, the cover never fully transitioned.
    @discardableResult
    func assertNotDismissed() -> Self {
        XCTAssertTrue(
            endButton.exists,
            "BUG-3 detected: endButton not visible — ActiveWorkout cover dismissed unexpectedly."
        )
        XCTAssertFalse(
            progressIndicator.exists,
            "BUG-3 detected: progressIndicator still visible — coordinator did not start (phase stuck at .idle)."
        )
        return self
    }

    /// BUG-4 (indirect): If the coordinator phase is wrong, exerciseTitle will not appear.
    @discardableResult
    func assertActiveContentVisible() -> Self {
        XCTAssertTrue(
            exerciseTitle.exists,
            "BUG-4 (indirect): exerciseTitle not visible — coordinator phase may be incorrect."
        )
        return self
    }

    // MARK: - Transitions

    /// Opens the exercise's options and then "Descanso entre series".
    /// The menu item exists as soon as the menu starts to open; it is tapped only
    /// once it is hittable (fully presented), else the tap may only close the menu.
    func openExerciseRest() -> ExerciseRestSheetScreen {
        let menu = app.buttons[AXID.ActiveWorkout.exerciseOptionsMenu]
        menu.waitUntilHittable()
        menu.tap()
        let restButton = app.buttons[AXID.ActiveWorkout.exerciseRestButton]
        XCTAssertTrue(restButton.waitForExistence(timeout: 3), "Exercise options did not show the rest item.")
        restButton.waitUntilHittable()
        restButton.tap()
        return ExerciseRestSheetScreen(app: app).waitUntilLoaded()
    }

    /// Taps the log-set button and returns an already-validated SetLogSheetScreen.
    func tapLogSet() -> SetLogSheetScreen {
        logSetButton.tap()
        return SetLogSheetScreen(app: app).waitUntilLoaded()
    }

    /// Taps the end button of a workout with no working sets; returns the
    /// validated discard prompt (T6 AC6.1).
    func tapEndWithoutSets() -> DiscardWorkoutScreen {
        endButton.tap()
        return DiscardWorkoutScreen(app: app).waitUntilLoaded()
    }

    /// Taps the end button and returns an already-validated WorkoutSummaryScreen.
    /// BUG-2 coverage: if the fullScreenCover chain is broken, waitUntilLoaded times out here.
    func tapEnd() -> WorkoutSummaryScreen {
        endButton.tap()
        return WorkoutSummaryScreen(app: app).waitUntilLoaded()
    }
}
