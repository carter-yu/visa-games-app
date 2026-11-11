import Foundation

// Clock + elapsed status chip C1 (0.39.0 / 86): what the child glance chip layer (`StatusClockLayer` in the app)
// draws on each screen. clock-playtime design §1.3, §2.1–2.3, §2.7, §6, §9 C1, D-C0b and D-C0c (Carter 2026-11-10);
// chip-rows/compare.md FINAL v1 §5 for the chip's inside. Pure decisions, so the Linux checks cover them: screen →
// route, route → slot, tone and language, the Think Pause dim, the colours under the macOS contrast and transparency
// settings, the words at one moment, and when those words can next change. No view, timer, storage or play-time
// ledger (C6). C5 (0.39.0 / 87): Watch shows the chip in the status strip above the player (design §2.5, Decision 7).

// MARK: - Screen → route

extension StatusRoute {
    /// The screen `ShellView.childOrLegacy` shows, tested in its branch order (parent controls, provider blocked,
    /// Time's up, the lock screens, the play screens, then the setup shell). Nil under parent controls (C2 puts the
    /// chip in the parent bars; a parent's 試玩 board is a parent screen) and for an open round without a kind, which
    /// `CanvasActivityHost` leaves empty.
    public init?(mode: Mode, providerBlocked: Bool, timesUp: Bool, taskRoundOpen: Bool, letterTicketUnavailable: Bool,
                 boardKind: ActivityKind?, playRoute: PlayStageRoute) {
        if mode == .parent { return nil }
        if providerBlocked {
            self = .providerBlocked
            return
        }
        if timesUp {
            self = .timesUp
            return
        }
        switch mode {
        case .lock:
            if !taskRoundOpen {
                self = letterTicketUnavailable ? .letterUnavailable : .depot
            } else if let boardKind {
                self = StatusRoute(board: boardKind)
            } else {
                return nil
            }
        case .play:
            switch playRoute {
            case .stamp: self = .stamp
            case .emptyAllowlist: self = .emptyAllowlist
            case .resumeChoice: self = .resumeChoice
            case .videoPicker: self = .videoPicker
            case .watch: self = .watch
            }
        case .setup:
            self = .setup
        case .parent:
            return nil
        }
    }
}

// MARK: - Plan

/// Everything the chip layer draws on one screen. ShellView makes one per render; nil draws nothing.
public struct StatusChipPlan: Equatable, Sendable {
    /// The hidden rule: no chip on the LM family (LineMatch / ShapeTrace / TapCount) until C4 nudges its header 78 u
    /// left (design §2.4; today's header panel and visa badge run under S). C4 takes the route out of this set and
    /// gives it a slot in `StatusSlot.rect(for:)`; the checks require the two to agree. C5 did the same for Watch (the
    /// strip above the player, §2.5).
    public static let hiddenRoutes: Set<StatusRoute> = [.lineMatchFamily]

    public let route: StatusRoute
    /// S, S_pick or the Watch strip slot, canvas units (`screenRect` places it on screen).
    public let slot: LineMatchRect
    public let tone: StatusChipTone
    public let language: StatusChipLanguage
    /// Think Pause is running: the whole chip drops to `StatusChipStyle.thinkPauseOpacity` (design §2.7).
    public let dimmed: Bool

    /// Nil without a route (parent controls) and on `hiddenRoutes`. `activeKind` is the model's active activity: the
    /// board's kind on a board, the finished round's kind on the stamp.
    public init?(route: StatusRoute?, activeKind: ActivityKind?, thinkPauseRemaining: Int) {
        guard let route, !Self.hiddenRoutes.contains(route), let slot = StatusSlot.rect(for: route) else { return nil }
        self.route = route
        self.slot = slot
        tone = StatusChipTone(route: route)
        language = StatusChipLanguage(route: route, activeKind: activeKind)
        dimmed = thinkPauseRemaining > 0
    }

    /// Where the layer draws the chip on a `width` × `height` screen, in points: the slot on the canvas stage
    /// (`StatusSlot.onScreen`), except on Watch, which lays out from the screen edges (design §2.5): there it is the
    /// strip's chip (`WatchStripLayout.chip`), at the top right of the TV safe rect and 8 u above the player on any
    /// screen. The two agree on 16:9; on a taller screen the stage is letterboxed and its slot would sit on the player.
    public func screenRect(screenWidth width: Double, screenHeight height: Double) -> LineMatchRect {
        route == .watch
            ? WatchStripLayout.chip(screenWidth: width, screenHeight: height)
            : StatusSlot.onScreen(slot, screenWidth: width, screenHeight: height)
    }
}

/// Day on the light boards, night on the dusk boards (design §1.3, §2.3).
public enum StatusChipTone: Equatable, Sendable {
    case day
    case night

