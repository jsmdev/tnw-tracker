import TNWTrackerKit
import XCTest

/// Page Object for the routine list (`SessionListView`).
@MainActor
struct RoutineListScreen {
    let app: XCUIApplication

    // MARK: - Queries

    func row(_ routineId: UUID) -> XCUIElement {
        app.buttons[AXID.RoutineList.row(routineId)]
    }

    var favoriteAction: XCUIElement {
        app.buttons[AXID.RoutineList.favoriteAction]
    }

    // MARK: - Landing

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> Self {
        XCTAssertTrue(
            row(SampleTrainingData.RoutineID.fullBodyA).waitForExistence(timeout: timeout),
            "RoutineListScreen did not load: the Full Body A row was not found within \(timeout)s."
        )
        return self
    }

    // MARK: - Assertions

    /// True when the rows are on screen in this order, top to bottom.
    func showsInOrder(_ routineIds: [UUID]) -> Bool {
        let tops = routineIds.map { row($0).frame.minY }
        return tops == tops.sorted() && Set(tops).count == tops.count
    }

    func isFavorite(_ routineId: UUID) -> Bool {
        (row(routineId).value as? String)?.isEmpty == false
    }

    // MARK: - Actions

    /// Swipes the row and taps the favourite action (mark or unmark).
    @discardableResult
    func toggleFavoriteBySwiping(_ routineId: UUID) -> Self {
        let target = row(routineId)
        // Swipe once the push animation has settled; a swipe during it is lost.
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: target)
        _ = XCTWaiter().wait(for: [hittable], timeout: 3)
        target.swipeLeft()
        if !favoriteAction.waitForExistence(timeout: 2) {
            target.swipeLeft()
        }
        XCTAssertTrue(favoriteAction.waitForExistence(timeout: 3), "The favourite swipe action did not appear.")
        favoriteAction.tap()
        return self
    }

    func openRoutine(_ routineId: UUID) -> RoutineDetailScreen {
        row(routineId).tap()
        return RoutineDetailScreen(app: app).waitUntilLoaded()
    }

    /// Back to Home with the navigation bar's back button.
    func back() -> HomeScreen {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        return HomeScreen(app: app).waitUntilLoaded()
    }
}
