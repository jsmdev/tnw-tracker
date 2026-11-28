import TNWTrackerKit
import XCTest

/// fast-add-exercise S6: an exercise's history is one tap away, in its sheet and
/// from «La última vez» in the workout. Invented sample data: Goblet Squat was
/// done as 12, 10, 10 reps at 16 kg; Seated Row Machine was never done.
@MainActor
final class ExerciseHistoryUITests: XCTestCase {
    private typealias Sample = SampleTrainingData.ExerciseID

    private var historyElements: Set<String> {
        [AXID.ExerciseHistory.best, AXID.ExerciseHistory.empty, AXID.ExerciseHistory.seeAllButton]
    }

    private func historyRow(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "exerciseHistory.row.")).firstMatch
    }

    func test_sheetShowsTheExerciseHistory() throws {
        let app = launchUITestApp()
        let home = HomeScreen(app: app).waitUntilLoaded(timeout: 10)
        let squat = home.openExercises().openSheet(Sample.gobletSquat)

        let row = historyRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the sheet shows no history")
        XCTAssertTrue(row.label.contains("12 × 16 kg"), "unexpected history row: \(row.label)")
        XCTAssertTrue(row.label.contains("10 × 16 kg"), "unexpected history row: \(row.label)")
        let best = app.staticTexts[AXID.ExerciseHistory.best]
        XCTAssertTrue(best.exists)
        XCTAssertTrue(best.label.contains("16 kg"), "unexpected best set: \(best.label)")
        best.swipeUp()
        attachScreenshot(of: app, named: "Exercise sheet with its history")
        try app.auditAccessibility(screen: "exercise sheet history", only: historyElements)

        squat.dismiss()
        _ = ExerciseListScreen(app: app).openSheet(Sample.seatedRow)
        XCTAssertTrue(app.staticTexts[AXID.ExerciseHistory.empty].waitForExistence(timeout: 5))
        XCTAssertFalse(historyRow(app).exists, "an exercise never done has no history")
    }

    func test_lastTimeInTheWorkoutOpensTheHistory() throws {
        let app = launchUITestApp()
        _ = HomeScreen(app: app).waitUntilLoaded(timeout: 10)
            .startFreeSession()
            .addExercise(Sample.gobletSquat, named: "Goblet Squat")

        let lastTime = app.buttons[AXID.ActiveWorkout.lastTime]
        XCTAssertTrue(lastTime.waitForExistence(timeout: 3), "«La última vez» is not a button")
        lastTime.tap()

        XCTAssertTrue(app.descendants(matching: .any)[AXID.ExerciseHistory.list].waitForExistence(timeout: 5))
        let row = historyRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.label.contains("12 × 16 kg"), "unexpected history row: \(row.label)")
        attachScreenshot(of: app, named: "History from the workout")
        try app.auditAccessibility(screen: "workout history sheet", only: [AXID.ExerciseHistory.closeButton])

        app.buttons[AXID.ExerciseHistory.closeButton].tap()
        XCTAssertTrue(app.buttons[AXID.ActiveWorkout.lastTime].waitForExistence(timeout: 3), "back in the workout")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
