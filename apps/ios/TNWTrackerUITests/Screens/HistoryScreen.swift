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
        let tab = TabBar(app: app).button(.history)
        XCTAssertTrue(
            tab.waitForExistence(timeout: timeout),
            "HistoryScreen did not load: the Historial tab is missing."
        )
        XCTAssertTrue(tab.isSelected, "the Historial tab is not selected")
        return self
    }
}
