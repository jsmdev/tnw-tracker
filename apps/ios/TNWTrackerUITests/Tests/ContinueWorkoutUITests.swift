import TNWTrackerKit
import XCTest

/// A session left in progress is offered on Home with "Continuar entrenamiento",
/// which replaces the buttons that would start another one, and reopens the
/// session where the user was. Invented sample data.
@MainActor
final class ContinueWorkoutUITests: XCTestCase {
    private typealias Sample = SampleTrainingData.ExerciseID

    func test_sessionInProgressIsContinuedFromHome() throws {
        let app = launchUITestApp()
        let home = HomeScreen(app: app).waitUntilLoaded(timeout: 10)
        XCTAssertFalse(home.continueButton.exists, "nothing in progress yet")

        let active = home.startFreeSession()
            .addExercise(Sample.gobletSquat, named: "Goblet Squat")
            .tapLogSet().enterReps(8).saveStartingRest().tapSkip()

        let back = active.minimize()
        XCTAssertTrue(back.continueButton.waitForExistence(timeout: 5))
        XCTAssertFalse(back.freeSessionButton.exists, "no second session while one is in progress")
        XCTAssertFalse(back.quickStartButton.exists, "no second session while one is in progress")
        // No contrast audit of the button: it is the shared PrimaryButton (white on
        // the system blue), which fails contrast everywhere, like "Iniciar workout".

        let resumed = back.continueWorkout()
        XCTAssertEqual(resumed.exerciseTitle.label, "Goblet Squat")

        let summary = resumed.tapEnd()
        summary.assertWorkoutNameVisible()
        let home2 = summary.tapClose()
        XCTAssertTrue(home2.freeSessionButton.waitForExistence(timeout: 5))
        XCTAssertFalse(home2.continueButton.exists, "the finished session is not offered")
    }
}
