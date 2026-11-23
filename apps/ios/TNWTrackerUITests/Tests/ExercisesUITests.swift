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

        // AC1: no related videos, no section.
        let squat = list.openSheet(Sample.gobletSquat)
        XCTAssertFalse(squat.relatedVideos.exists, "no related videos: the section is absent")

        // AC1: each one by its title and source, never its address.
        let press = squat.close().openSheet(Sample.chestPress)
        let youTube = press.relatedVideo(1)
        let other = press.relatedVideo(2)
        XCTAssertTrue(youTube.waitForExistence(timeout: 5))
        XCTAssertTrue(youTube.label.contains("Chest press, step by step"), youTube.label)
        XCTAssertTrue(youTube.label.contains("YouTube"), youTube.label)
        XCTAssertTrue(other.label.contains("Chest press guide"), other.label)
        XCTAssertTrue(other.label.contains("Example"), other.label)
        let address = NSPredicate(format: "label CONTAINS[c] 'youtube.com' OR label CONTAINS[c] 'example.test'")
        XCTAssertEqual(app.descendants(matching: .any).matching(address).count, 0, "no address on screen")
        XCTAssertFalse(press.relatedVideoPlayer.exists, "nothing plays until asked")

        // AC2: the main video plays first; the related one takes over from it.
        press.toggleVideo()
        XCTAssertTrue(press.video.waitForExistence(timeout: 5))
        youTube.tap()
        XCTAssertTrue(press.relatedVideoPlayer.waitForExistence(timeout: 5), "it plays in the sheet")
        XCTAssertTrue(press.video.waitForNonExistence(timeout: 5), "one video at a time: the main one closes")
        // Audit once the row has finished opening: mid-animation the audit misreads contrast.
        waitUntilStill(press.relatedVideoPlayer)
        attachScreenshot(of: app, named: "exercise sheet, related video playing")
        try app.auditAccessibility(screen: "exercise sheet, related video playing")

        // AC3: «Abrir en YouTube» opens it outside the app.
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        press.openInYouTube(1).tap()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10), "the video opens outside the app")
        app.activate()

        // AC6: collapsing the row stops it; opening the main video closes it too.
        XCTAssertTrue(press.relatedVideoPlayer.waitForExistence(timeout: 5))
        press.toggleVideo()
        XCTAssertTrue(press.relatedVideoPlayer.waitForNonExistence(timeout: 5), "the main video closes the related one")
        youTube.tap()
        XCTAssertTrue(press.relatedVideoPlayer.waitForExistence(timeout: 5))
        youTube.tap()
        XCTAssertTrue(press.relatedVideoPlayer.waitForNonExistence(timeout: 5), "tapping it again stops it")

        // AC4: a link to another site opens outside the app, with no player.
        other.tap()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10), "the link opens outside the app")
        app.activate()
        XCTAssertFalse(press.relatedVideoPlayer.exists, "no player for another site")

        _ = press.close().openHomeTab()
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
