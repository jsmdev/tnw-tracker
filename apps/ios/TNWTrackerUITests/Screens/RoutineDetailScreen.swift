import TNWTrackerKit
import XCTest

/// Page Object for the routine detail (`SessionDetailView`).
@MainActor
struct RoutineDetailScreen {
    let app: XCUIApplication

    // MARK: - Queries

    var favoriteButton: XCUIElement {
        app.buttons[AXID.RoutineDetail.favoriteButton]
    }

    var startButton: XCUIElement {
        app.buttons[AXID.RoutineDetail.startButton]
    }

    /// A routine item's target ("3 × 6–8", T8), found by what VoiceOver reads,
    /// in either language.
    func target(spokenAs labels: [String]) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    // MARK: - Landing

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> Self {
        XCTAssertTrue(
            favoriteButton.waitForExistence(timeout: timeout),
            "RoutineDetailScreen did not load: favoriteButton not found within \(timeout)s."
        )
        return self
    }

    // MARK: - Actions

    @discardableResult
    func toggleFavorite() -> Self {
        favoriteButton.tap()
        return self
    }

    func tapStart() -> ActiveWorkoutScreen {
        startButton.tap()
        return ActiveWorkoutScreen(app: app).waitUntilLoaded()
    }

    /// Taps an exercise of the routine: its sheet opens (AC2).
    func openExercise(named name: String) -> ExerciseSheetScreen {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no exercise row for \(name)")
        row.waitUntilHittable()
        row.tap()
        return ExerciseSheetScreen(app: app).waitUntilLoaded()
    }

    /// Whether the routine lists an exercise named `name`.
    func hasExercise(named name: String) -> Bool {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.waitForExistence(timeout: 5)
    }

    /// Back to Home, when the detail was opened from "Otras rutinas".
    func backToHome() -> HomeScreen {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        return HomeScreen(app: app).waitUntilLoaded()
    }

    /// Back to the routine list.
    func back() -> RoutineListScreen {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        return RoutineListScreen(app: app).waitUntilLoaded()
    }
}
