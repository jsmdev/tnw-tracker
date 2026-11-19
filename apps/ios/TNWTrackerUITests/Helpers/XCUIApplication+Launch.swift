import XCTest

/// Launches the app configured for UI testing.
/// Sets `--uitesting` launch argument (implies in-memory SwiftData store + auth bypass).
@MainActor
/// `extraArguments` select a variant, such as `--uitesting-store-of-another-user`.
func launchUITestApp(extraArguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitesting"] + extraArguments
    app.launch()
    return app
}
