import Foundation
import Supabase

public protocol AuthRepositoryProtocol: AnyObject, Sendable {
    func signIn(email: String, password: String) async throws -> Session
    func signOut() async throws
    func currentSession() async -> Session?
    func authStateChanges() -> AsyncStream<AuthChangeEvent>
}

@MainActor
public final class AuthRepository: AuthRepositoryProtocol {
    private let supabase: SupabaseClient

    public init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    public func signIn(email: String, password: String) async throws -> Session {
        try await supabase.auth.signIn(email: email, password: password)
    }

    public func signOut() async throws {
        try await supabase.auth.signOut()
    }

    public func currentSession() async -> Session? {
        try? await supabase.auth.session
    }

    public func authStateChanges() -> AsyncStream<AuthChangeEvent> {
        AsyncStream { continuation in
            Task {
                for await (event, _) in supabase.auth.authStateChanges {
                    continuation.yield(event)
                }
            }
        }
    }
}
