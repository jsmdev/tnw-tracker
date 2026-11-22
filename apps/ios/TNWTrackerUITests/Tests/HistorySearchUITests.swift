import TNWTrackerKit
import XCTest

/// #174 S8: the history searches by exercise, filters by kind, period and
/// source, and shows how many workouts match. Sample data: Full Body A (with
/// machine data, Chest Press Machine) and Full Body B (manual, Bench Press).
@MainActor
final class HistorySearchUITests: XCTestCase {
    private func openHistory() -> (XCUIApplication, HistoryScreen) {
        let app = launchUITestApp()
        _ = HomeScreen(app: app).waitUntilLoaded(timeout: 10)
        TabBar(app: app).select(.history)
        let history = HistoryScreen(app: app).waitUntilLoaded()
        XCTAssertTrue(history.row(named: "Full Body A").waitForExistence(timeout: 10))
        return (app, history)
    }

    func test_filtersNarrowTheListAndClear() throws {
        let (app, history) = openHistory()
        XCTAssertEqual(history.countValue, 2)
        XCTAssertFalse(history.clearFilters.exists, "nothing to clear yet")
        // The filters with the default selection, before scrolling: audited here.
        // The month title scales and wraps at the largest text size (checked by hand).
        try app.auditAccessibility(
            screen: "history filters",
            dynamicTypeChecked: [AXID.History.month],
            contentUnderTabBar: true
        )

        history.tapChip(AXID.History.sourceChip("manual"))
        XCTAssertTrue(history.row(named: "Full Body A").waitForNonExistence(timeout: 5))
        XCTAssertTrue(history.row(named: "Full Body B").exists)
        XCTAssertEqual(history.countValue, 1)
        XCTAssertTrue(history.chip(AXID.History.sourceChip("manual")).isSelected)

        history.tapChip(AXID.History.kindChip("Full Body A"))
        XCTAssertTrue(history.noResults.waitForExistence(timeout: 5), "manual Full Body A: none")
        attachScreenshot(of: app, named: "history with no match")

        history.clearFilters.tap()
        XCTAssertTrue(history.row(named: "Full Body A").waitForExistence(timeout: 5))
        XCTAssertTrue(history.row(named: "Full Body B").exists)
        XCTAssertEqual(history.countValue, 2)
    }

    func test_searchFindsWorkoutsByExercise() throws {
        let (app, history) = openHistory()

        history.search("chest press")
        XCTAssertTrue(history.row(named: "Full Body B").waitForNonExistence(timeout: 5))
        XCTAssertTrue(history.row(named: "Full Body A").exists)
        XCTAssertEqual(history.countValue, 1)
        attachScreenshot(of: app, named: "history search by exercise")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
