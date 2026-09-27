import Foundation

/// D8 helpers: construct only the official YouTube nocookie embed URL for a validated id.
/// Rejects arbitrary http(s) URLs, watch pages, search URLs, and malformed ids.
public enum YouTubeEmbedURL: Sendable {
    /// Host used for scoped embeds (privacy-enhanced / nocookie pattern).
    public static let embedHost = "www.youtube-nocookie.com"

    /// YouTube video ids are 11 characters from [A-Za-z0-9_-].
    public static func isValidVideoID(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return trimmed.unicodeScalars.count == 11 && trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Parse a parent-pasted ID or known YouTube URL. This does not grant navigation permission.
    public static func extractVideoID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidVideoID(trimmed) { return trimmed }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(),
              components.user == nil, components.password == nil, components.port == nil else { return nil }

        let id: String?
        switch host {
        case "youtube.com", "www.youtube.com", "m.youtube.com":
            if components.path == "/watch" {
                let matches = components.queryItems?.filter { $0.name == "v" } ?? []
                id = matches.count == 1 ? matches[0].value : nil
            } else if components.path.hasPrefix("/embed/") {
                id = String(components.path.dropFirst("/embed/".count))
            } else {
                id = nil
            }
        case "www.youtube-nocookie.com", "youtube-nocookie.com":
            id = components.path.hasPrefix("/embed/")
                ? String(components.path.dropFirst("/embed/".count)) : nil
        case "youtu.be", "www.youtu.be":
            id = components.path.hasPrefix("/") ? String(components.path.dropFirst()) : nil
        default:
            id = nil
        }
        guard let id, id.utf8.count == 11, isValidVideoID(id) else { return nil }
        return id
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
