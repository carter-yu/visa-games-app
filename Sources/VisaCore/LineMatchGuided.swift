import Foundation

// 連一連 guided roads (v0.24.0 / v0.24.1, design "Guided level（引導連線）", ADR 0013; mockups 07a–07c).
// v0.24.1: own ActivityKinds — lineMatchGuidedStraight (L1 roads) and lineMatchGuidedBridge (L2).
// Each word joins its picture with a pre-drawn road. The child drives a small truck along each
// road, top → bottom. Nothing can be wrong, so there is no 完成, no 擦晒, no miss and no Think
// Pause: guided rounds are practice exposure, never mastery evidence.

// MARK: - Mode

/// Free matching (v0.23.0) or guided roads. Written to `game_dealt.match_mode`: the record
/// envelope already owns `mode` (lock / parent / play).
public enum LineMatchMode: String, CaseIterable, Sendable, Codable, Hashable {
    case free
    case guided

    public static let fieldKey = "match_mode"

    /// Guided roads are only dealt at ★ / ★★. ★★★ is always free match.
    public static func isGuidedLevel(_ level: ActivityLevel) -> Bool { level != .l3 }

    /// "G1" / "G2" in guided item ids ("L1" / "L2" stay free match).
    public static func guidedCode(_ level: ActivityLevel) -> String { "G\(level.rawValue)" }
}

/// What a guided question adds to the pairs: one road colour per left row and, at ★★, which
/// of the two crossing roads is drawn over the other (the bridge; it means nothing for play).
public struct LineMatchGuidedPlan: Sendable, Equatable, Codable, Hashable {
    /// Index into `LineMatchRoadPalette.roads`, per left row. All different.
    public var colorIndices: [Int]
    /// ★★: the left row whose road goes over the bridge. Nil at ★ (no crossing).
    public var bridgeOverRow: Int?

    public init(colorIndices: [Int], bridgeOverRow: Int?) {
        self.colorIndices = colorIndices
        self.bridgeOverRow = bridgeOverRow
    }

    /// ★: every word on its picture's row (identity order, no bridge). ★★: exactly one pair of
    /// roads crosses and the bridge is one of those two roads. Colours are distinct palette entries.
    public func isWellFormed(rightOrder: [Int], level: ActivityLevel) -> Bool {
        let n = rightOrder.count
        guard colorIndices.count == n, Set(colorIndices).count == n,
              colorIndices.allSatisfy({ LineMatchRoadPalette.roads.indices.contains($0) }) else { return false }
        switch LineMatchGuidedLayout.style(for: level) {
        case .straight:
            return rightOrder == Array(0..<n) && bridgeOverRow == nil
        case .staggered:
            let inverted = LineMatchGuidedGeometry.invertedRows(rightOrder: rightOrder)
            guard inverted.count == 1, let pair = inverted.first, let over = bridgeOverRow else { return false }
            return over == pair.upper || over == pair.lower
        }
    }
}

// MARK: - Road colours

public struct LineMatchRoadColor: Sendable, Equatable {
    public let name: String
    /// Driven part of the road.
    public let full: UInt32
    /// Not driven yet.
    public let pale: UInt32
}

/// Design: teal, pink, yellow, purple, blue. Never green or red — those belong to the dots and
/// the tick. Colour is never the only cue: the road shape itself joins each pair.
public enum LineMatchRoadPalette {
    public static let roads: [LineMatchRoadColor] = [
        LineMatchRoadColor(name: "teal", full: 0x2E9FA6, pale: 0xCBE9EA),
        LineMatchRoadColor(name: "pink", full: 0xF49AB0, pale: 0xFBDCE4),
        LineMatchRoadColor(name: "yellow", full: 0xFFC93C, pale: 0xFFEDB8),
        LineMatchRoadColor(name: "purple", full: 0xA98BE0, pale: 0xE6DCF7),
        LineMatchRoadColor(name: "blue", full: 0x4C8FE0, pale: 0xD3E4F8)
    ]
    /// Green dot / tick and red dot (mockup `dot-go`, `tick-dot`, `dot-end`).
    public static let goGreen: UInt32 = 0x5DBB63
    public static let endRed: UInt32 = 0xEE5A4C

    public static func color(_ index: Int) -> LineMatchRoadColor {
        roads[((index % roads.count) + roads.count) % roads.count]
    }
}

// MARK: - Road geometry

