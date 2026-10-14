import Foundation

// MARK: - Stage geometry (1280 × 720 canvas units)

public struct LineMatchPoint: Sendable, Equatable, Codable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: LineMatchPoint) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

public struct LineMatchRect: Sendable, Equatable, Codable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func contains(_ point: LineMatchPoint) -> Bool {
        point.x >= x && point.x <= maxX && point.y >= y && point.y <= maxY
    }

    public func intersects(_ other: LineMatchRect) -> Bool {
        x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
    }

    /// Clear space between two rectangles (0 when they touch or overlap).
    public func gap(to other: LineMatchRect) -> Double {
        let dx = max(0, max(other.x - maxX, x - other.maxX))
        let dy = max(0, max(other.y - maxY, y - other.maxY))
        return max(dx, dy)
    }
}

/// Where everything sits on the line-match board (approved mockups 05a–05i).
///
/// ★ (2 pairs): wide rows, 240 × 140 cards, 擦晒 bottom-left and 完成 in the bottom bar, inset
/// so its right edge is 1080 (the parent long-press corner stays empty).
/// ★★ / ★★★ (3–4 pairs): 120u-high cards beside the buttons — 擦晒 160 × 160 bottom-left,
/// 完成 160 × 160 top-right — every card ≥ 80u from both buttons.
public struct LineMatchLayout: Sendable, Equatable {
    public enum Style: String, Sendable { case wide, side }

    public var style: Style
    public var leftCards: [LineMatchRect]
    public var rightCards: [LineMatchRect]
    public var leftDots: [LineMatchPoint]
    public var rightDots: [LineMatchPoint]
    public var eraser: LineMatchRect
    public var done: LineMatchRect
    /// Centre of the progress dots + status line.
    public var status: LineMatchPoint

    /// Drawn dot radius (the hit radius comes from `LineMatchTolerance`).
    public static let dotRadius: Double = 22
    /// Dots sit this far outside their card.
    public static let dotOffset: Double = 30
    /// The child-board parent corner (`ParentLayer` hold target at 1220, 664, 44u, plus its
    /// 24u drift allowance) — nothing on this board may sit here (design §8.5).
    public static let parentCornerKeepOut = LineMatchRect(x: 1196, y: 640, width: 84, height: 80)
    /// Header band (prompt, game pill, visa ticket).
    public static let header = LineMatchRect(x: 20, y: 16, width: 1240, height: 96)

    public static func make(pairCount n: Int, category: LineMatchCategory) -> LineMatchLayout {
        let count = max(1, n)
        if count <= 2 {
            let rows = [130.0, 328.0].prefix(count)
            let left = rows.map { LineMatchRect(x: 44, y: $0, width: 240, height: 140) }
            let right = rows.map { LineMatchRect(x: 996, y: $0, width: 240, height: 140) }
            return LineMatchLayout(
                style: .wide, leftCards: left, rightCards: right,
                leftDots: left.map { LineMatchPoint(x: $0.maxX + dotOffset, y: $0.midY) },
                rightDots: right.map { LineMatchPoint(x: $0.x - dotOffset, y: $0.midY) },
                eraser: LineMatchRect(x: 24, y: 548, width: 200, height: 160),
                done: LineMatchRect(x: 840, y: 548, width: 240, height: 160),
                status: LineMatchPoint(x: 532, y: 630)
            )
        }
        let rows: [Double] = count == 3 ? [140, 290, 440] : [122, 252, 382, 512]
        let numbers = category == .numbers
        let leftX: Double = numbers ? 264 : 304
        let leftWidth: Double = numbers ? 240 : 140
        let rightX: Double = numbers ? 846 : 836
        let rightWidth: Double = numbers ? 170 : 180
        let left = rows.prefix(count).map { LineMatchRect(x: leftX, y: $0, width: leftWidth, height: 120) }
        let right = rows.prefix(count).map { LineMatchRect(x: rightX, y: $0, width: rightWidth, height: 120) }
        let leftDots = left.map { LineMatchPoint(x: $0.maxX + dotOffset, y: $0.midY) }
        let rightDots = right.map { LineMatchPoint(x: $0.x - dotOffset, y: $0.midY) }
        let middle = ((leftDots.first?.x ?? 0) + (rightDots.first?.x ?? 0)) / 2
        return LineMatchLayout(
            style: .side, leftCards: left, rightCards: right, leftDots: leftDots, rightDots: rightDots,
            eraser: LineMatchRect(x: 24, y: 548, width: 160, height: 160),
            done: LineMatchRect(x: 1096, y: 130, width: 160, height: 160),
            status: LineMatchPoint(x: middle, y: count == 3 ? 636 : 652)
        )
    }

