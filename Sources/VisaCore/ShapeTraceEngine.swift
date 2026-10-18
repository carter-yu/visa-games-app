import Foundation

// 畫線畫形 / Lines & Shapes engine (v0.25.0, design shape-trace §2.4, §7.2–7.3, ADR 0014).
// Generalises the guided 連一連 truck (`LineMatchGuidedBoard`) from one x-monotone road per row
// to strokes made of lines, corners and arcs. The guided 連一連 board is left untouched: its
// behaviour and tests stay exactly as they were (design §7.2 "refactor safety" is met by not
// refactoring it in phase 1).

// MARK: - Path

/// One piece of a stroke, in stage units (1280 × 720, y grows down).
public enum TraceSegment: Sendable, Equatable {
    /// Straight to a point.
    case line(to: LineMatchPoint)
    /// Arc around `center`. Angles in radians, screen convention (0 = right, +π/2 = down).
    /// A negative sweep turns anticlockwise on screen (12 o'clock → 9 o'clock → 6 → 3).
    case arc(center: LineMatchPoint, radius: Double, startAngle: Double, sweep: Double)
    /// Cubic Bézier to `to` (v0.28.0 numerals; design number-quantity §11.1). Joins with a cubic
    /// are never corners by themselves: numeral corners are named explicitly.
    case cubic(c1: LineMatchPoint, c2: LineMatchPoint, to: LineMatchPoint)
}

/// A stroke's centre line: segments sampled every ≤ 6u, with arc length, corner checkpoints and
/// a windowed nearest-point search (design §7.2). Closed strokes (circles) start and end at the
/// same point, so the board only ever searches a window around the vehicle.
public struct TracePath: Sendable, Equatable {
    public static let sampleSpacing: Double = 6

    public let points: [LineMatchPoint]
    public let cumulative: [Double]
    /// Arc lengths where the stroke turns a corner (the vehicle must stop here first).
    public let corners: [Double]
    /// Start = end (a circle).
    public let closed: Bool

    /// Corners the vehicle must reach before turning back on itself (numeral 3's middle, 9's top).
    /// While short of a cusp the windowed search stops at it; once there it never looks behind it
    /// (design number-quantity §11.1 "cusp window"). Always a subset of `corners`.
    public let cusps: [Double]

    public init(start: LineMatchPoint, segments: [TraceSegment], closed: Bool = false) {
        let built = Self.sample(start: start, segments: segments)
        var corners: [Double] = []
        for (index, segment) in segments.enumerated() {
            if index > 0, case .line = segment, case .line = segments[index - 1] {
                corners.append(built.joins[index - 1].distance)
            }
        }
        self.points = built.points
        self.cumulative = built.cumulative
        self.corners = corners
        self.cusps = []
        self.closed = closed
    }

    /// A stroke from SVG path data (one subpath, absolute or relative, M L H V C S Q T A Z), mapped
    /// into stage units by `scale` then `offset`. `corners` / `cusps` name segment joins in the
    /// source coordinates; a named point that is not a join is ignored (tests catch it).
    public init(svg data: String, scale: Double = 1, offset: LineMatchPoint = LineMatchPoint(x: 0, y: 0),
                corners: [LineMatchPoint] = [], cusps: [LineMatchPoint] = [], closed: Bool = false) {
        let commands = (try? SVGPathData.parse(data)) ?? []
        func map(_ x: Double, _ y: Double) -> LineMatchPoint {
            LineMatchPoint(x: offset.x + x * scale, y: offset.y + y * scale)
        }
        var start = offset
        var segments: [TraceSegment] = []
        var current = start
        for command in commands {
            switch command {
            case .move(let x, let y):
                if segments.isEmpty { start = map(x, y); current = start }
            case .line(let x, let y):
                current = map(x, y)
                segments.append(.line(to: current))
            case .quad(let cx, let cy, let x, let y):
                let c = map(cx, cy), end = map(x, y)
                let c1 = LineMatchPoint(x: current.x + 2 / 3 * (c.x - current.x), y: current.y + 2 / 3 * (c.y - current.y))
                let c2 = LineMatchPoint(x: end.x + 2 / 3 * (c.x - end.x), y: end.y + 2 / 3 * (c.y - end.y))
                segments.append(.cubic(c1: c1, c2: c2, to: end))
                current = end
            case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
                current = map(x, y)
                segments.append(.cubic(c1: map(c1x, c1y), c2: map(c2x, c2y), to: current))
            case .close:
                if current.distance(to: start) > 0.01 { segments.append(.line(to: start)) }
                current = start
            }
        }
        let built = Self.sample(start: start, segments: segments)
        func joins(_ named: [LineMatchPoint]) -> [Double] {
            named.compactMap { p in
                let target = map(p.x, p.y)
                return built.joins.dropLast().first { $0.point.distance(to: target) < 0.5 }?.distance
            }.sorted()
        }
        self.points = built.points
        self.cumulative = built.cumulative
        let cuspDistances = joins(cusps)
        self.corners = Array(Set(joins(corners) + cuspDistances)).sorted()
        self.cusps = cuspDistances
        self.closed = closed
    }

