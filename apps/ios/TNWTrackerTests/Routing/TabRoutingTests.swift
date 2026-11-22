import Foundation
import Testing
@testable import TNWTracker

/// Each tab keeps its own navigation stack (#174 S2, S4).
@Suite("Tab routing")
@MainActor
struct TabRoutingTests {
    @Test("the app opens on Inicio with every stack empty")
    func startsOnHome() {
        let router = Router()
        #expect(router.selectedTab == .home)
        #expect(AppTab.allCases.allSatisfy { router.path(for: $0).isEmpty })
    }

    @Test("push goes to the selected tab's stack only")
    func pushToSelectedTab() {
        let router = Router()
        router.selectedTab = .history
        router.push(.settings)
        #expect(router.path(for: .history).count == 1)
        #expect(router.path(for: .home).isEmpty)
    }

    @Test("switching tabs keeps each tab's navigation")
    func switchingKeepsNavigation() {
        let router = Router()
        router.push(.settings)
        router.selectedTab = .exercises
        router.selectedTab = .home
        #expect(router.path(for: .home).count == 1)
    }

    @Test("popToRoot empties the selected tab's stack, not the others")
    func popToRootSelectedOnly() {
        let router = Router()
        router.push(.settings)
        router.selectedTab = .history
        router.push(.settings)
        router.popToRoot()
        #expect(router.path(for: .history).isEmpty)
        #expect(router.path(for: .home).count == 1)
    }

    @Test("a deep link selects the tab that owns the screen", arguments: [
        ("tnwtracker://exercise/AAAABBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF", AppTab.exercises),
        ("tnwtracker://settings", AppTab.home),
        ("tnwtracker://session-history", AppTab.home),
        ("tnwtracker://session/8400E1D8-3F4A-4B3F-9DAB-1234567890AB", AppTab.home)
    ])
    func deepLinkSelectsTab(link: String, tab: AppTab) throws {
        let router = Router()
        router.selectedTab = .history
        router.handle(deepLink: try #require(URL(string: link)))
        #expect(router.selectedTab == tab)
        #expect(router.path(for: tab).count == 1)
        #expect(router.path(for: .history).isEmpty)
    }

    @Test("a finished workout belongs to Historial (#174 S7)")
    func workoutDetailBelongsToHistory() {
        #expect(Route.workoutDetail(sessionID: UUID()).tab == .history)
    }

    @Test("the workout deep link changes no tab (the root view presents it)")
    func workoutLinkKeepsTab() throws {
        let router = Router()
        router.selectedTab = .history
        router.handle(deepLink: try #require(URL(string: "tnwtracker://workout/active")))
        #expect(router.selectedTab == .history)
    }
}
