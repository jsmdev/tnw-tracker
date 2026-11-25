import TNWTrackerKit
import XCTest

/// Page Object for the exercise sheet (`ExerciseSheetView`, #137 S7).
@MainActor
struct ExerciseSheetScreen {
    let app: XCUIApplication

    var name: XCUIElement {
        app.staticTexts[AXID.ExerciseSheet.name]
    }

    var closeButton: XCUIElement {
        app.buttons[AXID.ExerciseSheet.closeButton]
    }

    var image: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.image]
    }

    var placeholder: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.placeholder]
    }

    var videoToggle: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.videoToggle].firstMatch
    }

    var video: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.video]
    }

    /// Opens or closes the "Watch video" section.
    func toggleVideo() {
        let button = app.buttons.matching(
            NSPredicate(format: "identifier == %@", AXID.ExerciseSheet.videoToggle)
        ).firstMatch
        (button.exists ? button : videoToggle).tap()
    }

    var relatedLinks: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.relatedLinks].firstMatch
    }

    /// The `number`th related video's row, from 1.
    func relatedLink(_ number: Int) -> XCUIElement {
        app.buttons[AXID.ExerciseSheet.relatedLink(number)]
    }

    /// "Abrir en YouTube" under the `number`th related video, from 1.
    func openInYouTube(_ number: Int) -> XCUIElement {
        app.buttons[AXID.ExerciseSheet.relatedLinkOpen(number)]
    }

    var relatedLinkPlayer: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.relatedLinkPlayer].firstMatch
    }

    var relatedHeader: XCUIElement {
        app.staticTexts[AXID.ExerciseSheet.relatedHeader]
    }

    /// «Añadir enlace» (S10).
    var addLinkButton: XCUIElement {
        app.buttons[AXID.ExerciseSheet.addLinkButton]
    }

    /// The menu of the `number`th related link, from 1: only personal links have one.
    func relatedLinkMenu(_ number: Int) -> XCUIElement {
        app.buttons[AXID.ExerciseSheet.relatedLinkMenu(number)]
    }

    /// «Añadir enlace»: opens the form.
    func openAddLink() -> RelatedLinkFormScreen {
        addLinkButton.tap()
        return RelatedLinkFormScreen(app: app).waitUntilLoaded()
    }

    /// «Editar título» in the `number`th link's menu.
    func openEditTitle(_ number: Int) -> RelatedLinkFormScreen {
        relatedLinkMenu(number).tap()
        let edit = app.buttons[AXID.ExerciseSheet.relatedLinkEditTitle]
        XCTAssertTrue(edit.waitForExistence(timeout: 3), "the menu offers «Editar título»")
        edit.tap()
        return RelatedLinkFormScreen(app: app).waitUntilLoaded()
    }

    /// «Eliminar» in the `number`th link's menu; returns the confirmation's «Eliminar».
    func askToDelete(_ number: Int) -> XCUIElement {
        relatedLinkMenu(number).tap()
        let delete = app.buttons[AXID.ExerciseSheet.relatedLinkDelete]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "the menu offers «Eliminar»")
        delete.tap()
        let confirm = app.alerts.buttons[AXID.ExerciseSheet.relatedLinkDeleteConfirm].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "deleting asks first")
        return confirm
    }

    var primaryMuscles: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.primaryMuscles]
    }

    func setupStep(_ number: Int) -> XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.setupStep(number)]
    }

    func executionStep(_ number: Int) -> XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.executionStep(number)]
    }

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> Self {
        XCTAssertTrue(
            name.waitForExistence(timeout: timeout),
            "ExerciseSheetScreen did not load: the exercise name was not found within \(timeout)s."
        )
        return self
    }

    func close() -> ExerciseListScreen {
        closeButton.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5), "The exercise sheet did not close.")
        return ExerciseListScreen(app: app)
    }
}