/// One road, left word card → right picture card, in stage units (1280 × 720).
/// A cubic with horizontal tangents at both ends (mockup `gen_guided.py` `Road`), sampled
/// into a polyline. The truck drives from the green dot to the red dot along the centre line.
public struct LineMatchRoad: Sendable, Equatable {
    public static let samples = 96

    public let row: Int
    public let slot: Int
    public let width: Double
    public let colorIndex: Int
    /// Bezier control points (start under the word card, end under the picture card).
    public let controls: [LineMatchPoint]
    /// Centre line, `samples + 1` points, x strictly increasing.
    public let points: [LineMatchPoint]
    /// Arc length at each point.
    public let cumulative: [Double]
    /// Arc length of the green dot (the truck starts here).
    public let goDistance: Double
    /// Arc length of the red dot (the road is finished here).
    public let endDistance: Double

    public init(row: Int, slot: Int, from start: LineMatchPoint, to end: LineMatchPoint, goX: Double, endX: Double,
                width: Double, colorIndex: Int) {
        self.row = row
        self.slot = slot
        self.width = width
        self.colorIndex = colorIndex
        let k = 0.42 * (end.x - start.x)
        let controls = [start, LineMatchPoint(x: start.x + k, y: start.y), LineMatchPoint(x: end.x - k, y: end.y), end]
        self.controls = controls
        var points: [LineMatchPoint] = []
        var cumulative: [Double] = []
        var total = 0.0
        for index in 0...Self.samples {
            let point = Self.bezier(controls, t: Double(index) / Double(Self.samples))
            if let last = points.last { total += last.distance(to: point) }
            points.append(point)
            cumulative.append(total)
        }
        self.points = points
        self.cumulative = cumulative
        self.goDistance = Self.distance(atX: goX, points: points, cumulative: cumulative)
        self.endDistance = Self.distance(atX: endX, points: points, cumulative: cumulative)
    }

    static func bezier(_ p: [LineMatchPoint], t: Double) -> LineMatchPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return LineMatchPoint(x: a * p[0].x + b * p[1].x + c * p[2].x + d * p[3].x,
                              y: a * p[0].y + b * p[1].y + c * p[2].y + d * p[3].y)
    }

    /// Arc length where the centre line reaches `x` (the road is x-monotone).
    static func distance(atX x: Double, points: [LineMatchPoint], cumulative: [Double]) -> Double {
        guard let first = points.first, x > first.x else { return 0 }
        for index in 1..<points.count where points[index].x >= x {
            let a = points[index - 1], b = points[index]
            let f = b.x > a.x ? (x - a.x) / (b.x - a.x) : 0
            return cumulative[index - 1] + f * (cumulative[index] - cumulative[index - 1])
        }
        return cumulative.last ?? 0
    }

    public var length: Double { cumulative.last ?? 0 }
    public var start: LineMatchPoint { controls[0] }
    public var end: LineMatchPoint { controls[3] }
    /// Straight across (★). ★★ roads never are.
    public var isHorizontal: Bool { abs(start.y - end.y) < 0.5 }

    /// Index of the segment holding arc length `distance`.
    private func segment(at distance: Double) -> Int {
        let clamped = min(max(distance, 0), length)
        var low = 0
        var high = cumulative.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if cumulative[mid] <= clamped { low = mid } else { high = mid }
        }
        return low
    }

    public func point(at distance: Double) -> LineMatchPoint {
        guard points.count > 1 else { return points.first ?? LineMatchPoint(x: 0, y: 0) }
        let clamped = min(max(distance, 0), length)
        let index = segment(at: clamped)
        let a = points[index], b = points[index + 1]
        let span = cumulative[index + 1] - cumulative[index]
        let f = span > 0 ? (clamped - cumulative[index]) / span : 0
        return LineMatchPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    /// Heading in radians (0 = pointing right; positive = down the screen).
    public func angle(at distance: Double) -> Double {
        guard points.count > 1 else { return 0 }
        let index = segment(at: distance)
        let a = points[index], b = points[index + 1]
        return atan2(b.y - a.y, b.x - a.x)
    }

    /// Nearest centre-line point to `p`: its arc length and how far `p` is from it.
    public func project(_ p: LineMatchPoint) -> (distance: Double, offset: Double) {
        var best = (distance: 0.0, offset: Double.greatestFiniteMagnitude)
        for index in 0..<(points.count - 1) {
            let a = points[index], b = points[index + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            var f = 0.0
            if lengthSquared > 0 { f = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1) }
            let q = LineMatchPoint(x: a.x + dx * f, y: a.y + dy * f)
            let offset = q.distance(to: p)
            if offset < best.offset {
                best = (cumulative[index] + f * (cumulative[index + 1] - cumulative[index]), offset)
            }
        }
        return best
    }

    /// Smallest gap between the two centre lines (x-aligned samples; roads share their x span).
    public func minimumSeparation(to other: LineMatchRoad) -> Double {
        var best = Double.greatestFiniteMagnitude
        for point in points {
            best = min(best, other.project(point).offset)
        }
        return best
    }
}