    /// Left row under `point`: inside its card or within `radius` of its green dot (nearest wins).
    public func leftRow(at point: LineMatchPoint, radius: Double) -> Int? {
        Self.nearest(point, dots: leftDots, cards: leftCards, radius: radius)
    }

    /// Right slot under `point` (drop zone = the card or `radius` around its red dot).
    public func rightSlot(at point: LineMatchPoint, radius: Double) -> Int? {
        Self.nearest(point, dots: rightDots, cards: rightCards, radius: radius)
    }

    private static func nearest(_ point: LineMatchPoint, dots: [LineMatchPoint], cards: [LineMatchRect],
                                radius: Double) -> Int? {
        var best: (index: Int, distance: Double)?
        for index in dots.indices {
            let distance = point.distance(to: dots[index])
            let inCard = cards.indices.contains(index) && cards[index].contains(point)
            guard distance <= radius || inCard else { continue }
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.index
    }
}

// MARK: - Board state machine (design §1.6 / §6; D2, D3)

public struct LineMatchLine: Sendable, Equatable, Hashable, Codable {
    public var row: Int
    public var slot: Int

    public init(row: Int, slot: Int) {
        self.row = row
        self.slot = slot
    }
}

public enum LineMatchDragStart: Sendable, Equatable {
    /// Pen down on a green dot / picture card: the truck follows from this row.
    case started(row: Int)
    /// Pen down on the right side: 「由綠點開始啊」. Motor slip, never a miss (tag `wrong_direction`).
    case wrongDirection
    /// Row already judged right (locked green).
    case lockedRow
    /// Empty space, or the question is finished.
    case ignored
}

public enum LineMatchDropOutcome: Sendable, Equatable {
    /// Line now joins `row` → `slot`. `replaced` = an earlier line from this row or into this
    /// slot was taken away (the child changed their mind).
    case joined(row: Int, slot: Int, replaced: Int)
    /// Same line drawn again.
    case unchanged(row: Int, slot: Int)
    /// Let go between the dots or on a judged card: the line springs back. Not a miss (D2).
    case retracted(row: Int)
    case ignored
}

public enum LineMatchEraserState: Sendable, Equatable {
    /// 6th use: hidden until the next 完成.
    case hidden
    /// 3 s cooldown after a use.
    case coolingDown(remaining: Double)
    /// Nothing unjudged to clear (grey).
    case empty
    case ready
}

public enum LineMatchEraseOutcome: Sendable, Equatable {
    /// `nudge` = 4th use: 「試吓撳完成啦！」 and 完成 glows. `hidden` = the eraser is now put away.
    case cleared(lines: Int, nudge: Bool, hidden: Bool)
    case ignored(LineMatchEraserState)
}

public struct LineMatchJudgement: Sendable, Equatable {
    /// Lines judged right this time (now locked green).
    public var correct: [LineMatchLine]
    /// Lines judged wrong (cleared; orange rings show where they were).
    public var wrong: [LineMatchLine]
    public var solved: Bool { wrong.isEmpty }
}

public enum LineMatchSubmitOutcome: Sendable, Equatable {
    /// Some green dots have no line: gentle 「仲有未連嘅」, no penalty.
    case notReady(missing: Int)
    /// Judged. Any wrong line = ONE miss for the whole submit (D3).
    case judged(LineMatchJudgement)
    /// Already solved.
    case ignored
}

/// Pure line-match board. The app owns the clock (`now`, seconds) and the wrong-answer policy;
/// this type only decides what a drag, an erase or a 完成 does.
public struct LineMatchBoard: Sendable, Equatable {
    public static let eraserCooldownSeconds: Double = 3
    /// 4th erase in a question: nudge toward 完成.
    public static let eraserNudgeUse = 4
    /// 6th erase in a question: eraser hides until the next 完成 (and after every later use).
    public static let eraserHideUse = 6
    /// Orange rings stay this long after the Think Pause ends.
    public static let rejectFlashSeconds: Double = 1.5

    public let question: LineMatchQuestion
    public let layout: LineMatchLayout
    public let tolerance: LineMatchTolerance

