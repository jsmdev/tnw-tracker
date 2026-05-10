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
                    try? await SeedService(container: container).seedIfNeeded()
                #endif
                appEnv?.startAuthListener()
                appEnv?.startIntentObserver()
                // Restaurar sesión existente: Supabase guarda la sesión en Keychain pero
                // NO emite .signedIn al arrancar si ya estaba activa. Hay que setear
                // currentUserId aquí o makeActiveWorkoutCoordinator() crashea.
                if let session = await appEnv?.authRepository.currentSession() {
                    appEnv?.isAuthenticated = true
                    appEnv?.currentUserId = UUID(uuidString: session.user.id.uuidString)
                }
            }
        }
    }
}