/// Where two roads cross: the point and the arc length on each road.
public struct LineMatchRoadCrossing: Sendable, Equatable {
    public var point: LineMatchPoint
    public var distanceOnFirst: Double
    public var distanceOnSecond: Double
}

public enum LineMatchGuidedGeometry {
    /// Left-row pairs `(upper, lower)` whose roads swap order on the way across: the upper word's
    /// picture sits lower than the lower word's picture. With the staggered picture column, each
    /// such pair is exactly one crossing, and nothing else crosses.
    public static func invertedRows(rightOrder: [Int]) -> [(upper: Int, lower: Int)] {
        var slotOfRow: [Int: Int] = [:]
        for (slot, row) in rightOrder.enumerated() { slotOfRow[row] = slot }
        var result: [(upper: Int, lower: Int)] = []
        let rows = rightOrder.sorted()
        for (i, upper) in rows.enumerated() {
            for lower in rows[(i + 1)...] where (slotOfRow[upper] ?? 0) > (slotOfRow[lower] ?? 0) {
                result.append((upper, lower))
            }
        }
        return result
    }

    /// ★★ right-column orders with exactly one crossing: the identity with one adjacent swap
    /// (`[1, 0, 2]`, `[0, 2, 1]` for three pairs). In a fixed order so seeds stay stable.
    public static func singleCrossingOrders(count n: Int) -> [[Int]] {
        guard n >= 2 else { return [Array(0..<max(n, 0))] }
        return (0..<(n - 1)).map { k in
            var order = Array(0..<n)
            order.swapAt(k, k + 1)
            return order
        }
    }

    /// Every permutation of `0..<n` (tests enumerate all layouts with it).
    public static func permutations(count n: Int) -> [[Int]] {
        guard n > 0 else { return [[]] }
        var result: [[Int]] = []
        for rest in permutations(count: n - 1) {
            for index in 0...rest.count {
                var next = rest
                next.insert(n - 1, at: index)
                result.append(next)
            }
        }
        return result
    }

    /// Where two road centre lines cross (polyline intersection). Both roads are x-monotone,
    /// so only segments overlapping in x are tested. Touches closer than 1u are merged.
    public static func crossings(_ a: LineMatchRoad, _ b: LineMatchRoad) -> [LineMatchRoadCrossing] {
        var found: [LineMatchRoadCrossing] = []
        var j = 0
        for i in 0..<(a.points.count - 1) {
            let p1 = a.points[i], p2 = a.points[i + 1]
            let minX = min(p1.x, p2.x), maxX = max(p1.x, p2.x)
            while j < b.points.count - 2, max(b.points[j].x, b.points[j + 1].x) < minX { j += 1 }
            var k = j
            while k < b.points.count - 1, min(b.points[k].x, b.points[k + 1].x) <= maxX {
                let q1 = b.points[k], q2 = b.points[k + 1]
                if let hit = intersect(p1, p2, q1, q2) {
                    let t = hit.0, u = hit.1
                    let point = LineMatchPoint(x: p1.x + (p2.x - p1.x) * t, y: p1.y + (p2.y - p1.y) * t)
                    if !found.contains(where: { $0.point.distance(to: point) < 1 }) {
                        found.append(LineMatchRoadCrossing(
                            point: point,
                            distanceOnFirst: a.cumulative[i] + t * (a.cumulative[i + 1] - a.cumulative[i]),
                            distanceOnSecond: b.cumulative[k] + u * (b.cumulative[k + 1] - b.cumulative[k])))
                    }
                }
                k += 1
            }
        }
        return found
    }

