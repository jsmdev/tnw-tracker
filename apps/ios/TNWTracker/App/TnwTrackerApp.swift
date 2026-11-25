import SwiftUI
import TNWTrackerKit

@main
struct TnwTrackerApp: App {
    @State private var accounts: AppAccounts?
    @Environment(\.scenePhase) private var scenePhase
    /// The splash stays at least this long, so its hand-over never reads as a flash.
    @State private var splashMinimumElapsed = false

    /// The splash until the saved session is known (and its minimum time is up),
    /// then the account or the login: the login never shows to someone signed in.
    private var route: LaunchRoute {
        guard let accounts, splashMinimumElapsed else { return .splash }
        return accounts.launchRoute
    }

    /// UI tests never reach YouTube: related video covers and players show stand-ins.
    private static var isUITesting: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("--uitesting")
        #else
            false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch route {
                case .splash:
                    SplashView()
                        .transition(.asymmetric(
                            insertion: .identity,
                            removal: .opacity.combined(with: .scale(scale: 1.15))
                        ))
                case .login:
                    if let accounts {
                        LoginView { email, password in
                            _ = try await accounts.authRepository.signIn(email: email, password: password)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(AXID.Login.screen)
                        .transition(.opacity)
                    }
                case .account:
                    if let accounts, let env = accounts.current {
                        // One view tree per account: nothing of one account's screens survives a switch (S10).
                        RootView()
                            .environment(env)
                            .environment(accounts)
                            .environment(\.relatedLinksUseNetwork, !Self.isUITesting)
                            .id(env.userId)
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeOut(duration: 0.35), value: route)
            .task {
                try? await Task.sleep(for: .seconds(0.6))
                splashMinimumElapsed = true
            }
            .task {
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                        // UI test bypass: pre-authenticated, in-memory store with the
                        // invented sample data, no real auth and no sync.
                        let accounts = await AppAccounts.bootstrapForUITesting()
                        accounts.startIntentObserver()
                        self.accounts = accounts
                        // Live Activities left by an earlier run make the system
                        // relaunch the app in the background, without `--uitesting`,
                        // racing the next run's first launch (T11).
                        await LiveActivityController.endAll()
                        return
                    }
                #endif
                let accounts: AppAccounts
                do {
                    accounts = try AppAccounts.bootstrap()
                } catch {
                    fatalError("Failed to open the account stores: \(error)")
                }
                self.accounts = accounts
                // El auth listener maneja la restauración: al suscribirse, Supabase
                // emite `.initialSession` con la sesión persistida (o nil), que abre
                // el store de esa cuenta.
                accounts.startAuthListener()
                accounts.startIntentObserver()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                accounts?.sceneDidEnterBackground()
            }
        }
    }
}
