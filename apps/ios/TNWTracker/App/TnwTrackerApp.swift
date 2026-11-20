import SwiftUI
import TNWTrackerKit

@main
struct TnwTrackerApp: App {
    private let store: TrainingStore = {
        do {
            #if DEBUG
                let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
                return try TrainingStore(inMemory: isUITesting)
            #else
                return try TrainingStore()
            #endif
        } catch {
            fatalError("Failed to open the training store: \(error)")
        }
    }()

    @State private var appEnv: AppEnvironment?

    var body: some Scene {
        WindowGroup {
            Group {
                if let env = appEnv {
                    if env.isAuthenticated {
                        RootView()
                            .environment(env)
                    } else {
                        LoginView { email, password in
                            _ = try await env.authRepository.signIn(email: email, password: password)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .task {
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                        // UI test bypass: pre-authenticated, in-memory store, no real auth.
                        // The invented sample data populates the empty in-memory store.
                        // startAuthListener and currentSession are NOT called.
                        appEnv = AppEnvironment.bootstrapForUITesting(store: store)
                        try? SampleTrainingData.loadIfEmpty(into: store)
                        if ProcessInfo.processInfo.arguments.contains("--uitesting-store-of-another-user") {
                            appEnv?.signInOnStoreOfAnotherUserForUITesting()
                        }
                        appEnv?.startIntentObserver()
                        // Live Activities left by an earlier run make the system
                        // relaunch the app in the background, without `--uitesting`,
                        // racing the next run's first launch (T11).
                        await LiveActivityController.endAll()
                        return
                    }
                #endif
                appEnv = AppEnvironment.bootstrap(store: store)
                #if DEBUG
                    appEnv?.loadSampleDataIfUnowned()
                #endif
                // El auth listener maneja la restauración: al suscribirse, Supabase
                // emite `.initialSession` con la sesión persistida (o nil). `handle`
                // resuelve isAuthenticated + currentUserId desde ese evento.
                appEnv?.startAuthListener()
                appEnv?.startIntentObserver()
            }
        }
    }
}
