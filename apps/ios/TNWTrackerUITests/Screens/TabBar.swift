import TNWTrackerKit
import XCTest

/// The app's tab bar (#174). Tabs are found by position: on iOS 26.0 a `Tab`'s
/// accessibility identifier does not reach its tab bar button.
@MainActor
struct TabBar {
    enum Item: Int, CaseIterable {
        case home, history, exercises
    }

    let app: XCUIApplication

    func button(_ item: Item) -> XCUIElement {
        app.tabBars.buttons.element(boundBy: item.rawValue)
    }

    /// Waits for the tab and taps it.
    func select(_ item: Item) {
        let tab = button(item)
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "tab \(item) is not in the tab bar")
        tab.waitUntilHittable()
        tab.tap()
    }
}
