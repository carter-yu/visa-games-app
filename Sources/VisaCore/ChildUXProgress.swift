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

/// Canvas play boards need a mission ticket. `selectedStars` is in-memory only, so a cold
/// start mid-visa (durable `endsAt`) or parent 「測試一分鐘簽證」 used to leave ticket nil and
/// `ShellView.childOrLegacy` fell through to ADR 0006 `legacyShell` (wooden sign + visa
/// seconds + yellow 「播放准許影片」). Always resolve a ticket so play stays on canvas.
public enum PlayPresentation: Sendable {
    /// Ticket for stamp / picker / watch / Time's up. Falls back to easy (的士短程).
    public static func ticket(selectedStars: Int?) -> MissionTicket {
        if let stars = selectedStars,
           let difficulty = ChildDifficulty(rawValue: stars),
           let match = MissionTicket.all.first(where: { $0.difficulty == difficulty }) {
            return match
        }
        return MissionTicket.all[0]
    }

    /// Map banked Confirmed reward seconds (10 / 20 / 30 min) back to stars. Nil otherwise.
    public static func stars(fromAwardedSeconds seconds: TimeInterval) -> Int? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        switch Int(seconds.rounded()) {
        case 600: return ChildDifficulty.easy.rawValue
        case 1_200: return ChildDifficulty.medium.rawValue
        case 1_800: return ChildDifficulty.challenge.rawValue
        default: return nil
        }
    }
}