    /// Segment intersection parameters, or nil (parallel segments never count).
    static func intersect(_ p1: LineMatchPoint, _ p2: LineMatchPoint, _ q1: LineMatchPoint,
                          _ q2: LineMatchPoint) -> (Double, Double)? {
        let rx = p2.x - p1.x, ry = p2.y - p1.y
        let sx = q2.x - q1.x, sy = q2.y - q1.y
        let denominator = rx * sy - ry * sx
        guard abs(denominator) > 1e-12 else { return nil }
        let qpx = q1.x - p1.x, qpy = q1.y - p1.y
        let t = (qpx * sy - qpy * sx) / denominator
        let u = (qpx * ry - qpy * rx) / denominator
        guard t >= 0, t <= 1, u >= 0, u <= 1 else { return nil }
        return (t, u)
    }

    /// Every crossing between the roads of one board, as (upper row, lower row, crossing).
    public static func allCrossings(_ roads: [LineMatchRoad]) -> [(upper: Int, lower: Int, crossing: LineMatchRoadCrossing)] {
        var result: [(upper: Int, lower: Int, crossing: LineMatchRoadCrossing)] = []
        for i in roads.indices {
            for j in roads.indices where j > i {
                for crossing in crossings(roads[i], roads[j]) {
                    result.append((roads[i].row, roads[j].row, crossing))
                }
            }
        }
        return result
    }
}

// MARK: - Layout (mockups 07a / 07b / 07c)

/// Guided board layout in stage units. Word / number cards on the LEFT, pictures / counted
/// objects on the RIGHT. ★ "straight": 240 × 140 cards on two shared rows, 100u roads.
/// ★★ "staggered": 220 × 120 cards, the picture column half a row lower, 64u S-roads.
/// No buttons; nothing in the bottom-right parent zone (x ≥ 1080, y ≥ 580).
public struct LineMatchGuidedLayout: Sendable, Equatable {
    public enum Style: String, Sendable { case straight, staggered }

    public let style: Style
    public let leftCards: [LineMatchRect]
    public let rightCards: [LineMatchRect]
    /// Green dot per left row (the truck starts here).
    public let goDots: [LineMatchPoint]
    /// Red dot per right slot (the road ends here; the tick replaces it).
    public let endDots: [LineMatchPoint]
    /// Road ends, under the cards (the road "leaves" one card and "enters" the other).
    public let roadStartX: Double
    public let roadEndX: Double
    public let roadWidth: Double
    /// White chevrons ahead of the truck (★ only).
    public let chevrons: Bool
    /// 「眼睛、eye」 bubble per right slot, the point its tail touches, and whether the text is
    /// stacked (two lines, beside the card) or on one line.
    public let bubbles: [LineMatchRect]
    public let bubbleTails: [LineMatchPoint]
    public let bubbleStacked: [Bool]
    /// Progress dots + status line.
    public let status: LineMatchRect
    public let wordChineseSize: Double
    public let wordEnglishSize: Double
    public let pictureSide: Double
    /// Mini truck (210 × 126 art) drawn at this width.
    public let truckWidth: Double

    /// Bottom-right parent long-press zone: nothing is drawn here (design "Layout rules").
    public static let parentZone = LineMatchRect(x: 1080, y: 580, width: 200, height: 140)
    public static let dotRadius: Double = 22
    public static let tickRadius: Double = 30

    public static func style(for level: ActivityLevel) -> Style {
        level == .l1 ? .straight : .staggered
    }

    public static func make(level: ActivityLevel, pairCount n: Int) -> LineMatchGuidedLayout {
        switch style(for: level) {
        case .straight: return straight(pairCount: n)
        case .staggered: return staggered(pairCount: n)
        }
    }

    static func straight(pairCount n: Int) -> LineMatchGuidedLayout {
        let rows = Array([205.0, 430.0].prefix(max(1, min(n, 2))))
        let left = rows.map { LineMatchRect(x: 44, y: $0 - 70, width: 240, height: 140) }
        let right = rows.map { LineMatchRect(x: 996, y: $0 - 70, width: 240, height: 140) }
        // Row 1's bubble sits between the rows, row 2's under its card (mockup 07a).
        let bubbleTops = [282.0, 512.0]
        return LineMatchGuidedLayout(
            style: .straight, leftCards: left, rightCards: right,
            goDots: rows.map { LineMatchPoint(x: 322, y: $0) },
            endDots: rows.map { LineMatchPoint(x: 958, y: $0) },
            roadStartX: 272, roadEndX: 1008, roadWidth: 100, chevrons: true,
            bubbles: rows.indices.map { LineMatchRect(x: 640, y: bubbleTops[$0], width: 360, height: 72) },
            bubbleTails: rows.map { LineMatchPoint(x: 958, y: $0 + tickRadius + 5) },
            bubbleStacked: rows.map { _ in false },
            status: LineMatchRect(x: 440, y: 588, width: 400, height: 110),
            wordChineseSize: 66, wordEnglishSize: 28, pictureSide: 120, truckWidth: 130
        )
    }

