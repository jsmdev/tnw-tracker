import Foundation
import os.log
import Supabase

private let logger = Logger(subsystem: "com.tnwtracker", category: "auth")

/// Cambio de estado de autenticación que propaga el `userId` de la sesión
/// asociada al evento. Supabase entrega `(event, session)` juntos en el stream;
/// re-consultar `auth.session` desde el handler devuelve nil por reentrancy, así
/// que tomamos el `userId` directamente del evento.
public struct AuthStateChange: Sendable {
    public let event: AuthChangeEvent
    public let userId: UUID?

    public init(event: AuthChangeEvent, userId: UUID?) {
        self.event = event
        self.userId = userId
    }
}

@MainActor
public protocol AuthRepositoryProtocol: AnyObject, Sendable {
    func signIn(email: String, password: String) async throws -> Auth.Session
    func signOut() async throws
    func currentSession() async -> Auth.Session?
    func authStateChanges() -> AsyncStream<AuthStateChange>
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

    /// Signs out on this device only (`.local`): the account's other devices stay
    /// signed in. The client forgets the session and emits `.signedOut` before it
    /// calls the auth service, so offline the session still ends on the device and
    /// only the server-side revocation of its refresh token is lost (it throws).
    public func signOut() async throws {
        logger.info("Auth: signOut")
        try await supabase.auth.signOut(scope: .local)
    }

    public func currentSession() async -> Auth.Session? {
        let session = try? await supabase.auth.session
        logger.info("Auth: currentSession lookup, present=\(session != nil)")
        return session
    }

    public func authStateChanges() -> AsyncStream<AuthStateChange> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, session) in supabase.auth.authStateChanges {
                    logger
                        .info("Auth: authStateChanges event=\(String(describing: event)) hasSession=\(session != nil)")
                    continuation.yield(AuthStateChange(event: event, userId: session?.user.id))
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
