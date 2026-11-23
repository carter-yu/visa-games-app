import Foundation

// 畫直線・四方 guidance (four-direction design §6). The levels reuse the approved tracing help's numbers
// (`TapCountGuidePlan`, `TapCountGuideData`): 多啲 demo before every line, pause help after 1 s, ghost to the finish
// after 5 s, re-demo after 15 s; 標準 (default) demo until 識咗, headlights, 2 s / 8 s / 20 s; 少啲 no demo, no
// headlights, no pause help, ghost after 8 s. The level is the one dealt with the round (the snapshot), never the live
// setting. Every guidance paint stays within [F, G], G = L − 15.5 the near edge of the painted finish bar; nothing ever
// points toward green. 識咗 is kept per oriented variant in the card's own store, starting empty, and only the child's
// rounds write it.

public enum OrientedLineHelp: Sendable, Equatable {
    case none
    /// Joined and F still for the level's pause time: the glow and up to 3 big chevrons from F to T, the ghost once.
    case pause(from: Double, to: Double, since: Double)
    /// Down but not joined, or off the road, for 2 s: a ring on the car and the forward arrow to T (no trail).
    case ring(OrientedLineAway, from: Double, to: Double, since: Double)
    /// No progress for the ghost time: the ghost runs once until its frontmost paint reaches G.
    case ghostToEnd(from: Double, to: Double, since: Double)
    /// No progress for the re-demo time with the pen up: the prompt and the demo again.
    case redemo(since: Double)

    /// One key per help episode (noted once).
    public var key: String? {
        switch self {
        case .none: return nil
        case let .pause(from, _, since): return "pause.\(Int(from)).\(Int(since * 10))"
        case let .ring(away, from, _, since): return "ring.\(away == .offRoad ? "road" : "join").\(Int(from)).\(Int(since * 10))"
        case let .ghostToEnd(from, _, since): return "ghost.\(Int(from)).\(Int(since * 10))"
        case let .redemo(since): return "redemo.\(Int(since * 10))"
        }
    }

    /// `TapCountGuideRun.noteHelp` kind: pause help counts as a stall.
    public var kind: String {
        switch self {
        case .none: return "none"
        case .pause: return "stall"
        case .ring: return "ring"
        case .ghostToEnd: return "ghost_to_end"
        case .redemo: return "redemo"
        }
    }
}

/// A ghost car at one moment: its frontmost paint (body, dashed outline and wheels) and its nose along the line.
public struct OrientedLineGhost: Sendable, Equatable {
    public let front: Double
    public let opacity: Double

    public var nose: Double { front - OrientedLineCoach.ghostOutline }
}

/// The demo at one moment: its ghost (nil once it has faded) and its own route glow [0, G] (nil once faded) with the
/// route's opacity.
public struct OrientedLineDemoFrame: Equatable, Sendable {
    public let ghost: OrientedLineGhost?
    public let route: ClosedRange<Double>?
    public let routeOpacity: Double
}

public enum OrientedLineCoach {
    /// The pause arrow reaches this far ahead of F (T = min(F + 180, G)).
    public static let pauseReach: Double = 180
    /// The ghost is omitted when T − F is shorter than this (PROVISIONAL).
    public static let ghostMinimumRun: Double = 20
    /// The ghost's dashed outline reaches this far past its body's nose at scale 0.45.
    public static let ghostOutline: Double = 1.35
    /// Today's taxi at scale 0.45: about 79 × 41 u.
    public static let carLength: Double = 79
    /// Static chevrons: every 90 u from F + 60 to L − 30.
    public static let chevronStart: Double = 60
    public static let chevronSpacing: Double = 90
    public static let chevronEndInset: Double = 30
    /// A ">" reaches 10 u either side of its centre along u, with a 6 u stroke; headlights add a 2 u ink outline; the
    /// pause chevrons are 1.6 × as big.
    public static let chevronHalf: Double = 10
    public static let chevronStroke: Double = 6
    public static let headlightOutline: Double = 2
    public static let bigChevronScale: Double = 1.6
    /// The pause chevrons sit at F + 30, F + 90 and F + 150 (when they fit within T).
    public static let pauseChevronOffsets: [Double] = [30, 90, 150]
    /// Demo drive (PROVISIONAL) and the ghost run of a pause (the approved tracing help's 1.2 s).
    public static let demoSeconds: Double = 1.4
    public static var pauseGhostSeconds: Double { TapCountGuideData.timing.stallRingGhostSeconds }

