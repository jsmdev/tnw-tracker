import Foundation
import Supabase
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

/// At launch the app restores the saved session before it decides what to show:
/// the splash stays until the auth service answers, so the login never flashes
/// for someone who is already signed in.
@Suite("Launch route")
@MainActor
struct LaunchRouteTests {
    private func accounts() -> AppAccounts {
        AppAccounts.makeForTesting(
            authRepository: AuthRepositoryMock(),
            remote: { _ in InMemoryTrainingRemoteStore() }
        )
    }

    @Test("While the saved session is being restored the splash shows, not the login")
    func splashUntilTheSessionIsKnown() {
        let accounts = accounts()

        #expect(accounts.launchRoute == .splash)
        #expect(accounts.current == nil)
    }

    @Test("A restored session goes straight to its account")
    func restoredSessionOpensTheAccount() async {
        let accounts = accounts()
        let userId = UUID()

        await accounts.handle(AuthStateChange(event: .initialSession, userId: userId))

        #expect(accounts.launchRoute == .account(userId))
        #expect(accounts.current?.userId == userId)
    }

    @Test("With no saved session the login shows")
    func noSavedSessionShowsTheLogin() async {
        let accounts = accounts()

        await accounts.handle(AuthStateChange(event: .initialSession, userId: nil))

        #expect(accounts.launchRoute == .login)
    }

    @Test("Signing out after launch shows the login")
    func signingOutShowsTheLogin() async {
        let accounts = accounts()
        await accounts.handle(AuthStateChange(event: .initialSession, userId: UUID()))

        await accounts.handle(AuthStateChange(event: .signedOut, userId: nil))

        #expect(accounts.launchRoute == .login)
        #expect(accounts.current == nil)
    }

    @Test("Signing in from the login goes to the account")
    func signingInFromTheLogin() async {
        let accounts = accounts()
        await accounts.handle(AuthStateChange(event: .initialSession, userId: nil))
        let userId = UUID()

        await accounts.handle(AuthStateChange(event: .signedIn, userId: userId))

        #expect(accounts.launchRoute == .account(userId))
    }
}
