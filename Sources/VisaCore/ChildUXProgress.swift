import Foundation

/// Auto-hint after this many incorrect taps (Carter 2026-09-30 / D7 assisted).
public enum ActivityHintPolicy: Sendable {
    public static let missesBeforeAutoHint = 2

    /// `missCount` is the number of incorrect answers so far (including the latest).
    public static func shouldAutoHint(afterMissCount missCount: Int) -> Bool {
        missCount >= missesBeforeAutoHint
    }
}

/// Road-timer math for the watch screen (board 4). Position = elapsed / total.
public struct RoadTimerProgress: Equatable, Sendable {
    /// 0...1 along the road (0 at start flag, 1 at garage).
    public let fraction: Double
    /// Ceil of remaining seconds as whole minutes for 「仲有 N 分鐘」.
    public let remainingMinutesCeil: Int
    public let remainingSeconds: TimeInterval
    public let almostHome: Bool

    public init(elapsed: TimeInterval, total: TimeInterval, remaining: TimeInterval) {
        let safeTotal = max(total, 0.001)
        let clampedElapsed = min(max(elapsed, 0), safeTotal)
        fraction = min(1, max(0, clampedElapsed / safeTotal))
        let safeRemaining = max(remaining, 0)
        remainingSeconds = safeRemaining
        remainingMinutesCeil = Int(max(0, ceil(safeRemaining / 60)))
        almostHome = safeRemaining > 0 && safeRemaining <= 60
    }

    public static func from(endsAt: Date, totalSeconds: TimeInterval, now: Date) -> RoadTimerProgress {
        let remaining = max(0, endsAt.timeIntervalSince(now))
        let elapsed = max(0, totalSeconds - remaining)
        return RoadTimerProgress(elapsed: elapsed, total: totalSeconds, remaining: remaining)
    }
}

/// Which child board shows while a play visa runs (Holiday P0, v0.11.0).
/// Stamp gate → (Go) → empty stage | video picker | watch.
public enum PlayStageRoute: Equatable, Sendable {
    case stamp
    case emptyAllowlist
    case videoPicker
    case watch

    public static func route(awaitingDeparture: Bool, allowlistCount: Int, activeVideoID: String?) -> PlayStageRoute {
        if awaitingDeparture { return .stamp }
        if allowlistCount == 0 { return .emptyAllowlist }
        if activeVideoID == nil { return .videoPicker }
        return .watch
    }
}