    /// The plan of one line: the dealt level and that variant's 識咗 at the start of the line.
    public static func plan(level: TapCountGuidanceLevel, learned: Bool) -> TapCountGuidePlan {
        TapCountGuidePlan(level: level, learned: learned)
    }

    /// Painted half-extent of a chevron along u.
    public static func chevronReach(big: Bool = false, outlined: Bool = false) -> Double {
        (chevronHalf + chevronStroke / 2 + (outlined ? headlightOutline : 0)) * (big ? bigChevronScale : 1)
    }

    /// T = min(F + 180, G).
    public static func pauseTarget(line: OrientedLine, frontier: Double) -> Double {
        min(frontier + pauseReach, line.guidanceLimit)
    }

    /// Static chevron centres (every level): F + 60 + 90k up to L − 30, painted within [F, G].
    public static func staticChevrons(line: OrientedLine, frontier: Double) -> [Double] {
        guard frontier < line.guidanceLimit else { return [] }
        let reach = chevronReach()
        var out: [Double] = []
        var s = frontier + chevronStart
        while s <= line.length - chevronEndInset {
            if s - reach >= frontier, s + reach <= line.guidanceLimit { out.append(s) }
            s += chevronSpacing
        }
        return out
    }

    /// Headlights (多啲 / 標準, kept after 識咗 at 標準): the next 3 chevrons ahead of the nose, outlines within [F, G].
    public static func headlights(plan: TapCountGuidePlan, line: OrientedLine, frontier: Double) -> [Double] {
        guard plan.headlights else { return [] }
        let reach = chevronReach(outlined: true)
        return Array(staticChevrons(line: line, frontier: frontier)
            .filter { $0 - reach >= frontier && $0 + reach <= line.guidanceLimit }
            .prefix(TapCountGuideData.timing.headlightDots))
    }

    /// The glow of a pause or a ring: [F, T] with butt caps; nil once there is no room before G.
    public static func glow(line: OrientedLine, frontier: Double) -> ClosedRange<Double>? {
        let target = pauseTarget(line: line, frontier: frontier)
        return target > frontier ? frontier...target : nil
    }

    /// The pause's big chevrons: those whose paint fits within [F, T].
    public static func pauseChevrons(line: OrientedLine, frontier: Double) -> [Double] {
        let target = pauseTarget(line: line, frontier: frontier)
        let reach = chevronReach(big: true)
        return pauseChevronOffsets.map { frontier + $0 }.filter { $0 - reach >= frontier && $0 + reach <= target }
    }

