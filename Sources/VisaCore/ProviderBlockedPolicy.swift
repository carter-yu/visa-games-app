import Foundation

/// v0.21.1: YouTube "Sign in to confirm you're not a bot" / embed blocked (design
/// `youtube-bot-check.md` Slice 1). Pure value code — detection outcome, time credit and
/// the 2-strike rule. Child never reaches Google account pages.
public enum ProviderBlockedPolicy: Sendable {
    /// Ready / buffering without `playing` for this long → blocked (watchdog).
    public static let watchdogSeconds: TimeInterval = 12
    /// Wall-clock seconds credited back per blocked load (visa `endsAt`).
    public static let creditPerLoadSeconds: TimeInterval = 60
    /// Cap on credited seconds per play visa.
    public static let creditPerVisaSeconds: TimeInterval = 180
    /// Blocked loads in one visa before Time's up (remaining banked).
    public static let strikesBeforeTimesUp = 2

    public enum DetectVia: String, Sendable, Equatable, CaseIterable {
        case page
        case playerError = "player_error"
        case watchdog
    }

    public struct CreditState: Sendable, Equatable {
        /// Seconds already credited this visa.
        public var creditedSeconds: TimeInterval
        /// Blocked loads this visa (strikes).
        public var strikes: Int
        /// Video ids that must not be offered again this visa.
        public var unavailableIDs: Set<String>

        public init(creditedSeconds: TimeInterval = 0, strikes: Int = 0, unavailableIDs: Set<String> = []) {
            self.creditedSeconds = creditedSeconds
            self.strikes = strikes
            self.unavailableIDs = unavailableIDs
        }

        public var room: TimeInterval { max(0, ProviderBlockedPolicy.creditPerVisaSeconds - creditedSeconds) }
    }

    public enum Outcome: Sendable, Equatable {
        /// Show the blocked board, then return to the picker (id marked unavailable).
        case returnToPicker(creditSeconds: TimeInterval, state: CreditState)
        /// Credit, bank leftover visa seconds into viewing, then Time's up.
        case timesUp(creditSeconds: TimeInterval, bankRemainingVisa: Bool, state: CreditState)
    }

    /// Seconds to add to `endsAt` for a load that spent `elapsed` wall-clock seconds blocked.
    public static func creditSeconds(elapsed: TimeInterval, state: CreditState) -> TimeInterval {
        let spent = max(0, min(elapsed.isFinite ? elapsed : 0, creditPerLoadSeconds))
        return min(spent, state.room)
    }

    /// Apply one blocked load. `elapsed` is wall-clock since the embed load started.
    public static func applyBlocked(videoID: String, elapsed: TimeInterval, state: CreditState) -> Outcome {
        let id = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = state
        let credit = creditSeconds(elapsed: elapsed, state: next)
        next.creditedSeconds += credit
        next.strikes += 1
        if YouTubeEmbedURL.isValidVideoID(id) { next.unavailableIDs.insert(id) }
        if next.strikes >= strikesBeforeTimesUp {
            return .timesUp(creditSeconds: credit, bankRemainingVisa: true, state: next)
        }
        return .returnToPicker(creditSeconds: credit, state: next)
    }

    /// True when the IFrame API has reported ready (or equivalent) but never `playing`,
    /// and `elapsed` has reached the watchdog.
    public static func watchdogFired(readySeen: Bool, playingSeen: Bool, elapsed: TimeInterval) -> Bool {
        readySeen && !playingSeen && elapsed >= watchdogSeconds - 1e-9
    }
}

/// Safari-equivalent `applicationNameForUserAgent` suffix for WKWebView (same WebKit engine).
public enum SafariUserAgent: Sendable {
    public static let fallbackVersion = "17.0"
    public static let safariBuild = "605.1.15"

    /// `Version/<v> Safari/605.1.15`. Prefer Safari's Info.plist when present.
    public static func applicationName(safariVersion: String? = nil) -> String {
        let raw = (safariVersion ?? readSafariShortVersion() ?? fallbackVersion)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let version = raw.isEmpty ? fallbackVersion : String(raw.prefix(16))
        return "Version/\(version) Safari/\(safariBuild)"
    }

    public static func readSafariShortVersion() -> String? {
        let url = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let version = dict["CFBundleShortVersionString"] as? String,
              !version.isEmpty else { return nil }
        return version
    }
}
