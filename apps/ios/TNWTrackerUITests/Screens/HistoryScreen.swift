import TNWTrackerKit
import XCTest

/// Page Object for the Historial tab (#174).
@MainActor
struct HistoryScreen {
    let app: XCUIApplication

    /// The list, or the empty state when no workout is finished yet.
    var title: XCUIElement {
        app.navigationBars.staticTexts.firstMatch
    }

    func row(_ sessionId: UUID) -> XCUIElement {
        app.descendants(matching: .any)[AXID.History.row(sessionId)]
    }

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> Self {
        XCTAssertTrue(
            app.tabBars.buttons[AXID.Tabs.history].waitForExistence(timeout: timeout),
            "HistoryScreen did not load: the Historial tab is missing."
        )
        XCTAssertTrue(app.tabBars.buttons[AXID.Tabs.history].isSelected, "the Historial tab is not selected")
        return self
    }
}