    static func staggered(pairCount n: Int) -> LineMatchGuidedLayout {
        let count = max(1, min(n, 3))
        let leftRows = Array([190.0, 330.0, 470.0].prefix(count))
        let rightRows = Array([260.0, 400.0, 540.0].prefix(count))
        let left = leftRows.map { LineMatchRect(x: 44, y: $0 - 60, width: 220, height: 120) }
        let right = rightRows.map { LineMatchRect(x: 820, y: $0 - 60, width: 220, height: 120) }
        // Top picture: bubble above the card. Lower pictures: no room above, so beside the card
        // (stacked text), kept above y 580 so the parent zone stays empty.
        var bubbles: [LineMatchRect] = []
        var tails: [LineMatchPoint] = []
        var stacked: [Bool] = []
        for (slot, card) in right.enumerated() {
            if slot == 0 {
                bubbles.append(LineMatchRect(x: 740, y: 124, width: 360, height: 72))
                tails.append(LineMatchPoint(x: card.midX + 40, y: card.y + 2))
                stacked.append(false)
            } else {
                let top = min(card.midY - 48, parentZone.y - 4 - 96)
                bubbles.append(LineMatchRect(x: card.maxX + 16, y: top, width: 212, height: 96))
                tails.append(LineMatchPoint(x: card.maxX + 4, y: min(card.midY, top + 96 - 24)))
                stacked.append(true)
            }
        }
        return LineMatchGuidedLayout(
            style: .staggered, leftCards: left, rightCards: right,
            goDots: leftRows.map { LineMatchPoint(x: 286, y: $0) },
            endDots: rightRows.map { LineMatchPoint(x: 798, y: $0) },
            roadStartX: 252, roadEndX: 832, roadWidth: 64, chevrons: false,
            bubbles: bubbles, bubbleTails: tails, bubbleStacked: stacked,
            status: LineMatchRect(x: 360, y: 588, width: 400, height: 110),
            wordChineseSize: 54, wordEnglishSize: 24, pictureSide: 104, truckWidth: 106
        )
    }

    /// One road per left row, to the slot showing that row's picture.
    public func roads(for question: LineMatchQuestion) -> [LineMatchRoad] {
        question.pairs.indices.compactMap { row in
            guard let slot = question.correctSlot(forRow: row), goDots.indices.contains(row),
                  endDots.indices.contains(slot) else { return nil }
            let colors = question.guided?.colorIndices ?? []
            return LineMatchRoad(
                row: row, slot: slot,
                from: LineMatchPoint(x: roadStartX, y: goDots[row].y),
                to: LineMatchPoint(x: roadEndX, y: endDots[slot].y),
                goX: goDots[row].x, endX: endDots[slot].x, width: roadWidth,
                colorIndex: colors.indices.contains(row) ? colors[row] : row)
        }
    }

    /// Everything drawn on the board (for the keep-out tests).
    public var allRects: [LineMatchRect] { leftCards + rightCards + bubbles + [status] }
}

// MARK: - Board (pure reducer; the app owns the clock)

public enum LineMatchGuidedPenDown: Sendable, Equatable {
    /// Pen down within 90u of the truck: it now follows the pen along the road.
    case grabbed(row: Int)
    /// Pen down on a red dot or a picture: 「由綠點開始啊！」. Never a miss (`wrong_start`).
    case wrongStart
    /// Pen down somewhere else: the truck waits (the hint shows after 2 s).
    case notNearTruck
    /// Every road is done.
    case ignored
}

public enum LineMatchGuidedMove: Sendable, Equatable {
    /// The truck moved forward along the road.
    case drove(row: Int)
    /// Pen on the road at or behind the truck: nothing moves.
    case waiting(row: Int)
    /// Pen off the road, too far ahead of the truck, or never took hold of it. The truck waits.
    case away(row: Int)
    /// The truck reached the red dot: the road is done.
    case completed(row: Int)
    case ignored
}

