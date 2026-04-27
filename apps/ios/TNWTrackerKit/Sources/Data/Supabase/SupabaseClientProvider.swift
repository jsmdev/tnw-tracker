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
        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }
}
