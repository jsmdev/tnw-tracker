import TNWTrackerKit
import XCTest

/// T10 AC10.1: Home lists "Otras rutinas" (the routines "Próxima sesión" does not
/// propose, favourites first with a star) and opens the full list with "Ver todas";
/// accessibility audit on the new elements.
@MainActor
final class OtherRoutinesUITests: XCTestCase {
    private let fullBodyA = SampleTrainingData.RoutineID.fullBodyA
    private let fullBodyB = SampleTrainingData.RoutineID.fullBodyB

    func test_homeListsOtherRoutinesAndOpensTheFullList() throws {
        let app = launchUITestApp()
        let home = HomeScreen(app: app).waitUntilLoaded(timeout: 10)

        // Home proposes Full Body A; "Otras rutinas" lists only Full Body B.
        XCTAssertEqual(home.nextSessionTitle.label, "Full Body A")
        XCTAssertTrue(home.otherRoutine(fullBodyB).waitForExistence(timeout: 5))
        XCTAssertFalse(home.otherRoutine(fullBodyA).exists, "The proposed routine is not repeated.")
        XCTAssertFalse(home.isFavorite(fullBodyB), "No favourites yet: no star.")
        XCTAssertTrue(home.seeAllRoutinesButton.exists)
        try app.auditAccessibility(
            screen: "home other routines",
            only: [AXID.Home.otherRoutine(fullBodyB), AXID.Home.seeAllRoutinesButton]
        )

        // A row opens the routine's detail, which shows the target reps as a range (T8).
        let detail = home.openOtherRoutine(fullBodyB)
        XCTAssertTrue(
            detail.target(spokenAs: ["3 series de 6 a 8 repeticiones", "3 sets of 6 to 8 reps"]).waitForExistence(timeout: 3),
            "The bench press target should read 3 × 6–8."
        )
        let homeAgain = detail.backToHome()

        // "Ver todas" opens the full list, both routines in it.
        let list = homeAgain.openRoutineList()
        XCTAssertTrue(list.showsInOrder([fullBodyA, fullBodyB]))

        // Both favourites: Home proposes Full Body A (done longest ago) and lists
        // Full Body B in "Otras rutinas" with its star.
        list.toggleFavoriteBySwiping(fullBodyB)
        list.toggleFavoriteBySwiping(fullBodyA)
        let homeWithFavourites = list.back()
        XCTAssertTrue(homeWithFavourites.nextSessionTitle.waitForLabel("Full Body A"))
        XCTAssertTrue(homeWithFavourites.otherRoutine(fullBodyB).waitForExistence(timeout: 5))
        XCTAssertTrue(homeWithFavourites.isFavorite(fullBodyB), "The favourite shows its star.")
        try app.auditAccessibility(screen: "home other routines with a favourite", only: [AXID.Home.otherRoutine(fullBodyB)])
    }
}