/// Guided 連一連 board. Pure value: the view runs it locally per pen event and hands the result
/// to the model on pen-up / road done, so the model is never published per move.
public struct LineMatchGuidedBoard: Sendable, Equatable {
    /// Pen must come down this close to the truck to take hold of it (design: 90u).
    public static let grabRadius: Double = 90
    /// At most this far forward per move event (no "teleport" to the end).
    public static let maxStep: Double = 60
    /// Pen further ahead along the road than this: the truck waits instead of chasing.
    public static let leadLimit: Double = 150
    /// Road done at 97% (or within the tolerance's arrival slack of the red dot).
    public static let arrivalFraction: Double = 0.97
    /// Off the road this long → the tiny hint (glow ring, dotted trail, status line).
    public static let hintAfterSeconds: Double = 2
    /// No pen at all this long → Stampy reads the instruction again.
    public static let idleRepromptSeconds: Double = 20

    public let question: LineMatchQuestion
    public let layout: LineMatchGuidedLayout
    /// One road per left row (index = row).
    public let roads: [LineMatchRoad]
    public let tolerance: LineMatchTolerance

    /// Truck position (arc length) per row. Never goes down.
    public private(set) var progress: [Double]
    /// Rows driven to the end, in the order they were finished (always top → bottom).
    public private(set) var doneRows: [Int] = []
    public private(set) var dragging = false
    public private(set) var holding = false
    public private(set) var offRoad = false
    /// When the pen went away from the truck / road during this stroke (hint clock).
    public private(set) var awaySince: Double?
    public private(set) var offPathCount = 0
    public private(set) var lifts = 0
    public private(set) var wrongStarts = 0
    public private(set) var strokes = 0
    public private(set) var deviationSum = 0.0
    public private(set) var deviationSamples = 0
    public private(set) var startedAt: Double?
    public private(set) var finishedAt: Double?

    public init(question: LineMatchQuestion, tolerance: LineMatchTolerance = .standard) {
        self.question = question
        self.tolerance = tolerance
        let layout = LineMatchGuidedLayout.make(level: question.level, pairCount: question.pairCount)
        self.layout = layout
        let roads = layout.roads(for: question)
        self.roads = roads
        self.progress = roads.map(\.goDistance)
    }

    public var rows: Range<Int> { 0..<roads.count }
    /// The road being driven: the top-most one not done yet.
    public var currentRow: Int? { rows.first { !doneRows.contains($0) } }
    public var isComplete: Bool { !roads.isEmpty && doneRows.count == roads.count }
    public var remainingRoads: Int { roads.count - doneRows.count }

    public func isDone(row: Int) -> Bool { doneRows.contains(row) }

    /// Right slot whose road is done (tick, glow, bubble).
    public func isDone(slot: Int) -> Bool {
        guard question.rightOrder.indices.contains(slot) else { return false }
        return doneRows.contains(question.rightOrder[slot])
    }

    /// Where the truck is: on the current road, or parked at the last red dot when all are done.
    public var truckRow: Int? { currentRow ?? doneRows.last }

    public var truckPoint: LineMatchPoint? {
        guard let row = truckRow, roads.indices.contains(row) else { return nil }
        return roads[row].point(at: progress[row])
    }

    /// Half of the judged corridor: drawn width × 1.0 / 1.5 / 2.2 (窄 / 標準 / 闊), halved.
    public func corridorHalfWidth(row: Int) -> Double {
        guard roads.indices.contains(row) else { return 0 }
        return roads[row].width * tolerance.roadWidthFactor / 2
    }

    /// Arc length at which `row` counts as driven.
    public func arrivalDistance(row: Int) -> Double {
        guard roads.indices.contains(row) else { return 0 }
        let road = roads[row]
        let span = road.endDistance - road.goDistance
        return road.endDistance - max(span * (1 - Self.arrivalFraction), tolerance.arrivalSlack)
    }

    /// 0…1 driven share of `row` (green dot → red dot).
    public func fraction(row: Int) -> Double {
        guard roads.indices.contains(row) else { return 0 }
        let road = roads[row]
        let span = road.endDistance - road.goDistance
        guard span > 0 else { return 1 }
        return min(max((progress[row] - road.goDistance) / span, 0), 1)
    }

    /// The tiny hint: pen away from the truck / road for over 2 s during a stroke.
    public func showsHint(now: Double) -> Bool {
        guard dragging, let since = awaySince else { return false }
        return now - since >= Self.hintAfterSeconds
    }

