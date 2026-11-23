import TNWTrackerKit
import XCTest

/// #137 S7, T2b, #174: the Ejercicios tab opens "Exercises", which lists the account's exercises by
/// name; a row opens the exercise's sheet with its how-to steps, its muscles
/// and its image or a placeholder; #182 S9: the video under "Watch video". Invented sample data and an invented image;
/// accessibility audit on each screen.
@MainActor
final class ExercisesUITests: XCTestCase {
    private typealias Sample = SampleTrainingData.ExerciseID

    func test_homeOpensTheExerciseListAndASheet() throws {
        let app = launchUITestApp()
        let home = HomeScreen(app: app).waitUntilLoaded(timeout: 10)

        let list = home.openExercises()
        XCTAssertTrue(list.showsInOrder([Sample.benchPress, Sample.chestPress, Sample.gobletSquat]), "sorted by name")
        try app.auditAccessibility(screen: "exercise list")

        // Steps and muscles as stored; no media: the neutral placeholder.
        let squat = list.openSheet(Sample.gobletSquat)
        XCTAssertEqual(squat.name.label, "Goblet Squat")
        XCTAssertTrue(squat.setupStep(1).waitForExistence(timeout: 3))
        XCTAssertTrue(squat.setupStep(1).label.contains("Hold the weight close to the chest."))
        XCTAssertTrue(squat.executionStep(2).label.contains("Stand up tall."))
        XCTAssertTrue(squat.primaryMuscles.exists)
        XCTAssertTrue(squat.placeholder.waitForExistence(timeout: 5))
        XCTAssertFalse(squat.videoToggle.exists, "no video, no video section")
        try app.auditAccessibility(screen: "exercise sheet, no media")

        // The exercise with an image shows it.
        let press = squat.close().openSheet(Sample.chestPress)
        XCTAssertEqual(press.name.label, "Chest Press Machine")
        XCTAssertTrue(press.image.waitForExistence(timeout: 5), "the invented image shows")
        XCTAssertTrue(press.videoToggle.exists, "#182 S9: the video has its own section")
        XCTAssertFalse(press.video.exists, "#182 S9: closed at first")
        try app.auditAccessibility(screen: "exercise sheet, image")

        // #182 S9: "Watch video" opens the system player; the photo stays.
        press.toggleVideo()
        XCTAssertTrue(press.video.waitForExistence(timeout: 5), "the player shows when the section opens")
        XCTAssertTrue(press.image.exists, "the photo stays visible")
        attachScreenshot(of: app, named: "exercise sheet, video open")
        try app.auditAccessibility(screen: "exercise sheet, video open")
        press.toggleVideo()
        XCTAssertTrue(press.video.waitForNonExistence(timeout: 5), "the section closes again")

        _ = press.close().openHomeTab()
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
