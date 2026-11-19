import Foundation
import Supabase
@testable import TNWTrackerKit

/// The local Supabase stack (`supabase start` at the repository root) for
/// contract tests. Never a remote project.
///
/// The keys are not committed: pass them through `xcodebuild` with the
/// `TEST_RUNNER_` prefix, which hands them to the test process without it:
///
///     eval "$(supabase status -o env | grep -E '^(API_URL|ANON_KEY|SERVICE_ROLE_KEY)=')"
///     TEST_RUNNER_TNW_LOCAL_SUPABASE_URL="$API_URL" \
///     TEST_RUNNER_TNW_LOCAL_SUPABASE_ANON_KEY="$ANON_KEY" \
///     TEST_RUNNER_TNW_LOCAL_SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
///     xcodebuild test -scheme TNWTracker -destination 'platform=iOS Simulator,name=iPhone 17' \
///       -only-testing:TNWTrackerTests/SupabaseTrainingRemoteStoreContractTests
///
/// Without them, or when the stack does not answer, the suite is skipped.
enum LocalSupabaseStack {
    struct Configuration: Sendable {
        let url: URL
        let anonKey: String
        /// Optional: only used to delete the throwaway users afterwards.
        let serviceRoleKey: String?
    }

    static let configuration: Configuration? = {
        let environment = ProcessInfo.processInfo.environment
        guard
            let urlText = environment["TNW_LOCAL_SUPABASE_URL"], let url = URL(string: urlText),
            let anonKey = environment["TNW_LOCAL_SUPABASE_ANON_KEY"], !anonKey.isEmpty
        else { return nil }
        let serviceRoleKey = environment["TNW_LOCAL_SUPABASE_SERVICE_ROLE_KEY"].flatMap { $0.isEmpty ? nil : $0 }
        return Configuration(url: url, anonKey: anonKey, serviceRoleKey: serviceRoleKey)
    }()

    /// `true` when the stack is configured and its auth service answers.
    static func isAvailable() async -> Bool {
        guard let configuration else { return false }
        var request = URLRequest(url: configuration.url.appending(path: "auth/v1/health"), timeoutInterval: 2)
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let session = URLSession(configuration: .ephemeral)
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Runs `body` as a new user signed up on the local stack, then deletes it.
    static func withThrowawayUser(_ body: (SupabaseClient, UUID) async throws -> Void) async throws {
        let configuration = try configured()
        let client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: InMemoryAuthStorage(),
                    autoRefreshToken: false,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
        let email = "sync-contract-\(UUID().uuidString.lowercased())@example.test"
        let response = try await client.auth.signUp(email: email, password: UUID().uuidString)
        let userId = response.user.id
        do {
            try await body(client, userId)
        } catch {
            await deleteUser(userId, configuration: configuration)
            throw error
        }
        await deleteUser(userId, configuration: configuration)
    }

    private static func configured() throws -> Configuration {
        guard let configuration else { throw URLError(.badURL) }
        return configuration
    }

    private static func deleteUser(_ id: UUID, configuration: Configuration) async {
        guard let serviceRoleKey = configuration.serviceRoleKey else { return }
        let admin = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: serviceRoleKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: InMemoryAuthStorage(),
                    autoRefreshToken: false,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
        try? await admin.auth.admin.deleteUser(id: id)
    }
}

/// Keeps the throwaway session out of the host app's keychain.
private final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.withLock { values[key] = value }
    }

    func retrieve(key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    func remove(key: String) throws {
        lock.withLock { values[key] = nil }
    }
}
