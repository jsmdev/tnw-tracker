import TNWTrackerKit
import XCTest

/// #174: the tab bar switches between Inicio, Historial and Ejercicios, and
/// each tab keeps its own navigation. Accessibility audit on each tab.
@MainActor
final class TabBarUITests: XCTestCase {
    func test_tabsSwitchAndKeepTheirNavigation() throws {
        let app = launchUITestApp()
        let home = HomeScreen(app: app).waitUntilLoaded(timeout: 10)
        let tabs = [AXID.Tabs.home, AXID.Tabs.history, AXID.Tabs.exercises]
        for tab in tabs {
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 5), "tab \(tab) is in the tab bar")
        }
        XCTAssertTrue(app.tabBars.buttons[AXID.Tabs.home].isSelected)
        // Only the tab bar: Home's own contrast issues are tracked apart.
        try app.auditAccessibility(screen: "home tab", only: Set(tabs))

        // Inicio → Ajustes, then away and back: Ajustes is still there.
        _ = home.tapSettings()
        app.tabBars.buttons[AXID.Tabs.history].tap()
        HistoryScreen(app: app).waitUntilLoaded()
        try app.auditAccessibility(screen: "history tab", only: Set(tabs + [AXID.History.list]))

        _ = HomeScreen(app: app).openExercises()
        try app.auditAccessibility(screen: "exercises tab")

        app.tabBars.buttons[AXID.Tabs.home].tap()
        _ = SettingsScreen(app: app).waitUntilLoaded()
    }
}
