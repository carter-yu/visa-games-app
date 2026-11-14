import Foundation

// Hanzi H3 write core (0.38.0 / 84): design hanzi-tap v2 § Writing, its H3 row and child copy table, LOCKED D5 (MOE
// order), D10 (numbered starts), D11 (sign semantics) and D12 (右's shared start). The 田字格 placement of the
// 300 × 300 glyph box on the write card, the numbered starts with their direction arrows, the sign boxes the clearance
// checks read, the write copy from the pack, and the 搵完寫 write round. The round drives the shared trace engine and
// coach (`NumeralGuide(hanzi:)`, `TapCountGuideCoach`, `TapCountDemoTimeline`, `TapCountGuideRun`) with the Hanzi
// compact style and 右's STOP turn injected, as `TapLetterWriteRound` does for letters. Writing is practice: nothing
// here can miss, cost fuel or change the find result. `TapHanziWriteBoardView` draws it; AppModel owns the clocks,
// the voice and saving. No parent card, setting or report (H4). H4.1 adds the 寫字格 lines for the parent's 田字格 /
// 米字格 choice (`HanziWritingGridGeometry`).

// MARK: - Board placement

/// The write card and its 田字格 square in stage units (1280 × 720): the design's 1920 × 1080 frames scaled by 2/3.
/// The card is the letter write card's frame; the square holds the 300 × 300 box scaled uniformly (mockups 01–05).
public enum HanziWriteBoard {
    public static let card = LineMatchRect(x: 440, y: 126, width: 400, height: 408)
    public static let square = LineMatchRect(x: 465, y: 166, width: 350, height: 350)
    /// Stage units per glyph unit (7 / 6), the same on both axes: no stretch.
    public static var scale: Double { square.width / HanziGlyphs.boxSize.width }
    public static var offset: LineMatchPoint { LineMatchPoint(x: square.x, y: square.y) }
    /// The judged lane: the pack's 36 glyph units on the board.
    public static var laneWidth: Double { HanziGlyphs.laneWidth * scale }
    /// A stroke counts as drawn no earlier than this share of its length (design `shortStrokeProgressFraction`), so
    /// 下's short 點 is a short down-right stroke, never a tap or a nudge.
    public static let minimumArrivalFraction = 0.7
    /// The pen takes the car only this near it (half the 36-unit lane): never from a later start or the red end, and
    /// the car then moves only as far as the pen moves (`ShapeTracePenRule.orderedStarts`). A pen that takes it this
    /// far ahead still finishes every stroke in one pen-down: 下's 點 leaves the car at 70.87 − 21 ≥ 70% of it.
    public static var holdRadius: Double { HanziGlyphs.laneWidth / 2 * scale }
    /// The direction arrow sits this far (glyph units) along each stroke from its start (mockups 01–05).
    public static let arrowLead: Double = 24
    /// A numbered start's disc: radius 10 plus half its 2-unit outline (glyph units, mockups 01–05).
    public static let labelRadius: Double = 11

    public static func stage(_ p: LineMatchPoint) -> LineMatchPoint {
        LineMatchPoint(x: offset.x + p.x * scale, y: offset.y + p.y * scale)
    }

    /// The pack's centre lines on the board, in MOE order (D5); empty for a glyph the pack does not name.
    public static func paths(_ glyph: String, in pack: HanziPack) -> [TracePath] {
        HanziGlyphs.paths(glyph, in: pack, offset: offset, scale: scale)
    }

    /// The shared guide on the board: beats, cues and sign centres placed with the strokes, with the compact style and
    /// the STOP-turn pause (`NumeralGuide(hanzi:in:offset:scale:)`). Nil for a find-only or unknown glyph.
    public static func guide(_ glyph: String, in pack: HanziPack) -> NumeralGuide? {
        NumeralGuide(hanzi: glyph, in: pack, offset: offset, scale: scale)
    }

