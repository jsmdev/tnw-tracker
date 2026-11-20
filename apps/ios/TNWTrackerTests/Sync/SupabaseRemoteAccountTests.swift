import Foundation
import Supabase
import Testing
@testable import TNWTrackerKit

/// The Supabase remote store of one account sends nothing unless the shared
/// client is signed in as that account (S10), and no response goes through a
/// URL cache. No network: the client points at a closed local port, so a
/// request that got sent would fail with a network error instead.
@Suite("Supabase remote store, one account")
struct SupabaseRemoteAccountTests {
    let client: SupabaseClient
    let store: SupabaseTrainingRemoteStore
    let user = UUID()

    init() throws {
        let url = try #require(URL(string: "http://127.0.0.1:9"))
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: "test-anon-key",
            options: SupabaseClientOptions(auth: .init(storage: InMemoryAuthStorage(), autoRefreshToken: false))
        )
        store = SupabaseTrainingRemoteStore(client: client, userId: user)
    }

    @Test("S10 signed out, every request is refused before it is sent")
    func signedOutSendsNothing() async throws {
        let session = RemoteSessionRow(
            id: UUID(), userId: user, completedAt: Date(timeIntervalSince1970: 1_898_848_800), timeZone: "UTC"
        )
        let refused = RemoteSessionError.notSignedInAsAccount
        await #expect(throws: refused) { _ = try await store.pull(RemoteSessionRow.self, after: nil, limit: 1) }
        await #expect(throws: refused) {
            try await store.upsert([RemoteRoutineRow(id: UUID(), userId: user, name: "Legs")])
        }
        await #expect(throws: refused) { try await store.delete(.routines, ids: [UUID()]) }
        await #expect(throws: refused) { try await store.deleteChildren(.routineItems, of: UUID(), keeping: []) }
        await #expect(throws: refused) {
            try await store.pushSession(RemoteSessionAggregate(session: session, entries: [], sets: []))
        }
    }

    @Test("S10 an answer that arrives once the client is no longer the account's is thrown away")
    func answerAfterAnotherSignInIsRefused() async throws {
        let signedIn = SignedInUser(user)
        let store = SupabaseTrainingRemoteStore(client: client, userId: user) { signedIn.next() }

        // The request is sent (signed in as the account); before its answer, another account signs in.
        await #expect(throws: RemoteSessionError.notSignedInAsAccount) {
            try await store.delete(.sessions, ids: [UUID()])
        }
        #expect(signedIn.reads == 2)
    }

    @Test("S10 still signed in as the account, the request's own error comes through")
    func sameAccountGetsTheRequestError() async throws {
        let store = SupabaseTrainingRemoteStore(client: client, userId: user) { [user] in user }

        await #expect(throws: URLError.self) { try await store.delete(.sessions, ids: [UUID()]) }
    }

    @Test("S4 what a PostgREST error tells the sync", arguments: [
        ("23505", "duplicate key value violates unique constraint", "rejected"),
        ("22P02", "invalid input syntax for type uuid", "rejected"),
        ("42501", "new row violates row-level security policy for table \"entries\"", "rejected"),
        ("42501", "permission denied for table entries", "session"),
        ("PGRST301", "JWT cryptographic operation failed", "session"),
        ("PGRST303", "JWT expired", "session"),
        ("XX000", "internal error", "server"),
        ("57014", "canceling statement due to statement timeout", "server")
    ])
    func classifiesPostgrestErrors(code: String, message: String, kind: String) {
        let error = SupabaseTrainingRemoteStore.classified(PostgrestError(code: code, message: message))

        switch kind {
        case "rejected": #expect(error as? RemoteStoreError == .rejected(code: code, message: message))
        case "session": #expect(error as? RemoteSessionError == .sessionRefused)
        default: #expect(error as? RemoteServerError == RemoteServerError(code: code, message: message))
        }
    }

    @Test("S4 an error without a PostgREST answer passes through")
    func otherErrorsPassThrough() {
        let error = SupabaseTrainingRemoteStore.classified(URLError(.timedOut))

        #expect((error as? URLError)?.code == .timedOut)
    }

    @Test("S10 the app's client never keeps responses in a URL cache")
    func noURLCache() {
        let configuration = SupabaseClientProvider.makeURLSession().configuration

        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }
}

/// The signed-in user the remote store reads: the account at the first read,
/// another one after it, as if another account signed in during a request.
private final class SignedInUser: @unchecked Sendable {
    private let lock = NSLock()
    private let account: UUID
    private var count = 0

    init(_ account: UUID) {
        self.account = account
    }

    var reads: Int {
        lock.withLock { count }
    }

    func next() -> UUID {
        lock.withLock {
            count += 1
            return count == 1 ? account : UUID()
        }
    }
}
