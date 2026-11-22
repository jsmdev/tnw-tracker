import TNWTrackerKit
import XCTest

/// Page Object for a finished workout of the history (#174 S7).
@MainActor
struct WorkoutDetailScreen {
    let app: XCUIApplication

    var list: XCUIElement {
        app.descendants(matching: .any)[AXID.WorkoutDetail.list]
    }

    var deleteButton: XCUIElement {
        app.buttons[AXID.WorkoutDetail.deleteButton].firstMatch
    }

    var importedNote: XCUIElement {
        app.descendants(matching: .any)[AXID.WorkoutDetail.importedNote]
    }

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> Self {
        XCTAssertTrue(list.waitForExistence(timeout: timeout), "WorkoutDetailScreen did not load.")
        return self
    }

    /// Deletes the workout and confirms; the app goes back to the history.
    func delete() -> HistoryScreen {
        deleteButton.waitUntilHittable()
        deleteButton.tap()
        DeleteWorkoutAlert(app: app).confirm()
        return HistoryScreen(app: app)
    }

    func back() -> HistoryScreen {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        back.waitUntilHittable()
        back.tap()
        return HistoryScreen(app: app)
    }
}

/// "¿Borrar este entrenamiento?" (#174 S7).
@MainActor
struct DeleteWorkoutAlert {
    let app: XCUIApplication

    func confirm() {
        let confirm = app.buttons[AXID.DeleteWorkout.confirm].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the delete confirmation did not appear")
        confirm.tap()
    }
}