    /// Every numbered start of `glyph`, in order (D10): all visible, only the current one takes the pen. A pack leader
    /// moves the number, never the start (D12: 右's ③ and ④ share one start with two leaders). `current` is the
    /// stroke being written; nil once the glyph is drawn.
    public static func startMarks(_ glyph: String, in pack: HanziPack, current: Int?) -> [HanziStartMark] {
        guard let character = pack.characters[glyph] else { return [] }
        let paths = paths(glyph, in: pack)
        guard paths.count == character.strokes.count else { return [] }
        return zip(character.strokes, paths).enumerated().compactMap { index, pair in
            let (stroke, path) = pair
            guard let marker = stroke.marker else { return nil }
            let start = stage(marker.anchor.point)
            let shift = marker.leaderToActualStart == true ? marker.reviewLabelOffset : nil
            let label = shift.map { LineMatchPoint(x: start.x + $0.x * scale, y: start.y + $0.y * scale) } ?? start
            let lead = min(path.length, arrowLead * scale)
            let state: HanziStartMark.State = current.map { index < $0 ? .done : index == $0 ? .current : .future } ?? .done
            return HanziStartMark(stroke: index, label: marker.label, start: start, labelAt: label, leader: shift != nil,
                                  arrowAt: path.point(at: lead), arrowAngle: path.angle(at: lead), state: state)
        }
    }

    /// Where a cue's sign is drawn (stage units): the AHEAD disc or the STOP octagon artwork around its anchor, at the
    /// guide's sign scale. The clearance checks keep it inside the 田字格 square and off every lane.
    public static func signBox(_ cue: NumeralGuide.Cue, guide: NumeralGuide) -> LineMatchRect {
        let art = cue.sign == .ahead ? TapCountArt.guideAhead : TapCountArt.guideStop
        let scale = cue.sign == .ahead ? guide.aheadSignScale : guide.stopSignScale
        let anchor = TapCountArt.anchor(art)
        return LineMatchRect(x: cue.signPoint.x - anchor.x * scale, y: cue.signPoint.y - anchor.y * scale,
                             width: art.width * scale, height: art.height * scale)
    }
}

/// One numbered start on the write board (stage units).
public struct HanziStartMark: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// Written: a small muted label.
        case done
        /// The ordered start that takes the pen (green).
        case current
        /// Not reached yet: a subdued outline.
        case future
    }

    public let stroke: Int
    public let label: String
    /// The true start (never moved).
    public let start: LineMatchPoint
    /// Where the number sits: the start itself, or the pack's leader offset with a line back to the start.
    public let labelAt: LineMatchPoint
    public let leader: Bool
    /// The small direction arrow, `HanziWriteBoard.arrowLead` along the stroke, and its heading (radians).
    public let arrowAt: LineMatchPoint
    public let arrowAngle: Double
    public let state: State

    /// Only the current start takes the pen (D10). The trace engine enforces it (`ShapeTracePenRule.orderedStarts`):
    /// a pen-down on a later start is a coached wrong start unless it is also the current start (右's ③ / ④).
    public var acceptsInput: Bool { state == .current }
}

// MARK: - 寫字格

/// One line of the write board's grid (stage units).
public struct HanziGridLine: Equatable, Sendable {
    public enum Role: String, Equatable, Sendable {
        /// A side of the square.
        case border
        /// The centre vertical or horizontal.
        case centre
        /// A 米字格 corner-to-corner diagonal.
        case diagonal
    }

    public let role: Role
    public let from: LineMatchPoint
    public let to: LineMatchPoint
    /// The border is a faint solid line; the centre cross and the diagonals share one light dash, so a diagonal is
    /// never stronger than the cross.
    public var dashed: Bool { role != .border }

    public init(role: Role, from: LineMatchPoint, to: LineMatchPoint) {
        self.role = role
        self.from = from
        self.to = to
    }
}

/// 寫字格 lines (D3; 米字格 since H4.1): a pure function of the grid and the square, never of a glyph, its strokes,
/// their judging or the coach. The write board strokes them under everything else.
public enum HanziWritingGridGeometry {
    /// 田字格: the four sides, then the centre vertical and horizontal. 米字格: the same six, then both diagonals
    /// (top-left to bottom-right, top-right to bottom-left).
    public static func lines(for grid: HanziWritingGrid, in square: LineMatchRect) -> [HanziGridLine] {
        let topLeft = LineMatchPoint(x: square.x, y: square.y), topRight = LineMatchPoint(x: square.maxX, y: square.y)
        let bottomRight = LineMatchPoint(x: square.maxX, y: square.maxY)
        let bottomLeft = LineMatchPoint(x: square.x, y: square.maxY)
        var lines = [
            HanziGridLine(role: .border, from: topLeft, to: topRight),
            HanziGridLine(role: .border, from: topRight, to: bottomRight),
            HanziGridLine(role: .border, from: bottomRight, to: bottomLeft),
            HanziGridLine(role: .border, from: bottomLeft, to: topLeft),
            HanziGridLine(role: .centre, from: LineMatchPoint(x: square.midX, y: square.y),
                          to: LineMatchPoint(x: square.midX, y: square.maxY)),
            HanziGridLine(role: .centre, from: LineMatchPoint(x: square.x, y: square.midY),
                          to: LineMatchPoint(x: square.maxX, y: square.midY))
        ]
        if grid == .mizi {
            lines += [HanziGridLine(role: .diagonal, from: topLeft, to: bottomRight),
                      HanziGridLine(role: .diagonal, from: topRight, to: bottomLeft)]
        }
        return lines
    }
}

