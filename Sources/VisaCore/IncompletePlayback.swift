import Foundation

/// Durable cursor for the last unfinished child-play video (Carter 2026-10-02 resume lock).
/// Parent preview never writes this. Only one incomplete cursor is kept.
public struct IncompletePlayback: Equatable, Sendable, Codable {
    public var videoID: String
    /// Last observed player position in seconds (floor'd when written to embed `start=`).
    public var positionSeconds: TimeInterval

    public init(videoID: String, positionSeconds: TimeInterval) {
        self.videoID = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.positionSeconds = positionSeconds
    }

    /// Valid id + finite position strictly greater than zero.
    public var isValid: Bool {
        YouTubeEmbedURL.isValidVideoID(videoID)
            && positionSeconds.isFinite
            && positionSeconds > 0
    }

    /// Returns a normalized cursor, or nil when invalid.
    public static func make(videoID: String, positionSeconds: TimeInterval) -> IncompletePlayback? {
        let cursor = IncompletePlayback(videoID: videoID, positionSeconds: positionSeconds)
        return cursor.isValid ? cursor : nil
    }
}

/// Pure helpers for when to save / offer Continue (testable without AppKit).
public enum IncompletePlaybackPolicy: Sendable {
    /// Child play only; time-out stops only; never on ended / nav reject / parent.
    public static func shouldSaveOnStop(
        isChildPlay: Bool,
        reason: PlaybackStopReason,
        positionSeconds: TimeInterval?
    ) -> Bool {
        guard isChildPlay else { return false }
        switch reason {
        case .budgetExhausted, .sessionExpired:
            guard let positionSeconds, positionSeconds.isFinite, positionSeconds > 0 else { return false }
            return true
        case .navigationRejected, .notAllowlisted, .invalidVideoID, .providerBlocked:
            return false
        }
    }

    /// Offer Continue when the saved id is still on the allowlist.
    public static func shouldOfferContinue(
        incomplete: IncompletePlayback?,
        allowlistContainsID: (String) -> Bool
    ) -> IncompletePlayback? {
        guard let incomplete, incomplete.isValid, allowlistContainsID(incomplete.videoID) else {
            return nil
        }
        return incomplete
    }
}
