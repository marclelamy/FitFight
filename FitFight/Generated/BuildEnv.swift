/// Written by TestFlight or App Store CI before archive.
/// Empty strings mean `SupabaseConfig` / `APIConfig` use their fallbacks.
/// Do not put `sb_secret_...` here.
enum BuildEnv {
    static let supabaseURL = ""
    static let supabasePublishableKey = ""
    static let apiBaseURL = ""
}
