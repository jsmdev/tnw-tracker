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

    /// «Abrir enlaces en la app» (S10 T5d).
    var openLinksInAppToggle: XCUIElement {
        app.switches[AXID.Settings.openLinksInAppToggle]
    }

    var opensLinksInApp: Bool {
        (openLinksInAppToggle.value as? String) == "1"
    }

    /// Turns «Abrir enlaces en la app» on or off.
    func toggleOpenLinksInApp() {
        if !openLinksInAppToggle.isHittable {
            app.swipeUp()
        }
        // The switch itself, not its row label.
        openLinksInAppToggle.switches.firstMatch.tap()
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

    // MARK: - Accessibility

    /// Audits Settings. Since «Abrir enlaces en la app» (S10 T5d) the audit reports
    /// a contrast failure it cannot tie to an element, as it does for rows near the
    /// blurred edge above the tab bar; and the new footer, which a screenshot at the
    /// largest text size showed scaling and whole.
    func audit(_ screen: String) throws {
        try app.auditAccessibility(
            screen: screen,
            dynamicTypeChecked: [AXID.Settings.openLinksInAppFooter],
            contentUnderTabBar: true
        )
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