    /// What the line shows now. No help once F ≥ G, and none after the line is done.
    public static func help(plan: TapCountGuidePlan, run: TapCountGuideRun, board: OrientedLineBoard,
                            now: Double) -> OrientedLineHelp {
        guard let line = board.currentLine else { return .none }
        let frontier = board.frontier
        let limit = line.guidanceLimit
        guard frontier < limit else { return .none }
        let lastMove = max(board.lastProgressAt ?? -Double.infinity, run.readyAt)
        let idle = now - lastMove
        if let redemo = plan.redemoSeconds, idle >= redemo, !board.penIsDown {
            return .redemo(since: lastMove + redemo)
        }
        // Recovery comes first (design §5.1, §6.2): a pen down off the road or not joined gets its ring whatever ran
        // before it, and the ghost to the finish is a single run that never stands in for later guidance.
        if let away = board.away(now: now) {
            let since = (away == .offRoad ? board.offRoadSince : board.awaySince) ?? now
            return .ring(away, from: frontier, to: pauseTarget(line: line, frontier: frontier),
                         since: since + OrientedLineBoard.hintAfterSeconds)
        }
        if let ghost = plan.ghostToEndSeconds, idle >= ghost, limit - frontier >= ghostMinimumRun - 1e-9,
           now - (lastMove + ghost) <= ghostToEndShownSeconds(line: line, from: frontier, to: limit) {
            return .ghostToEnd(from: frontier, to: limit, since: lastMove + ghost)
        }
        if let stall = plan.stallSeconds, board.segment == .joined {
            let since = max(lastMove, board.joinedAt ?? -Double.infinity)
            if now - since >= stall {
                return .pause(from: frontier, to: pauseTarget(line: line, frontier: frontier), since: since + stall)
            }
        }
        return .none
    }

    /// A ghost run lasts its drive and then fades out over another quarter of it.
    static let ghostRunTail = 1.25

    /// The drive of a ghost to the finish: the demo's pace, at least 0.6 s.
    public static func ghostToEndSeconds(line: OrientedLine, from: Double, to: Double) -> Double {
        max(0.6, (to - from) / max(line.guidanceLimit / demoSeconds, 1))
    }

    /// How long a ghost to the finish is on screen from its start (drive and fade); after that the help is over.
    public static func ghostToEndShownSeconds(line: OrientedLine, from: Double, to: Double) -> Double {
        ghostRunTail * ghostToEndSeconds(line: line, from: from, to: to)
    }

    /// The ghost of a pause (one 1.2 s run) or a ghost-to-the-finish help: its frontmost paint moves forward only, from
    /// F to T ≤ G; nil when T − F < 20 u or after its run. With Reduce Motion there is no ghost: guidance is static and
    /// the ghost becomes the lit stretch (design §6.2; the pause's glow, or `litStretch` for a ghost to the finish).
    public static func ghost(_ help: OrientedLineHelp, line: OrientedLine, now: Double,
                             reduceMotion: Bool = false) -> OrientedLineGhost? {
        guard !reduceMotion else { return nil }
        let run: (from: Double, to: Double, since: Double, seconds: Double)
        switch help {
        case let .pause(from, to, since): run = (from, to, since, pauseGhostSeconds)
        case let .ghostToEnd(from, to, since): run = (from, to, since, ghostToEndSeconds(line: line, from: from, to: to))
        case .none, .ring, .redemo: return nil
        }
        let to = min(run.to, line.guidanceLimit)
        // 1e-9: a run of exactly 20 u (F = L − 35.5) still shows; positions come from projections.
        guard to - run.from >= ghostMinimumRun - 1e-9 else { return nil }
        let u = (now - run.since) / run.seconds
        guard u >= 0, u <= ghostRunTail else { return nil }
        let front = run.from + (to - run.from) * min(u, 1)
        return OrientedLineGhost(front: front, opacity: u > 1 ? max(0, 1 - (u - 1) * 4) : 1)
    }

    /// With Reduce Motion a ghost to the finish is the lit stretch [F, G] instead (design §6.2), on screen for as long
    /// as the ghost's run would be. Nil otherwise (the pause's lit stretch is its glow).
    public static func litStretch(_ help: OrientedLineHelp, line: OrientedLine, now: Double,
                                  reduceMotion: Bool) -> ClosedRange<Double>? {
        guard reduceMotion, case let .ghostToEnd(from, to, since) = help else { return nil }
        let end = min(to, line.guidanceLimit)
        guard end - from >= ghostMinimumRun - 1e-9, now >= since,
              now - since <= ghostToEndShownSeconds(line: line, from: from, to: end) else { return nil }
        return from...end
    }

