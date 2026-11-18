import XCTest

/// Launches the app configured for UI testing.
/// Sets `--uitesting` launch argument (implies in-memory SwiftData store + auth bypass).
@MainActor
func launchUITestApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitesting"]
    app.launch()
    return app
}

extension XCUIApplication {
    /// Opens a `tnwtracker://` deep link in the running app, keeping its state
    /// (`XCUIApplication.open(_:)` relaunches it, which empties the in-memory store).
    /// Confirms the system "Open in …" prompt when it appears.
    func openDeepLink(_ link: String) {
        guard let url = URL(string: link) else { return XCTFail("Invalid deep link \(link)") }
        XCUIDevice.shared.system.open(url)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirm = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "Abrir"])).firstMatch
        if confirm.waitForExistence(timeout: 2) {
            confirm.tap()
        }
    }
}