    /// Night on Time's up and Resume (dusk gradient, moon) and on Watch (the dark player, C5); day everywhere else,
    /// Setup included.
    public init(route: StatusRoute) {
        switch route {
        case .timesUp, .resumeChoice, .watch:
            self = .night
        case .depot, .boardTwo, .hanziLetter, .lineMatchFamily, .stamp, .videoPicker, .emptyAllowlist, .letterUnavailable,
             .providerBlocked, .setup:
            self = .day
        }
    }
}

/// The language of the bottom row (design Q3): `52 分鐘` on Cantonese boards, `52 min` on the English (ABC) boards.
public enum StatusChipLanguage: Equatable, Sendable {
    case cantonese
    case english

    /// English on the Letters boards, on the stamp after a Letters round (that stamp is English-only:
    /// `StampSuccessView` `englishOnly`) and on the English tap-count twins (LM family, shown from C4). Cantonese
    /// everywhere else.
    public init(route: StatusRoute, activeKind: ActivityKind?) {
        switch route {
        case .hanziLetter, .stamp:
            self = activeKind?.isTapLetterFamily == true ? .english : .cantonese
        case .lineMatchFamily:
            self = activeKind?.tapCountLanguage == .english ? .english : .cantonese
        case .depot, .boardTwo, .timesUp, .resumeChoice, .videoPicker, .emptyAllowlist, .letterUnavailable,
             .providerBlocked, .watch, .setup:
            self = .cantonese
        }
    }
}

extension StatusChipText {
    /// The text the board shows: `zh` on Cantonese boards, `en` on English boards.
    public func text(in language: StatusChipLanguage) -> String { language == .english ? en : zh }

    /// The spoken form: both languages, Cantonese first, on Cantonese boards (design §6); English alone on English
    /// boards, like their other labels (`StampSuccessView`: "Go!").
    public func spoken(in language: StatusChipLanguage) -> String { language == .english ? en : bilingual }
}

extension StatusChipCopy {
    /// The chip's one accessibility label: the time now (clock.a11y), then the time since app start (chip.a11y,
    /// D-C0b): 「而家時間：下午3時45分。由開App計：52 分鐘」 / `Time now: 3:45 PM. Since app start: 52 min`.
    public static func chipAccessibility(clock: StatusChipText, elapsed: StatusChipText) -> StatusChipText {
        StatusChipText(zh: "\(clock.zh)。\(elapsed.zh)", en: "\(clock.en). \(elapsed.en)")
    }
}

// MARK: - Words

/// The chip's words at one moment: the top row from the wall clock, the bottom row from the two uptimes only.
public struct StatusChipContent: Equatable, Sendable {
    /// Top row: `3:45`.
    public let clock: String
    /// Bottom row, in the board's language: `52 分鐘` / `52 min`.
    public let elapsed: String
    /// One label for the whole chip, in `StatusChipText.spoken(in:)` form.
    public let accessibilityLabel: String

    /// `date` is the clock's instant (the timeline entry); it never reaches the elapsed figure.
    public init(date: Date, launchUptime: TimeInterval, nowUptime: TimeInterval, language: StatusChipLanguage) {
        let since = ElapsedSinceLaunch(launchUptime: launchUptime, nowUptime: nowUptime)
        clock = StatusClockText.clock(date)
        elapsed = since.text.text(in: language)
        accessibilityLabel = StatusChipCopy.chipAccessibility(clock: StatusClockText.accessibility(date),
                                                              elapsed: since.accessibility).spoken(in: language)
    }
}

// MARK: - Style

/// The chip's colours and outline (design §1.3, §6): palette tokens, opacities and canvas-unit widths. Flat: no
/// shadow, no press state, and no colour change with the time of day or the total.
public struct StatusChipStyle: Equatable, Sendable {
    /// Think Pause dim (design §2.7, matching the board dimming).
    public static let thinkPauseOpacity = 0.45
    /// The dim fades in and out over 0.2 s; Reduce Motion drops the fade.
    public static let thinkPauseFadeSeconds = 0.2

    public let fill: UInt32
    public let fillOpacity: Double
    public let outline: UInt32
    public let outlineOpacity: Double
    /// Canvas units: 2, or 3 with Increase Contrast (the app's pressable things use 5).
    public let outlineWidth: Double
    /// Digits and words.
    public let text: UInt32
    /// The clock glyph's line: the outline colour at full strength (inkSoft by day, Paper at night, Ink with Increase
    /// Contrast, as the design mockups draw it).
    public let glyph: UInt32

    /// Day: Paper at 92%, a 2 u inkSoft outline, Ink text. Night: Ink at 80%, a 2 u Paper outline at 35%, Paper text.
    /// Increase Contrast: a solid fill and a solid 3 u outline in the text colour (Ink by day; Paper at night, where
    /// an Ink outline would vanish into the Ink fill). Reduce Transparency: a solid fill.
    public init(tone: StatusChipTone, increaseContrast: Bool, reduceTransparency: Bool) {
        let solid = increaseContrast || reduceTransparency
        switch tone {
        case .day:
            fill = DesignTokens.Palette.paper
            fillOpacity = solid ? 1 : 0.92
            outline = increaseContrast ? DesignTokens.Palette.ink : DesignTokens.Palette.inkSoft
            outlineOpacity = 1
            text = DesignTokens.Palette.ink
        case .night:
            fill = DesignTokens.Palette.ink
            fillOpacity = solid ? 1 : 0.8
            outline = DesignTokens.Palette.paper
            outlineOpacity = increaseContrast ? 1 : 0.35
            text = DesignTokens.Palette.paper
        }
        outlineWidth = increaseContrast ? 3 : 2
        glyph = outline
    }
}

