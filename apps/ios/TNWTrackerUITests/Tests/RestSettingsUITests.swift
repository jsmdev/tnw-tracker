import TNWTrackerKit
import XCTest

/// T3 AC3.7: an exercise's "Descanso entre series" changed in one session is
/// saved and shown in the next session; accessibility audit on the changed screens.
@MainActor
final class RestSettingsUITests: XCTestCase {
    func test_exerciseRestIsSavedForTheNextSession() throws {
        // One launch: `--uitesting` uses an in-memory store.
        let app = launchUITestApp()
        let home = HomeScreen(app: app).waitUntilLoaded(timeout: 10)

        // Session 1: the routine's 90 s, changed to 105 s with +15 s.
        let active = home.tapQuickStart()
        // Unchanged controls of this screen fail contrast already (end, pause,
        // log set): audit only the new exercise options button here.
        try app.auditAccessibility(screen: "active workout", only: [AXID.ActiveWorkout.exerciseOptionsMenu])
        var rest = active.openExerciseRest()
        XCTAssertEqual(rest.seconds, 90, "No saved setting: the routine item's rest.")
        XCTAssertTrue(rest.isEnabled)
        rest.increase()
        XCTAssertEqual(rest.seconds, 105)

        // Off greys out the duration and keeps it; on again restores it.
        rest.toggle()
        XCTAssertFalse(rest.isEnabled)
        XCTAssertFalse(rest.increaseButton.isEnabled)
        XCTAssertEqual(rest.seconds, 105)
        rest.toggle()
        XCTAssertTrue(rest.isEnabled)
        XCTAssertTrue(rest.increaseButton.isEnabled)

        try app.auditAccessibility(screen: "exercise rest sheet")
        // No set logged: the workout is discarded (T6), the rest setting stays.
        let homeAgain = rest.done().tapEndWithoutSets().discard()

        // Session 2: same exercise, the saved rest. The discarded session does not
        // count, so Home still proposes Full Body A.
        rest = homeAgain.tapQuickStart().openExerciseRest()
        XCTAssertEqual(rest.seconds, 105, "The rest saved in the previous session.")
        XCTAssertTrue(rest.isEnabled)
        // Its rest between sets runs with −15 s / +15 s (new controls on the timer).
        let timer = rest.done().tapLogSet().enterReps(8).saveStartingRest()
        try app.auditAccessibility(screen: "rest timer", only: [AXID.RestTimer.decreaseButton, AXID.RestTimer.increaseButton])
        timer.increaseButton.tap()
        timer.decreaseButton.tap()
        let homeLast = timer.tapSkip().tapEnd().tapClose().waitUntilLoaded()

        // Settings: "Descanso al cambiar de ejercicio".
        let settings = homeLast.tapSettings()
        XCTAssertTrue(settings.changeExerciseRestDuration.exists)
        try app.auditAccessibility(screen: "settings")
    }
}
