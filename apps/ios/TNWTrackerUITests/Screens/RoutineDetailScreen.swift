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

    // MARK: - Landing

    /// Opens the detail through its deep link `tnwtracker://session/<id>`.
    static func open(_ routineId: UUID, in app: XCUIApplication) -> Self {
        app.openDeepLink("tnwtracker://session/\(routineId.uuidString)")
        return RoutineDetailScreen(app: app).waitUntilLoaded()
    }

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

    /// Back to the routine list.
    func back() -> RoutineListScreen {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        return RoutineListScreen(app: app).waitUntilLoaded()
    }
}
