import Foundation

// Pure state machines behind the recorder. All times are `mono` seconds
// (`ProcessInfo.systemUptime`), so a wall-clock change cannot corrupt a duration.

/// One dealt child (or UAT) round: answers, pauses, parent interruptions, result.
public struct PerfRoundTracker: Sendable, Equatable {
    /// Each unlocked stretch counts at most this long toward `active_ms` (idle cap).
    public static let idleCapSeconds: Double = 120
    /// A wrong tap sooner than this after the board unlocked is flagged `fast`.
    public static let fastWrongSeconds: Double = 1.5

    public let round: String
    public let kind: ActivityKind
    public let item: String
    public let stars: Int
    public let pendingStart: Int
    public let dealtMono: Double
    public let slots: [String]

    public private(set) var answers = 0
    public private(set) var misses = 0
    public private(set) var correctSteps = 0
    public private(set) var stepsBeforeFirstMiss: Int?
    public private(set) var hintShown = false
    public private(set) var mashTaps = 0
    public private(set) var firstTapMs: Int?
    public private(set) var wrongChoices: [String] = []
    public private(set) var activeSeconds: Double = 0
    public private(set) var parentSeconds: Double = 0
    private var unlockedSince: Double?
    private var lastUnlock: Double
    private var parentSince: Double?
    private var pauseSince: Double?
    private var lastWrongChoice: String?

    public init(round: String, kind: ActivityKind, item: String, stars: Int, pendingStart: Int,
                slots: [String], mono: Double) {
        self.round = round
        self.kind = kind
        self.item = item
        self.stars = stars
        self.pendingStart = pendingStart
        self.slots = slots
        self.dealtMono = mono
        self.unlockedSince = mono
        self.lastUnlock = mono
    }

    public struct AnswerFacts: Sendable, Equatable {
        public var n: Int
        public var slot: Int?
        public var msSinceDeal: Int
        public var msSinceUnlock: Int
        public var repeatWrong: Bool
        public var fast: Bool
    }

    /// Evaluated tap. `choice` is the option identity (`find-nytaxi`, `count-2`, asset id…).
    public mutating func answer(choice: String, correct: Bool, mono: Double) -> AnswerFacts {
        closeActiveStretch(at: mono)
        answers += 1
        let sinceDeal = max(0, mono - dealtMono - parentSeconds)
        let sinceUnlock = max(0, mono - lastUnlock)
        if firstTapMs == nil { firstTapMs = Self.ms(sinceDeal) }
        var repeatWrong = false
        var fast = false
        if correct {
            correctSteps += 1
            unlockedSince = mono
        } else {
            if stepsBeforeFirstMiss == nil { stepsBeforeFirstMiss = correctSteps }
            misses += 1
            repeatWrong = lastWrongChoice == choice
            fast = sinceUnlock < Self.fastWrongSeconds
            lastWrongChoice = choice
            wrongChoices.append(choice)
            // The Think Pause starts right after a wrong tap.
            unlockedSince = nil
        }
        return AnswerFacts(
            n: answers,
            slot: slots.firstIndex(of: choice),
            msSinceDeal: Self.ms(sinceDeal),
            msSinceUnlock: Self.ms(sinceUnlock),
            repeatWrong: repeatWrong,
            fast: fast
        )
    }

    public mutating func pauseStarted(mono: Double) {
        closeActiveStretch(at: mono)
        unlockedSince = nil
        pauseSince = mono
    }

    /// Think Pause over and fuel left: the board unlocks again.
    public mutating func pauseEnded(mono: Double) {
        pauseSince = nil
        guard parentSince == nil else { return }
        unlockedSince = mono
        lastUnlock = mono
    }

    public mutating func parentStarted(mono: Double) {
        guard parentSince == nil else { return }
        closeActiveStretch(at: mono)
        parentSince = mono
    }

    public mutating func parentEnded(mono: Double) {
        guard let since = parentSince else { return }
        parentSeconds += max(0, mono - since)
        parentSince = nil
        if pauseSince == nil {
            unlockedSince = mono
            lastUnlock = mono
        }
    }

    public mutating func noteHint() { hintShown = true }
    public mutating func noteMashTap() { mashTaps += 1 }

    public enum Outcome: String, Sendable, Equatable {
        case solved
        /// Pending fuel reached 0 (back to the depot, no visa).
        case zeroed
        /// Dealt but never finished (relaunch, reset, quit, storage failure).
        case abandoned
    }