/// Inside the R2 chip, chip-relative canvas units (compare.md FINAL v1 §5). One fixed frame and fixed type on every
/// screen: no shrinking, truncation or resizing, because the widest strings fit by budget (`99 小時 59 分`, +4.2 u
/// measured).
public enum StatusChipLayout {
    public static let padding: Double = 6
    public static let cornerRadius: Double = 10
    /// Clock glyph: Ø 12 at x 6–18, centred at y 13.5.
    public static let glyph = LineMatchRect(x: 6, y: 7.5, width: 12, height: 12)
    /// Top row `3:45`: 16 u bold from x 22 (the glyph plus a quarter em), baseline 18.5.
    public static let clockX: Double = 22
    public static let clockBaseline: Double = 18.5
    public static let clockSize: Double = 16
    public static let clockWeight = 700
    /// Bottom row: 11.5 u semibold from x 6, baseline 33.5.
    public static let elapsedX: Double = 6
    public static let elapsedBaseline: Double = 33.5
    public static let elapsedSize: Double = 11.5
    public static let elapsedWeight = 600
    /// The glyph as fractions of its radius (the R2 mockups): face circle 0.86, line 0.26 (1.56 u), minute hand 0.55
    /// up to 12, hour hand 0.42 across to 3. The hands never move.
    public static let glyphFace = 0.86
    public static let glyphLine = 0.26
    public static let glyphMinuteHand = 0.55
    public static let glyphHourHand = 0.42
}

// MARK: - Refresh

/// When the chip's words can next change: the next wall-clock minute (top row) or the next whole minute since launch
/// (bottom row), whichever comes first. A coarse tick, at most two a minute and never per frame; the app's
/// `TimelineView` redraws only at these instants.
///
/// The sequence starts with `start`, then every boundary after it, in order. Bottom-row instants come
/// `elapsedGrace` after the uptime minute, so a wall clock that runs a little ahead of the uptime (NTP slew) cannot
/// redraw just before the minute turns. The uptime at a later instant is `uptimeAtStart` plus the wall time since
/// `start`: after a Mac sleep or a clock change the bottom row can lag until the next wall minute's redraw, which
/// reads the real uptime again. The bottom row stops scheduling at 100 h (`99+` never changes) and when the uptimes
/// are unusable (backwards or not finite); the wall minutes go on for ever.
public struct StatusChipRefresh: Sequence, IteratorProtocol, Sendable {
    public static let elapsedGrace: TimeInterval = 1

    private var pending: Date?
    /// The next wall minute, in seconds since the reference date (a whole minute in every zone with whole-minute
    /// offsets, Hong Kong included); nil for a start that is not a real instant.
    private var nextWall: TimeInterval?
    /// The first bottom-row instant, in seconds since the reference date; later ones follow every 60 s.
    private let elapsedBase: TimeInterval
    /// How many bottom-row changes remain (the last is `99+ 小時` at 100 h), and how many have been returned.
    private let elapsedCount: Int
    private var elapsedIndex = 0

    public init(start: Date, uptimeAtStart: TimeInterval, launchUptime: TimeInterval) {
        let seconds = start.timeIntervalSinceReferenceDate
        pending = start
        nextWall = seconds.isFinite ? ((seconds / 60).rounded(.down) + 1) * 60 : nil
        let elapsed = uptimeAtStart - launchUptime
        let overflow = Double(ElapsedSinceLaunch.overflowMinutes) * 60
        if seconds.isFinite, elapsed.isFinite, elapsed >= 0, elapsed < overflow {
            let minute = (elapsed / 60).rounded(.down)
            elapsedBase = seconds + ((minute + 1) * 60 - elapsed) + Self.elapsedGrace
            elapsedCount = ElapsedSinceLaunch.overflowMinutes - Int(minute)
        } else {
            elapsedBase = 0
            elapsedCount = 0
        }
    }

    public mutating func next() -> Date? {
        if let first = pending {
            pending = nil
            return first
        }
        guard let wall = nextWall else { return nil }
        if elapsedIndex < elapsedCount {
            let elapsed = elapsedBase + 60 * Double(elapsedIndex)
            if elapsed <= wall {
                elapsedIndex += 1
                if elapsed < wall { return Date(timeIntervalSinceReferenceDate: elapsed) }
            }
        }
        nextWall = wall + 60
        return Date(timeIntervalSinceReferenceDate: wall)
    }
}