    /// Unjudged lines: left row → right slot. One per row, one per slot.
    public private(set) var lines: [Int: Int] = [:]
    /// Lines judged right on an earlier 完成 (green). The eraser never clears these.
    public private(set) var locked: [Int: Int] = [:]
    /// Row whose line is being drawn now (its old line, if any, is lifted until the drop).
    public private(set) var activeRow: Int?
    /// Where the last wrong 完成 cleared lines (orange rings).
    public private(set) var rejectedRows: [Int] = []
    public private(set) var rejectedSlots: [Int] = []
    public private(set) var rejectFlashUntil: Double?
    public private(set) var solved = false

    public private(set) var eraserUses = 0
    public private(set) var eraserReadyAt: Double?
    public private(set) var eraserHidden = false
    public private(set) var eraserEverHidden = false
    /// 4th erase → 完成 glows until the next 完成.
    public private(set) var submitNudge = false

    public private(set) var submits = 0
    public private(set) var wrongSubmits = 0
    /// Every line judged wrong so far in this question.
    public private(set) var judgedWrongLines: Set<LineMatchLine> = []
    /// The last 完成 repeated a line already judged wrong (`answer_attempt.repeat_wrong`; the
    /// choice id is always `submit`, so the tracker's own check would flag every 2nd miss).
    public private(set) var lastSubmitRepeatedWrong = false
    /// Lines the child replaced or moved before a 完成 (self-correction; design §1.6 stats).
    public private(set) var preSubmitChanges = 0
    public private(set) var incompleteStrokes = 0
    public private(set) var wrongDirections = 0
    public private(set) var joins = 0

    public init(question: LineMatchQuestion, tolerance: LineMatchTolerance = .standard) {
        self.question = question
        self.tolerance = tolerance
        self.layout = LineMatchLayout.make(pairCount: question.pairCount, category: question.category)
    }

    public var rows: Range<Int> { 0..<question.pairCount }
    public var hitRadius: Double { tolerance.dotRadius }

    /// Right slots already taken by a line (open or locked).
    public var joinedRows: Set<Int> { Set(lines.keys).union(locked.keys) }
    public var joinedCount: Int { joinedRows.count }
    public var missingCount: Int { question.pairCount - joinedCount }

    /// 完成 lights up once every green dot has a line (design §1.6).
    public var canSubmit: Bool { !solved && missingCount == 0 }

    /// Hint target after 2 misses: the first pair not yet locked right.
    public var hintRow: Int? { solved ? nil : rows.first(where: { locked[$0] == nil }) }

    /// Lines to draw, open first then locked (the active row's old line is hidden).
    public var visibleLines: [(line: LineMatchLine, locked: Bool)] {
        let open = lines.keys.sorted().filter { $0 != activeRow }.map {
            (line: LineMatchLine(row: $0, slot: lines[$0] ?? 0), locked: false)
        }
        let done = locked.keys.sorted().map { (line: LineMatchLine(row: $0, slot: locked[$0] ?? 0), locked: true) }
        return open + done
    }

    public func slotIsLocked(_ slot: Int) -> Bool { locked.values.contains(slot) }

    /// Numbers: objects on left card `row`, relative to the card's top-left. Every card of the
    /// question uses the same object size, so only the count differs (design §6 排法).
    public func objectPlacements(row: Int) -> [LineMatchObjectPlacement] {
        guard let object = question.countObject, question.pairs.indices.contains(row),
              layout.leftCards.indices.contains(row) else { return [] }
        let card = layout.leftCards[row]
        let scale = LineMatchCountLayout.objectScale(object: object, counts: question.pairs.map(\.count),
                                                     cardWidth: card.width, cardHeight: card.height)
        return LineMatchCountLayout.placements(count: question.pairs[row].count, object: object, scale: scale,
                                               cardWidth: card.width, cardHeight: card.height)
    }

    /// Red dot the pen would join if it let go here (for the "grow" highlight). Nil = retract.
    public func dropTarget(at point: LineMatchPoint) -> Int? {
        guard activeRow != nil, let slot = layout.rightSlot(at: point, radius: hitRadius) else { return nil }
        return slotIsLocked(slot) ? nil : slot
    }

    // MARK: Drag

