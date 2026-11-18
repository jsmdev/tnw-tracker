import TNWTrackerKit
import XCTest

/// T5 AC5.5: mark a routine as favourite, see it first in the list and proposed
/// on Home; accessibility audit on the list, the routine detail and Home.
@MainActor
final class FavoriteRoutinesUITests: XCTestCase {
    private let fullBodyA = SampleTrainingData.RoutineID.fullBodyA
    private let fullBodyB = SampleTrainingData.RoutineID.fullBodyB

    func test_favouriteRoutineIsListedFirstAndProposedOnHome() throws {
        let app = launchUITestApp()
        let home = HomeScreen(app: app).waitUntilLoaded(timeout: 10)

        // Before: no favourites, Home proposes Full Body A (done longest ago).
        XCTAssertEqual(home.nextSessionTitle.label, "Full Body A")
        try app.auditAccessibility(screen: "home", only: [AXID.Home.nextSessionTitle])

        // AC5.4 swipe: mark Full Body B. AC5.1: it moves first, with the star.
        let list = home.openRoutineList()
        XCTAssertTrue(list.showsInOrder([fullBodyA, fullBodyB]))
        XCTAssertFalse(list.isFavorite(fullBodyB))
        list.toggleFavoriteBySwiping(fullBodyB)
        XCTAssertTrue(list.isFavorite(fullBodyB))
        XCTAssertTrue(list.showsInOrder([fullBodyB, fullBodyA]))
        try app.auditAccessibility(screen: "routine list", only: [AXID.RoutineList.row(fullBodyB)])

        // AC5.3: Home proposes the favourite.
        let homeWithFavourite = list.back()
        XCTAssertTrue(
            homeWithFavourite.nextSessionTitle.waitForLabel("Full Body B"),
            "Home should propose the favourite Full Body B."
        )
        try app.auditAccessibility(screen: "home with a favourite", only: [AXID.Home.nextSessionTitle])

        // AC5.4 star in the detail: unmark Full Body B, it goes back to the name order.
        let detail = homeWithFavourite.openRoutineList().openRoutine(fullBodyB)
        try app.auditAccessibility(screen: "routine detail", only: [AXID.RoutineDetail.favoriteButton])
        detail.toggleFavorite()
        try app.auditAccessibility(screen: "routine detail unmarked", only: [AXID.RoutineDetail.favoriteButton])
        let listAgain = detail.back()
        XCTAssertFalse(listAgain.isFavorite(fullBodyB))
        XCTAssertTrue(listAgain.showsInOrder([fullBodyA, fullBodyB]))
        XCTAssertTrue(listAgain.back().nextSessionTitle.waitForLabel("Full Body A"))
    }
}

extension XCUIElement {
    /// Waits until the element shows `label` (screens reload on appear).
    func waitForLabel(_ label: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
