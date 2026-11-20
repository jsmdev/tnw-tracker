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

    var rirMaximumStepper: XCUIElement {
        app.steppers[AXID.Settings.rirMaximumStepper]
    }

    var signOutButton: XCUIElement {
        app.buttons[AXID.Settings.signOutButton]
    }

    var signOutConfirmButton: XCUIElement {
        // The system may list the dialog's button twice (sheet and popover).
        app.buttons[AXID.Settings.signOutConfirmButton].firstMatch
    }

    var signOutCancelButton: XCUIElement {
        app.buttons[AXID.Settings.signOutCancelButton].firstMatch
    }

    // MARK: - Actions

    /// Taps "Sign out" and waits for its confirmation.
    @discardableResult
    func tapSignOut() -> Self {
        if !signOutButton.isHittable {
            app.swipeUp()
        }
        signOutButton.waitUntilHittable()
        signOutButton.tap()
        XCTAssertTrue(
            signOutConfirmButton.waitForExistence(timeout: 3),
            "The sign-out confirmation did not appear."
        )
        return self
    }

    /// Dismisses the confirmation without signing out: its Cancel button, or a
    /// tap outside where the system shows it without one.
    func dismissSignOutConfirmation() {
        if signOutCancelButton.exists {
            signOutCancelButton.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        }
        XCTAssertTrue(
            signOutConfirmButton.waitForNonExistence(timeout: 3),
            "The sign-out confirmation is still shown."
        )
    }

    /// Confirms the sign-out: the login shows.
    func confirmSignOut() -> LoginScreen {
        signOutConfirmButton.tap()
        return LoginScreen(app: app).waitUntilLoaded()
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
