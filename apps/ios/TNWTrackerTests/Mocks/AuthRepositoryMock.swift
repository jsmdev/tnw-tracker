import Foundation
import Supabase
@testable import TNWTrackerKit

/// Mock de `AuthRepositoryProtocol` para tests de cancellation del auth listener.
///
/// Expone `emit(_ event:)` para disparar eventos al stream activo,
/// y contadores de streams creados / terminados para verificar cancellation.
@MainActor
final class AuthRepositoryMock: AuthRepositoryProtocol {
    // MARK: - Counters

    private(set) var streamCreatedCount = 0
    private(set) var streamTerminatedCount = 0
    var activeStreamCount: Int {
        streamCreatedCount - streamTerminatedCount
    }

    // MARK: - Stream control

    private var continuation: AsyncStream<AuthChangeEvent>.Continuation?

    /// Emite un evento al stream activo (si hay uno).
    func emit(_ event: AuthChangeEvent) {
        continuation?.yield(event)
    }

    // MARK: - AuthRepositoryProtocol

    func signIn(email: String, password: String) async throws -> Auth.Session {
        fatalError("Not implemented in mock")
    }

    func signOut() async throws {
        fatalError("Not implemented in mock")
    }

    func currentSession() async -> Auth.Session? {
        nil
    }

    func authStateChanges() -> AsyncStream<AuthChangeEvent> {
        streamCreatedCount += 1
        return AsyncStream<AuthChangeEvent> { [weak self] cont in
            self?.continuation = cont
            cont.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.streamTerminatedCount += 1
                    self?.continuation = nil
                }
            }
        }
    }
}
