import TNWTrackerKit
import XCTest

/// T6 AC6.5: ending a workout with no working sets asks to discard it
/// (AC6.1), "Seguir entrenando" keeps it (AC6.3) and "Descartar" deletes it
/// with no effect on "Próxima sesión" (AC6.2); accessibility audit on the prompt.
@MainActor
final class DiscardEmptyWorkoutUITests: XCTestCase {
    func test_workoutWithoutSetsAsksToDiscard() throws {
        let app = launchUITestApp()
        let home = HomeScreen(app: app).waitUntilLoaded(timeout: 10)
        XCTAssertEqual(home.nextSessionTitle.label, "Full Body A")

        // AC6.1: no sets logged, "Terminar" asks first.
        let prompt = home.tapQuickStart().tapEndWithoutSets()
        XCTAssertTrue(prompt.title.exists, "The prompt shows its question.")
        XCTAssertTrue(prompt.keepTrainingButton.exists)
        try app.auditAccessibility(
            screen: "discard prompt",
            only: [AXID.DiscardWorkout.discardButton, AXID.DiscardWorkout.keepTrainingButton]
        )

        // AC6.3: "Seguir entrenando" keeps the workout as it was.
        let active = prompt.keepTraining()
        active.assertActiveContentVisible()
        XCTAssertFalse(prompt.discardButton.exists)

        // AC6.2: "Descartar" deletes it: Home again, no summary, same proposal
        // (a saved Full Body A would rotate the proposal to Full Body B).
        let homeAgain = active.tapEndWithoutSets().discard()
        XCTAssertFalse(app.buttons[AXID.Summary.closeButton].exists, "No summary for a discarded workout.")
        XCTAssertTrue(homeAgain.nextSessionTitle.waitForLabel("Full Body A"))
    }
}
