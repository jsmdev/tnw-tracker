import SwiftData
import SwiftUI
import TNWTrackerKit

@main
struct TnwTrackerApp: App {
    private let container: ModelContainer = {
        do {
            return try ModelContainerFactory.makeContainer()
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
                appEnv = AppEnvironment.bootstrap(modelContext: container.mainContext)
                #if DEBUG
                    try? SeedService.seedIfNeeded(context: container.mainContext)
                #endif
                appEnv?.startAuthListener()
                // Verificar sesión existente
                if await appEnv?.authRepository.currentSession() != nil {
                    appEnv?.isAuthenticated = true
                }
            }
        }
    }
}
