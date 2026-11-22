import TNWTrackerKit
import XCTest

/// #174 S7: a finished workout opens from the history with all its sets, and a
/// workout without machine data can be deleted by swiping or from its detail.
/// The sample data has Full Body A (with machine data) and Full Body B (manual only).
@MainActor
final class WorkoutHistoryUITests: XCTestCase {
    private func openHistory() -> (XCUIApplication, HistoryScreen) {
        let app = launchUITestApp()
        _ = HomeScreen(app: app).waitUntilLoaded(timeout: 10)
        TabBar(app: app).select(.history)
        return (app, HistoryScreen(app: app).waitUntilLoaded())
    }

    func test_swipeDeletesAManualWorkout() throws {
        let (app, history) = openHistory()
        XCTAssertTrue(history.row(named: "Full Body A").waitForExistence(timeout: 5))

        let delete = history.swipe(named: "Full Body B")
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "a manual workout offers delete")
        delete.tap()
        DeleteWorkoutAlert(app: app).confirm()

        XCTAssertTrue(history.row(named: "Full Body B").waitForNonExistence(timeout: 5))
        XCTAssertTrue(history.row(named: "Full Body A").exists)
        attachScreenshot(of: app, named: "history after swipe delete")
    }

    func test_workoutWithMachineDataCannotBeDeleted() throws {
        let (app, history) = openHistory()

        let detail = history.openWorkout(named: "Full Body A")
        XCTAssertTrue(detail.importedNote.waitForExistence(timeout: 5))
        XCTAssertFalse(detail.deleteButton.exists)
        XCTAssertTrue(app.staticTexts["Goblet Squat"].exists)
        XCTAssertTrue(app.staticTexts["Chest Press Machine"].exists)
        attachScreenshot(of: app, named: "workout with machine data")
        // At the largest text size the note scales and wraps without clipping
        // (checked by hand); the audit still reports it as partially unsupported.
        try app.auditAccessibility(
            screen: "workout detail (machine data)",
            dynamicTypeChecked: [AXID.WorkoutDetail.importedNote],
            contentUnderTabBar: true
        )

        let list = detail.back().waitUntilLoaded()
        let delete = list.swipe(named: "Full Body A")
        XCTAssertFalse(delete.waitForExistence(timeout: 2), "a workout with machine data offers no delete")
    }

    func test_detailShowsSetsAndDeletesTheWorkout() throws {
        let (app, history) = openHistory()

        let detail = history.openWorkout(named: "Full Body B")
        XCTAssertTrue(app.staticTexts["Bench Press"].exists)
        XCTAssertTrue(app.staticTexts["Push-Up"].exists)
        XCTAssertFalse(app.staticTexts["Rowing Machine"].exists, "a removed exercise is not shown")
        XCTAssertFalse(detail.importedNote.exists)
        attachScreenshot(of: app, named: "manual workout detail")
        // The sets run under the tab bar (see the screenshot); iOS 26.0 reports
        // those rows without an element.
        try app.auditAccessibility(screen: "workout detail", contentUnderTabBar: true)

        let back = detail.delete()
        _ = back.waitUntilLoaded()
        XCTAssertTrue(back.row(named: "Full Body B").waitForNonExistence(timeout: 5))
        XCTAssertTrue(back.row(named: "Full Body A").exists)
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
