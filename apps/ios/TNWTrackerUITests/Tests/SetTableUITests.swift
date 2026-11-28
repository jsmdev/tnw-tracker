import TNWTrackerKit
import XCTest

/// fast-add-exercise S5: the current exercise shows a set table ready to log,
/// without tapping «Registrar serie»: last time's sets, or 3 × 15 reps at 0 kg
/// for an exercise never done. A check logs a row; «Añadir serie» adds one.
/// Invented sample data: Goblet Squat was done as 12, 10, 10 reps at 16 kg;
/// Seated Row Machine was never done.
@MainActor
final class SetTableUITests: XCTestCase {
    private typealias Sample = SampleTrainingData.ExerciseID

    /// The set table's own elements; the rest of the workout screen is unchanged.
    private var tableElements: Set<String> {
        let rows = (1 ... 3).flatMap { number in
            [
                AXID.ActiveWorkout.setRepsField(number), AXID.ActiveWorkout.setWeightField(number),
                AXID.ActiveWorkout.setCheckButton(number), AXID.ActiveWorkout.setDetailsButton(number),
                AXID.ActiveWorkout.doneSetRow(number)
            ]
        }
        return Set(rows + [AXID.ActiveWorkout.addSetButton, AXID.ActiveWorkout.setTableHeader])
    }

    /// The number fields: a screenshot at the largest accessibility text size
    /// showed them stacked, scaled and unclipped (the audit flags any UIKit field).
    private var fieldsCheckedByHand: Set<String> {
        Set((1 ... 4).flatMap { [AXID.ActiveWorkout.setRepsField($0), AXID.ActiveWorkout.setWeightField($0)] })
    }

    private func value(of field: XCUIElement) -> String {
        field.value as? String ?? ""
    }

    func test_tableStartsFromLastTimeAndACheckLogsTheRow() throws {
        let app = launchUITestApp()
        let active = HomeScreen(app: app).waitUntilLoaded(timeout: 10)
            .startFreeSession()
            .addExercise(Sample.gobletSquat, named: "Goblet Squat")

        // AC1: one row per set of the last time, ready at once.
        XCTAssertTrue(active.repsField(1).waitForExistence(timeout: 3), "the set table is not shown")
        XCTAssertEqual([1, 2, 3].map { value(of: active.repsField($0)) }, ["12", "10", "10"])
        XCTAssertEqual([1, 2, 3].map { value(of: active.weightField($0)) }, ["16", "16", "16"])
        XCTAssertFalse(active.repsField(4).exists, "as many rows as last time")
        attachScreenshot(of: app, named: "Set table from last time")
        try app.auditAccessibility(
            screen: "workout set table",
            only: tableElements,
            dynamicTypeChecked: fieldsCheckedByHand
        )

        // AC4: a row is edited, then its check logs it and starts the rest.
        active.type("11", into: active.repsField(1))
        XCTAssertEqual(value(of: active.repsField(1)), "11")
        let afterCheck = active.check(1).waitUntilLoaded().tapSkip()
        let done = afterCheck.doneRow(1)
        XCTAssertTrue(done.waitForExistence(timeout: 3), "the checked row shows as done")
        XCTAssertTrue(done.label.contains("11 × 16"), "unexpected done row: \(done.label)")
        XCTAssertFalse(afterCheck.repsField(1).exists, "the checked row leaves the rows to do")
        XCTAssertEqual(value(of: afterCheck.repsField(2)), "10")

        // AC5: «Añadir serie» adds a row with the values of the row above.
        afterCheck.addSetButton.tap()
        XCTAssertTrue(afterCheck.repsField(4).waitForExistence(timeout: 3))
        XCTAssertEqual(value(of: afterCheck.repsField(4)), "10")
        XCTAssertEqual(value(of: afterCheck.weightField(4)), "16")
        attachScreenshot(of: app, named: "Set table after a check and an added row")
        try app.auditAccessibility(
            screen: "set table with a done row",
            only: tableElements,
            dynamicTypeChecked: fieldsCheckedByHand
        )
    }

    func test_exerciseNeverDoneStartsWithThreeRowsOf15RepsAt0Kg() {
        let app = launchUITestApp()
        let active = HomeScreen(app: app).waitUntilLoaded(timeout: 10)
            .startFreeSession()
            .addExercise(Sample.seatedRow, named: "Seated Row Machine")

        // AC2: 3 rows of 15 reps and 0 kg.
        XCTAssertTrue(active.repsField(1).waitForExistence(timeout: 3), "the set table is not shown")
        XCTAssertEqual([1, 2, 3].map { value(of: active.repsField($0)) }, ["15", "15", "15"])
        XCTAssertEqual([1, 2, 3].map { value(of: active.weightField($0)) }, ["0", "0", "0"])
        XCTAssertFalse(active.repsField(4).exists)
        attachScreenshot(of: app, named: "Set table of an exercise never done")

        // AC4 (review probe): typing and checking straight away, with the keyboard
        // still up, logs the typed value.
        let reps = active.repsField(1)
        reps.tap()
        reps.typeText("12")
        let afterCheck = active.check(1).waitUntilLoaded().tapSkip()
        let done = afterCheck.doneRow(1)
        XCTAssertTrue(done.waitForExistence(timeout: 3), "the checked row shows as done")
        XCTAssertTrue(done.label.contains("12 × 0"), "the typed reps were not logged: \(done.label)")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