    /// `round_result` fields (without the envelope).
    public mutating func result(outcome: Outcome, earnedMinutes: Int, assisted: Bool,
                                reason: String?, mono: Double) -> [String: PerfValue] {
        if let since = parentSince { parentSeconds += max(0, mono - since); parentSince = nil }
        closeActiveStretch(at: mono)
        let total = max(0, mono - dealtMono - parentSeconds)
        var fields: [String: PerfValue] = [
            "round": .string(round),
            "kind": .string(kind.rawValue),
            "item": .string(item),
            "stars": .int(stars),
            "outcome": .string(outcome.rawValue),
            "reason": .optionalString(reason),
            "first_try": .optionalBool(answers > 0 ? (misses == 0 && outcome == .solved) : nil),
            "misses": .int(misses),
            "answers": .int(answers),
            "hint_used": .bool(hintShown),
            "assisted": .bool(assisted),
            "pending_start": .int(pendingStart),
            "earned_min": .int(outcome == .solved ? earnedMinutes : 0),
            "active_ms": .int(Self.ms(activeSeconds)),
            "total_ms": .int(Self.ms(total)),
            "parent_ms": .int(Self.ms(parentSeconds)),
            "first_tap_ms": .optionalInt(firstTapMs),
            "mash_taps": .int(mashTaps),
            "wrong_choices": .strings(wrongChoices)
        ]
        if kind == .sequenceShortToLong {
            fields["steps_before_first_miss"] = .optionalInt(stepsBeforeFirstMiss ?? (answers > 0 ? correctSteps : nil))
        }
        return fields
    }

    private mutating func closeActiveStretch(at mono: Double) {
        guard let since = unlockedSince else { return }
        activeSeconds += min(Self.idleCapSeconds, max(0, mono - since))
        unlockedSince = nil
    }

    static func ms(_ seconds: Double) -> Int {
        guard seconds.isFinite else { return 0 }
        return Int((seconds * 1000).rounded())
    }
}

/// Why a video stopped. Verified against `AppModel` (v0.19.0) — the child has no stop
/// button: a child play ends only by finishing, by the visa / viewing bank running out,
/// or by rare technical paths.
public enum PerfVideoStopReason: String, Sendable, Equatable, CaseIterable {
    /// YouTube reported ended (state 0) — watched to the end.
    case ended
    /// The visa clock ran out (tick expiry or `sessionExpired` stop). Resume cursor saved.
    case visaExpired = "visa_expired"
    /// The viewing bank ran out first (`budgetExhausted`). Resume cursor saved.
    case budgetExhausted = "budget_exhausted"
    /// D8 guard: a tap inside the embed tried to leave it (e.g. the YouTube logo).
    /// The app returns to the picker. Rare; technical, not a dislike signal.
    case navGuard = "nav_guard"
    /// A parent opened parent controls mid-play (the player is torn down).
    case parentUnlock = "parent_unlock"
    /// Parent stopped an inline 試播 preview (Stop, segment switch, ended preview, Return).
    case previewStopped = "preview_stopped"
    /// Parent removed the playing video from the allowlist.
    case allowlistRemoved = "allowlist_removed"
    /// Parent 「清除簽證及重設儲存」.
    case storageReset = "storage_reset"
    /// `state.json` could not be saved (app falls back to lock).
    case storageFailure = "storage_failure"
    /// A new start replaced an open play without an end report (defensive; not expected).
    case superseded
    /// Parent quit the app.
    case appTerminate = "app_terminate"
    /// Defensive fallback; not expected.
    case unknown

    /// The visa or the viewing bank ran out (information only, never a dislike signal).
    public var isTimeUp: Bool { self == .visaExpired || self == .budgetExhausted }
}

/// One video load: watch time from `currentTime` samples, position, wall time.
public struct PerfPlayTracker: Sendable, Equatable {
    /// Forward steps larger than this between ~1 Hz samples are seeks, not watching.
    public static let maxForwardStepSeconds: Double = 2.5

    public let play: String
    public let video: String
    public let source: String
    public let startSeconds: Double
    public let startMono: Double
    public private(set) var durationSeconds: Double?
    public private(set) var lastPosition: Double
    public private(set) var maxPosition: Double
    public private(set) var watchedSeconds: Double = 0
    public private(set) var samples = 0

    public init(play: String, video: String, source: String, startSeconds: Double?,
                durationSeconds: Double?, mono: Double) {
        self.play = play
        self.video = video
        self.source = source
        let start = max(0, (startSeconds ?? 0).isFinite ? (startSeconds ?? 0) : 0)
        self.startSeconds = start
        self.startMono = mono
        self.durationSeconds = durationSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.lastPosition = start
        self.maxPosition = start
    }

    public mutating func noteDuration(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        durationSeconds = seconds
    }

    /// Player `currentTime` (posted about once a second while playing).
    public mutating func sample(position: Double) {
        guard position.isFinite, position >= 0 else { return }
        samples += 1
        let step = position - lastPosition
        if step > 0, step <= Self.maxForwardStepSeconds {
            watchedSeconds += step
        }
        lastPosition = position
        maxPosition = max(maxPosition, position)
    }

    public func progressFields(mono: Double) -> [String: PerfValue] {
        [
            "play": .string(play),
            "video": .string(video),
            "pos_s": .seconds(lastPosition),
            "watched_s": .seconds(watchedSeconds),
            "wall_s": .seconds(max(0, mono - startMono))
        ]
    }