    /// The demo route's glow at full strength, and the reused fades after the drive (design §6.1): the route over
    /// 1.5 s, the ghost over 0.6 s.
    public static let demoRouteOpacity = 0.8
    public static var demoRouteFadeSeconds: Double { TapCountGuideData.timing.routeFadeSeconds }
    public static var demoGhostFadeSeconds: Double { TapCountGuideData.timing.mergeSeconds }

    /// The demo at `now` (design §6.1): parked at the start in the lead-in; driving to G with its own route lit; then,
    /// once the drive is over, parked at G and fading, the route more slowly. A touch that ends the demo removes it at
    /// once. With Reduce Motion it is shown in its end pose with the route lit, and fades the same way. Nil when nothing
    /// of the demo is on screen.
    public static func demoFrame(line: OrientedLine, run: TapCountGuideRun, now: Double,
                                 reduceMotion: Bool = false) -> OrientedLineDemoFrame? {
        guard let start = run.demoStartedAt, run.demoStoppedAt == nil, !run.isGlance else { return nil }
        let t = now - start
        if t < run.demoDuration {
            return OrientedLineDemoFrame(ghost: demoGhost(line: line, t: max(t, 0), reduceMotion: reduceMotion),
                                         route: t >= 0 ? demoRoute(line: line) : nil, routeOpacity: demoRouteOpacity)
        }
        let after = t - run.demoDuration
        let ghostLeft = 1 - after / demoGhostFadeSeconds, routeLeft = 1 - after / demoRouteFadeSeconds
        guard ghostLeft > 0 || routeLeft > 0 else { return nil }
        let parked = demoGhost(line: line, t: demoSeconds)
        return OrientedLineDemoFrame(ghost: ghostLeft > 0 ? OrientedLineGhost(front: parked.front, opacity: ghostLeft) : nil,
                                     route: routeLeft > 0 ? demoRoute(line: line) : nil,
                                     routeOpacity: routeLeft > 0 ? demoRouteOpacity * routeLeft : 0)
    }

    /// The demo ghost at `t` seconds into the demo: parked at the green start (nose at s = 0), then forward until its
    /// frontmost paint reaches G. Its route glow is [0, G] with a butt cap.
    public static func demoGhost(line: OrientedLine, t: Double, reduceMotion: Bool = false) -> OrientedLineGhost {
        let start = ghostOutline
        let u = reduceMotion ? 1 : min(max(t / demoSeconds, 0), 1)
        return OrientedLineGhost(front: start + (line.guidanceLimit - start) * u, opacity: 1)
    }

    public static func demoRoute(line: OrientedLine) -> ClosedRange<Double> { 0...line.guidanceLimit }
}

// MARK: - What is said is what is shown (Q8, design §6.2, §6.4)

extension OrientedLineCopy {
    /// The lines that start a line: the demo's three (「睇住架車先！」, the way, 「到你喇！」) or the start words.
    public static func lineStart(_ variant: OrientedLineVariant, demo: Bool) -> [SpokenPrompt] {
        demo ? [demoWatch, OrientedLineCopy.demo(variant), demoTurn] : [start(variant)]
    }

    /// The line a help episode says, chosen from the board the help was seen on — the view's current one, never an older
    /// commit: a ring before anything is drawn names the green start, after it the way on; a ghost to the finish says
    /// 「架車等緊你」 only with the pen up and the car under way.
    public static func helpLine(_ help: OrientedLineHelp, board: OrientedLineBoard) -> SpokenPrompt? {
        guard let line = board.currentLine else { return nil }
        switch help {
        case .none:
            return nil
        case .pause:
            return pause(line.variant)
        case let .ring(away, _, _, _):
            if away == .offRoad { return ShapeTraceCopy.offPathPrompt }
            return board.frontier < OrientedLineBoard.liftMinimum ? wrongStart(line.variant) : pause(line.variant)
        case .ghostToEnd:
            return !board.penIsDown && board.frontier >= OrientedLineBoard.liftMinimum ? lifted : nil
        case .redemo:
            return redemo
        }
    }
}

