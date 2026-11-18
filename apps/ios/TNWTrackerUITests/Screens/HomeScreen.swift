import TNWTrackerKit
import XCTest

/// Page Object for the Home screen.
/// Convention: properties are element queries; functions fire actions and return the next validated screen.
@MainActor
struct HomeScreen {
    let app: XCUIApplication

    // MARK: - Queries

    var quickStartButton: XCUIElement {
        app.buttons[AXID.Home.quickStartButton]
    }

    /// Name of the routine "Próxima sesión" proposes.
    var nextSessionTitle: XCUIElement {
        app.staticTexts[AXID.Home.nextSessionTitle]
    }

    var settingsButton: XCUIElement {
        app.buttons[AXID.Home.settingsButton]
    }

    // MARK: - Landing

    /// Waits for the Home landing element. Fails the test with a descriptive message if it times out.
    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> Self {
        XCTAssertTrue(
            quickStartButton.waitForExistence(timeout: timeout),
            "HomeScreen did not load: quickStartButton not found within \(timeout)s. "
                + "Possible: auth bypass not active, seed not applied, or router did not pop to root."
        )
        return self
    }

    // MARK: - Transitions

    /// Taps the settings button and returns an already-validated SettingsScreen.
    func tapSettings() -> SettingsScreen {
        settingsButton.tap()
        return SettingsScreen(app: app).waitUntilLoaded()
    }

    /// Opens the routine list. It has no in-app entry point yet, so this uses its
    /// deep link `tnwtracker://session-history`.
    func openRoutineList() -> RoutineListScreen {
        RoutineListScreen.open(in: app)
    }

    /// Opens a routine's detail through its deep link `tnwtracker://session/<id>`.
    func openRoutine(_ routineId: UUID) -> RoutineDetailScreen {
        RoutineDetailScreen.open(routineId, in: app)
    }

    /// Taps the quick-start button and returns an already-validated ActiveWorkoutScreen.
    func tapQuickStart() -> ActiveWorkoutScreen {
        quickStartButton.tap()
        return ActiveWorkoutScreen(app: app).waitUntilLoaded()
    }
}
