import Foundation

/// Why playback must not start or must stop (ADR 0002 D4/D5 + ADR 0003 D8).
public enum PlaybackStopReason: String, Sendable, Equatable {
    case notAllowlisted
    case invalidVideoID
    case budgetExhausted
    case sessionExpired
    case navigationRejected
    /// YouTube blocked the embed (bot-check / player error / ready-never-playing).
    case providerBlocked
}

public struct PlaybackDecision: Sendable, Equatable {
    public var allowed: Bool
    public var stopReason: PlaybackStopReason?

    public init(allowed: Bool, stopReason: PlaybackStopReason? = nil) {
        self.allowed = allowed
        self.stopReason = stopReason
    }

    public static func allow() -> PlaybackDecision {
        PlaybackDecision(allowed: true, stopReason: nil)
    }

    public static func deny(_ reason: PlaybackStopReason) -> PlaybackDecision {
        PlaybackDecision(allowed: false, stopReason: reason)
    }
}

/// Pure seam: allowlisted id + viewing budget + absolute session deadline. No navigation.
public struct PlaybackPolicy: Sendable, Equatable {
    public init() {}

    /// Whether a new playback of `videoID` may start at `now`.
    public func evaluateStart(
        videoID: String,
        allowlist: VideoAllowlist,
        remainingViewingBudgetSeconds: TimeInterval,
        sessionEndsAt: Date?,
        now: Date
    ) -> PlaybackDecision {
        let trimmed = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard YouTubeEmbedURL.isValidVideoID(trimmed) else {
            return .deny(.invalidVideoID)
        }
        guard allowlist.contains(id: trimmed) else {
            return .deny(.notAllowlisted)
        }
        guard let endsAt = sessionEndsAt, endsAt > now else {
            return .deny(.sessionExpired)
        }
        guard remainingViewingBudgetSeconds.isFinite, remainingViewingBudgetSeconds > 0 else {
            return .deny(.budgetExhausted)
        }
        return .allow()
    }

    /// Whether an already-running playback must stop at `now`.
    public func evaluateContinue(
        remainingViewingBudgetSeconds: TimeInterval,
        sessionEndsAt: Date?,
        now: Date
    ) -> PlaybackDecision {
        guard let endsAt = sessionEndsAt, endsAt > now else {
            return .deny(.sessionExpired)
        }
        guard remainingViewingBudgetSeconds.isFinite, remainingViewingBudgetSeconds > 0 else {
            return .deny(.budgetExhausted)
        }
        return .allow()
    }

    /// D8: child path must never navigate to an arbitrary URL.
    public func evaluateNavigation(to urlString: String) -> PlaybackDecision {
        if YouTubeEmbedURL.rejectsArbitraryURL(urlString) {
            return .deny(.navigationRejected)
        }
        // Even an allowlisted-shaped embed URL is not a free navigation grant for the child;
        // ScopedPlayerView loads only the URL it constructed for the current allowlisted id.
        return .deny(.navigationRejected)
    }
}

/// Minimal playback engine protocol so tests can use a fake without WebKit.
public protocol PlaybackEngine: AnyObject {
    var isPlaying: Bool { get }
    var currentVideoID: String? { get }
    var lastStopReason: PlaybackStopReason? { get }
    func load(videoID: String, allowlist: VideoAllowlist, policy: PlaybackPolicy,
              remainingViewingBudgetSeconds: TimeInterval, sessionEndsAt: Date?, now: Date) -> PlaybackDecision
    func tick(remainingViewingBudgetSeconds: TimeInterval, sessionEndsAt: Date?, now: Date,
              policy: PlaybackPolicy) -> PlaybackDecision
    func stop(reason: PlaybackStopReason)
}

/// Deterministic in-memory engine for offline VisaCoreChecks (no WebKit).
public final class FakePlaybackEngine: PlaybackEngine, @unchecked Sendable {
    public private(set) var isPlaying = false
    public private(set) var currentVideoID: String?
    public private(set) var lastStopReason: PlaybackStopReason?
    public private(set) var loadCount = 0

    public init() {}

    @discardableResult
    public func load(
        videoID: String,
        allowlist: VideoAllowlist,
        policy: PlaybackPolicy,
        remainingViewingBudgetSeconds: TimeInterval,
        sessionEndsAt: Date?,
        now: Date
    ) -> PlaybackDecision {
        let decision = policy.evaluateStart(
            videoID: videoID,
            allowlist: allowlist,
            remainingViewingBudgetSeconds: remainingViewingBudgetSeconds,
            sessionEndsAt: sessionEndsAt,
            now: now
        )
        loadCount += 1
        if decision.allowed {
            isPlaying = true
            currentVideoID = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
            lastStopReason = nil
        } else {
            isPlaying = false
            currentVideoID = nil
            lastStopReason = decision.stopReason
        }
        return decision
    }

    @discardableResult
    public func tick(
        remainingViewingBudgetSeconds: TimeInterval,
        sessionEndsAt: Date?,
        now: Date,
        policy: PlaybackPolicy
    ) -> PlaybackDecision {
        guard isPlaying else {
            return .deny(lastStopReason ?? .budgetExhausted)
        }
        let decision = policy.evaluateContinue(
            remainingViewingBudgetSeconds: remainingViewingBudgetSeconds,
            sessionEndsAt: sessionEndsAt,
            now: now
        )
        if !decision.allowed, let reason = decision.stopReason {
            stop(reason: reason)
        }
        return decision
    }

    public func stop(reason: PlaybackStopReason) {
        isPlaying = false
        currentVideoID = nil
        lastStopReason = reason
    }
}
