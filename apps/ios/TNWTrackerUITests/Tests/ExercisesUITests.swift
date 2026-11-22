import TNWTrackerKit
import XCTest

/// #137 S7, T2b, #174: the Ejercicios tab opens "Exercises", which lists the account's exercises by
/// name; a row opens the exercise's sheet with its how-to steps, its muscles
/// and its image or a placeholder. Invented sample data and an invented image;
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
        try app.auditAccessibility(screen: "exercise sheet, no media")

        // The exercise with an image shows it.
        let press = squat.close().openSheet(Sample.chestPress)
        XCTAssertEqual(press.name.label, "Chest Press Machine")
        XCTAssertTrue(press.image.waitForExistence(timeout: 5), "the invented image shows")
        try app.auditAccessibility(screen: "exercise sheet, image")

        _ = press.close().openHomeTab()
    }
}
