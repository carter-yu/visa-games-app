import Foundation

/// One parent-approved video identity for D8 allowlisted playback.
/// `id` is the provider video id (YouTube id for the current embed pattern).
public struct ApprovedVideo: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    /// Optional English display title (parent UI / future child chrome).
    public var titleEnglish: String?
    /// Optional Hong Kong Traditional Chinese display title. Never Simplified Chinese.
    public var titleCantonese: String?
    /// Nominal duration for **D4 budget-fit** (PlaybackPolicy / whether the video fits the remaining
    /// viewing bank) — not the live YouTube player length. Default **120** is a safe short scaffold
    /// when the parent only pasted an id (upsert requires duration > 0). YouTube oEmbed does not
    /// return duration; without a Data API key, parents may override via Advanced, else 120 remains.
    public var durationSeconds: TimeInterval
    /// Real length reported by the scoped player (IFrame API `getDuration`, v0.12.0).
    /// Display-only for parent cards; never replaces the D4 `durationSeconds` above.
    /// Optional so pre-v0.12.0 allowlist JSON still decodes.
    public var playerDurationSeconds: TimeInterval?

    public init(
        id: String,
        titleEnglish: String? = nil,
        titleCantonese: String? = nil,
        durationSeconds: TimeInterval,
        playerDurationSeconds: TimeInterval? = nil
    ) {
        self.id = id
        self.titleEnglish = titleEnglish
        self.titleCantonese = titleCantonese
        self.durationSeconds = durationSeconds
        self.playerDurationSeconds = playerDurationSeconds
    }

    /// True once the player has reported a real length for this video.
    public var hasPlayerDuration: Bool {
        guard let seconds = playerDurationSeconds else { return false }
        return seconds.isFinite && seconds > 0
    }

    /// Parent card chip: real length (`5:01`) when known, else the nominal budget-fit
    /// duration marked approximate (`~2:00`).
    public var parentDurationLabel: String {
        if hasPlayerDuration, let seconds = playerDurationSeconds {
            return Self.clockLabel(seconds: seconds)
        }
        return "~" + Self.clockLabel(seconds: durationSeconds)
    }

    /// `m:ss` or `h:mm:ss`, rounded to the nearest second. Non-finite / negative → `0:00`.
    public static func clockLabel(seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours):" + twoDigits(minutes) + ":" + twoDigits(secs)
        }
        return "\(minutes):" + twoDigits(secs)
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
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

    /// Store the player-reported length for an allowlisted id. Returns true when it changed
    /// by at least one second (avoids rewriting storage on jitter). Bad values are ignored.
    @discardableResult
    public mutating func recordPlayerDuration(id: String, seconds: TimeInterval) -> Bool {
        guard seconds.isFinite, seconds > 0,
              let index = videos.firstIndex(where: { $0.id == id }) else { return false }
        if let existing = videos[index].playerDurationSeconds, abs(existing - seconds) < 1 {
            return false
        }
        videos[index].playerDurationSeconds = seconds
        return true
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

/// Live status of the parent paste field (v0.12.0 preview-before-add).
public enum ParentAllowlistDraft: Equatable, Sendable {
    case empty
    case invalid
    case ready(videoID: String)
    case alreadyAllowlisted(videoID: String)

    /// Parse the pasted URL / id with the same D8 extractor as `addAllowlistedVideo`.
    public static func evaluate(_ input: String, allowlist: VideoAllowlist) -> ParentAllowlistDraft {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let id = YouTubeEmbedURL.extractVideoID(from: trimmed) else { return .invalid }
        return allowlist.contains(id: id) ? .alreadyAllowlisted(videoID: id) : .ready(videoID: id)
    }

    public var videoID: String? {
        switch self {
        case .ready(let id), .alreadyAllowlisted(let id): return id
        case .empty, .invalid: return nil
        }
    }

    /// Only a new valid id enables the Add button.
    public var canAdd: Bool {
        if case .ready = self { return true }
        return false
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
