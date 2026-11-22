import TNWTrackerKit
import XCTest

/// Page Object for the Historial tab (#174).
@MainActor
struct HistoryScreen {
    let app: XCUIApplication

    /// The list, or the empty state when no workout is finished yet.
    var title: XCUIElement {
        app.navigationBars.staticTexts.firstMatch
    }

    func row(_ sessionId: UUID) -> XCUIElement {
        app.descendants(matching: .any)[AXID.History.row(sessionId)]
    }

    var count: XCUIElement {
        app.staticTexts[AXID.History.count]
    }

    var noResults: XCUIElement {
        app.staticTexts[AXID.History.noResults]
    }

    var clearFilters: XCUIElement {
        app.buttons[AXID.History.clearFilters].firstMatch
    }

    func chip(_ identifier: String) -> XCUIElement {
        app.buttons[identifier].firstMatch
    }

    func tapChip(_ identifier: String) {
        let chip = chip(identifier)
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "no chip \(identifier)")
        chip.waitUntilHittable()
        chip.tap()
    }

    /// Types in the search field (shown above the list).
    func search(_ text: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no search field")
        field.tap()
        field.typeText(text)
    }

    /// The row of the workout called `name` (the sample data's ids are not fixed).
    func row(named name: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'history.row.' AND label BEGINSWITH %@", name))
            .firstMatch
    }

    func openWorkout(named name: String) -> WorkoutDetailScreen {
        let row = row(named: name)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no history row for \(name)")
        row.waitUntilHittable()
        row.tap()
        return WorkoutDetailScreen(app: app).waitUntilLoaded()
    }

    /// Swipes the row to show its actions. Returns the delete action, which a
    /// workout with machine data does not have.
    func swipe(named name: String) -> XCUIElement {
        let row = row(named: name)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no history row for \(name)")
        row.waitUntilHittable()
        row.swipeLeft()
        return app.buttons[AXID.History.deleteAction].firstMatch
    }

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> Self {
        let tab = TabBar(app: app).button(.history)
        XCTAssertTrue(
            tab.waitForExistence(timeout: timeout),
            "HistoryScreen did not load: the Historial tab is missing."
        )
        XCTAssertTrue(tab.isSelected, "the Historial tab is not selected")
        return self
    }
}