/// The lines just said for this card, shown on screen as they are said: one state drives both the voice and the text.
/// Said on a line at F, they show until F moves or the line changes (design §6.2: the pause line hides as soon as F
/// moves), judged on the board the child is drawing on now.
public struct OrientedLineCaption: Sendable, Equatable {
    public let lines: [SpokenPrompt]
    public let lineIndex: Int
    public let frontier: Double

    public init(_ lines: [SpokenPrompt], on board: OrientedLineBoard) {
        self.lines = lines
        lineIndex = board.lineIndex
        frontier = board.frontier
    }

    public func isShowing(on board: OrientedLineBoard) -> Bool {
        !lines.isEmpty && board.lineIndex == lineIndex && board.frontier <= frontier
    }
}

public enum OrientedLineRecord {
    /// A round's `round_result` extras: the board's practice fields and the dealt help level's guidance record, both
    /// from the round's own snapshot.
    public static func resultFields(board: OrientedLineBoard, guide: OrientedLineGuideTally?,
                                    playtest: Bool) -> [String: PerfValue] {
        var fields = board.resultFields(playtest: playtest)
        if let guide { fields.merge(guide.resultFields) { _, guided in guided } }
        return fields
    }
}

// MARK: - The round's guidance record (one TapCountGuideRun per line)

public struct OrientedLineGuideTally: Equatable, Sendable {
    /// The dealt 畫線提示 (snapshot).
    public let level: TapCountGuidanceLevel
    public private(set) var run: TapCountGuideRun?
    public private(set) var finished: [TapCountGuideRun] = []
    /// Refusals and on-demand demos noted on the current line (help, not clean).
    public private(set) var otherHelps = 0

    public init(question: OrientedLineQuestion) {
        level = question.dealt.lineHelp
    }

    /// A line becomes current: its plan from the dealt level and its variant's 識咗 now.
    public mutating func startLine(learned: Bool, now: Double, demoLead: Double) {
        if let run { finished.append(run) }
        run = TapCountGuideRun(plan: OrientedLineCoach.plan(level: level, learned: learned),
                               demoDuration: OrientedLineCoach.demoSeconds, now: now, demoLead: demoLead)
    }

    /// A help episode is shown: noted once; any help means the line is not clean.
    @discardableResult
    public mutating func note(_ help: OrientedLineHelp) -> Bool {
        guard let key = help.key, run != nil else { return false }
        return run!.noteHelp(key: key, kind: help.kind)
    }

    /// A refused touch on the red end (reverse or early finish): coached, so not a clean line.
    public mutating func noteRefusal(_ index: Int) {
        guard run != nil else { return }
        if run!.noteHelp(key: "refused.\(index)", kind: "refused") { otherHelps += 1 }
    }

    /// The header asked for the demo again: it counts as help.
    public mutating func demoOnDemand(now: Double, lead: Double) {
        guard run != nil else { return }
        run!.restartDemo(now: now, lead: lead)
        if run!.noteHelp(key: "demo.\(Int(now * 10))", kind: "redemo") { otherHelps += 1 }
    }

    /// The coach's re-demo (idle with the pen up): the demo again. The help itself is noted by `note(.redemo)`.
    public mutating func redemo(now: Double, lead: Double) {
        guard run != nil else { return }
        run!.restartDemo(now: now, lead: lead)
    }

    /// A touch while the demo plays ends it; true = the touch is swallowed (it never paints or moves the car).
    public mutating func touch(now: Double) -> Bool {
        guard run != nil else { return false }
        return run!.skipDemo(now: now)
    }

    public var currentClean: Bool { run?.clean ?? true }

    private var all: [TapCountGuideRun] { finished + (run.map { [$0] } ?? []) }

