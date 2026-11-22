import TNWTrackerKit
import XCTest

/// Page Object for the exercises screen (`ExerciseListView`, #137 T2b).
@MainActor
struct ExerciseListScreen {
    let app: XCUIApplication

    func row(_ exerciseId: UUID) -> XCUIElement {
        app.buttons[AXID.Exercises.row(exerciseId)]
    }

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> Self {
        XCTAssertTrue(
            row(SampleTrainingData.ExerciseID.benchPress).waitForExistence(timeout: timeout),
            "ExerciseListScreen did not load: the Bench Press row was not found within \(timeout)s."
        )
        return self
    }

    /// True when the rows are on screen in this order, top to bottom.
    func showsInOrder(_ exerciseIds: [UUID]) -> Bool {
        let tops = exerciseIds.map { row($0).frame.minY }
        return tops == tops.sorted() && Set(tops).count == tops.count
    }

    func openSheet(_ exerciseId: UUID) -> ExerciseSheetScreen {
        let target = row(exerciseId)
        if !target.isHittable {
            app.swipeUp()
        }
        target.waitUntilHittable()
        target.tap()
        return ExerciseSheetScreen(app: app).waitUntilLoaded()
    }

    /// Back to Home with the navigation bar's back button.
    /// Back to Inicio through its tab: the list is the Ejercicios tab's root (#174).
    func openHomeTab() -> HomeScreen {
        TabBar(app: app).select(.home)
        return HomeScreen(app: app).waitUntilLoaded()
    }
}
