import Foundation

/// Authenticated backend for private uploads and domain commands.
/// Empty `FFAPIBaseURL` / `BuildEnv.apiBaseURL` means backend features are disabled.
enum APIConfig {
    static var baseURL: URL? {
        let raw = firstNonEmpty(BuildEnv.apiBaseURL, bundleString("FFAPIBaseURL"))
        guard let raw else { return nil }
        return URL(string: raw)
    }

    private static func bundleString(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }

    private static func firstNonEmpty(_ values: String...) -> String? {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    static var publicOrigin: URL {
        guard let baseURL else { return URL(string: "https://fitfight.app")! }
        var root = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let range = root.range(of: "/api/v1", options: .caseInsensitive) {
            root = String(root[..<range.lowerBound])
        }
        return URL(string: root) ?? URL(string: "https://fitfight.app")!
    }

    static func joinShareURL(code: String, referralCode: UUID) -> URL {
        publicOrigin.appendingPathComponent("j").appendingPathComponent(code)
            .appending(queryItems: [URLQueryItem(name: "ref", value: referralCode.uuidString.lowercased())])
    }
}
