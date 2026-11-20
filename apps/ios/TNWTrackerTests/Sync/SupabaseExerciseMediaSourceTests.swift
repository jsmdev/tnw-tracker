import Foundation
import Supabase
import Testing
@testable import TNWTrackerKit

/// #137 S2, S10: the app downloads an exercise's media from the private bucket
/// with the account's own session, and only while the shared client is signed
/// in as that account. The first tests need no network: the client points at
/// a closed local port. The contract test runs against the local Supabase
/// stack (see `LocalSupabaseStack`) and is skipped without it.
@Suite("Supabase exercise media source (#137, S10)")
struct SupabaseExerciseMediaSourceTests {
    let client: SupabaseClient
    let user = UUID()

    init() throws {
        let url = try #require(URL(string: "http://127.0.0.1:9"))
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: "test-anon-key",
            options: SupabaseClientOptions(auth: .init(storage: InMemoryAuthStorage(), autoRefreshToken: false))
        )
    }

    @Test("S10 signed out, or signed in as another account, the download is refused before it is sent")
    func refusedUnlessSignedInAsTheAccount() async throws {
        let path = InventedMedia.path(user: user, file: "photo.png")

        await #expect(throws: RemoteSessionError.notSignedInAsAccount) {
            try await SupabaseExerciseMediaSource(client: client, userId: user).download(path: path)
        }
        await #expect(throws: RemoteSessionError.notSignedInAsAccount) {
            try await SupabaseExerciseMediaSource(client: client, userId: user) { UUID() }.download(path: path)
        }
    }

    @Test("S10 signed in as the account, the request's own error comes through")
    func sameAccountGetsTheRequestError() async throws {
        let source = SupabaseExerciseMediaSource(client: client, userId: user) { [user] in user }

        let error = await #expect(throws: (any Error).self) {
            try await source.download(path: InventedMedia.path(user: user, file: "photo.png"))
        }
        #expect(error as? RemoteSessionError == nil, "the account was signed in: the request was sent")
    }

    @Test(
        "S2 local stack: the owner downloads its object with its session; another user is refused",
        .enabled(if: LocalSupabaseStack.configuration != nil)
    )
    func ownerDownloadsAndAnotherUserIsRefused() async throws {
        guard await LocalSupabaseStack.hasServiceRole() else { return }
        let bytes = InventedMedia.png()
        try await LocalSupabaseStack.withThrowawayUser { owner, ownerId in
            let path = InventedMedia.path(user: ownerId, file: "photo.png")
            try await owner.storage.from(SupabaseExerciseMediaSource.bucket)
                .upload(path, data: bytes, options: FileOptions(contentType: "image/png"))

            let downloaded = try await SupabaseExerciseMediaSource(client: owner, userId: ownerId).download(path: path)
            #expect(downloaded == bytes)

            try await LocalSupabaseStack.withThrowawayUser { other, otherId in
                await #expect(throws: StorageError.self) {
                    try await SupabaseExerciseMediaSource(client: other, userId: otherId).download(path: path)
                }
            }
            try await owner.storage.from(SupabaseExerciseMediaSource.bucket).remove(paths: [path])
        }
    }
}
