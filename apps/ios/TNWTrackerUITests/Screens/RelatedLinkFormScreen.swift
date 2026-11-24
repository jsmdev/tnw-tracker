import TNWTrackerKit
import XCTest

/// Page Object for the sheet that adds a personal related link or edits its
/// title (`RelatedLinkFormSheet`, S10).
@MainActor
struct RelatedLinkFormScreen {
    let app: XCUIApplication

    var address: XCUIElement {
        app.textFields[AXID.RelatedLinkForm.address]
    }

    var title: XCUIElement {
        app.textFields[AXID.RelatedLinkForm.title]
    }

    var site: XCUIElement {
        app.descendants(matching: .any)[AXID.RelatedLinkForm.site].firstMatch
    }

    var previewImage: XCUIElement {
        app.images[AXID.RelatedLinkForm.previewImage]
    }

    var problem: XCUIElement {
        app.descendants(matching: .any)[AXID.RelatedLinkForm.problem].firstMatch
    }

    var saveButton: XCUIElement {
        app.buttons[AXID.RelatedLinkForm.saveButton]
    }

    var cancelButton: XCUIElement {
        app.buttons[AXID.RelatedLinkForm.cancelButton]
    }

    @discardableResult
    func waitUntilLoaded(timeout: TimeInterval = 5) -> Self {
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: timeout),
            "RelatedLinkFormScreen did not load: «Guardar» was not found within \(timeout)s."
        )
        return self
    }

    func typeAddress(_ text: String) {
        address.tap()
        address.typeText(text)
    }

    /// Replaces the title with `text`.
    func replaceTitle(with text: String) {
        // At the end of the text, so deleting removes all of it.
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let current = (title.value as? String) ?? ""
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    /// «Guardar», when it is expected to close the sheet.
    func save() {
        saveButton.tap()
        XCTAssertTrue(saveButton.waitForNonExistence(timeout: 5), "the link was saved and the sheet closed")
    }

    func cancel() {
        cancelButton.tap()
        XCTAssertTrue(saveButton.waitForNonExistence(timeout: 5), "the sheet closed")
    }
}