// MARK: - Copy

/// A line with an optional small sub-line (the tray, the legend, 右's corner and its pen rule).
public struct HanziWriteLine: Equatable, Sendable {
    public let text: String
    public let sub: String?

    public init(_ text: String, sub: String? = nil) {
        self.text = text
        self.sub = sub
    }
}

/// The write board's lines from the pack's child copy (design child copy table), `{H}` filled. HK Traditional `zhHK`
/// is shown and, only with audio on, spoken. Beat, cue, merge and hop lines come with the guide
/// (`HanziGuideData.spec`).
public struct HanziWriteCopy: Equatable, Sendable {
    /// Every pack line the write board shows; a pack missing one, or a template without its placeholder, gives no copy.
    public static let keys: [String: [String]] = [
        "writeHeader": ["{H}"], "writeSubline": [], "writeWatch": ["{H}"], "writeTurn": ["{H}"], "writeReprompt": ["{H}"],
        "writeDone": ["{H}"], "redemo": [], "stopSign": [], "trayDemo": [], "trayTrace": [], "trayStall": [],
        "cornerPenRule": [], "legendHeadlights": [], "legendAhead": [], "legendStop": []
    ]
    /// The footer's Find → Write chips (mockups 01–05).
    public static let findChip = "搵晒"
    public static let writeChip = "寫"

    private let lines: [String: HanziText]

    public init?(pack: HanziPack) {
        var lines: [String: HanziText] = [:]
        for (key, placeholders) in Self.keys {
            guard let line = pack.copy[key], !line.zhHK.isEmpty,
                  placeholders.allSatisfy({ line.zhHK.components(separatedBy: $0).count == 2 }) else { return nil }
            lines[key] = line
        }
        self.lines = lines
    }

    private func zh(_ key: String, _ glyph: String = "") -> String {
        (lines[key]?.zhHK ?? "").replacingOccurrences(of: "{H}", with: glyph)
    }

    private func line(_ key: String) -> HanziWriteLine {
        HanziWriteLine(zh(key), sub: lines[key]?.zhHKSub)
    }

    private func parts(_ key: String) -> (before: String, after: String) {
        let parts = zh(key, "{H}").components(separatedBy: "{H}")
        return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
    }

    /// The header around its glyph, so the view draws the glyph from its centre lines: 「而家寫『」, 「』！」.
    public var headerParts: (before: String, after: String) { parts("writeHeader") }
    /// The header once the glyph is drawn: 「你寫咗『」, 「』！」.
    public var doneParts: (before: String, after: String) { parts("writeDone") }
    /// 「由綠色起點，跟住箭嘴寫。」
    public var subline: String { zh("writeSubline") }
    /// 「而家寫『右』！先睇車仔。」 as the demo car sets off.
    public func watch(_ glyph: String) -> String { zh("writeWatch", glyph) }
    /// 「到你喇！跟住箭嘴寫『右』。」 when the pen is the child's.
    public func turn(_ glyph: String) -> String { zh("writeTurn", glyph) }
    /// 「喺綠色箭嘴開始，寫『右』！」 (robot, wrong start).
    public func reprompt(_ glyph: String) -> String { zh("writeReprompt", glyph) }
    /// 「你寫咗『右』！」
    public func done(_ glyph: String) -> String { zh("writeDone", glyph) }
    /// 「再睇車仔行一次！」 before the 20 s re-demo.
    public var redemo: String { zh("redemo") }
    /// The word on the STOP sign: 「停」.
    public var stopWord: String { zh("stopSign") }
    /// The tray while the demo plays, while the child writes, and while a help runs.
    public var trayDemo: HanziWriteLine { line("trayDemo") }
    public var trayTrace: HanziWriteLine { line("trayTrace") }
    public var trayStall: HanziWriteLine { line("trayStall") }
    /// 右's corner: the cue line with 「轉彎唔提筆。」 under it.
    public func stopCue(_ cueLine: String) -> HanziWriteLine { HanziWriteLine(cueLine, sub: zh("cornerPenRule")) }
    /// The legend: 「頭燈」—「睇下一段」, 「繼續」—「經過交接位」, 「停」—「停一停，再轉彎」.
    public var legendHeadlights: HanziWriteLine { line("legendHeadlights") }
    public var legendAhead: HanziWriteLine { line("legendAhead") }
    public var legendStop: HanziWriteLine { line("legendStop") }
    /// The card's stroke counter: 「第 4 / 5 筆」.
    public func strokeCount(_ stroke: Int, of total: Int) -> String { "第 \(stroke) / \(total) 筆" }
}

