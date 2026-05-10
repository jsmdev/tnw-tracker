import Foundation
import os.log
import Supabase

private let logger = Logger(subsystem: "com.tnwtracker", category: "auth")

@MainActor
public protocol AuthRepositoryProtocol: AnyObject, Sendable {
    func signIn(email: String, password: String) async throws -> Auth.Session
    func signOut() async throws
    func currentSession() async -> Auth.Session?
    func authStateChanges() -> AsyncStream<AuthChangeEvent>
}

@MainActor
public final class AuthRepository: AuthRepositoryProtocol {
    private let supabase: SupabaseClient

    public init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    public func signIn(email: String, password: String) async throws -> Auth.Session {
        logger.info("Auth: signIn attempt")
        let session = try await supabase.auth.signIn(email: email, password: password)
        logger.info("Auth: signIn success")
        return session
    }

    public func signOut() async throws {
        logger.info("Auth: signOut")
        try await supabase.auth.signOut()
    }

    public func currentSession() async -> Auth.Session? {
        let session = try? await supabase.auth.session
        logger.info("Auth: currentSession lookup, present=\(session != nil)")
        return session
    }

    public func authStateChanges() -> AsyncStream<AuthChangeEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, _) in supabase.auth.authStateChanges {
                    logger.info("Auth: authStateChanges event=\(String(describing: event))")
                    continuation.yield(event)
                }
            }
            // Cuando el consumer cancela su Task externo, el AsyncStream termina
            // y este callback cancela el Task interno — evita leak en la chain.
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
