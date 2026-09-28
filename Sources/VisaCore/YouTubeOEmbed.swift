import Foundation

/// YouTube oEmbed helpers for parent allowlist metadata (title + thumbnail hint).
/// No API key. oEmbed does **not** return duration — see `ApprovedVideo.durationSeconds` (D4 budget-fit).
public enum YouTubeOEmbed: Sendable {
    /// Parsed subset of the public oEmbed JSON. Duration is intentionally absent.
    public struct Response: Sendable, Equatable {
        public var title: String?
        public var thumbnailURL: URL?

        public init(title: String? = nil, thumbnailURL: URL? = nil) {
            self.title = title
            self.thumbnailURL = thumbnailURL
        }
    }

    /// Build `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v={id}&format=json`.
    /// Returns nil when the id is not a valid YouTube video id.
    public static func requestURL(videoID: String) -> URL? {
        guard YouTubeEmbedURL.isValidVideoID(videoID) else { return nil }
        let id = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/oembed"
        components.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(id)"),
            URLQueryItem(name: "format", value: "json")
        ]
        return components.url
    }

    /// Offline-friendly parse of oEmbed JSON. No network. Missing/empty title → nil title.
    public static func parse(_ data: Data) -> Response? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        let trimmedTitle = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (trimmedTitle?.isEmpty == false) ? trimmedTitle : nil
        let thumb: URL?
        if let raw = payload.thumbnail_url?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw),
           let scheme = url.scheme?.lowercased(),
           scheme == "https" || scheme == "http" {
            thumb = url
        } else {
            thumb = nil
        }
        return Response(title: title, thumbnailURL: thumb)
    }

    private struct Payload: Decodable {
        var title: String?
        var thumbnail_url: String?
    }
}
