import TNWTrackerKit
import XCTest

/// Page Object for the login screen, shown while signed out.
@MainActor
struct LoginScreen {
    let app: XCUIApplication

    var screen: XCUIElement {
        app.otherElements[AXID.Login.screen]
    }

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> Self {
        XCTAssertTrue(
            screen.waitForExistence(timeout: timeout),
            "LoginScreen did not load: \(AXID.Login.screen) not found within \(timeout)s."
        )
        return self
    }
}
