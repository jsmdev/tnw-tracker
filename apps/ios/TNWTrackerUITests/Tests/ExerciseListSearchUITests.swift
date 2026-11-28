import TNWTrackerKit
import XCTest

/// fast-add-exercise S7 and S8: the exercise list shows each exercise's photo
/// and has a search field, also in the workout's picker. Invented sample data:
/// only Chest Press Machine has a photo.
@MainActor
final class ExerciseListSearchUITests: XCTestCase {
    private typealias Sample = SampleTrainingData.ExerciseID

    func test_listShowsPhotosAndSearchFiltersByName() throws {
        let app = launchUITestApp()
        let list = HomeScreen(app: app).waitUntilLoaded(timeout: 10).openExercises()

        // S7: the photo shows in the row's square; without one, the initial stays.
        XCTAssertTrue(app.images[AXID.Exercises.photo(Sample.chestPress)].waitForExistence(timeout: 5), "no photo")
        XCTAssertFalse(app.images[AXID.Exercises.photo(Sample.gobletSquat)].exists, "an exercise without photo")
        attachScreenshot(of: app, named: "Exercise list with photos")

        // S8: typing keeps only the matching names, ignoring case and accents.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3), "the list has no search field")
        search.tap()
        search.typeText("PRESS")
        XCTAssertTrue(list.row(Sample.chestPress).waitForExistence(timeout: 3))
        XCTAssertTrue(list.row(Sample.benchPress).exists)
        XCTAssertFalse(list.row(Sample.gobletSquat).exists, "a name without «press» is hidden")
        attachScreenshot(of: app, named: "Exercise search")
        try app.auditAccessibility(
            screen: "exercise search",
            only: [AXID.Exercises.row(Sample.chestPress), AXID.Exercises.row(Sample.benchPress)]
        )

        search.typeText("zzz")
        XCTAssertTrue(app.descendants(matching: .any)[AXID.Exercises.noResults].waitForExistence(timeout: 3))
    }

    func test_workoutPickerSearchesToo() {
        let app = launchUITestApp()
        let active = HomeScreen(app: app).waitUntilLoaded(timeout: 10).startFreeSession()
        active.addExerciseButton.waitUntilHittable()
        active.addExerciseButton.tap()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the picker has no search field")
        search.tap()
        search.typeText("goblet")
        let squat = app.buttons[AXID.Exercises.row(Sample.gobletSquat)]
        XCTAssertTrue(squat.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons[AXID.Exercises.row(Sample.benchPress)].exists)
        squat.tap()
        XCTAssertTrue(active.exerciseTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(active.exerciseTitle.label, "Goblet Squat")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
