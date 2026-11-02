import Foundation

/// Where the household's records live.
///
/// Read from `supabase.json` in the bundle, which is git ignored, because the
/// repository is public. The file being absent is a normal state, not an
/// error: a fresh clone has no sync and everything else works, which is how it
/// should be. Sync is the one feature that needs a server, and nothing else in
/// the app should fail to build because a server has not been set up.
struct SupabaseConfig: Sendable, Decodable {
    let url: URL
    /// The publishable key. It ships inside the app on purpose: it identifies
    /// the project and nothing more. What actually keeps one household's
    /// recipes away from everyone else is the row level security in
    /// `supabase/schema.sql`, which the key cannot bypass. The secret key
    /// could, which is why it is never in here.
    let anonKey: String

    static let resourceName = "supabase"

    static func load(from bundle: Bundle = MiseBundle.resources) -> SupabaseConfig? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(SupabaseConfig.self, from: data),
              !config.anonKey.isEmpty
        else { return nil }

        // A secret key in here would be a serious mistake and an easy one, so
        // it is refused rather than used.
        guard !config.anonKey.hasPrefix("sb_secret_"),
              !config.anonKey.lowercased().contains("service_role")
        else {
            assertionFailure("supabase.json holds a secret key. It must hold the publishable one.")
            return nil
        }

        return config
    }

    var isConfigured: Bool { !anonKey.isEmpty }
}