    /// `round_result` guidance fields (practice diagnostics only).
    public var resultFields: [String: PerfValue] {
        let runs = all
        let demos = runs.reduce(0) { $0 + $1.demosPlayed }
        let skips = runs.reduce(0) { $0 + $1.demoSkips }
        return [
            "guide_level": .string(level.rawValue),
            "demo": .string(demos == 0 ? "none" : skips > 0 ? "skipped" : "played"),
            "demos": .int(demos),
            "stall_helps": .int(runs.reduce(0) { $0 + $1.stalls }),
            "ghosts_to_end": .int(runs.reduce(0) { $0 + $1.ghostsToEnd }),
            "redemos": .int(runs.reduce(0) { $0 + $1.redemos }),
            "guide_clean": .bool(runs.allSatisfy(\.clean))
        ]
    }
}

// MARK: - 識咗 per oriented variant (the card's own store; starts empty; never copied)

public struct OrientedLineGuideProgress: Equatable, Sendable, Codable {
    public private(set) var streaks: [String: Int]

    public init(streaks: [String: Int] = [:]) {
        self.streaks = streaks.filter { key, _ in OrientedLineVariant.allCases.contains { $0.learnKey == key } }
    }

    /// 識咗 = this many clean lines of a variant in a row (the approved tracing help's rule).
    public static var cleanInARow: Int { TapCountGuideData.cleanInARow }

    public func streak(_ variant: OrientedLineVariant) -> Int { streaks[variant.learnKey] ?? 0 }

    public func isLearned(_ variant: OrientedLineVariant) -> Bool { streak(variant) >= Self.cleanInARow }

    /// A clean line adds one in a row; any help on it starts that variant again. Only the dealt line's own key moves.
    public mutating func record(_ variant: OrientedLineVariant, clean: Bool) {
        streaks[variant.learnKey] = clean ? min(99, streak(variant) + 1) : 0
    }

    public var learned: [OrientedLineVariant] { OrientedLineVariant.allCases.filter(isLearned) }
}

/// Which lane a line was drawn in: a parent's 試玩 never writes 識咗.
public enum OrientedLineLane: Sendable, Equatable {
    case child
    case playtest
}

/// The help lines already said on each lane's current line, so each is said at most once a line (design §6.4). The
/// lanes are kept apart: a parent's 試玩 never fills or clears the child's record, nor the child's the 試玩's.
public struct OrientedLineSpokenLines: Equatable, Sendable {
    private var said: [OrientedLineLane: Set<String>] = [:]

    public init() {}

    /// True the first time `key` is said on the lane's current line (and records it).
    public mutating func firstTime(_ key: String, lane: OrientedLineLane) -> Bool {
        said[lane, default: []].insert(key).inserted
    }

    /// A new line or a new deal on that lane: its lines may be said again. The other lane keeps its record.
    public mutating func newLine(_ lane: OrientedLineLane) {
        said[lane] = nil
    }

    public func hasSaid(_ key: String, lane: OrientedLineLane) -> Bool {
        said[lane]?.contains(key) == true
    }
}

public enum OrientedLineLearning {
    /// After a line is done: the child lane records the dealt line's variant, judged clean by its own guidance record;
    /// the 試玩 lane changes nothing. Returns the progress to save (nil when nothing changed).
    public static func lineDone(_ progress: OrientedLineGuideProgress, variant: OrientedLineVariant, clean: Bool,
                                lane: OrientedLineLane) -> OrientedLineGuideProgress? {
        guard lane == .child else { return nil }
        var next = progress
        next.record(variant, clean: clean)
        return next
    }
}

/// UserDefaults; missing or corrupt → nothing learned. Its own key only: no other store is read to fill it.
public struct OrientedLineGuideProgressStore {
    public static let key = "VisaGames.orientedLineGuideProgress.v1"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> OrientedLineGuideProgress {
        guard let data = defaults.data(forKey: Self.key),
              let progress = try? JSONDecoder().decode(OrientedLineGuideProgress.self, from: data) else {
            return OrientedLineGuideProgress()
        }
        return OrientedLineGuideProgress(streaks: progress.streaks)
    }

    public func save(_ progress: OrientedLineGuideProgress) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