    public func endFields(reason: PerfVideoStopReason, resumeSaved: Bool, mono: Double) -> [String: PerfValue] {
        let wall = max(0, mono - startMono)
        let reached: Double? = {
            if reason == .ended { return 1 }
            guard let duration = durationSeconds else { return nil }
            return min(1, maxPosition / duration)
        }()
        return [
            "play": .string(play),
            "video": .string(video),
            "source": .string(source),
            "stop_reason": .string(reason.rawValue),
            "completed": .bool(reason == .ended),
            "start_s": .seconds(startSeconds),
            "last_pos_s": .seconds(lastPosition),
            "max_pos_s": .seconds(maxPosition),
            // No `currentTime` samples (embed error, no IFrame API): 0 watched, flagged `none`.
            "watched_s": .seconds(samples > 0 ? watchedSeconds : 0),
            "wall_s": .seconds(wall),
            "duration_s": .seconds(durationSeconds),
            "completion": .seconds(reached),
            "telemetry": .string(samples > 0 ? "full" : "none"),
            "resume_saved": .bool(resumeSaved)
        ]
    }
}

/// Play sessions: a new one after launch, after a 30-minute gap, or on the first
/// non-parent event after parent mode (so a parent's depot testing right after
/// leaving parent controls is its own session that 「唔計呢段」 can drop).
public struct PerfSessionClock: Sendable, Equatable {
    public static let idleGapSeconds: TimeInterval = 30 * 60

    public enum StartReason: String, Sendable, Equatable {
        case launch
        case idleGap = "idle_gap"
        case afterParent = "after_parent"
    }

    public private(set) var current: String?
    private var lastActivity: Date?
    private var parentSinceLastChild = false

    public init() {}

    /// Session id for an event, plus the reason when a new session starts.
    public mutating func session(isParentMode: Bool, now: Date,
                                 mint: () -> String) -> (id: String, started: StartReason?) {
        if isParentMode {
            parentSinceLastChild = true
            if let current { return (current, nil) }
            let id = mint()
            current = id
            lastActivity = now
            return (id, .launch)
        }
        var reason: StartReason?
        if current == nil {
            reason = .launch
        } else if parentSinceLastChild {
            reason = .afterParent
        } else if let last = lastActivity, now.timeIntervalSince(last) >= Self.idleGapSeconds {
            reason = .idleGap
        }
        if reason != nil { current = mint() }
        parentSinceLastChild = false
        lastActivity = now
        return (current ?? "", reason)
    }
}

/// Where the current visa came from (decides `parent_test_visa`).
public enum PerfVisaSource: String, Sendable, Equatable, Codable {
    case earned
    case parentTest = "parent_test"
    /// Visa found running at launch without a matching marker.
    case unknown
}

/// The single actor rule (design §5.12). First match wins.
public enum PerfActorRule {
    public static func resolve(
        mode: Mode,
        isPlaytest: Bool,
        isVideoEvent: Bool,
        uatOn: Bool,
        visaSource: PerfVisaSource?
    ) -> PerfActor {
        if mode == .parent, isPlaytest { return .parentPlaytest }
        if mode == .parent { return isVideoEvent ? .parentPreview : .parent }
        if mode == .setup { return .system }
        if uatOn { return .parentUAT }
        if mode == .play, visaSource == .parentTest { return .parentTestVisa }
        return .child
    }

    public static func modeName(_ mode: Mode) -> String {
        switch mode {
        case .setup: return "setup"
        case .lock: return "lock"
        case .parent: return "parent"
        case .play: return "play"
        }
    }
}

/// What counts toward the child's performance. Everything else is kept but tagged.
public enum PerfFilter {
    public static func countable(_ event: PerfEvent, excludedSessions: Set<String>) -> Bool {
        event.v == PerfEvent.schemaVersion
            && event.actor == .child
            && !excludedSessions.contains(event.session)
    }

    /// `stats_exclude` / `stats_include`: last write wins per session.
    public static func excludedSessions(in events: [PerfEvent]) -> Set<String> {
        var state: [String: Bool] = [:]
        for event in PerfCodec.ordered(events) {
            guard let session = event.string("target_session") else { continue }
            switch event.type {
            case .statsExclude: state[session] = true
            case .statsInclude: state[session] = false
            default: break
            }
        }
        return Set(state.filter { $0.value }.map(\.key))
    }
}

/// 「家長測試中」 switch: memory only, auto-off after 60 minutes.
public struct PerfUATSwitch: Sendable, Equatable {
    public static let durationSeconds: TimeInterval = 60 * 60

    public private(set) var until: Date?

    public init() {}

    public func isOn(at now: Date) -> Bool {
        guard let until else { return false }
        return now < until
    }

    public mutating func turnOn(now: Date) { until = now.addingTimeInterval(Self.durationSeconds) }
    public mutating func turnOff() { until = nil }

    /// True exactly once when the 60 minutes run out.
    public mutating func expireIfNeeded(now: Date) -> Bool {
        guard let until, now >= until else { return false }
        self.until = nil
        return true
    }

    /// Whole minutes left, rounded up (for 「仲有 n 分鐘」).
    public func minutesLeft(at now: Date) -> Int {
        guard let until, now < until else { return 0 }
        return Int(ceil(until.timeIntervalSince(now) / 60))
    }
}
