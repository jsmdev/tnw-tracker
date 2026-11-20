import Foundation
import Supabase

@MainActor
public final class SupabaseClientProvider {
    public static let shared = SupabaseClientProvider()

    public let client: SupabaseClient

    private init() {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        else {
            fatalError("SUPABASE_URL y SUPABASE_ANON_KEY deben estar en Info.plist")
        }
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(global: .init(session: Self.makeURLSession()))
        )
    }

    /// The client's requests never go through a URL cache (S10): the shared
    /// cache keeps responses on disk keyed by URL only, so one account's
    /// training rows could outlive its sign-out or answer another account's
    /// identical request.
    nonisolated static func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}
