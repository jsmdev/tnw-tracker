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

    /// "Ver todas" in "Otras rutinas" (T10).
    var seeAllRoutinesButton: XCUIElement {
        app.buttons[AXID.Home.seeAllRoutinesButton]
    }

    /// A row of "Otras rutinas" (T10).
    func otherRoutine(_ routineId: UUID) -> XCUIElement {
        app.buttons[AXID.Home.otherRoutine(routineId)]
    }

    /// True when the "Otras rutinas" row shows the favourite star.
    func isFavorite(_ routineId: UUID) -> Bool {
        (otherRoutine(routineId).value as? String)?.isEmpty == false
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

    /// Opens the routine list with "Ver todas" in "Otras rutinas" (T10).
    func openRoutineList() -> RoutineListScreen {
        tapWhenHittable(seeAllRoutinesButton)
        return RoutineListScreen(app: app).waitUntilLoaded()
    }

    /// Opens a routine of "Otras rutinas" in its detail (T10).
    func openOtherRoutine(_ routineId: UUID) -> RoutineDetailScreen {
        tapWhenHittable(otherRoutine(routineId))
        return RoutineDetailScreen(app: app).waitUntilLoaded()
    }

    /// Home may sit below the navigation bar's large title or a returning push:
    /// scroll the element in and wait until a tap can reach it.
    private func tapWhenHittable(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) is not on Home.")
        if !element.isHittable {
            app.swipeUp()
        }
        element.waitUntilHittable()
        element.tap()
    }

    /// Taps the quick-start button and returns an already-validated ActiveWorkoutScreen.
    func tapQuickStart() -> ActiveWorkoutScreen {
        quickStartButton.tap()
        return ActiveWorkoutScreen(app: app).waitUntilLoaded()
    }
}
