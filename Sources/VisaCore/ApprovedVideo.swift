import Foundation

/// One parent-approved video identity for D8 allowlisted playback.
/// `id` is the provider video id (YouTube id for the current embed pattern).
public struct ApprovedVideo: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    /// Optional English display title (parent UI / future child chrome).
    public var titleEnglish: String?
    /// Optional Hong Kong Traditional Chinese display title. Never Simplified Chinese.
    public var titleCantonese: String?
    /// Nominal duration used for budget-fit decisions (ADR 0002 D4).
    public var durationSeconds: TimeInterval

    public init(
        id: String,
        titleEnglish: String? = nil,
        titleCantonese: String? = nil,
        durationSeconds: TimeInterval
    ) {
        self.id = id
        self.titleEnglish = titleEnglish
        self.titleCantonese = titleCantonese
        self.durationSeconds = durationSeconds
    }

    /// Bilingual label for parent lists; falls back to the raw id.
    public var parentLabel: String {
        switch (titleCantonese, titleEnglish) {
        case let (c?, e?): return "\(c) / \(e)"
        case let (c?, nil): return c
        case let (nil, e?): return e
        default: return id
        }
    }

    /// True when the parent supplied at least one display title.
    public var hasParentTitle: Bool {
        let cantonese = titleCantonese?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let english = titleEnglish?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !cantonese.isEmpty || !english.isEmpty
    }

    /// Primary line for the parent allowlist row. Never substitutes the raw id here —
    /// untitled rows show a bilingual placeholder so the id can stay visible as secondary.
    public var parentListTitle: String {
        hasParentTitle ? parentLabel : "(未命名 / Untitled)"
    }

    /// Derived YouTube thumbnail CDN URL for parent allowlist preview. Nil if id invalid.
    /// Not persisted — Codable stays backward compatible with existing allowlist JSON.
    public var thumbnailURL: URL? {
        YouTubeEmbedURL.thumbnailURL(videoID: id)
    }
}

/// Parent-maintained set of approved videos. Unknown ids are not playable (D8).
public struct VideoAllowlist: Sendable, Equatable, Codable {
    public private(set) var videos: [ApprovedVideo]

    public init(videos: [ApprovedVideo] = []) {
        self.videos = Self.dedupe(videos)
    }

    public var ids: Set<String> { Set(videos.map(\.id)) }

    public func contains(id: String) -> Bool {
        ids.contains(id)
    }

    public func video(id: String) -> ApprovedVideo? {
        videos.first { $0.id == id }
    }

    /// Insert or replace by id. Empty ids are rejected.
    @discardableResult
    public mutating func upsert(_ video: ApprovedVideo) -> Bool {
        let trimmed = video.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, video.durationSeconds.isFinite, video.durationSeconds > 0 else {
            return false
        }
        var copy = video
        copy.id = trimmed
        if let index = videos.firstIndex(where: { $0.id == trimmed }) {
            videos[index] = copy
        } else {
            videos.append(copy)
        }
        return true
    }

    public mutating func remove(id: String) {
        videos.removeAll { $0.id == id }
    }

    private static func dedupe(_ videos: [ApprovedVideo]) -> [ApprovedVideo] {
        var seen = Set<String>()
        var result: [ApprovedVideo] = []
        for video in videos {
            let id = video.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !seen.contains(id) else { continue }
            seen.insert(id)
            var copy = video
            copy.id = id
            result.append(copy)
        }
        return result
    }
}

/// Parent allowlist persistence for the M2 scaffold (UserDefaults).
/// Durable Snapshot schema for allowlist may arrive with P1-3/P1-4; this store is explicit scaffold config.
public struct VideoAllowlistStore {
    public static let key = "VisaGames.videoAllowlist.v1"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> VideoAllowlist {
        guard let data = defaults.data(forKey: Self.key) else { return VideoAllowlist() }
        return (try? JSONDecoder().decode(VideoAllowlist.self, from: data)) ?? VideoAllowlist()
    }

    public func save(_ allowlist: VideoAllowlist) {
        guard let data = try? JSONEncoder().encode(allowlist) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
