import XCTest

/// Launches the app configured for UI testing.
/// Sets `--uitesting` launch argument (implies in-memory SwiftData store + auth bypass).
/// `extraArguments` such as `--keep-device-preferences`, to relaunch with the
/// device preferences an earlier launch set.
@MainActor
func launchUITestApp(extraArguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitesting"] + extraArguments
    app.launch()
    return app
}
