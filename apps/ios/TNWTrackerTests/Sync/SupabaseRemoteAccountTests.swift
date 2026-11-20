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

    @Test("S10 the app's client never keeps responses in a URL cache")
    func noURLCache() {
        let configuration = SupabaseClientProvider.makeURLSession().configuration

        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }
}
