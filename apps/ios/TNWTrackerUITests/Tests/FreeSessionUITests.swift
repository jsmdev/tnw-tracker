import TNWTrackerKit
import XCTest

/// #137 S5: Home starts a free session without a routine; the user adds an
/// exercise from the list, logs a set and finishes with a summary. Invented
/// sample data; accessibility audit on the new screens.
@MainActor
final class FreeSessionUITests: XCTestCase {
    private typealias Sample = SampleTrainingData.ExerciseID

    func test_freeSessionFromHomeToSummary() throws {
        let app = launchUITestApp()
        let home = HomeScreen(app: app).waitUntilLoaded(timeout: 10)

        try app.auditAccessibility(screen: "home", only: [AXID.Home.freeSessionButton])
        let active = home.startFreeSession()
        XCTAssertFalse(active.addSetButton.exists, "no exercise yet: nothing to log")
        // Only the new button: "Pausar" and "Finalizar workout" fail contrast already.
        try app.auditAccessibility(screen: "free session, no exercises", only: [AXID.ActiveWorkout.addExerciseButton])

        active.addExerciseButton.waitUntilHittable()
        active.addExerciseButton.tap()
        XCTAssertTrue(app.buttons[AXID.Exercises.row(Sample.gobletSquat)].waitForExistence(timeout: 5))
        try app.auditAccessibility(screen: "exercise picker")
        app.buttons[AXID.ActiveWorkout.exercisePickerCancelButton].tap()
        XCTAssertFalse(active.addSetButton.waitForExistence(timeout: 1), "cancel picks nothing")

        let summary = active
            .addExercise(Sample.gobletSquat, named: "Goblet Squat")
            .tapLogSet().enterReps(8).saveStartingRest().tapSkip()
            .tapEnd()
        summary.assertWorkoutNameVisible()
        _ = summary.tapClose()
    }
}
