import TNWTrackerKit
import XCTest

/// Page Object for the prompt shown when ending a workout with no working sets (T6).
@MainActor
struct DiscardWorkoutScreen {
    let app: XCUIApplication

    /// The prompt's title, in es-ES or en.
    static let titles = [
        "No has registrado ninguna serie. ¿Descartar el entrenamiento?",
        "You haven't logged any sets. Discard the workout?"
    ]

    // MARK: - Queries

    var title: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label IN %@", Self.titles)).firstMatch
    }

    var discardButton: XCUIElement {
        app.buttons[AXID.DiscardWorkout.discardButton].firstMatch
    }

    var keepTrainingButton: XCUIElement {
        app.buttons[AXID.DiscardWorkout.keepTrainingButton].firstMatch
    }

    // MARK: - Landing

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 3) -> Self {
        XCTAssertTrue(
            discardButton.waitForExistence(timeout: timeout),
            "DiscardWorkoutScreen did not load: discardButton not found within \(timeout)s."
        )
        return self
    }

    // MARK: - Actions

    /// "Seguir entrenando": back to the workout, unchanged.
    func keepTraining() -> ActiveWorkoutScreen {
        keepTrainingButton.tap()
        return ActiveWorkoutScreen(app: app).waitUntilLoaded()
    }

    /// "Descartar": the session is deleted and Home shows again, with no summary.
    func discard() -> HomeScreen {
        discardButton.tap()
        // Wait for the workout cover to finish closing before using Home.
        let endButton = app.buttons[AXID.ActiveWorkout.endButton]
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: endButton)
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: 5),
            .completed,
            "The workout did not close after discarding."
        )
        return HomeScreen(app: app).waitUntilLoaded()
    }
}