    public mutating func beginDrag(at point: LineMatchPoint) -> LineMatchDragStart {
        activeRow = nil
        guard !solved else { return .ignored }
        if let row = layout.leftRow(at: point, radius: hitRadius) {
            if locked[row] != nil { return .lockedRow }
            activeRow = row
            clearRejected()
            return .started(row: row)
        }
        if layout.rightSlot(at: point, radius: hitRadius) != nil {
            wrongDirections += 1
            return .wrongDirection
        }
        return .ignored
    }

    public mutating func endDrag(at point: LineMatchPoint) -> LineMatchDropOutcome {
        guard let row = activeRow else { return .ignored }
        activeRow = nil
        guard let slot = dropTargetSlot(at: point) else {
            incompleteStrokes += 1
            return .retracted(row: row)
        }
        if lines[row] == slot { return .unchanged(row: row, slot: slot) }
        var replaced = 0
        if lines[row] != nil { replaced += 1 }
        for (other, taken) in lines where other != row && taken == slot {
            lines[other] = nil
            replaced += 1
        }
        lines[row] = slot
        joins += 1
        preSubmitChanges += replaced
        return .joined(row: row, slot: slot, replaced: replaced)
    }

    /// Think Pause, window change or a lost gesture: drop the live line, change nothing else.
    public mutating func cancelDrag() {
        activeRow = nil
    }

    private func dropTargetSlot(at point: LineMatchPoint) -> Int? {
        guard let slot = layout.rightSlot(at: point, radius: hitRadius), !slotIsLocked(slot) else { return nil }
        return slot
    }

    // MARK: Eraser

    public func eraserState(now: Double) -> LineMatchEraserState {
        if eraserHidden { return .hidden }
        if let readyAt = eraserReadyAt, now < readyAt { return .coolingDown(remaining: readyAt - now) }
        if lines.isEmpty { return .empty }
        return .ready
    }

    /// 擦晒: clears every unjudged line (never the locked green ones). No penalty; counted for stats.
    public mutating func erase(now: Double) -> LineMatchEraseOutcome {
        let state = eraserState(now: now)
        guard state == .ready else { return .ignored(state) }
        let cleared = lines.count
        lines.removeAll()
        activeRow = nil
        clearRejected()
        eraserUses += 1
        eraserReadyAt = now + Self.eraserCooldownSeconds
        let nudge = eraserUses == Self.eraserNudgeUse
        if nudge { submitNudge = true }
        if eraserUses >= Self.eraserHideUse {
            eraserHidden = true
            eraserEverHidden = true
        }
        return .cleared(lines: cleared, nudge: nudge, hidden: eraserHidden)
    }

    // MARK: 完成

    /// Judges every open line at once. Right lines lock green; wrong lines are cleared and
    /// ringed. The caller applies ONE wrong-answer consequence when `wrong` is not empty.
    public mutating func submit() -> LineMatchSubmitOutcome {
        guard !solved else { return .ignored }
        activeRow = nil
        guard canSubmit else { return .notReady(missing: missingCount) }
        submits += 1
        eraserHidden = false
        submitNudge = false
        var correct: [LineMatchLine] = []
        var wrong: [LineMatchLine] = []
        for row in lines.keys.sorted() {
            guard let slot = lines[row] else { continue }
            let line = LineMatchLine(row: row, slot: slot)
            if question.isCorrect(row: row, slot: slot) { correct.append(line) } else { wrong.append(line) }
        }
        lines.removeAll()
        for line in correct { locked[line.row] = line.slot }
        rejectedRows = wrong.map(\.row)
        rejectedSlots = wrong.map(\.slot)
        rejectFlashUntil = nil
        lastSubmitRepeatedWrong = wrong.contains { judgedWrongLines.contains($0) }
        judgedWrongLines.formUnion(wrong)
        if wrong.isEmpty {
            solved = true
        } else {
            wrongSubmits += 1
        }
        return .judged(LineMatchJudgement(correct: correct, wrong: wrong))
    }

    /// The Think Pause after a wrong 完成 ended: the orange rings flash for 1.5 s more.
    public mutating func noteUnlocked(now: Double) {
        guard !rejectedRows.isEmpty || !rejectedSlots.isEmpty else { return }
        rejectFlashUntil = now + Self.rejectFlashSeconds
    }

    /// Orange rings show through the Think Pause and for 1.5 s after it.
    public func showsRejectRings(now: Double, paused: Bool) -> Bool {
        guard !rejectedRows.isEmpty || !rejectedSlots.isEmpty else { return false }
        if paused { return true }
        guard let until = rejectFlashUntil else { return false }
        return now < until
    }

