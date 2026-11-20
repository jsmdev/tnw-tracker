import Foundation
import Supabase

/// Where an exercise's image and video bytes come from (#137 S2): one object of
/// the private `exercise-media` bucket, named by its object path
/// (`<user id>/<exercise id>/<file>`, the value of `image_uri` / `video_uri`).
public protocol ExerciseMediaSource: Sendable {
    /// The object's bytes. Throws when it cannot be downloaded now (offline,
    /// refused, missing); nothing is kept.
    func download(path: String) async throws -> Data
}

/// `ExerciseMediaSource` over Supabase Storage for one account: the
/// authenticated object endpoint, with the signed-in user's session, so the
/// bucket's policies give each user only the objects under their own folder.
/// No public or signed URL exists anywhere: the request carries the session's
/// token and the shared client's URL session keeps no cache. Like
/// `SupabaseTrainingRemoteStore`, it sends nothing unless the client is signed
/// in as `userId`, and throws the answer away if another account signed in
/// while it was on its way (S10).
public struct SupabaseExerciseMediaSource: ExerciseMediaSource {
    /// The private bucket of the exercises' media (`supabase/migrations`, T1).
    public static let bucket = "exercise-media"

    private let client: SupabaseClient
    private let userId: UUID
    /// The user the client is signed in as now.
    private let signedInUser: @Sendable () -> UUID?

    public init(client: SupabaseClient, userId: UUID) {
        self.init(client: client, userId: userId) { client.auth.currentSession?.user.id }
    }

    /// `signedInUser` stands in for the client's session, for tests.
    init(client: SupabaseClient, userId: UUID, signedInUser: @escaping @Sendable () -> UUID?) {
        self.client = client
        self.userId = userId
        self.signedInUser = signedInUser
    }

    public func download(path: String) async throws -> Data {
        try requireAccount()
        let data: Data
        do {
            data = try await client.storage.from(Self.bucket).download(path: path)
        } catch {
            try requireAccount()
            throw error
        }
        try requireAccount()
        return data
    }

    private func requireAccount() throws {
        guard signedInUser() == userId else { throw RemoteSessionError.notSignedInAsAccount }
    }
}
