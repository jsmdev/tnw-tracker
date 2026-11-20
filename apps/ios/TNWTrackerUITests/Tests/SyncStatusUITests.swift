import TNWTrackerKit
import XCTest

/// #135 S10: signed in on a store that holds another account's data, Settings
/// says so in a plain message and the app stays usable; accessibility audit.
@MainActor
final class SyncStatusUITests: XCTestCase {
    func test_storeOfAnotherAccountIsExplainedInSettings() throws {
        let app = launchUITestApp(extraArguments: ["--uitesting-store-of-another-user"])
        let settings = HomeScreen(app: app).waitUntilLoaded(timeout: 10).tapSettings().waitUntilLoaded()

        XCTAssertTrue(settings.syncStatusMessage.waitForExistence(timeout: 3))
        XCTAssertTrue(settings.changeExerciseRestToggle.isHittable, "The message does not block the screen.")
        try app.auditAccessibility(
            screen: "settings with the sync status",
            scrollsAtLargeSizes: [AXID.Settings.syncStatusMessage]
        )
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "settings-store-of-another-account"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func test_ownStoreShowsNoSyncMessage() {
        let app = launchUITestApp()
        let settings = HomeScreen(app: app).waitUntilLoaded(timeout: 10).tapSettings().waitUntilLoaded()

        XCTAssertFalse(settings.syncStatusMessage.exists)
    }
}
