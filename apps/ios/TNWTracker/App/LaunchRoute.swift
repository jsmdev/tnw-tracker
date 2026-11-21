import Foundation

/// The screen the app shows at its root.
enum LaunchRoute: Equatable {
    /// The saved session is still being restored.
    case splash
    /// Nobody is signed in.
    case login
    /// The signed-in account.
    case account(UUID)
}

extension AppAccounts {
    /// What the app shows: the splash while the saved session is restored, then
    /// the signed-in account or the login.
    var launchRoute: LaunchRoute {
        if let current { return .account(current.userId) }
        return isSessionResolved ? .login : .splash
    }
}
