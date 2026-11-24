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

    /// #182 S9 (T4b-ui): related videos show by cover, title and source; a
    /// YouTube one plays in the sheet, one video at a time, and «Abrir en
    /// YouTube» or any other link opens outside the app. No network: covers and
    /// the player are stand-ins.
    func test_relatedVideosPlayInTheSheetAndOpenOutside() throws {
        let app = launchUITestApp()
        let list = HomeScreen(app: app).waitUntilLoaded(timeout: 10).openExercises()

        // S10 AC1: no related links, the section still offers «Añadir enlace».
        let squat = list.openSheet(Sample.gobletSquat)
        XCTAssertTrue(squat.relatedHeader.waitForExistence(timeout: 5), "the section shows with no links")
        XCTAssertTrue(squat.addLinkButton.exists)
        XCTAssertFalse(squat.relatedLink(1).exists, "no rows")

        // AC1: each one by its title and source, never its address.
        let press = squat.close().openSheet(Sample.chestPress)
        let youTube = press.relatedLink(1)
        let other = press.relatedLink(2)
        XCTAssertTrue(youTube.waitForExistence(timeout: 5))
        XCTAssertTrue(youTube.label.contains("Chest press, step by step"), youTube.label)
        XCTAssertTrue(youTube.label.contains("YouTube"), youTube.label)
        XCTAssertTrue(other.label.contains("Chest press guide"), other.label)
        XCTAssertTrue(other.label.contains("Example"), other.label)
        let address = NSPredicate(format: "label CONTAINS[c] 'youtube.com' OR label CONTAINS[c] 'example.test'")
        XCTAssertEqual(app.descendants(matching: .any).matching(address).count, 0, "no address on screen")
        XCTAssertFalse(press.relatedLinkPlayer.exists, "nothing plays until asked")

        // AC2: the main video plays first; the related one takes over from it.
        press.toggleVideo()
        XCTAssertTrue(press.video.waitForExistence(timeout: 5))
        youTube.tap()
        XCTAssertTrue(press.relatedLinkPlayer.waitForExistence(timeout: 5), "it plays in the sheet")
        XCTAssertTrue(press.video.waitForNonExistence(timeout: 5), "one video at a time: the main one closes")
        // Audit once the row has finished opening: mid-animation the audit misreads contrast.
        waitUntilStill(press.relatedLinkPlayer)
        attachScreenshot(of: app, named: "exercise sheet, related video playing")
        // Only the related section: the sheet has scrolled, so its top lies under
        // the blurred top edge; test_homeOpensTheExerciseListAndASheet audits it.
        try app.auditAccessibility(
            screen: "exercise sheet, related video playing",
            only: [
                AXID.ExerciseSheet.relatedHeader, AXID.ExerciseSheet.relatedLink(1),
                AXID.ExerciseSheet.relatedLink(2),
                AXID.ExerciseSheet.relatedLinkOpen(1), AXID.ExerciseSheet.relatedLinkPlayer
            ]
        )

        // AC3: «Abrir en YouTube» opens it outside the app.
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        // Safari's first launch on a CI runner can take well over 10s.
        let safariLaunch: TimeInterval = 30
        press.openInYouTube(1).tap()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: safariLaunch), "the video opens outside the app")
        app.activate()

        // AC6: collapsing the row stops it; opening the main video closes it too.
        XCTAssertTrue(press.relatedLinkPlayer.waitForExistence(timeout: 5))
        press.toggleVideo()
        XCTAssertTrue(press.relatedLinkPlayer.waitForNonExistence(timeout: 5), "the main video closes the related one")
        youTube.tap()
        XCTAssertTrue(press.relatedLinkPlayer.waitForExistence(timeout: 5))
        youTube.tap()
        XCTAssertTrue(press.relatedLinkPlayer.waitForNonExistence(timeout: 5), "tapping it again stops it")

        // AC4: a link to another site opens outside the app, with no player.
        other.tap()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: safariLaunch), "the link opens outside the app")
        app.activate()
        XCTAssertFalse(press.relatedLinkPlayer.exists, "no player for another site")

        _ = press.close().openHomeTab()
    }

    /// S10 T5c (AC1-AC4): the user adds a link from a pasted address with its
    /// preview, after ours and labelled «Personal»; edits its title and deletes
    /// it, after confirming. Ours have no menu; an address that is not https is
    /// refused. No network: the preview is a stand-in.
    func test_personalLinksAreAddedEditedAndDeleted() throws {
        let app = launchUITestApp()
        let press = HomeScreen(app: app).waitUntilLoaded(timeout: 10).openExercises().openSheet(Sample.chestPress)

        // AC4: ours have no menu.
        XCTAssertTrue(press.relatedLink(2).waitForExistence(timeout: 5))
        XCTAssertFalse(press.relatedLinkMenu(1).exists, "ours cannot be edited or deleted")
        XCTAssertFalse(press.relatedLinkMenu(2).exists, "ours cannot be edited or deleted")

        // AC3: an address that is not https is refused with a message.
        var form = press.openAddLink()
        form.typeAddress("http://blog.example.test/chest")
        form.replaceTitle(with: "Chest notes")
        form.saveButton.tap()
        XCTAssertTrue(form.problem.waitForExistence(timeout: 3), "refused with a message")
        attachScreenshot(of: app, named: "add link, address refused")
        try app.auditAccessibility(
            screen: "add link, address refused", only: formIDs.union([AXID.RelatedLinkForm.problem])
        )
        form.cancel()
        XCTAssertFalse(press.relatedLink(3).exists, "nothing was added")

        // AC2: the preview shows its image, title and site; the title is filled in.
        form = press.openAddLink()
        form.typeAddress("https://blog.example.test/chest-press-notes")
        XCTAssertTrue(form.previewImage.waitForExistence(timeout: 5), "the preview's image shows")
        XCTAssertTrue(form.site.label.contains(StandInLinkPreviewProvider.site), form.site.label)
        XCTAssertEqual(form.title.value as? String, StandInLinkPreviewProvider.title, "the title is filled in")
        attachScreenshot(of: app, named: "add link, preview")
        // Only our elements: the audit reports a contrast failure it cannot tie
        // to any element on the system Form (its section headers and keyboard).
        try app.auditAccessibility(screen: "add link, preview", only: formIDs)
        form.save()

        // AC2: after ours, labelled «Personal», by title and site, never its address.
        let personal = press.relatedLink(3)
        XCTAssertTrue(personal.waitForExistence(timeout: 5), "the link is added after ours")
        XCTAssertTrue(personal.label.contains(StandInLinkPreviewProvider.title), personal.label)
        XCTAssertTrue(personal.label.contains(StandInLinkPreviewProvider.site), personal.label)
        XCTAssertTrue(personal.label.contains("Personal"), personal.label)
        XCTAssertFalse(press.relatedLink(1).label.contains("Personal"), "ours carry no label")
        let address = NSPredicate(format: "label CONTAINS[c] 'example.test' OR value CONTAINS[c] 'example.test'")
        XCTAssertEqual(app.descendants(matching: .any).matching(address).count, 0, "no address on screen")
        XCTAssertTrue(press.relatedLinkMenu(3).exists, "a personal link has a menu")
        // The new row in full, «Personal» included, for the screenshot.
        app.swipeUp()
        // Audit once the scroll has settled: mid-scroll the audit misreads contrast.
        waitUntilStill(personal)
        attachScreenshot(of: app, named: "related links, personal added")
        // Without the header: after this scroll the CI simulator measures it where
        // the first row is shown; test_relatedVideosPlayInTheSheetAndOpenOutside audits it.
        try app.auditAccessibility(
            screen: "related links, personal added",
            only: [
                AXID.ExerciseSheet.relatedLink(1),
                AXID.ExerciseSheet.relatedLink(2), AXID.ExerciseSheet.relatedLink(3),
                AXID.ExerciseSheet.relatedLinkMenu(3), AXID.ExerciseSheet.addLinkButton
            ]
        )

        // AC4: its title is edited.
        form = press.openEditTitle(3)
        XCTAssertFalse(form.address.exists, "only the title is edited")
        form.replaceTitle(with: "My chest press notes")
        attachScreenshot(of: app, named: "edit link title")
        try app.auditAccessibility(screen: "edit link title", only: formIDs)
        form.save()
        XCTAssertTrue(waitForLabel(of: press.relatedLink(3), containing: "My chest press notes"))

        // AC4: it is deleted after confirming.
        let confirm = press.askToDelete(3)
        attachScreenshot(of: app, named: "delete link, confirmation")
        confirm.tap()
        XCTAssertTrue(press.relatedLink(3).waitForNonExistence(timeout: 5), "the link is gone")
        XCTAssertTrue(press.relatedLink(2).exists, "ours stay")

        _ = press.close().openHomeTab()
    }

    private let formIDs: Set<String> = [
        AXID.RelatedLinkForm.address, AXID.RelatedLinkForm.title, AXID.RelatedLinkForm.site,
        AXID.RelatedLinkForm.previewImage, AXID.RelatedLinkForm.saveButton, AXID.RelatedLinkForm.cancelButton
    ]

    private func waitForLabel(of element: XCUIElement, containing text: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits until `element` keeps the same frame for half a second.
    private func waitUntilStill(_ element: XCUIElement, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        var last = element.frame
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            let now = element.frame
            if now == last {
                return
            }
            last = now
        }
        XCTFail("\(element) kept moving for \(timeout)s")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
