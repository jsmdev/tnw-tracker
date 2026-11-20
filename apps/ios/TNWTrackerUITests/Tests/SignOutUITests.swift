import TNWTrackerKit
import XCTest

/// T9 (S10): "Sign out" in Settings asks for confirmation, then the login
/// shows and nothing of the account's screens is left; accessibility audit on
/// the changed Settings screen and its confirmation.
@MainActor
final class SignOutUITests: XCTestCase {
    func test_signOutFromSettingsShowsTheLogin() throws {
        let app = launchUITestApp()
        let settings = HomeScreen(app: app).waitUntilLoaded(timeout: 10).tapSettings()
        attachScreenshot(of: app, named: "Settings with Sign out")
        try app.auditAccessibility(screen: "settings")

        // Dismissing the confirmation keeps the account open.
        settings.tapSignOut()
        // The dialog's own text is the system's: audit only its button here.
        try app.auditAccessibility(screen: "sign-out confirmation", only: [AXID.Settings.signOutConfirmButton])
        settings.dismissSignOutConfirmation()
        XCTAssertTrue(settings.signOutButton.waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements[AXID.Login.screen].exists, "cancelled: still signed in")

        let login = settings.tapSignOut().confirmSignOut()

        XCTAssertTrue(login.screen.exists)
        XCTAssertFalse(settings.signOutButton.exists, "the account's screens are gone")
        XCTAssertFalse(app.buttons[AXID.Home.settingsButton].exists)
        attachScreenshot(of: app, named: "Signed out: login")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