    /// Samples `segments` every ≤ 6u. `joins[i]` = arc length and point at the end of segment i.
    private static func sample(start: LineMatchPoint, segments: [TraceSegment])
        -> (points: [LineMatchPoint], cumulative: [Double], joins: [(distance: Double, point: LineMatchPoint)]) {
        var points = [start]
        var cumulative = [0.0]
        var joins: [(distance: Double, point: LineMatchPoint)] = []
        var total = 0.0
        var current = start
        func append(_ point: LineMatchPoint) {
            total += points[points.count - 1].distance(to: point)
            points.append(point)
            cumulative.append(total)
        }
        for segment in segments {
            switch segment {
            case .line(let end):
                let length = current.distance(to: end)
                let steps = max(1, Int((length / sampleSpacing).rounded(.up)))
                for step in 1...steps {
                    let f = Double(step) / Double(steps)
                    append(LineMatchPoint(x: current.x + (end.x - current.x) * f, y: current.y + (end.y - current.y) * f))
                }
                current = end
            case .arc(let center, let radius, let startAngle, let sweep):
                let length = abs(sweep) * radius
                let steps = max(2, Int((length / sampleSpacing).rounded(.up)))
                for step in 1...steps {
                    let angle = startAngle + sweep * Double(step) / Double(steps)
                    append(LineMatchPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
                }
                current = points[points.count - 1]
            case .cubic(let c1, let c2, let end):
                // |B'(t)| ≤ 3 × the longest control leg, so uniform t steps stay ≤ 6u apart.
                let leg = max(current.distance(to: c1), c1.distance(to: c2), c2.distance(to: end))
                let steps = max(2, Int((3 * leg / sampleSpacing).rounded(.up)))
                let p0 = current
                for step in 1...steps {
                    let t = Double(step) / Double(steps)
                    let u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    append(LineMatchPoint(x: a * p0.x + b * c1.x + c * c2.x + d * end.x,
                                          y: a * p0.y + b * c1.y + c * c2.y + d * end.y))
                }
                current = end
            }
            joins.append((total, current))
        }
        return (points, cumulative, joins)
    }

    private init(points: [LineMatchPoint], cumulative: [Double], corners: [Double], cusps: [Double], closed: Bool) {
        self.points = points
        self.cumulative = cumulative
        self.corners = corners
        self.cusps = cusps
        self.closed = closed
    }

    /// A straight stroke.
    public static func line(_ from: LineMatchPoint, _ to: LineMatchPoint) -> TracePath {
        TracePath(start: from, segments: [.line(to: to)])
    }

    /// A polyline with a corner at every inner point (𠃍, 「<」).
    public static func polyline(_ points: [LineMatchPoint]) -> TracePath {
        TracePath(start: points[0], segments: points.dropFirst().map { .line(to: $0) })
    }

    /// One full circle from 12 o'clock, anticlockwise on screen (like writing o; design D5).
    public static func circle(center: LineMatchPoint, radius: Double) -> TracePath {
        TracePath(start: LineMatchPoint(x: center.x, y: center.y - radius),
                  segments: [.arc(center: center, radius: radius, startAngle: -Double.pi / 2, sweep: -2 * Double.pi)],
                  closed: true)
    }

    public var length: Double { cumulative.last ?? 0 }
    public var start: LineMatchPoint { points.first ?? LineMatchPoint(x: 0, y: 0) }
    public var end: LineMatchPoint { points.last ?? LineMatchPoint(x: 0, y: 0) }

    /// The same stroke driven the other way (direction hint off; design §7.3).
    public var reversed: TracePath {
        let total = length
        return TracePath(points: points.reversed(), cumulative: cumulative.reversed().map { total - $0 },
                         corners: corners.reversed().map { total - $0 }, cusps: cusps.reversed().map { total - $0 },
                         closed: closed)
    }

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
        guard points.count > 1 else { return start }
        let clamped = min(max(distance, 0), length)
        let index = segment(at: clamped)
        let a = points[index], b = points[index + 1]
        let span = cumulative[index + 1] - cumulative[index]
        let f = span > 0 ? (clamped - cumulative[index]) / span : 0
        return LineMatchPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    /// Heading in radians (0 = right, +π/2 = down the screen).
    public func angle(at distance: Double) -> Double {
        guard points.count > 1 else { return 0 }
        var index = segment(at: distance)
        if index >= points.count - 1 { index = points.count - 2 }
        let a = points[index], b = points[index + 1]
        return atan2(b.y - a.y, b.x - a.x)
    }

    /// Unit direction of the piece leading into `distance` (just before it).
    public func incomingDirection(at distance: Double) -> (dx: Double, dy: Double) {
        let angle = angle(at: max(0, distance - 1))
        return (cos(angle), sin(angle))
    }

    /// Nearest centre-line point to `p` with its arc length inside `window` only (design §7.2:
    /// a closed circle must never project its start onto its end, and the two legs of 𠃍 must
    /// never swap near the corner).
    public func project(_ p: LineMatchPoint, window: ClosedRange<Double>) -> (distance: Double, offset: Double) {
        let lowEnd = max(0, window.lowerBound)
        let highEnd = min(length, window.upperBound)
        guard points.count > 1, highEnd >= lowEnd else { return (lowEnd, point(at: lowEnd).distance(to: p)) }
        var best = (distance: lowEnd, offset: Double.greatestFiniteMagnitude)
        for index in 0..<(points.count - 1) {
            let c0 = cumulative[index], c1 = cumulative[index + 1]
            guard c1 >= lowEnd, c0 <= highEnd, c1 > c0 else { continue }
            let a = points[index], b = points[index + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            var f = lengthSquared > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared : 0
            let fLow = max(0, (lowEnd - c0) / (c1 - c0))
            let fHigh = min(1, (highEnd - c0) / (c1 - c0))
            f = min(max(f, fLow), fHigh)
            let q = LineMatchPoint(x: a.x + dx * f, y: a.y + dy * f)
            let offset = q.distance(to: p)
            if offset < best.offset { best = (c0 + f * (c1 - c0), offset) }
        }
        return best
    }

    /// Whole-path projection (tests and keep-out checks).
    public func project(_ p: LineMatchPoint) -> (distance: Double, offset: Double) {
        project(p, window: 0...length)
    }

    /// Smallest gap between two centre lines.
    public func minimumSeparation(to other: TracePath) -> Double {
        points.reduce(Double.greatestFiniteMagnitude) { min($0, other.project($1).offset) }
    }

    /// Twice the signed area of the closed polyline. Negative = anticlockwise on screen (y down).
    public var signedArea: Double {
        guard points.count > 2 else { return 0 }
        var sum = 0.0
        for index in 0..<points.count {
            let a = points[index], b = points[(index + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum
    }

    /// Bounding box of the centre line.
    public var bounds: LineMatchRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0
        return LineMatchRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }
}

// MARK: - Board (pure reducer; the app owns the clock)

public enum ShapeTracePenDown: Sendable, Equatable {
    /// Pen down within 90u of the vehicle: it now follows the pen along the stroke.
    case grabbed(shape: Int, stroke: Int)
    /// Pen down on the red end of the stroke with the direction hint on: 「跟住箭嘴方向畫啊！」.
    case reverse
    /// Pen down on another stroke's marker: 「由綠色箭嘴開始啊！」. Never a miss.
    case wrongStart
    /// Pen down somewhere else: the vehicle waits (the hint shows after 2 s).
    case notNearVehicle
    /// Everything is drawn.
    case ignored
}

/// ★★★ 擦晒 (design §2.6): clears the current shape only; finished shapes never change.
public enum ShapeTraceErase: Sendable, Equatable {
    case cleared
    /// 4th press on this shape: cleared, and Stampy says 「唔使擦都得，慢慢畫就得㗎！」.
    case clearedNudge
    /// 6th press: cleared, and the button hides until this shape is drawn.
    case clearedAndHidden
    /// Within 3 s of the last press: nothing happens.
    case coolingDown
    /// No eraser here (★ / ★★, finished round, or hidden).
    case unavailable
}

public enum ShapeTraceMove: Sendable, Equatable {
    case drove
    /// Pen on the stroke at or behind the vehicle.
    case waiting
    /// Pen off the stroke, too far ahead, or never took hold of the vehicle.
    case away
    /// The vehicle just reached a corner and stopped (「停！轉彎！」).
    case cornerReached
    /// The pen ran on past the corner in the old direction (stop sign + turn arrow).
    case cornerOvershoot
    /// A stroke is done; more strokes in this shape.
    case strokeDone(shape: Int, stroke: Int)
    /// The last stroke of a shape is done.
    case shapeDone(shape: Int)
    /// The last stroke of the last shape is done.
    case allDone
    case ignored
}

/// Practice stats of one shape (design §4.5 `per_shape`).
public struct ShapeTraceShapeStats: Sendable, Equatable {
    public var deviationSum = 0.0
    public var deviationSamples = 0
    public var maxDeviation = 0.0
    public var lifts = 0
    public var offPath = 0
    public var cornerOvershoots = 0
    public var cornerCuts = 0
    public var endOvershoots = 0
    public var reverseDirections = 0
    public var wrongStarts = 0
    public var startedAt: Double?
    public var finishedAt: Double?
    /// ★★★: share of the child's ink outside the judged corridor (set when the shape is drawn).
    public var inkOutsideRatio: Double?
    public var erasers = 0
    public var eraserLocked = false

    public init() {}

    public var meanDeviation: Double? { deviationSamples > 0 ? deviationSum / Double(deviationSamples) : nil }
}

/// 畫線畫形 board: one shape after another, one stroke after another, a vehicle that only goes
/// forwards and waits at every corner. Nothing can be wrong: off the path, lifts, reverse
/// starts and corner overshoots are tags only. Pure value: the view runs it on a local copy per
/// pen event and hands it to the model on pen-up and at every milestone.
public struct ShapeTraceBoard: Sendable, Equatable {
    public static let grabRadius: Double = 90
    public static let maxStep: Double = 60
    public static let leadLimit: Double = 150
    public static let arrivalFraction: Double = 0.97
    public static let hintAfterSeconds: Double = 2
    public static let idleRepromptSeconds: Double = 20
    /// No progress on a stroke this long → a ghost vehicle shows the way once (design §2.5).
    public static let ghostDemoAfterSeconds: Double = 8
    /// Pen this far past a corner along the old direction = `corner_overshoot`.
    public static let cornerOvershootU: Double = 24
    /// Pen projected this far past a corner the vehicle has not reached = `corner_cut`.
    public static let cornerCutU: Double = 40
    /// The windowed search looks this far behind the vehicle.
    public static let windowBehind: Double = 40
    /// ★★★ ink: one point every 4u (design §7.3); a cap keeps one shape's ink bounded.
    public static let inkSpacing: Double = 4
    public static let inkPointCap = 4000
    /// ★★★ 擦晒: 3 s cooldown, nudge on the 4th press, hide on the 6th (design §2.6).
    public static let eraserCooldown: Double = 3
    public static let eraserNudgeAt = 4
    public static let eraserHideAt = 6

    public let question: ShapeTraceQuestion
    public let tolerance: LineMatchTolerance
    /// On: only the arrow direction is accepted. Off: starting at the red end reverses the stroke.
    public let directionHint: Bool

    public private(set) var shapeIndex = 0
    public private(set) var strokeIndex = 0
    /// Vehicle position (arc length) on the current stroke. Never goes down.
    public private(set) var progress = 0.0
    /// Strokes driven the other way (direction hint off), as "shape.stroke".
    public private(set) var reversedStrokes: [String] = []
    public private(set) var dragging = false
    public private(set) var holding = false
    public private(set) var offPath = false
    public private(set) var awaySince: Double?
    /// When the current stroke last moved (or became current). Ghost demo clock.
    public private(set) var lastProgressAt: Double?
    /// v0.30.0: the latest pen-down (tap-count guidance: a stall counts from here or the last progress).
    public private(set) var lastPenDownAt: Double?
    /// Corners of the current stroke already tagged as overshoot / cut / reached.
    public private(set) var cornersOvershot: [Double] = []
    public private(set) var cornersCut: [Double] = []
    public private(set) var cornersReached: [Double] = []
    public private(set) var offPathCount = 0
    public private(set) var lifts = 0
    public private(set) var wrongStarts = 0
    public private(set) var reverseDirections = 0
    public private(set) var cornerOvershoots = 0
    public private(set) var cornerCuts = 0
    public private(set) var endOvershoots = 0
    public private(set) var penDowns = 0
    public private(set) var shapeStats: [ShapeTraceShapeStats]
    public private(set) var startedAt: Double?
    public private(set) var finishedAt: Double?
    /// ★★★: the current shape's crayon ink (one polyline per pen-down; kept off the path too).
    public private(set) var ink: [[LineMatchPoint]] = []
    /// ★★★: ink of finished shapes (locked; 擦晒 never touches it).
    public private(set) var doneInk: [[[LineMatchPoint]]]
    public private(set) var inking = false
    /// ★★★ 擦晒 presses (whole round / this shape) and the last press time.
    public private(set) var erases = 0
    public private(set) var erasesThisShape = 0
    public private(set) var lastEraseAt: Double?
    public private(set) var eraserHidden = false

    public init(question: ShapeTraceQuestion, tolerance: LineMatchTolerance = .standard, directionHint: Bool = true) {
        self.question = question
        self.tolerance = tolerance
        self.directionHint = directionHint
        self.shapeStats = question.shapes.map { _ in ShapeTraceShapeStats() }
        self.doneInk = question.shapes.map { _ in [] }
    }

    /// ★★★ 自己畫: the child's own ink, no vehicle drawn, 擦晒.
    public var recordsInk: Bool { question.level == .l3 }

    /// ★★★: 擦晒 shows (hidden after the 6th press until the shape is drawn).
    public var eraserVisible: Bool { recordsInk && !isComplete && !eraserHidden }

    /// ★★★: every ink point of `shape` (finished or current).
    public func inkPolylines(shape: Int) -> [[LineMatchPoint]] {
        if shape == shapeIndex, !isComplete { return ink }
        return doneInk.indices.contains(shape) ? doneInk[shape] : []
    }

    public var shapes: [ShapeTraceShape] { question.shapes }
    public var isComplete: Bool { !shapes.isEmpty && shapeIndex >= shapes.count }
    public var remainingShapes: Int { max(0, shapes.count - shapeIndex) }
    public var currentShape: Int? { isComplete ? nil : shapeIndex }

    public func isDone(shape: Int) -> Bool { shape < shapeIndex }

    /// Strokes of `shape` already drawn (all of them once the shape is done).
    public func doneStrokes(shape: Int) -> Int {
        guard shapes.indices.contains(shape) else { return 0 }
        if shape < shapeIndex { return shapes[shape].strokes.count }
        if shape == shapeIndex { return strokeIndex }
        return 0
    }

    private static func key(_ shape: Int, _ stroke: Int) -> String { "\(shape).\(stroke)" }

    public func isReversed(shape: Int, stroke: Int) -> Bool {
        reversedStrokes.contains(Self.key(shape, stroke))
    }

    /// The stroke as it is driven (reversed when the child started at the red end, hint off).
    public func path(shape: Int, stroke: Int) -> TracePath? {
        guard shapes.indices.contains(shape), shapes[shape].strokes.indices.contains(stroke) else { return nil }
        let path = shapes[shape].strokes[stroke]
        return isReversed(shape: shape, stroke: stroke) ? path.reversed : path
    }

    public var currentPath: TracePath? {
        isComplete ? nil : path(shape: shapeIndex, stroke: strokeIndex)
    }

    /// Where the vehicle is: on the current stroke, or parked at the end of the last one.
    public var vehiclePoint: LineMatchPoint? {
        if let path = currentPath { return path.point(at: progress) }
        guard let last = shapes.indices.last, let stroke = shapes[last].strokes.indices.last,
              let path = path(shape: last, stroke: stroke) else { return nil }
        return path.end
    }

    public var vehicleAngle: Double {
        if let path = currentPath { return path.angle(at: progress) }
        guard let last = shapes.indices.last, let stroke = shapes[last].strokes.indices.last,
              let path = path(shape: last, stroke: stroke) else { return 0 }
        return path.angle(at: path.length)
    }

    /// Half of the judged corridor: drawn lane width × 1.0 / 1.5 / 2.2 (窄 / 標準 / 闊), halved.
    public var corridorHalfWidth: Double {
        question.laneWidth * tolerance.roadWidthFactor / 2
    }

    /// Arc length at which `path` counts as drawn (97% or the tolerance's arrival slack).
    public func arrivalDistance(_ path: TracePath) -> Double {
        path.length - max(path.length * (1 - Self.arrivalFraction), tolerance.arrivalSlack)
    }

    /// 0…1 drawn share of the current stroke.
    public var strokeFraction: Double {
        guard let path = currentPath, path.length > 0 else { return isComplete ? 1 : 0 }
        return min(max(progress / path.length, 0), 1)
    }

    /// 0…1 drawn share of the current shape (whole strokes plus the current one).
    public var shapeFraction: Double {
        guard let shape = currentShape else { return 1 }
        let strokes = shapes[shape].strokes
        let total = strokes.reduce(0) { $0 + $1.length }
        guard total > 0 else { return 0 }
        let done = strokes.prefix(strokeIndex).reduce(0) { $0 + $1.length }
        return min(1, (done + progress) / total)
    }

    /// The next corner the vehicle has not passed yet (it must stop there first).
    public var nextCorner: Double? {
        guard let path = currentPath else { return nil }
        return path.corners.first { $0 >= progress - 0.5 }
    }

    /// True while the vehicle is waiting at a corner it reached.
    public var isAtCorner: Bool {
        guard let path = currentPath else { return false }
        return path.corners.contains { abs($0 - progress) < 0.5 }
    }

    /// The tiny hint: pen away from the vehicle / stroke for over 2 s during a stroke.
    public func showsHint(now: Double) -> Bool {
        guard dragging, let since = awaySince else { return false }
        return now - since >= Self.hintAfterSeconds
    }

    /// No progress for 8 s on this stroke (the view shows the ghost once per stroke).
    public func ghostDue(now: Double) -> Bool {
        guard !isComplete, let since = lastProgressAt else { return false }
        return now - since >= Self.ghostDemoAfterSeconds
    }

    // MARK: Pen events

    public mutating func penDown(at point: LineMatchPoint, now: Double) -> ShapeTracePenDown {
        dragging = false
        holding = false
        offPath = false
        awaySince = nil
        inking = false
        guard let shape = currentShape, let path = currentPath, let vehicle = vehiclePoint else { return .ignored }
        if recordsInk, inkCount < Self.inkPointCap {
            ink.append([point])
            inking = true
        }
        penDowns += 1
        lastPenDownAt = now
        if startedAt == nil { startedAt = now }
        if lastProgressAt == nil { lastProgressAt = now }
        if shapeStats[shape].startedAt == nil { shapeStats[shape].startedAt = now }
        if point.distance(to: vehicle) <= Self.grabRadius {
            dragging = true
            holding = true
            return .grabbed(shape: shape, stroke: strokeIndex)
        }
        if !path.closed, point.distance(to: path.end) <= Self.grabRadius {
            reverseDirections += 1
            shapeStats[shape].reverseDirections += 1
            if directionHint || progress > 0.5 {
                wrongStarts += 1
                shapeStats[shape].wrongStarts += 1
                return .reverse
            }
            // Direction hint off: take the stroke from this end instead.
            reversedStrokes.append(Self.key(shape, strokeIndex))
            dragging = true
            holding = true
            return .grabbed(shape: shape, stroke: strokeIndex)
        }
        if isOnOtherMarker(point) {
            wrongStarts += 1
            shapeStats[shape].wrongStarts += 1
            return .wrongStart
        }
        dragging = true
        awaySince = now
        return .notNearVehicle
    }

    /// Pen down on the start or end of a stroke that is not the current one.
    private func isOnOtherMarker(_ point: LineMatchPoint) -> Bool {
        for (s, shape) in shapes.enumerated() where s >= shapeIndex {
            for (k, stroke) in shape.strokes.enumerated() where !(s == shapeIndex && k <= strokeIndex) {
                if point.distance(to: stroke.start) <= Self.grabRadius * 0.6
                    || point.distance(to: stroke.end) <= Self.grabRadius * 0.6 { return true }
            }
        }
        return false
    }

    private var inkCount: Int { ink.reduce(0) { $0 + $1.count } }

    /// ★★★: the crayon goes wherever the pen goes (off the path too; design §4.3).
    private mutating func recordInk(_ point: LineMatchPoint) {
        guard inking, !ink.isEmpty, inkCount < Self.inkPointCap else { return }
        let last = ink[ink.count - 1].last ?? point
        guard last.distance(to: point) >= Self.inkSpacing else { return }
        ink[ink.count - 1].append(point)
    }

    /// Arc-length window searched for the pen: 40u behind to 210u ahead of the vehicle, clipped at
    /// cusps (never past the next one, never behind one already reached). Strokes without cusps
    /// (every shape-trace stroke) get exactly the old window.
    public func searchWindow(_ path: TracePath) -> ClosedRange<Double> {
        var low = progress - Self.windowBehind
        var high = progress + Self.leadLimit + Self.maxStep
        if let reached = path.cusps.last(where: { $0 <= progress + 0.5 }) { low = max(low, reached) }
        if let ahead = path.cusps.first(where: { $0 > progress + 0.5 }) { high = min(high, ahead) }
        return low...max(low, high)
    }

    public mutating func penMove(to point: LineMatchPoint, now: Double) -> ShapeTraceMove {
        recordInk(point)
        guard dragging, let shape = currentShape, let path = currentPath else { return .ignored }
        if !holding {
            // Sliding onto the vehicle takes hold of it, as a fresh pen-down near it would.
            guard let vehicle = vehiclePoint, point.distance(to: vehicle) <= Self.grabRadius else {
                if awaySince == nil { awaySince = now }
                return .away
            }
            holding = true
        }
        let projection = path.project(point, window: searchWindow(path))
        let corner = nextCorner

        // Corner checkpoint: waiting at the corner, the pen ran on in the old direction.
        if let corner, abs(progress - corner) < 0.5, projection.distance <= corner + 8 {
            let cornerPoint = path.point(at: corner)
            let dir = path.incomingDirection(at: corner)
            let along = (point.x - cornerPoint.x) * dir.dx + (point.y - cornerPoint.y) * dir.dy
            if along > Self.cornerOvershootU {
                awaySince = awaySince ?? now
                if !cornersOvershot.contains(corner) {
                    cornersOvershot.append(corner)
                    cornerOvershoots += 1
                    shapeStats[shape].cornerOvershoots += 1
                    return .cornerOvershoot
                }
                return .away
            }
        }

        if projection.offset > corridorHalfWidth {
            if !offPath {
                offPath = true
                offPathCount += 1
                shapeStats[shape].offPath += 1
            }
            if awaySince == nil { awaySince = now }
            return .away
        }
        offPath = false
        shapeStats[shape].deviationSum += projection.offset
        shapeStats[shape].deviationSamples += 1
        shapeStats[shape].maxDeviation = max(shapeStats[shape].maxDeviation, projection.offset)
        if projection.distance - progress > Self.leadLimit {
            if awaySince == nil { awaySince = now }
            return .away
        }
        // Shortcut across a corner the vehicle has not reached yet: tagged once; it still waits.
        if let corner, progress < corner - 20, projection.distance > corner + Self.cornerCutU,
           !cornersCut.contains(corner) {
            cornersCut.append(corner)
            cornerCuts += 1
            shapeStats[shape].cornerCuts += 1
        }
        awaySince = nil
        guard projection.distance > progress + 0.01 else { return .waiting }
        var next = min(projection.distance, progress + Self.maxStep, path.length)
        var reachedCorner = false
        // A turn-back (cusp) counts as reached within half the corridor of its tip: a pen that turns
        // a little early would otherwise project onto the leg behind the vehicle and never get there.
        if let corner, path.cusps.contains(corner), progress < corner - 0.5, next < corner,
           corner - next <= corridorHalfWidth, corner - progress <= Self.maxStep {
            next = corner
        }
        if let corner {
            if progress < corner - 0.5, next >= corner {
                next = corner
                reachedCorner = true
            } else if abs(progress - corner) < 0.5, projection.distance <= corner + 8 {
                // Still at the corner: the pen has not turned onto the next piece yet.
                return .waiting
            }
        }
        progress = next
        lastProgressAt = now
        if reachedCorner {
            if !cornersReached.contains(corner ?? -1) { cornersReached.append(corner ?? -1) }
            return .cornerReached
        }
        guard next >= arrivalDistance(path), path.corners.allSatisfy({ $0 < next }) else { return .drove }
        // Stroke done. Pen run on past the end in the same direction = `end_overshoot`.
        let dir = path.incomingDirection(at: path.length)
        let along = (point.x - path.end.x) * dir.dx + (point.y - path.end.y) * dir.dy
        if along > Self.cornerOvershootU {
            endOvershoots += 1
            shapeStats[shape].endOvershoots += 1
        }
        return finishStroke(now: now)
    }

    private mutating func finishStroke(now: Double) -> ShapeTraceMove {
        let shape = shapeIndex
        let stroke = strokeIndex
        dragging = false
        holding = false
        offPath = false
        awaySince = nil
        cornersOvershot = []
        cornersCut = []
        cornersReached = []
        progress = 0
        lastProgressAt = now
        if stroke + 1 < shapes[shape].strokes.count {
            strokeIndex = stroke + 1
            return .strokeDone(shape: shape, stroke: stroke)
        }
        shapeStats[shape].finishedAt = now
        if recordsInk {
            doneInk[shape] = ink
            shapeStats[shape].inkOutsideRatio = inkOutsideRatio(ink, shape: shape)
            ink = []
            inking = false
            erasesThisShape = 0
            eraserHidden = false
            lastEraseAt = nil
        }
        shapeIndex = shape + 1
        strokeIndex = 0
        if isComplete {
            finishedAt = now
            return .allDone
        }
        return .shapeDone(shape: shape)
    }

    /// Pen up. The vehicle stays where it is; a lift mid-stroke is counted (never a miss).
    public mutating func penUp() {
        if dragging, holding, let shape = currentShape, progress > 0.5 {
            lifts += 1
            shapeStats[shape].lifts += 1
        }
        dragging = false
        holding = false
        offPath = false
        awaySince = nil
        inking = false
    }

    /// Gesture lost (window change, system cancel): like a lift, but not counted.
    public mutating func cancelStroke() {
        dragging = false
        holding = false
        offPath = false
        awaySince = nil
        inking = false
    }

    /// ★★★ 擦晒: clears the current shape's ink and progress (back to its first stroke). Finished
    /// shapes never change. 3 s cooldown; the 4th press nudges, the 6th hides the button until
    /// this shape is drawn (design §2.6).
    public mutating func erase(now: Double) -> ShapeTraceErase {
        guard eraserVisible, let shape = currentShape else { return .unavailable }
        if let last = lastEraseAt, now - last < Self.eraserCooldown { return .coolingDown }
        erases += 1
        erasesThisShape += 1
        lastEraseAt = now
        shapeStats[shape].erasers += 1
        ink = []
        inking = false
        strokeIndex = 0
        progress = 0
        reversedStrokes.removeAll { $0.hasPrefix("\(shape).") }
        dragging = false
        holding = false
        offPath = false
        awaySince = nil
        cornersOvershot = []
        cornersCut = []
        cornersReached = []
        lastProgressAt = now
        if erasesThisShape >= Self.eraserHideAt {
            eraserHidden = true
            shapeStats[shape].eraserLocked = true
            return .clearedAndHidden
        }
        return erasesThisShape == Self.eraserNudgeAt ? .clearedNudge : .cleared
    }

    /// Share of ink points farther from every stroke of `shape` than the judged half width.
    public func inkOutsideRatio(_ polylines: [[LineMatchPoint]], shape: Int) -> Double? {
        guard shapes.indices.contains(shape) else { return nil }
        let points = polylines.flatMap { $0 }
        guard !points.isEmpty else { return nil }
        let strokes = shapes[shape].strokes
        let half = corridorHalfWidth
        let outside = points.filter { p in strokes.allSatisfy { $0.project(p).offset > half } }.count
        return Double(outside) / Double(points.count)
    }

    /// Strokes finished so far (shape-major), for the monotonic check.
    public var strokesDone: Int {
        shapes.prefix(min(shapeIndex, shapes.count)).reduce(0) { $0 + $1.strokes.count } + (isComplete ? 0 : strokeIndex)
    }

    /// True when `self` can only have come from `older` by pen events: same question, the
    /// vehicle never went backwards, finished strokes stay finished, counters never drop.
    public func isMonotonicSuccessor(of older: ShapeTraceBoard) -> Bool {
        guard question == older.question, tolerance == older.tolerance, directionHint == older.directionHint else {
            return false
        }
        if erases < older.erases { return false }
        if erases > older.erases {
            // 擦晒 may take the current shape back to its first stroke; finished shapes stay.
            return shapeIndex >= older.shapeIndex && offPathCount >= older.offPathCount && lifts >= older.lifts
                && wrongStarts >= older.wrongStarts && penDowns >= older.penDowns
        }
        if shapeIndex == older.shapeIndex, !isComplete, inkCount < older.inkCount { return false }
        if strokesDone < older.strokesDone { return false }
        if strokesDone == older.strokesDone, progress < older.progress { return false }
        guard reversedStrokes.count >= older.reversedStrokes.count,
              Array(reversedStrokes.prefix(older.reversedStrokes.count)) == older.reversedStrokes else { return false }
        return offPathCount >= older.offPathCount && lifts >= older.lifts && wrongStarts >= older.wrongStarts
            && penDowns >= older.penDowns && cornerOvershoots >= older.cornerOvershoots
            && reverseDirections >= older.reverseDirections
    }

    // MARK: Stats (practice; never mastery evidence — design D10)

    public var meanDeviation: Double? {
        let samples = shapeStats.reduce(0) { $0 + $1.deviationSamples }
        guard samples > 0 else { return nil }
        return shapeStats.reduce(0) { $0 + $1.deviationSum } / Double(samples)
    }

    /// Shape names drawn (one exposure each).
    public var exposures: [String] {
        shapes.prefix(min(shapeIndex, shapes.count)).map(\.kind.rawValue)
    }

    /// `per_shape` rows: `shape:mean_dev:max_dev:lifts:off_path:overshoot:cut:end_overshoot:reverse:wrong_start:ms`.
    public var perShapeRows: [String] {
        shapes.indices.map { index in
            let s = shapeStats[index]
            let mean = s.meanDeviation.map { String(format: "%.1f", $0) } ?? ""
            let ms = (s.startedAt != nil && s.finishedAt != nil)
                ? String(Int((((s.finishedAt ?? 0) - (s.startedAt ?? 0)) * 1000).rounded())) : ""
            return [shapes[index].kind.rawValue, mean, String(format: "%.1f", s.maxDeviation), String(s.lifts),
                    String(s.offPath), String(s.cornerOvershoots), String(s.cornerCuts), String(s.endOvershoots),
                    String(s.reverseDirections), String(s.wrongStarts), ms].joined(separator: ":")
        }
    }

    /// Extra `round_result` fields.
    public var resultFields: [String: PerfValue] {
        var fields: [String: PerfValue] = [
            "practice": .string("shape_trace"),
            "shapes_done": .int(min(shapeIndex, shapes.count)),
            "shapes_total": .int(shapes.count),
            "off_path_count": .int(offPathCount),
            "lifts": .int(lifts),
            "wrong_start": .int(wrongStarts),
            "reverse_direction": .int(reverseDirections),
            "corner_overshoot": .int(cornerOvershoots),
            "corner_cut": .int(cornerCuts),
            "end_overshoot": .int(endOvershoots),
            "strokes": .int(penDowns),
            "exposures": .strings(exposures),
            "per_shape": .strings(perShapeRows),
            "tolerance": .string(tolerance.rawValue),
            "mean_dev_u": .seconds(meanDeviation)
        ]
        if let startedAt, let finishedAt {
            fields["duration_ms"] = .int(Int(((finishedAt - startedAt) * 1000).rounded()))
        }
        fields["shape_trace_level"] = .string(question.level.code)
        if recordsInk {
            let ratios = shapeStats.compactMap(\.inkOutsideRatio)
            fields["ink_outside_ratio"] = .seconds(ratios.isEmpty ? nil : ratios.reduce(0, +) / Double(ratios.count))
            fields["ink_outside"] = .strings(shapes.indices.map { index in
                shapeStats[index].inkOutsideRatio.map { String(format: "%.2f", $0) } ?? ""
            })
            fields["erasers"] = .int(erases)
            fields["eraser_locked"] = .int(shapeStats.filter(\.eraserLocked).count)
        }
        return fields
    }
}
