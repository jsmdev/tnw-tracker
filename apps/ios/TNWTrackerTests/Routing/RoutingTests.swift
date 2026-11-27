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

    // REQ-ROUTE-03: tnwtracker://workout/active → DeepLink.openActiveWorkout.
    @Test func parsesWorkoutActive() throws {
        let url = try #require(URL(string: "tnwtracker://workout/active"))
        #expect(DeepLinkParser.parse(url) == .openActiveWorkout)
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

    @Test func rejectsWorkoutWithoutActivePath() throws {
        let url = try #require(URL(string: "tnwtracker://workout"))
        #expect(DeepLinkParser.parse(url) == nil)
    }

    /// Cobertura parameterizada de URLs válidas e inválidas (REQ-ROUTE-03 verification).
    @Test(arguments: [
        ("tnwtracker://session/8400E1D8-3F4A-4B3F-9DAB-1234567890AB", true),
        ("tnwtracker://exercise/AAAABBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF", true),
        ("tnwtracker://session-history", true),
        ("tnwtracker://settings", true),
        ("tnwtracker://workout/active", true),
        ("tnwtracker://session/not-a-uuid", false),
        ("tnwtracker://workout", false),
        ("tnwtracker://nope", false),
        ("https://example.com/session/8400E1D8-3F4A-4B3F-9DAB-1234567890AB", false)
    ])
    func parameterizedValidAndInvalidUrls(input: String, isValid: Bool) throws {
        let url = try #require(URL(string: input))
        if isValid {
            #expect(DeepLinkParser.parse(url) != nil)
        } else {
            #expect(DeepLinkParser.parse(url) == nil)
        }
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
        #expect(router.presentedExercise == nil)
        #expect(router.exerciseToTrain == nil)
    }
}

/// Exercise sheet actions, AC1-AC4: one exercise sheet for the whole app, and
/// training the exercise picked in it once the sheet has closed.
@Suite("Router — exercise sheet")
@MainActor
struct RouterExerciseSheetTests {
    @Test("AC2 an exercise route opens its sheet instead of a screen")
    func exerciseRouteOpensTheSheet() {
        let router = Router()
        let id = UUID()

        router.push(.exerciseDetail(exerciseID: id))

        #expect(router.presentedExercise == ExercisePresentation(id: id))
        #expect(router.path.isEmpty, "nothing is pushed")
    }

    @Test("AC2 the exercise deep link opens the sheet on the Exercises tab")
    func deepLinkOpensTheSheet() throws {
        let router = Router()
        let id = UUID()
        let url = try #require(URL(string: "tnwtracker://exercise/\(id.uuidString)"))

        router.handle(deepLink: url)

        #expect(router.selectedTab == .exercises)
        #expect(router.presentedExercise == ExercisePresentation(id: id))
        #expect(router.exercisesPath.isEmpty)
    }

    @Test("AC3 with no workout in progress, the picked exercise starts a free session once the sheet closes")
    func trainStartsAFreeSession() throws {
        let router = Router()
        let exercise = UUID()
        router.presentExercise(exercise)

        router.train(exercise)

        #expect(router.presentedExercise == nil, "the sheet closes first")
        #expect(router.presentedActiveWorkout == nil, "nothing opens while the sheet is still closing")
        router.exerciseSheetDidClose(sessionInProgressId: nil)
        let presented = try #require(router.presentedActiveWorkout)
        #expect(presented.isFree)
        #expect(presented.startingExerciseId == exercise)
        #expect(router.exerciseToTrain == nil)
    }

    @Test("AC4 with a workout in progress, the picked exercise reopens that workout")
    func trainReopensTheWorkoutInProgress() {
        let router = Router()
        let exercise = UUID()
        let inProgress = UUID()
        router.presentExercise(exercise)

        router.train(exercise)
        router.exerciseSheetDidClose(sessionInProgressId: inProgress)

        let expected = ActiveWorkoutPresentation(id: inProgress, startingExerciseId: exercise)
        #expect(router.presentedActiveWorkout == expected)
        #expect(router.presentedActiveWorkout?.isFree == false)
    }

    @Test("opening another exercise forgets an exercise picked to train before")
    func openingAnotherExerciseForgetsTheEarlierPick() {
        let router = Router()
        router.train(UUID())

        router.presentExercise(UUID())
        router.presentedExercise = nil
        router.exerciseSheetDidClose(sessionInProgressId: nil)

        #expect(router.presentedActiveWorkout == nil)
    }

    @Test("closing the sheet without training opens nothing")
    func closingWithoutTrainingOpensNothing() {
        let router = Router()
        router.presentExercise(UUID())
        router.presentedExercise = nil

        router.exerciseSheetDidClose(sessionInProgressId: UUID())

        #expect(router.presentedActiveWorkout == nil)
    }

    @Test("other routes are still pushed")
    func otherRoutesArePushed() {
        let router = Router()
        router.push(.workoutDetail(sessionID: UUID()))
        #expect(router.path.count == 1)
        #expect(router.presentedExercise == nil)
    }
}
