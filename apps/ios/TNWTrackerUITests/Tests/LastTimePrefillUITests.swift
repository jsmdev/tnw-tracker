import TNWTrackerKit
import XCTest

/// fast-add-exercise S3: an exercise done before shows «La última vez» in the
/// workout, and each new set starts from the same set last time, so logging it
/// is one tap on «Guardar». Invented sample data: Goblet Squat was done four
/// days ago as 12, 10, 10 reps at 16 kg.
@MainActor
final class LastTimePrefillUITests: XCTestCase {
    private typealias Sample = SampleTrainingData.ExerciseID

    func test_addedExerciseStartsFromLastTime() throws {
        let app = launchUITestApp()
        let active = HomeScreen(app: app).waitUntilLoaded(timeout: 10)
            .startFreeSession()
            .addExercise(Sample.gobletSquat, named: "Goblet Squat")

        // AC4: last time shows under the exercise name.
        let lastTime = app.descendants(matching: .any)[AXID.ActiveWorkout.lastTime]
        XCTAssertTrue(lastTime.waitForExistence(timeout: 3), "«La última vez» is not shown")
        XCTAssertTrue(lastTime.label.contains("12 × 16 kg"), "unexpected last time: \(lastTime.label)")
        XCTAssertTrue(lastTime.label.contains("10 × 16 kg"), "unexpected last time: \(lastTime.label)")
        try app.auditAccessibility(screen: "workout with last time", only: [AXID.ActiveWorkout.lastTime])
        attachScreenshot(of: app, named: "Workout with last time")

        // AC1: set 1 starts as last time's set 1 and saves without typing.
        var sheet = active.tapLogSet()
        XCTAssertFalse(
            app.keyboards.firstMatch.waitForExistence(timeout: 2), "a prefilled sheet opens without the keyboard"
        )
        XCTAssertEqual(sheet.value(of: sheet.repsField), "12")
        XCTAssertEqual(sheet.value(of: sheet.weightField), "16")
        XCTAssertTrue(sheet.saveButton.isEnabled, "a prefilled set can be saved at once")
        attachScreenshot(of: app, named: "Set 1 prefilled")
        let afterFirst = sheet.saveStartingRest().tapSkip()

        // AC1: set 2 starts as last time's set 2.
        sheet = afterFirst.tapLogSet()
        XCTAssertEqual(sheet.value(of: sheet.repsField), "10")
        XCTAssertEqual(sheet.value(of: sheet.weightField), "16")

        // The prefill can be changed: typing replaces it.
        sheet.enterReps(9)
        XCTAssertEqual(sheet.value(of: sheet.repsField), "9")
        _ = sheet.cancel()
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