// MARK: - Write round

/// What the coach starts at a tick or pen move. Help is practice: it never marks the child wrong.
public enum TapHanziWriteCoach: Equatable, Sendable {
    /// A help episode starts: the stall ring with the ghost of the next bit, or the ghost to the stroke's end.
    case help(TapCountGuideHelp)
    /// 20 s idle with the pen up: the car demo again.
    case redemo
    /// The car nears a sign: its line, once per round.
    case cue(NumeralGuide.Cue)
}

/// 搵完寫's write round: the completed find, then the target on the 田字格 board with the shared coach. Mirrors
/// `TapLetterWriteRound`. Writing has no miss transition and never changes the find result, so the round's visa
/// minutes and recognition record are the find's alone.
public struct TapHanziWriteRound: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case transition, writing, done }

    /// What a pen-down did.
    public enum PenDown: Equatable, Sendable {
        /// The first touch while the car demo is on screen only ends it: nothing is painted.
        case demoDismissed
        case trace(ShapeTracePenDown)
        case ignored
    }

    /// The 20 s re-demo plays at most this often per round (the tap-count rule).
    public static let maxRedemos = 2

    /// The find as it was completed; writing never changes it.
    public let board: TapHanziBoard
    public let guide: NumeralGuide
    public let timeline: TapCountDemoTimeline
    public private(set) var trace: ShapeTraceBoard
    public private(set) var phase: Phase = .transition
    /// The coach: plan, demo clock and the help noted. Nil until writing begins.
    public private(set) var coach: TapCountGuideRun?

    /// Nil unless the find is a completed 搵完寫 find and its target has a guide on the board.
    public init?(found board: TapHanziBoard, pack: HanziPack, tolerance: LineMatchTolerance = .standard) {
        guard board.isComplete, board.finish == .awaitWriteRound,
              let guide = HanziWriteBoard.guide(board.target, in: pack) else { return nil }
        self.board = board
        self.guide = guide
        timeline = TapCountDemoTimeline(guide: guide)
        let shape = ShapeTraceShape(slot: "hanzi", kind: .numeral, strokes: guide.paths, colorIndex: 0,
                                    frame: HanziWriteBoard.square)
        let question = ShapeTraceQuestion(itemID: "tapHanzi.write.\(board.target)", kind: .tapHanziWrite, level: .l2,
            scene: .numeralBoard, shift: 0, big: true, slant: false, shapes: [shape], laneWidth: HanziWriteBoard.laneWidth,
            promptKey: "tapHanzi.write.\(board.target)", promptTraditionalChinese: "", promptEnglish: "",
            minimumArrivalFraction: HanziWriteBoard.minimumArrivalFraction,
            penRule: .orderedStarts(holdRadius: HanziWriteBoard.holdRadius))
        trace = ShapeTraceBoard(question: question, tolerance: tolerance)
    }

    public var glyph: String { board.target }
    public var canStamp: Bool { phase == .done && trace.isComplete }
    /// Writing-progress clean: no coach help, wrong start, reversal or off-path event (`HanziWriteProgress.isClean`).
    public var clean: Bool { HanziWriteProgress.isClean(guide: coach, trace: trace) }

    /// The car demo (or its lead-in) is on screen: the first touch ends it.
    public func demoPending(now: Double) -> Bool { phase == .writing && coach?.demoPending(now: now) == true }

    /// The beat whose line a stall or ghost shows: the one the car is in, never past a corner it has not reached, as
    /// the capped stall ghost (`NumeralGuide.stallGhostEnd`).
    public var helpBeat: Int? {
        trace.isComplete ? nil : guide.beatIndex(stroke: trace.strokeIndex, at: trace.progress)
    }

    /// Writing begins: the car demo plays first when `plan` says so (多啲 always, 標準 until learned, 少啲 never).
    public mutating func begin(plan: TapCountGuidePlan, now: Double, demoLead: Double) {
        guard phase == .transition else { return }
        phase = .writing
        coach = TapCountGuideRun(plan: plan, demoDuration: timeline.duration, now: now, demoLead: demoLead)
    }

    @discardableResult
    public mutating func penDown(at point: LineMatchPoint, now: Double) -> PenDown {
        guard phase == .writing, var run = coach else { return .ignored }
        if run.skipDemo(now: now) {
            coach = run
            return .demoDismissed
        }
        var next = trace
        let result = next.penDown(at: point, now: now)
        noteWrongStart(next)
        accept(next)
        return .trace(result)
    }

    /// Ignored while the demo is on screen (a dismissing touch never paints). A slide onto the car that a pen-down there
    /// would make a wrong start or reversal is coached as that pen-down (D10).
    @discardableResult
    public mutating func penMove(to point: LineMatchPoint, now: Double) -> ShapeTraceMove {
        guard phase == .writing, coach?.demoPending(now: now) == false else { return .ignored }
        var next = trace
        let move = next.penMove(to: point, now: now)
        noteWrongStart(next)
        accept(next)
        return move
    }

    /// A wrong start or a start at the red end (a reversal), by a pen-down or a slide, is coached, never a miss.
    private mutating func noteWrongStart(_ next: ShapeTraceBoard) {
        guard next.wrongStarts > trace.wrongStarts, var run = coach else { return }
        run.noteHelp(key: "wrong_start.\(next.wrongStarts)",
                     kind: next.reverseDirections > trace.reverseDirections ? "reverse" : "wrong_start")
        coach = run
    }

    public mutating func penUp() {
        guard phase == .writing else { return }
        var next = trace
        next.penUp()
        accept(next)
    }

    /// What the coach starts now (call on each clock tick and pen move): each help episode and each sign line once;
    /// the 20 s re-demo restarts the car at most `maxRedemos` times. The 2 / 8 / 20 s timers are the plan's.
    public mutating func coachTick(now: Double, demoLead: Double) -> [TapHanziWriteCoach] {
        guard phase == .writing, var run = coach, !run.demoPending(now: now) else { return [] }
        var started: [TapHanziWriteCoach] = []
        let help = TapCountGuideCoach.help(plan: run.plan, guide: guide, trace: trace, readyAt: run.readyAt, now: now)
        if let key = help.key {
            if case .redemo = help {
                if run.redemos < Self.maxRedemos, run.noteHelp(key: key, kind: help.kind) {
                    run.restartDemo(now: now, lead: demoLead)
                    started.append(.redemo)
                }
            } else if run.noteHelp(key: key, kind: help.kind) {
                started.append(.help(help))
            }
        }
        if run.plan.cueWords, !run.demoPending(now: now),
           let cue = TapCountGuideCoach.activeCue(guide: guide, trace: trace), run.noteCue(cue.index) {
            started.append(.cue(cue))
        }
        coach = run
        return started
    }

    /// Writing facts for the round result (practice; no score).
    public var resultFields: [String: PerfValue] {
        var fields: [String: PerfValue] = [
            "write_clean": .bool(clean), "lifts": .int(trace.lifts), "off_path": .int(trace.offPathCount),
            "wrong_start": .int(trace.wrongStarts), "reverse": .int(trace.reverseDirections),
            "corner_overshoot": .int(trace.cornerOvershoots), "strokes_drawn": .int(trace.strokesDone)
        ]
        if let coach {
            fields["guide_level"] = .string(coach.plan.level.rawValue)
            fields["guide_demo"] = .string(coach.demoCode)
            fields["guide_stalls"] = .int(coach.stalls)
            fields["guide_ghost_to_end"] = .int(coach.ghostsToEnd)
            fields["guide_redemos"] = .int(coach.redemos)
        }
        return fields
    }

    private mutating func accept(_ next: ShapeTraceBoard) {
        guard next.isMonotonicSuccessor(of: trace) else { return }
        trace = next
        if next.isComplete { phase = .done }
    }
}
