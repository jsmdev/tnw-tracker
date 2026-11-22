import TNWTrackerKit
import XCTest

/// #174: the tab bar switches between Inicio, Historial and Ejercicios, and
/// each tab keeps its own navigation. Accessibility audit on each tab.
@MainActor
final class TabBarUITests: XCTestCase {
    func test_tabsSwitchAndKeepTheirNavigation() throws {
        let app = launchUITestApp()
        let home = HomeScreen(app: app).waitUntilLoaded(timeout: 10)
        let tabBar = TabBar(app: app)
        for item in TabBar.Item.allCases {
            XCTAssertTrue(tabBar.button(item).waitForExistence(timeout: 10), "tab \(item) is in the tab bar")
        }
        XCTAssertEqual(app.tabBars.buttons.count, TabBar.Item.allCases.count)
        XCTAssertTrue(tabBar.button(.home).isSelected)
        // Only the tab bar: Home's own contrast issues are tracked apart.
        // The identifiers the tab bar exposes (none on iOS 26.0): never "", which
        // would bring every unidentified element of the screen into the audit.
        let tabIds = Set(TabBar.Item.allCases.map { tabBar.button($0).identifier }.filter { !$0.isEmpty })
        try app.auditAccessibility(screen: "home tab", only: tabIds)

        // Inicio → Ajustes, then away and back: Ajustes is still there.
        _ = home.tapSettings()
        tabBar.select(.history)
        HistoryScreen(app: app).waitUntilLoaded()
        try app.auditAccessibility(screen: "history tab", only: tabIds.union([AXID.History.list]))

        _ = HomeScreen(app: app).openExercises()
        XCTAssertTrue(tabBar.button(.exercises).isSelected)
        try app.auditAccessibility(screen: "exercises tab")

        tabBar.select(.home)
        _ = SettingsScreen(app: app).waitUntilLoaded()
    }
}