    // MARK: Pen events

    public mutating func penDown(at point: LineMatchPoint, now: Double) -> LineMatchGuidedPenDown {
        dragging = false
        holding = false
        offRoad = false
        awaySince = nil
        guard let row = currentRow, let truck = truckPoint else { return .ignored }
        strokes += 1
        if startedAt == nil { startedAt = now }
        if point.distance(to: truck) <= Self.grabRadius {
            dragging = true
            holding = true
            return .grabbed(row: row)
        }
        let nearEnd = layout.endDots.contains { point.distance(to: $0) <= Self.grabRadius }
            || layout.rightCards.contains { $0.contains(point) }
        if nearEnd {
            wrongStarts += 1
            return .wrongStart
        }
        dragging = true
        awaySince = now
        return .notNearTruck
    }

    public mutating func penMove(to point: LineMatchPoint, now: Double) -> LineMatchGuidedMove {
        guard dragging, let row = currentRow else { return .ignored }
        let road = roads[row]
        if !holding {
            // Sliding onto the truck takes hold of it, as a fresh pen-down near it would.
            guard let truck = truckPoint, point.distance(to: truck) <= Self.grabRadius else {
                if awaySince == nil { awaySince = now }
                return .away(row: row)
            }
            holding = true
        }
        let projection = road.project(point)
        if projection.offset > corridorHalfWidth(row: row) {
            if !offRoad {
                offRoad = true
                offPathCount += 1
            }
            if awaySince == nil { awaySince = now }
            return .away(row: row)
        }
        offRoad = false
        deviationSum += projection.offset
        deviationSamples += 1
        let current = progress[row]
        if projection.distance - current > Self.leadLimit {
            if awaySince == nil { awaySince = now }
            return .away(row: row)
        }
        awaySince = nil
        guard projection.distance > current else { return .waiting(row: row) }
        let next = min(projection.distance, current + Self.maxStep, road.endDistance)
        progress[row] = next
        guard next >= arrivalDistance(row: row) else { return .drove(row: row) }
        progress[row] = road.endDistance
        doneRows.append(row)
        // The next road needs a fresh pen-down at its green dot.
        dragging = false
        holding = false
        if isComplete { finishedAt = now }
        return .completed(row: row)
    }

    /// Pen up. The truck stays where it is; a lift mid-road is counted (never a miss).
    public mutating func penUp() {
        if dragging, holding, let row = currentRow, progress[row] > roads[row].goDistance {
            lifts += 1
        }
        dragging = false
        holding = false
        offRoad = false
        awaySince = nil
    }

    /// Gesture lost (window change, system cancel): like a lift, but not counted.
    public mutating func cancelStroke() {
        dragging = false
        holding = false
        offRoad = false
        awaySince = nil
    }

    /// True when `self` can only have come from `older` by pen events: same question, no
    /// truck went backwards, finished roads stay finished, counters never drop. The model
    /// refuses any other board (e.g. a stale copy from a view that missed an update).
    public func isMonotonicSuccessor(of older: LineMatchGuidedBoard) -> Bool {
        guard question == older.question, tolerance == older.tolerance,
              progress.count == older.progress.count else { return false }
        guard zip(progress, older.progress).allSatisfy({ $0 >= $1 }) else { return false }
        guard doneRows.count >= older.doneRows.count,
              Array(doneRows.prefix(older.doneRows.count)) == older.doneRows else { return false }
        return offPathCount >= older.offPathCount && lifts >= older.lifts && wrongStarts >= older.wrongStarts
            && strokes >= older.strokes
    }

    // MARK: Stats (practice exposure; never mastery evidence)

    /// Pair keys of the roads driven (each is one exposure: heard and driven once).
    public var exposures: [String] {
        doneRows.compactMap { question.pairs.indices.contains($0) ? question.pairs[$0].key : nil }
    }

    /// Mean distance of the pen from the road centre while on the road (pre-writing chart).
    public var meanDeviation: Double? {
        deviationSamples > 0 ? deviationSum / Double(deviationSamples) : nil
    }

