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

/// Which child board shows while a play visa runs (Holiday P0, v0.11.0; Resume Choice v0.15.0).
/// Stamp gate → (Go) → empty stage | resume choice | video picker | watch.
public enum PlayStageRoute: Equatable, Sendable {
    case stamp
    case emptyAllowlist
    /// Mid-video incomplete cursor + new visa after 「出發！」— continue or pick another.
    case resumeChoice
    case videoPicker
    case watch

    public static func route(
        awaitingDeparture: Bool,
        allowlistCount: Int,
        activeVideoID: String?,
        hasResumeCandidate: Bool = false
    ) -> PlayStageRoute {
        if awaitingDeparture { return .stamp }
        if allowlistCount == 0 { return .emptyAllowlist }
        if activeVideoID != nil { return .watch }
        if hasResumeCandidate { return .resumeChoice }
        return .videoPicker
    }
}

/// Where the child goes when the scoped player ends or is stopped (v0.12.0).
/// Carter UAT: after a ~5 min video ended with 12 min still on the road, the child was left
/// on the YouTube end card. Ended + time left → picker; no time left → Time's up.
public enum VideoEndRoute: Equatable, Sendable {
    /// Clear the active video; the same visa shows `VideoPickerView` again.
    case videoPicker
    /// End the play visa so the existing Time's up board (park and sleep) shows.
    case timesUp
    /// Parent preview: clear the player only (never ends a visa).
    case stopPreview
    /// Nothing playing (stale / duplicate signal).
    case ignore
}

public enum VideoEndRouting: Sendable {
    /// The allowlisted video reached YouTube's ended state.
    public static func afterVideoEnded(
        isChildPlay: Bool,
        hasActiveVideo: Bool,
        remainingViewingBudgetSeconds: TimeInterval,
        sessionEndsAt: Date?,
        now: Date
    ) -> VideoEndRoute {
        guard hasActiveVideo else { return .ignore }
        guard isChildPlay else { return .stopPreview }
        // Same D4/D5 rule as a running video: both the visa clock and the bank must have time.
        let decision = PlaybackPolicy().evaluateContinue(
            remainingViewingBudgetSeconds: remainingViewingBudgetSeconds,
            sessionEndsAt: sessionEndsAt,
            now: now
        )
        return decision.allowed ? .videoPicker : .timesUp
    }

    /// Playback was stopped by policy (tick) or by the D8 navigation guard.
    public static func afterPlaybackStopped(reason: PlaybackStopReason, isChildPlay: Bool) -> VideoEndRoute {
        guard isChildPlay else { return .stopPreview }
        switch reason {
        case .budgetExhausted, .sessionExpired:
            return .timesUp
        case .navigationRejected, .notAllowlisted, .invalidVideoID:
            return .videoPicker
        }
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

    /// Map banked Confirmed reward seconds (5 / 10 / 15 min) back to stars. Nil otherwise.
    public static func stars(fromAwardedSeconds seconds: TimeInterval) -> Int? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        switch Int(seconds.rounded()) {
        case 300: return ChildDifficulty.easy.rawValue
        case 600: return ChildDifficulty.medium.rawValue
        case 900: return ChildDifficulty.challenge.rawValue
        default: return nil
        }
    }
}
