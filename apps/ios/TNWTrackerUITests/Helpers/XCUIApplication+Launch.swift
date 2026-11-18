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