    /// Extra `round_result` fields.
    public var resultFields: [String: PerfValue] {
        var fields: [String: PerfValue] = [
            LineMatchMode.fieldKey: .string(LineMatchMode.guided.rawValue),
            "roads": .int(doneRows.count),
            "roads_total": .int(roads.count),
            "off_path_count": .int(offPathCount),
            "lifts": .int(lifts),
            "wrong_start": .int(wrongStarts),
            "strokes": .int(strokes),
            "exposures": .strings(exposures),
            "tolerance": .string(tolerance.rawValue),
            "mean_dev_u": .seconds(meanDeviation)
        ]
        if let startedAt, let finishedAt {
            fields["duration_ms"] = .int(Int(((finishedAt - startedAt) * 1000).rounded()))
        }
        return fields
    }
}

// MARK: - Child copy (HK Traditional + English; design "Copy")

public enum LineMatchGuidedCopy {
    public static let promptTraditionalChinese = "沿住條路揸，將字送去啱嘅圖！"
    public static let promptEnglish = "Drive along the road to take each word to its picture!"
    /// Never shown (guided rounds have no misses, so no auto-hint); kept in the usual format.
    public static let hint = "提示：由綠點開始，跟住條路揸。 / Hint: start at the green dot and follow the road."
    public static let badgeTraditionalChinese = "引導"
    public static let badgeEnglish = "Guided"
    public static let offRoadTraditionalChinese = "架車等緊你，返嚟條路度啦！"
    public static let offRoadEnglish = "The truck is waiting. Come back to the road!"
    public static let wrongStartTraditionalChinese = "由綠點開始啊！"
    public static let wrongStartEnglish = "Start from the green dot!"
    public static let doneTraditionalChinese = "全部送到！好叻呀！"
    public static let doneEnglish = "All delivered! Well done!"
    /// Kept for copy audits; the parent toggle was removed in v0.24.1 (three cards).
    public static let parentToggleTraditionalChinese = "引導連線（已拆成三個遊戲卡）"
    public static let parentToggleEnglish = "Guided match (split into three game cards in v0.24.1)"
    public static let parentPracticeTraditionalChinese = "引導練習"

    /// 「數吓有幾多隻，沿住條路揸！」 for numbers (measure word follows the object).
    public static func prompt(object: LineMatchCountObject?) -> (zh: String, en: String) {
        guard let object else { return (promptTraditionalChinese, promptEnglish) }
        return ("數吓有幾多\(object.measureWord)，沿住條路揸！",
                "Count the \(object.pluralEnglish), then drive along the road!")
    }

    public static func remainingTraditionalChinese(_ n: Int) -> String { "仲有 \(n) 條路" }
    public static func remainingEnglish(_ n: Int) -> String { n == 1 ? "1 more road to go" : "\(n) more roads to go" }

    /// Spoken after a road: the Cantonese word, then the English word (「眼睛、eye」, 「四、four」).
    public static func cue(_ pair: LineMatchPair) -> SpokenPrompt {
        SpokenPrompt(key: "lineMatch.cue.\(pair.key)", traditionalChinese: pair.labelTraditionalChinese,
                     english: pair.labelEnglish)
    }

    /// Bubble text 「眼睛、eye」.
    public static func bubble(_ pair: LineMatchPair) -> String {
        "\(pair.labelTraditionalChinese)、\(pair.labelEnglish)"
    }

    public static let offRoadPrompt = SpokenPrompt(key: "lineMatch.guided.offroad",
                                                   traditionalChinese: offRoadTraditionalChinese,
                                                   english: offRoadEnglish)
    public static let wrongStartPrompt = SpokenPrompt(key: "lineMatch.guided.wrongStart",
                                                      traditionalChinese: wrongStartTraditionalChinese,
                                                      english: wrongStartEnglish)

    public static var allTraditionalLines: [String] {
        [promptTraditionalChinese, prompt(object: .chick).zh, prompt(object: .minifire).zh, prompt(object: .apple).zh,
         hint.components(separatedBy: " / ").first ?? "", badgeTraditionalChinese, offRoadTraditionalChinese,
         wrongStartTraditionalChinese, doneTraditionalChinese, parentToggleTraditionalChinese,
         parentPracticeTraditionalChinese, remainingTraditionalChinese(2)]
    }

    public static var allEnglishLines: [String] {
        [promptEnglish, prompt(object: .chick).en, prompt(object: .minifire).en, prompt(object: .apple).en,
         hint.components(separatedBy: " / ").last ?? "", badgeEnglish, offRoadEnglish, wrongStartEnglish,
         doneEnglish, parentToggleEnglish, remainingEnglish(1), remainingEnglish(2)]
    }
}
