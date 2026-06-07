import SwiftData
import SwiftUI
import TNWTrackerKit

@main
struct TnwTrackerApp: App {
    private let container: ModelContainer = {
        do {
            #if DEBUG
                let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
                return try ModelContainerFactory.makeContainer(inMemory: isUITesting)
            #else
                return try ModelContainerFactory.makeContainer()
            #endif
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
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
            .modelContainer(container)
            .task {
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                        // UI test bypass: pre-authenticated, in-memory container, no real auth.
                        // SeedService runs to populate the empty in-memory store.
                        // startAuthListener and currentSession are NOT called.
                        appEnv = AppEnvironment.bootstrapForUITesting(modelContext: container.mainContext)
                        try? await SeedService(container: container).seedIfNeeded()
                        appEnv?.startIntentObserver()
                        return
                    }
                #endif
                appEnv = AppEnvironment.bootstrap(modelContext: container.mainContext)
                #if DEBUG
                    try? await SeedService(container: container).seedIfNeeded()
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