    private mutating func clearRejected() {
        rejectedRows = []
        rejectedSlots = []
        rejectFlashUntil = nil
    }

    // MARK: Stats (design §1.5 / §1.6; never a penalty)

    /// Tags + fields for the `answer_attempt` of one judged 完成.
    public func submitRecord(_ judgement: LineMatchJudgement) -> (tags: [String], fields: [String: PerfValue]) {
        var tags: [String] = []
        for line in judgement.wrong {
            for tag in LineMatchGenerator.tags(question: question, row: line.row, slot: line.slot)
            where !tags.contains(tag) {
                tags.append(tag)
            }
        }
        func names(_ lines: [LineMatchLine]) -> [String] {
            lines.map { line in
                let left = question.pairs.indices.contains(line.row) ? question.pairs[line.row].key : "?"
                let right = question.rightPair(atSlot: line.slot)?.key ?? "?"
                return "\(left)>\(right)"
            }
        }
        let fields: [String: PerfValue] = [
            "submit": .int(submits),
            "wrong_lines": .strings(names(judgement.wrong)),
            "right_lines": .strings(names(judgement.correct)),
            "locked": .int(locked.count),
            "eraser_uses": .int(eraserUses),
            "pre_submit_changes": .int(preSubmitChanges),
            "repeat_wrong": .bool(lastSubmitRepeatedWrong),
            "tolerance": .string(tolerance.rawValue)
        ]
        return (tags, fields)
    }

    /// Extra `round_result` fields for this question.
    public var resultFields: [String: PerfValue] {
        [
            "eraser_uses": .int(eraserUses),
            "eraser_locked": .bool(eraserEverHidden),
            "submit_attempts": .int(submits),
            "pre_submit_changes": .int(preSubmitChanges),
            "incomplete_strokes": .int(incompleteStrokes),
            "wrong_direction": .int(wrongDirections),
            "joins": .int(joins),
            "tolerance": .string(tolerance.rawValue)
        ]
    }
}

// MARK: - Child copy (HK Traditional + English; mockups 05a–05i)

public enum LineMatchCopy {
    public static let eraserTraditionalChinese = "擦晒"
    public static let eraserEnglish = "Clear"
    public static let doneTraditionalChinese = "完成"
    public static let doneEnglish = "Done"
    public static let gameTraditionalChinese = "連一連"
    public static let gameEnglish = "Line Match"
    public static let pullTraditionalChinese = "由綠點拉去紅點"
    public static let pullEnglish = "Pull from green to red"
    public static let allJoinedTraditionalChinese = "連好晒！撳完成"
    public static let allJoinedEnglish = "All joined: tap Done"
    public static let checkTraditionalChinese = "連好晒！撳「完成」睇吓啱唔啱"
    public static let checkEnglish = "All joined! Tap Done to check."
    /// Pen down on a red dot (`wrong_direction`, never a miss).
    public static let startGreenTraditionalChinese = "由綠點開始啊"
    public static let startGreenEnglish = "Start from a green dot"
    /// 完成 before every dot has a line (no penalty).
    public static let notReadyTraditionalChinese = "仲有未連嘅"
    public static let notReadyEnglish = "Some are not joined yet"
    /// 4th erase in a question (design §1.6).
    public static let tryDoneTraditionalChinese = "試吓撳完成啦！"
    public static let tryDoneEnglish = "Try tapping Done!"

    public static func moreToJoinTraditionalChinese(_ n: Int) -> String { "仲有 \(n) 條未連" }
    public static func moreToJoinEnglish(_ n: Int) -> String { "\(n) more to join" }

    public static var allTraditionalLines: [String] {
        [eraserTraditionalChinese, doneTraditionalChinese, gameTraditionalChinese, pullTraditionalChinese,
         allJoinedTraditionalChinese, checkTraditionalChinese, startGreenTraditionalChinese,
         notReadyTraditionalChinese, tryDoneTraditionalChinese, moreToJoinTraditionalChinese(2)]
    }

    public static var allEnglishLines: [String] {
        [eraserEnglish, doneEnglish, gameEnglish, pullEnglish, allJoinedEnglish, checkEnglish, startGreenEnglish,
         notReadyEnglish, tryDoneEnglish, moreToJoinEnglish(2)]
    }
}
