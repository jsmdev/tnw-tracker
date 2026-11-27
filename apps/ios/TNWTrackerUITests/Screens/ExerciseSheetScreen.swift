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

    /// The in-app browser a related link opens in (S10 T5d).
    var inAppBrowser: XCUIElement {
        app.descendants(matching: .any)[AXID.ExerciseSheet.inAppBrowser].firstMatch
    }

    /// Closes the in-app browser with its own Done button, back to the sheet.
    func closeInAppBrowser() {
        // The browser's own Done button: «OK» in Spanish, "Done" in English.
        // The browser runs in its own process: on a loaded CI runner its bar
        // can take longer than 5 s to show (the hierarchy dumped at a timeout
        // already had the button).
        let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["OK", "Done"])).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 15), "the in-app browser has its Done button")
        done.tap()
        XCTAssertTrue(inAppBrowser.waitForNonExistence(timeout: 5), "the in-app browser closes")
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

    // MARK: - Actions (AC3-AC5)

    /// «Entrenar este ejercicio» / «Añadir a la sesión en curso».
    var trainButton: XCUIElement {
        app.buttons[AXID.ExerciseSheet.trainButton]
    }

    /// Trains the exercise: the sheet closes and the workout opens.
    func train() -> ActiveWorkoutScreen {
        trainButton.waitUntilHittable()
        trainButton.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5), "the sheet closes before the workout opens")
        return ActiveWorkoutScreen(app: app).waitUntilLoaded(timeout: 10)
    }

    private func openAddToRoutine() {
        let button = app.buttons[AXID.ExerciseSheet.addToRoutineButton]
        button.waitUntilHittable()
        button.tap()
    }

    /// «Añadir a rutina» → the routine named `routineName`; returns the message
    /// shown after it. The choices carry their label, not an identifier.
    func addToRoutine(named routineName: String) -> String {
        openAddToRoutine()
        let option = app.buttons[routineName].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3), "«Añadir a rutina» offers the routine")
        option.tap()
        return dismissResult()
    }

    /// «Añadir a rutina» → «Nueva rutina…» → `name` → «Crear»; returns the message shown after it.
    func addToNewRoutine(named name: String) -> String {
        openAddToRoutine()
        let item = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["Nueva rutina…", "New routine…"])
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), "«Añadir a rutina» offers «Nueva rutina…»")
        item.tap()
        // An alert's text field carries no identifier in the accessibility tree.
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "the new routine asks for its name")
        let create = app.alerts.buttons[AXID.ExerciseSheet.newRoutineCreate].firstMatch
        XCTAssertFalse(create.isEnabled, "no name, no routine")
        field.typeText(name)
        create.tap()
        return dismissResult()
    }

    private func dismissResult() -> String {
        let okButton = app.alerts.buttons[AXID.ExerciseSheet.addToRoutineResult].firstMatch
        XCTAssertTrue(okButton.waitForExistence(timeout: 5), "adding tells the user what happened")
        let message = app.alerts.firstMatch.label
        okButton.tap()
        XCTAssertTrue(okButton.waitForNonExistence(timeout: 3))
        return message
    }

    /// Closes the sheet, wherever it was opened from.
    func dismiss() {
        closeButton.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5), "The exercise sheet did not close.")
    }

    func close() -> ExerciseListScreen {
        closeButton.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5), "The exercise sheet did not close.")
        return ExerciseListScreen(app: app)
    }
}
