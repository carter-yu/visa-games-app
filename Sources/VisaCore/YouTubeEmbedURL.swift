import Foundation

/// D8 helpers: construct only the official YouTube nocookie embed URL for a validated id.
/// Rejects arbitrary http(s) URLs, watch pages, search URLs, and malformed ids.
public enum YouTubeEmbedURL: Sendable {
    /// Host used for scoped embeds (privacy-enhanced / nocookie pattern).
    public static let embedHost = "www.youtube-nocookie.com"

    /// Tight allowlist of https hosts that may host the official `/embed/<id>` main frame
    /// after YouTube redirects the constructed nocookie URL. Not a general browsing permit.
    public static let allowedEmbedMainFrameHosts: Set<String> = [
        "www.youtube-nocookie.com",
        "youtube-nocookie.com",
        "www.youtube.com",
        "youtube.com",
        "m.youtube.com"
    ]

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

    /// `about:blank` (and nil) are benign WK intermediates during embed bootstrap — not escapes.
    public static func isBenignBlankURL(_ url: URL?) -> Bool {
        guard let url else { return true }
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "about" {
            let path = url.path.isEmpty ? (url.absoluteString.lowercased()) : url.path.lowercased()
            // about:blank absoluteString is typically "about:blank"
            return url.absoluteString.lowercased() == "about:blank" || path == "blank" || path.isEmpty
        }
        return false
    }

    /// Main-frame allow for the **same** allowlisted video id on official YouTube embed hosts.
    /// Construction still goes through nocookie `make(videoID:)`; this only permits the
    /// official embed redirect family (`/embed/<exact-id>`), not watch/search/channel pages.
    public static func isAllowedEmbedMainFrameURL(_ url: URL, videoID: String) -> Bool {
        let expectedID = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidVideoID(expectedID) else { return false }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        guard components.scheme?.lowercased() == "https" else { return false }
        guard let host = components.host?.lowercased(),
              allowedEmbedMainFrameHosts.contains(host) else { return false }
        let path = components.path
        guard path.hasPrefix("/embed/") else { return false }
        let id = String(path.dropFirst("/embed/".count))
        guard !id.contains("/"), isValidVideoID(id), id == expectedID else { return false }
        return true
    }

    /// True when a cancelled main-frame destination is a clear leave-embed escape
    /// (watch/search/channel/other-id/external). Used to decide whether to stop playback.
    public static func isClearEscapeURL(_ url: URL, videoID: String) -> Bool {
        if isBenignBlankURL(url) { return false }
        if isAllowedEmbedMainFrameURL(url, videoID: videoID) { return false }
        if isAllowedEmbedShellMainFrameURL(url) { return false }
        // Any other absolute http(s) (or non-embed path on YouTube hosts) is an escape.
        let scheme = (url.scheme ?? "").lowercased()
        return scheme == "http" || scheme == "https" || scheme == "javascript" || scheme == "file"
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

    /// HTTPS origin used as `loadHTMLString` baseURL so WK sends a YouTube-acceptable Referer.
    /// Path is host root (`/`) on the nocookie host only — not a general browse grant.
    public static func embedHTMLBaseURL() -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = embedHost
        components.path = "/"
        return components.url!
    }

    /// True for the intentional HTML-shell document at nocookie host root (Error 153 Referer fix).
    /// Does not allow youtube.com homepage, watch, search, or other paths.
    public static func isAllowedEmbedShellMainFrameURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        guard components.scheme?.lowercased() == "https" else { return false }
        guard let host = components.host?.lowercased(),
              host == embedHost || host == "youtube-nocookie.com" else { return false }
        let path = components.path
        return path.isEmpty || path == "/"
    }

    /// Minimal parent HTML wrapping the official nocookie iframe with referrerpolicy.
    /// Returns nil when the id is invalid. Iframe `src` is always `make(videoID:)`.
    public static func embedHTMLString(videoID: String) -> String? {
        guard let embedURL = make(videoID: videoID) else { return nil }
        let src = embedURL.absoluteString
        // Escape only what we interpolate; id was validated by make(videoID:).
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <title>Visa Games scoped embed</title>
        <style>
          html, body { margin: 0; padding: 0; height: 100%; background: #000; overflow: hidden; }
          iframe { border: 0; width: 100%; height: 100%; display: block; }
        </style>
        </head>
        <body>
        <iframe
          src="\(src)"
          title="Scoped YouTube embed"
          referrerpolicy="strict-origin-when-cross-origin"
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
          allowfullscreen
        ></iframe>
        </body>
        </html>
        """
    }
}
