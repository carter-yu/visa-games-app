import Foundation

/// D8 helpers: construct only the official YouTube nocookie embed URL for a validated id.
/// Rejects arbitrary http(s) URLs, watch pages, search URLs, and malformed ids.
public enum YouTubeEmbedURL: Sendable {
    /// Host used for scoped embeds (privacy-enhanced / nocookie pattern).
    public static let embedHost = "www.youtube-nocookie.com"

    /// YouTube video ids are 11 characters from [A-Za-z0-9_-].
    public static func isValidVideoID(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 11 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Build `https://www.youtube-nocookie.com/embed/<id>` with modest embed params.
    /// Returns nil when the id is not a valid YouTube video id.
    public static func make(videoID: String) -> URL? {
        guard isValidVideoID(videoID) else { return nil }
        let id = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents()
        components.scheme = "https"
        components.host = embedHost
        components.path = "/embed/\(id)"
        components.queryItems = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "modestbranding", value: "1"),
            URLQueryItem(name: "controls", value: "1")
        ]
        return components.url
    }

    /// True only for our constructed nocookie embed path for a valid id (ignoring benign query differences).
    public static func isAllowedEmbedURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        guard components.scheme?.lowercased() == "https" else { return false }
        guard components.host?.lowercased() == embedHost else { return false }
        let path = components.path
        guard path.hasPrefix("/embed/") else { return false }
        let id = String(path.dropFirst("/embed/".count))
        // Reject nested paths such as /embed/id/extra
        guard !id.contains("/"), isValidVideoID(id) else { return false }
        return true
    }

    /// Returns true when `string` must be rejected as a non-embed / arbitrary navigation target.
    public static func rejectsArbitraryURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        // Bare valid video ids are not arbitrary URLs; construction goes through `make(videoID:)`.
        if isValidVideoID(trimmed) { return false }
        guard let url = URL(string: trimmed) else { return true }
        return !isAllowedEmbedURL(url)
    }
}
