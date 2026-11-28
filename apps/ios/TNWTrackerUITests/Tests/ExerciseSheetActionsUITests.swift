import TNWTrackerKit
import XCTest

/// Exercise sheet actions (AC1-AC5): the sheet opens from a finished workout and
/// from a routine; «Entrenar este ejercicio» starts a free session with it, or
/// adds it to the workout in progress; «Añadir a rutina» adds it to a routine,
/// never twice, or creates one. Invented sample data; accessibility audit on
/// each changed screen.
@MainActor
final class ExerciseSheetActionsUITests: XCTestCase {
    private typealias Sample = SampleTrainingData.ExerciseID

    private func openHistoryWorkout(_ app: XCUIApplication, named name: String) -> WorkoutDetailScreen {
        TabBar(app: app).select(.history)
        return HistoryScreen(app: app).waitUntilLoaded().openWorkout(named: name)
    }

    func test_historyExerciseStartsAFreeSessionThenJoinsIt() throws {
        let app = launchUITestApp()
        _ = HomeScreen(app: app).waitUntilLoaded(timeout: 10)

        // AC1: a finished workout's exercise opens its sheet.
        let detail = openHistoryWorkout(app, named: "Full Body A")
        try app.auditAccessibility(
            screen: "workout detail, exercise rows",
            dynamicTypeChecked: [AXID.WorkoutDetail.importedNote],
            contentUnderTabBar: true
        )
        let squat = detail.openExercise(named: "Goblet Squat")
        XCTAssertEqual(squat.name.label, "Goblet Squat")
        XCTAssertTrue(squat.trainButton.waitForExistence(timeout: 3))
        XCTAssertTrue(
            ["Entrenar este ejercicio", "Train this exercise"].contains(squat.trainButton.label),
            "no workout in progress: «Entrenar este ejercicio», not \(squat.trainButton.label)"
        )
        attachScreenshot(of: app, named: "exercise sheet from history")
        try app.auditAccessibility(
            screen: "exercise sheet with actions",
            knownContrastIssues: [AXID.ExerciseSheet.trainButton]
        )

        // AC3: a free session starts with the exercise as the current one.
        let workout = squat.train()
        XCTAssertTrue(workout.exerciseTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(workout.exerciseTitle.label, "Goblet Squat")
        attachScreenshot(of: app, named: "free session started from the sheet")

        // AC4: with the workout in progress, another exercise joins it.
        // Closing the workout leaves it in progress and goes back to the detail.
        let minimize = app.buttons[AXID.ActiveWorkout.minimizeButton]
        minimize.waitUntilHittable()
        minimize.tap()
        let press = detail.waitUntilLoaded().openExercise(named: "Chest Press Machine")
        XCTAssertTrue(press.trainButton.waitForExistence(timeout: 3))
        XCTAssertTrue(
            ["Añadir a la sesión en curso", "Add to the workout in progress"].contains(press.trainButton.label),
            "a workout in progress: «Añadir a la sesión en curso», not \(press.trainButton.label)"
        )
        let resumed = press.train()
        XCTAssertTrue(resumed.exerciseTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(resumed.exerciseTitle.label, "Chest Press Machine")
        XCTAssertEqual(resumed.elapsedTimer.count, 1, "the same workout, not a second one")
        attachScreenshot(of: app, named: "exercise added to the workout in progress")
    }

    /// Bug (José, 2026-11-28): a session started from the sheet, minimized before
    /// any set, lost its exercise when it was continued.
    func test_exerciseStartedFromTheSheetSurvivesMinimizeBeforeAnySet() {
        let app = launchUITestApp()
        let home = HomeScreen(app: app).waitUntilLoaded(timeout: 10)
        let workout = home.openExercises().openSheet(Sample.gobletSquat).train()
        XCTAssertTrue(workout.exerciseTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(workout.exerciseTitle.label, "Goblet Squat")

        // Minimizing goes back to the Exercises tab, where the sheet was opened.
        let minimize = app.buttons[AXID.ActiveWorkout.minimizeButton]
        minimize.waitUntilHittable()
        minimize.tap()
        TabBar(app: app).select(.home)
        let resumed = HomeScreen(app: app).waitUntilLoaded().continueWorkout()
        XCTAssertTrue(resumed.exerciseTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(resumed.exerciseTitle.label, "Goblet Squat", "the exercise is still in the session")
        attachScreenshot(of: app, named: "continued session keeps its exercise")
    }

    func test_addToRoutineNeverTwiceAndNewRoutine() throws {
        let app = launchUITestApp()
        let home = HomeScreen(app: app).waitUntilLoaded(timeout: 10)
        let squat = home.openExercises().openSheet(Sample.gobletSquat)

        // AC5: added at the end of the routine, then never twice.
        let added = squat.addToRoutine(named: "Full Body B")
        XCTAssertTrue(
            added.hasPrefix("Añadido a") || added.hasPrefix("Added to"),
            "told it was added: \(added)"
        )
        XCTAssertTrue(added.contains("Full Body B"))
        let again = squat.addToRoutine(named: "Full Body B")
        XCTAssertTrue(
            again.contains("ya tiene") || again.contains("already has"),
            "told it was already there: \(again)"
        )

        // AC5: «Nueva rutina…» asks only for the name.
        let created = squat.addToNewRoutine(named: "Leg day")
        XCTAssertTrue(created.contains("Leg day"), "told the new routine has it: \(created)")
        attachScreenshot(of: app, named: "added to a new routine")

        squat.dismiss()
        TabBar(app: app).select(.home)
        let routines = HomeScreen(app: app).waitUntilLoaded().openRoutineList()
        XCTAssertTrue(app.staticTexts["Leg day"].waitForExistence(timeout: 5), "the new routine is listed")

        // AC2: the routine now ends with the exercise, and its row opens the sheet.
        let fullBodyB = routines.openRoutine(SampleTrainingData.RoutineID.fullBodyB)
        XCTAssertTrue(fullBodyB.hasExercise(named: "Goblet Squat"))
        let sheet = fullBodyB.openExercise(named: "Goblet Squat")
        XCTAssertEqual(sheet.name.label, "Goblet Squat")
        try app.auditAccessibility(
            screen: "exercise sheet from a routine",
            knownContrastIssues: [AXID.ExerciseSheet.trainButton]
        )
        sheet.dismiss()
    }

    /// AC6: once the name scrolls under the bar, the bar shows it, and hides it again on the way back.
    func test_sheetNameStaysInTheBarWhenScrolled() throws {
        let app = launchUITestApp()
        let press = HomeScreen(app: app).waitUntilLoaded(timeout: 10).openExercises().openSheet(Sample.chestPress)
        let barTitle = app.staticTexts[AXID.ExerciseSheet.barTitle]
        XCTAssertFalse(barTitle.exists, "the name is on screen: the bar shows nothing")

        app.swipeUp()
        XCTAssertTrue(barTitle.waitForExistence(timeout: 3), "scrolled away: the bar shows the name")
        XCTAssertEqual(barTitle.label, "Chest Press Machine")
        attachScreenshot(of: app, named: "exercise sheet, name in the bar")
        // Only the bar title is new here; the rest of the sheet is audited unscrolled.
        // Like the system's inline titles, it keeps the bar's text size (checked by hand).
        try app.auditAccessibility(
            screen: "exercise sheet, scrolled",
            only: [AXID.ExerciseSheet.barTitle],
            dynamicTypeChecked: [AXID.ExerciseSheet.barTitle]
        )

        app.swipeDown()
        XCTAssertTrue(barTitle.waitForNonExistence(timeout: 3), "back at the top: the name is in the content again")
        XCTAssertTrue(press.name.isHittable)
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
