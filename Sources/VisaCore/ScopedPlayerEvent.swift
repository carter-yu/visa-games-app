import Foundation

/// YouTube IFrame API `onStateChange` values (public API contract).
public enum YouTubePlayerState: Sendable {
    public static let unstarted = -1
    public static let ended = 0
    public static let playing = 1
    public static let paused = 2
    public static let buffering = 3
    public static let cued = 5

    /// Short English label for ScopedPlayer logs.
    public static func label(_ state: Int) -> String {
        switch state {
        case unstarted: return "unstarted"
        case ended: return "ended"
        case playing: return "playing"
        case paused: return "paused"
        case buffering: return "buffering"
        case cued: return "cued"
        default: return "unknown(\(state))"
        }
    }
}

/// Messages posted by the scoped embed HTML shell to `WKScriptMessageHandler` (v0.12.0).
/// The bridge is one-way and read-only: the page reports player state; Swift never lets the
/// page navigate, open windows, or pick another video (ADR 0003 D8).
public enum ScopedPlayerEvent: Equatable, Sendable {
    case ready(durationSeconds: TimeInterval?)
    case stateChanged(Int)
    case ended
    case duration(TimeInterval)
    /// Periodic player position while playing (v0.13.0 resume cursor).
    case currentTime(TimeInterval)
    case apiUnavailable(String)

    /// `window.webkit.messageHandlers.<name>.postMessage(...)` in the embed shell.
    public static let messageHandlerName = "visaPlayer"

    /// True when the event means the allowlisted video finished.
    public var indicatesEnded: Bool {
        switch self {
        case .ended: return true
        case .stateChanged(let state): return state == YouTubePlayerState.ended
        default: return false
        }
    }

    /// Parse a WK message body (`[String: Any]`). Returns nil for malformed bodies, unknown
    /// events, or a `videoID` that is not the player's current allowlisted id (stale page).
    public static func parse(_ body: Any, expectedVideoID: String) -> ScopedPlayerEvent? {
        guard let dict = body as? [String: Any],
              let event = dict["event"] as? String,
              let videoID = dict["videoID"] as? String else { return nil }
        let expected = expectedVideoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard YouTubeEmbedURL.isValidVideoID(expected), videoID == expected else { return nil }
        switch event {
        case "ended":
            return .ended
        case "state":
            guard let raw = number(dict["state"]), raw == raw.rounded(), abs(raw) < 100 else { return nil }
            return .stateChanged(Int(raw))
        case "ready":
            return .ready(durationSeconds: positiveSeconds(dict["duration"]))
        case "duration":
            guard let seconds = positiveSeconds(dict["seconds"]) else { return nil }
            return .duration(seconds)
        case "currentTime":
            guard let seconds = positiveSeconds(dict["seconds"]) else { return nil }
            return .currentTime(seconds)
        case "apiError":
            let detail = (dict["detail"] as? String) ?? "unknown"
            return .apiUnavailable(String(detail.prefix(80)))
        default:
            return nil
        }
    }

    private static func positiveSeconds(_ value: Any?) -> TimeInterval? {
        guard let seconds = number(value), seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: return double
        case let int as Int: return Double(int)
        case let number as NSNumber: return number.doubleValue
        default: return nil
        }
    }
}

/// One ended report per loaded video (YouTube can emit ended via both the API callback and
/// raw widget messages). `reset()` on every new load.
public struct PlaybackEndLatch: Equatable, Sendable {
    public private(set) var reportedVideoID: String?

    public init() {}

    public mutating func shouldReportEnd(videoID: String, loadedVideoID: String?) -> Bool {
        guard let loadedVideoID, videoID == loadedVideoID, reportedVideoID != videoID else { return false }
        reportedVideoID = videoID
        return true
    }

    public mutating func reset() {
        reportedVideoID = nil
    }
}
