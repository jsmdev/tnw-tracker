import Foundation
import Testing
@testable import TNWTracker

@Suite("Route")
struct RouteTests {
    @Test func sessionDetailEquality() throws {
        let id = try #require(UUID(uuidString: "8400E1D8-3F4A-4B3F-9DAB-1234567890AB"))
        let a = Route.sessionDetail(sessionID: id)
        let b = Route.sessionDetail(sessionID: id)
        #expect(a == b)
    }

    @Test func differentSessionIDsNotEqual() {
        let a = Route.sessionDetail(sessionID: UUID())
        let b = Route.sessionDetail(sessionID: UUID())
        #expect(a != b)
    }

    @Test func settingsEquality() {
        #expect(Route.settings == Route.settings)
    }
}

@Suite("DeepLinkParser")
struct DeepLinkParserTests {
    @Test func parsesSessionDetail() throws {
        let id = try #require(UUID(uuidString: "8400E1D8-3F4A-4B3F-9DAB-1234567890AB"))
        let url = try #require(URL(string: "tnwtracker://session/8400E1D8-3F4A-4B3F-9DAB-1234567890AB"))
        #expect(DeepLinkParser.route(from: url) == .sessionDetail(sessionID: id))
    }

    @Test func parsesExerciseDetail() throws {
        let id = try #require(UUID(uuidString: "AAAABBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"))
        let url = try #require(URL(string: "tnwtracker://exercise/AAAABBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"))
        #expect(DeepLinkParser.route(from: url) == .exerciseDetail(exerciseID: id))
    }

    @Test func parsesSettings() throws {
        let url = try #require(URL(string: "tnwtracker://settings"))
        #expect(DeepLinkParser.route(from: url) == .settings)
    }

    @Test func parsesSessionHistory() throws {
        let url = try #require(URL(string: "tnwtracker://session-history"))
        #expect(DeepLinkParser.route(from: url) == .sessionHistory)
    }

    @Test func rejectsUnknownScheme() throws {
        let url = try #require(URL(string: "https://example.com/session/8400E1D8-3F4A-4B3F-9DAB-1234567890AB"))
        #expect(DeepLinkParser.route(from: url) == nil)
    }

    @Test func rejectsUnknownHost() throws {
        let url = try #require(URL(string: "tnwtracker://unknownroute"))
        #expect(DeepLinkParser.route(from: url) == nil)
    }

    @Test func rejectsSessionDetailWithInvalidUUID() throws {
        let url = try #require(URL(string: "tnwtracker://session/not-a-uuid"))
        #expect(DeepLinkParser.route(from: url) == nil)
    }
}

@Suite("Router")
@MainActor
struct RouterTests {
    @Test func pushAppendsToPath() {
        let router = Router()
        router.push(.settings)
        #expect(router.path.count == 1)
    }

    @Test func pushMultipleRoutes() {
        let router = Router()
        let id = UUID()
        router.push(.sessionHistory)
        router.push(.sessionDetail(sessionID: id))
        #expect(router.path.count == 2)
    }

    @Test func popDecreasesCount() {
        let router = Router()
        router.push(.settings)
        router.push(.sessionHistory)
        router.pop()
        #expect(router.path.count == 1)
    }

    @Test func popOnEmptyPathIsNoop() {
        let router = Router()
        router.pop()
        #expect(router.path.isEmpty)
    }

    @Test func popToRootClears() {
        let router = Router()
        router.push(.settings)
        router.push(.sessionHistory)
        router.popToRoot()
        #expect(router.path.isEmpty)
    }

    @Test func initialStateHasNoPresentations() {
        let router = Router()
        #expect(router.presentedActiveWorkout == nil)
        #expect(router.presentedWorkoutSummary == nil)
    }
}
