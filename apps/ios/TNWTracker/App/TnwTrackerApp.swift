import SwiftUI
import TNWTrackerKit

@main
struct TnwTrackerApp: App {
    @State private var accounts: AppAccounts?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let accounts {
                    if let env = accounts.current {
                        // One view tree per account: nothing of one account's screens survives a switch (S10).
                        RootView()
                            .environment(env)
                            .environment(accounts)
                            .id(env.userId)
                    } else {
                        LoginView { email, password in
                            _ = try await accounts.authRepository.signIn(email: email, password: password)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(AXID.Login.screen)
                    }
                } else {
                    ProgressView()
                }
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
