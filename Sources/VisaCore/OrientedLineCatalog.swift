import Foundation

// 畫直線・四方 / Straight lines · Four ways (0.42.0; four-direction design, Carter t372u Q1–Q10 and t372s2028 C1–C6).
// A new card beside 畫直線 · 熱身 (`traceLines`), which stays exactly as it was. Four oriented straight strokes: → and
// ← across, ↗ up to the right and ↙ down the same road. Green is always the actual start and red the actual finish; one
// big line at a time; the whole road must be drawn (`OrientedLineBoard`, connected coverage). The card has its own
// settings (線形, 方向, 畫線提示 and its own 畫線寬容度), its own 試玩, stars and 識咗: nothing is read from or copied
// out of the original card. The English subtitle and the programmatic ids are implementer technical defaults
// (t373s2037), not Carter's wording.

// MARK: - Variants (design §4.1)

/// One oriented stroke. The variant only decides which end of its footprint is green (P0) and which is red (P1).
public enum OrientedLineVariant: String, CaseIterable, Sendable, Codable, Hashable {
    /// → across, left to right.
    case right
    /// ← across, right to left.
    case left
    /// ↗ bottom-left to top-right.
    case upRight
    /// ↙ the same diagonal road, top-right to bottom-left.
    case downLeft

    public var isHorizontal: Bool { self == .right || self == .left }
    /// → and ↗ (方向 左→右); ← and ↙ are leftward (右→左).
    public var isRightward: Bool { self == .right || self == .upRight }

    public init(horizontal: Bool, rightward: Bool) {
        switch (horizontal, rightward) {
        case (true, true): self = .right
        case (true, false): self = .left
        case (false, true): self = .upRight
        case (false, false): self = .downLeft
        }
    }

    /// The oriented kind in `game_dealt.shapes`, `exposures` and `per_shape` (design §9). `across` keeps the meaning it
    /// already has on 畫直線 · 熱身 (a rightward horizontal); these rows are written under the new kind only.
    public var factToken: String {
        switch self {
        case .right: return "across"
        case .left: return "across_left"
        case .upRight: return "up_right"
        case .downLeft: return "down_left"
        }
    }

    /// 識咗 key in `VisaGames.orientedLineGuideProgress.v1` (design §6.3).
    public var learnKey: String {
        switch self {
        case .right: return "line.right"
        case .left: return "line.left"
        case .upRight: return "line.upRight"
        case .downLeft: return "line.downLeft"
        }
    }

    /// Progress-row icon (design §4.4, Q6).
    public var arrow: String {
        switch self {
        case .right: return "→"
        case .left: return "←"
        case .upRight: return "↗"
        case .downLeft: return "↙"
        }
    }

    /// Where the green start is, in words (design §7: always the actual green end).
    public var sideTraditionalChinese: String {
        switch self {
        case .right: return "左邊"
        case .left: return "右邊"
        case .upRight: return "左下"
        case .downLeft: return "右上"
        }
    }

    public var sideEnglish: String {
        switch self {
        case .right: return "on the left"
        case .left: return "on the right"
        case .upRight: return "at the bottom left"
        case .downLeft: return "at the top right"
        }
    }

    /// The way to draw, in words (design §7).
    public var wayTraditionalChinese: String {
        switch self {
        case .right: return "向右"
        case .left: return "向左"
        case .upRight: return "斜斜向右上"
        case .downLeft: return "斜斜向左下"
        }
    }

    public var wayEnglish: String {
        switch self {
        case .right: return "right"
        case .left: return "left"
        case .upRight: return "up to the right"
        case .downLeft: return "down to the left"
        }
    }
}

// MARK: - Footprints (design §4.2; every number PROVISIONAL until R4)

/// A direction-free road: two bars and two sign positions. Its forward and reverse strokes share it exactly.
public enum OrientedLineFootprint: Sendable, Equatable, Hashable {
    /// Left bar x 300 / 330 / 360, right bar x 870 / 900 / 930, row y 300 / 330 / 360 (L 510–630 u).
    case horizontal(left: Int, right: Int, row: Int)
    /// Lower-left bar A = (420 / 450 / 480, 446); upper-right bar B = A + (278.5, −195.0): 340 u at 35°.
    case diagonal(Int)

    public static let leftXs: [Double] = [300, 330, 360]
    public static let rightXs: [Double] = [870, 900, 930]
    public static let rowYs: [Double] = [300, 330, 360]
    public static let diagonalXs: [Double] = [420, 450, 480]
    public static let diagonalY: Double = 446
    public static let diagonalRise = LineMatchPoint(x: 278.5, y: -195.0)

    public static let allHorizontal: [OrientedLineFootprint] = leftXs.indices.flatMap { left in
        rightXs.indices.flatMap { right in rowYs.indices.map { OrientedLineFootprint.horizontal(left: left, right: right, row: $0) } }
    }
    public static let allDiagonal: [OrientedLineFootprint] = diagonalXs.indices.map { OrientedLineFootprint.diagonal($0) }

    public var isHorizontal: Bool {
        if case .horizontal = self { return true }
        return false
    }

    /// Lower-left (or left) bar and upper-right (or right) bar, independent of direction.
    public var bars: (a: LineMatchPoint, b: LineMatchPoint) {
        switch self {
        case let .horizontal(left, right, row):
            let y = Self.rowYs[min(max(row, 0), 2)]
            return (LineMatchPoint(x: Self.leftXs[min(max(left, 0), 2)], y: y),
                    LineMatchPoint(x: Self.rightXs[min(max(right, 0), 2)], y: y))
        case let .diagonal(index):
            let a = LineMatchPoint(x: Self.diagonalXs[min(max(index, 0), 2)], y: Self.diagonalY)
            return (a, LineMatchPoint(x: a.x + Self.diagonalRise.x, y: a.y + Self.diagonalRise.y))
        }
    }

    /// Item-id code: `a<left><right>y<row>` or `d<index>`, one-based.
    public var code: String {
        switch self {
        case let .horizontal(left, right, row): return "a\(left + 1)\(right + 1)y\(row + 1)"
        case let .diagonal(index): return "d\(index + 1)"
        }
    }
}

// MARK: - One dealt line (design §4.1, §5.1)

/// A dealt line: its variant and footprint, green start P0 and red finish P1. Progress s = (p − P0)·u runs from 0 at
/// green to L at red; the lateral distance d = (p − P0)·n. Nothing about the pen rule uses screen x or y.
public struct OrientedLine: Sendable, Equatable {
    /// Sign centres sit this far beyond their bars (design §4.2).
    public static let signOffset: Double = 130
    public static let signRadius: Double = 44
    /// The painted sign (edge included): its whole disc is the hit target (design §5.1).
    public static let signPaintedRadius: Double = 47
    /// Solid green start bar across the corridor at P0.
    public static let startBarWidth: Double = 12
    /// Chequers over s ∈ [L − 10, L + 10]; completion C = L − 10.
    public static let finishBand: Double = 10
    /// Red rails centred at s = L ± 13, 5 u wide: the painted bar spans s ∈ [L − 15.5, L + 15.5].
    public static let railOffset: Double = 13
    public static let railWidth: Double = 5
    /// Drawn corridor caps: r 50 plus the 6 u ink edge, around each sign centre.
    public static let capRadius: Double = 56

    public let variant: OrientedLineVariant
    public let footprint: OrientedLineFootprint
    /// P0, the green start bar.
    public let start: LineMatchPoint
    /// P1, the red finish bar.
    public let finish: LineMatchPoint

    public init(variant: OrientedLineVariant, footprint: OrientedLineFootprint) {
        self.variant = variant
        self.footprint = footprint
        let bars = footprint.bars
        if variant.isRightward {
            start = bars.a
            finish = bars.b
        } else {
            start = bars.b
            finish = bars.a
        }
    }

    /// L, the bar-to-bar length.
    public var length: Double { start.distance(to: finish) }
    /// u = (P1 − P0) / L.
    public var unit: LineMatchPoint {
        let l = length
        return LineMatchPoint(x: (finish.x - start.x) / l, y: (finish.y - start.y) / l)
    }
    /// n: the screen-down side of the footprint, the same for both of its directions.
    public var normal: LineMatchPoint {
        let u = unit
        let n = LineMatchPoint(x: -u.y, y: u.x)
        return n.y > 0 || (n.y == 0 && n.x > 0) ? n : LineMatchPoint(x: -n.x, y: -n.y)
    }
    /// Heading in radians (0 = right, +π/2 = down): 0, π, −35°, 145°.
    public var angle: Double { atan2(finish.y - start.y, finish.x - start.x) }
    /// The green sign centre, P0 − 130u.
    public var greenSign: LineMatchPoint { point(at: -Self.signOffset) }
    /// The red sign centre, P1 + 130u.
    public var redSign: LineMatchPoint { point(at: length + Self.signOffset) }
    /// Completion C = L − 10: the near edge of the chequers.
    public var completion: Double { length - Self.finishBand }
    /// Guidance limit G = L − 15.5: the near edge of the painted finish bar (near rail's outer edge).
    public var guidanceLimit: Double { length - Self.railOffset - Self.railWidth / 2 }
    /// The bar-to-bar path (arc length = s), for drawing and the shared helpers.
    public var path: TracePath { .line(start, finish) }

    public func point(at s: Double) -> LineMatchPoint {
        let u = unit
        return LineMatchPoint(x: start.x + u.x * s, y: start.y + u.y * s)
    }

    /// s(p): progress along the line from green.
    public func progress(of p: LineMatchPoint) -> Double {
        let u = unit
        return (p.x - start.x) * u.x + (p.y - start.y) * u.y
    }

    /// d(p): signed lateral distance (positive toward `normal`).
    public func lateral(of p: LineMatchPoint) -> Double {
        let n = normal
        return (p.x - start.x) * n.x + (p.y - start.y) * n.y
    }

    public func onGreenSign(_ p: LineMatchPoint) -> Bool { p.distance(to: greenSign) <= Self.signPaintedRadius }
    public func onRedSign(_ p: LineMatchPoint) -> Bool { p.distance(to: redSign) <= Self.signPaintedRadius }

    /// Inside the judged corridor: within `halfWidth` either side between the two sign centres, or on either painted
    /// sign. Beyond the sign centres only the painted discs count (design §5.1, T18).
    public func isInside(_ p: LineMatchPoint, halfWidth: Double) -> Bool {
        let s = progress(of: p)
        if abs(lateral(of: p)) <= halfWidth, s >= -Self.signOffset, s <= length + Self.signOffset { return true }
        return onGreenSign(p) || onRedSign(p)
    }

    /// The drawn corridor's outer extents (sign centre to sign centre, round caps r 56).
    public var outerBounds: LineMatchRect {
        let g = greenSign, r = redSign
        let minX = min(g.x, r.x) - Self.capRadius, maxX = max(g.x, r.x) + Self.capRadius
        let minY = min(g.y, r.y) - Self.capRadius, maxY = max(g.y, r.y) + Self.capRadius
        return LineMatchRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The per-variant contract (design §4.1, T2): → Δx > 0, Δy = 0; ← Δx < 0, Δy = 0; ↗ Δx > 0, Δy < 0; ↙ Δx < 0,
    /// Δy > 0; a diagonal's angle size within 30°–40°.
    public var meetsContract: Bool {
        let dx = finish.x - start.x, dy = finish.y - start.y
        switch variant {
        case .right: return dx > 0 && abs(dy) < 1e-9
        case .left: return dx < 0 && abs(dy) < 1e-9
        case .upRight, .downLeft:
            let size = atan2(abs(dy), abs(dx)) * 180 / Double.pi
            guard size >= 30, size <= 40 else { return false }
            return variant == .upRight ? dx > 0 && dy < 0 : dx < 0 && dy > 0
        }
    }

    /// Bounds and keep-outs (design §4.2, T3): centreline top − 50 ≥ 118 and bottom ≤ 540; outer extents inside the
    /// stage below the header (top ≥ 120); nothing in the clock keep-out K, the parent corner or the status block.
    public var fitsLayout: Bool {
        let top = min(start.y, finish.y), bottom = max(start.y, finish.y)
        guard top - 50 >= ShapeTraceLayout.workspaceTop, bottom <= ShapeTraceLayout.workspaceBottom else { return false }
        let outer = outerBounds
        guard outer.x >= 0, outer.maxX <= 1280, outer.y >= 120 else { return false }
        return !intersects(OrientedLineLayout.keepOuts)
    }

    /// True when the drawn corridor (a capsule of radius `capRadius` around the sign-to-sign segment) touches a rect.
    public func intersects(_ rects: [LineMatchRect]) -> Bool {
        let g = greenSign, r = redSign
        for rect in rects {
            // Distance from the segment to the rectangle, sampled every 2 u (the capsule is straight and short).
            let steps = Int((g.distance(to: r) / 2).rounded(.up))
            for step in 0...steps {
                let f = Double(step) / Double(max(steps, 1))
                let p = LineMatchPoint(x: g.x + (r.x - g.x) * f, y: g.y + (r.y - g.y) * f)
                let cx = min(max(p.x, rect.x), rect.maxX), cy = min(max(p.y, rect.y), rect.maxY)
                if LineMatchPoint(x: cx, y: cy).distance(to: p) < Self.capRadius { return true }
            }
        }
        return false
    }
}

public enum OrientedLineLayout {
    /// Clock keep-out K, the parent long-press corner and the status block (design §4.2).
    public static let keepOuts: [LineMatchRect] = [
        LineMatchRect(x: 1182, y: 0, width: 98, height: 56),
        ShapeTraceLayout.parentZone,
        LineMatchRect(x: 440, y: 580, width: 400, height: 140)
    ]
    /// The progress row (→ ← ↗ ↙ icons, done ✓ / current / next) sits where today's progress dots do.
    public static let status = ShapeTraceLayout.status
}

// MARK: - Parent settings (design §3.2, §6.3, §8.2–8.3; C2, C3)

/// 線形 / Line shape. No 原本 / `classic` (C2).
public enum OrientedLineShapeSetting: String, CaseIterable, Sendable, Codable, Hashable {
    case across
    case diagonal
    case both

    public var labelTraditionalChinese: String {
        switch self {
        case .across: return "橫線"
        case .diagonal: return "斜線"
        case .both: return "橫斜都有"
        }
    }

    public var labelEnglish: String {
        switch self {
        case .across: return "Across"
        case .diagonal: return "Slanted"
        case .both: return "Both"
        }
    }

    /// Shapes per line (design §3.3): A-A-A, D-D-D, or A-D-A / A-D-D (the first line is always a horizontal warm-up).
    public var patterns: [[Bool]] {
        switch self {
        case .across: return [[true, true, true]]
        case .diagonal: return [[false, false, false]]
        case .both: return [[true, false, true], [true, false, false]]
        }
    }
}

/// 方向 / Direction.
public enum OrientedLineDirectionSetting: String, CaseIterable, Sendable, Codable, Hashable {
    case rightward
    case leftward
    case both

    public var labelTraditionalChinese: String {
        switch self {
        case .rightward: return "左→右"
        case .leftward: return "右→左"
        case .both: return "兩個方向都有"
        }
    }

    public var labelEnglish: String {
        switch self {
        case .rightward: return "Left to right"
        case .leftward: return "Right to left"
        case .both: return "Both ways"
        }
    }

    /// Directions per line (true = rightward). 兩個方向都有: one of R-L-R, L-R-L, R-R-L, L-L-R, R-L-L, L-R-R, so every
    /// round has at least one of each (design §3.3).
    public var patterns: [[Bool]] {
        switch self {
        case .rightward: return [[true, true, true]]
        case .leftward: return [[false, false, false]]
        case .both:
            return [[true, false, true], [false, true, false], [true, true, false], [false, false, true],
                    [true, false, false], [false, true, true]]
        }
    }

    /// The board badge's second line (design §7).
    public var badgeTraditionalChinese: String {
        switch self {
        case .rightward: return "向右 · Rightward"
        case .leftward: return "向左 · Leftward"
        case .both: return "左右都有 · Both ways"
        }
    }
}

/// The new card's own settings. Defaults: 橫斜都有 + 兩個方向都有 (C2), 畫線提示 標準 (Q7), 畫線寬容度 標準
/// (Astra locked review, Major 1). None of them is shared with 畫直線 · 熱身 or 畫形狀設定.
public struct OrientedLineSettings: Equatable, Sendable {
    public var lineShape: OrientedLineShapeSetting
    public var lineDirection: OrientedLineDirectionSetting
    /// 畫線提示 (多啲 / 標準 / 少啲).
    public var lineHelp: TapCountGuidanceLevel
    /// 畫線寬容度 of this card only: 窄 / 標準 / 闊. 跟連一連 is not offered (design §8.2).
    public var tolerance: LineMatchTolerance

    public init(lineShape: OrientedLineShapeSetting = .both, lineDirection: OrientedLineDirectionSetting = .both,
                lineHelp: TapCountGuidanceLevel = .standard, tolerance: LineMatchTolerance = .standard) {
        self.lineShape = lineShape
        self.lineDirection = lineDirection
        self.lineHelp = lineHelp
        self.tolerance = tolerance
    }

    public static let defaults = OrientedLineSettings()

    /// The variants this selection deals (the parent panel lights their thumbnails).
    public var variants: [OrientedLineVariant] {
        OrientedLineVariant.allCases.filter { variant in
            let shapeOK = lineShape == .both || (lineShape == .across) == variant.isHorizontal
            let directionOK = lineDirection == .both || (lineDirection == .rightward) == variant.isRightward
            return shapeOK && directionOK
        }
    }
}

/// UserDefaults store of the new card (never `VisaGames.shapeTraceSettings.v1`). Each field decodes on its own: a missing,
/// mistyped or unknown value (a stored `classic` included) takes that field's default and keeps the others; a blob that
/// is not a JSON object reads as the defaults. Any other key (the never-shipped `lineSet`) is ignored.
public struct OrientedLineSettingsStore {
    public static let key = "VisaGames.orientedLineSettings.v1"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> OrientedLineSettings {
        guard let data = defaults.data(forKey: Self.key) else { return .defaults }
        return Self.decode(data)
    }

    public func save(_ settings: OrientedLineSettings) {
        defaults.set(Self.encode(settings), forKey: Self.key)
    }

    public static func decode(_ data: Data) -> OrientedLineSettings {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .defaults }
        func value<T: RawRepresentable>(_ key: String, _ type: T.Type) -> T? where T.RawValue == String {
            (object[key] as? String).flatMap(T.init(rawValue:))
        }
        let fallback = OrientedLineSettings.defaults
        return OrientedLineSettings(
            lineShape: value("lineShape", OrientedLineShapeSetting.self) ?? fallback.lineShape,
            lineDirection: value("lineDirection", OrientedLineDirectionSetting.self) ?? fallback.lineDirection,
            lineHelp: value("lineHelp", TapCountGuidanceLevel.self) ?? fallback.lineHelp,
            tolerance: value("lineTolerance", LineMatchTolerance.self) ?? fallback.tolerance)
    }

    public static func encode(_ settings: OrientedLineSettings) -> Data {
        let object: [String: String] = [
            "lineShape": settings.lineShape.rawValue, "lineDirection": settings.lineDirection.rawValue,
            "lineHelp": settings.lineHelp.rawValue, "lineTolerance": settings.tolerance.rawValue
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}

// MARK: - A dealt round

/// A dealt 畫直線・四方 round: three lines shown one at a time, and the snapshot of the settings it was dealt with
/// (線形, 方向, 畫線提示, 畫線寬容度). Everything about the open round reads this snapshot, never the live store
/// (design §5.4, T20). A pure function of (seed, settings, avoidingItem).
public struct OrientedLineQuestion: Sendable, Equatable {
    public let itemID: String
    public let kind: ActivityKind
    public let dealt: OrientedLineSettings
    public let lines: [OrientedLine]
    /// Drawn corridor width (today's 100 u line lanes); the judged corridor is this × the dealt tolerance.
    public let laneWidth: Double
    public let prompt: SpokenPrompt

    public init(itemID: String, dealt: OrientedLineSettings, lines: [OrientedLine]) {
        self.itemID = itemID
        self.kind = .traceOrientedLines
        self.dealt = dealt
        self.lines = lines
        self.laneWidth = OrientedLineGenerator.laneWidth
        self.prompt = OrientedLineCopy.prompt(lines.map(\.variant))
    }

    /// Judged half-width: 50 / 75 / 110 u at 窄 / 標準 / 闊.
    public var halfWidth: Double { laneWidth * dealt.tolerance.roadWidthFactor / 2 }

    /// Three lines, each meeting its variant contract and the layout; the composition matches the dealt 線形 and 方向.
    public var isWellFormed: Bool {
        guard !itemID.isEmpty, lines.count == OrientedLineGenerator.linesPerRound else { return false }
        guard lines.allSatisfy({ $0.meetsContract && $0.fitsLayout }) else { return false }
        let shapes = lines.map(\.variant.isHorizontal), directions = lines.map(\.variant.isRightward)
        return dealt.lineShape.patterns.contains(shapes) && dealt.lineDirection.patterns.contains(directions)
    }
}

public enum OrientedLineGenerator {
    public static let laneWidth: Double = 100
    public static let linesPerRound = 3

    /// `traceOrientedLines.v1.<線形>.<方向>.<variants>.<footprints>` (design §3.3; never `traceLines.v4.…`).
    public static func itemID(shape: OrientedLineShapeSetting, direction: OrientedLineDirectionSetting,
                              lines: [OrientedLine]) -> String {
        "\(ActivityKind.traceOrientedLines.rawValue).v1.\(shape.rawValue).\(direction.rawValue)."
            + lines.map(\.variant.rawValue).joined(separator: "-") + "."
            + lines.map(\.footprint.code).joined(separator: "-")
    }

    public static func make(seed: String, settings: OrientedLineSettings = .defaults,
                            avoidingItem: String? = nil) -> OrientedLineQuestion {
        var question = build(seed: seed, settings: settings)
        guard let avoidingItem else { return question }
        var attempt = 0
        while question.itemID == avoidingItem, attempt < QuestionGeneration.maxRerolls {
            attempt += 1
            question = build(seed: "\(seed)#\(attempt)", settings: settings)
        }
        return question
    }

    static func build(seed: String, settings: OrientedLineSettings) -> OrientedLineQuestion {
        var rng = QuestionRNG(seed: seed, salt: ActivityKind.traceOrientedLines.rawValue)
        let shapes = rng.pick(settings.lineShape.patterns)
        let directions = rng.pick(settings.lineDirection.patterns)
        var lines: [OrientedLine] = []
        for index in 0..<linesPerRound {
            let footprint: OrientedLineFootprint = shapes[index]
                ? .horizontal(left: rng.below(3), right: rng.below(3), row: rng.below(3))
                : .diagonal(rng.below(3))
            lines.append(OrientedLine(variant: OrientedLineVariant(horizontal: shapes[index], rightward: directions[index]),
                                      footprint: footprint))
        }
        return OrientedLineQuestion(itemID: itemID(shape: settings.lineShape, direction: settings.lineDirection, lines: lines),
                                    dealt: settings, lines: lines)
    }

    /// The middle footprints: placeholder before the first deal and the per-kind reference facts.
    public static var reference: OrientedLineQuestion {
        let lines = [OrientedLine(variant: .right, footprint: .horizontal(left: 1, right: 1, row: 1)),
                     OrientedLine(variant: .downLeft, footprint: .diagonal(1)),
                     OrientedLine(variant: .left, footprint: .horizontal(left: 1, right: 1, row: 1))]
        return OrientedLineQuestion(itemID: itemID(shape: .both, direction: .both, lines: lines), dealt: .defaults,
                                    lines: lines)
    }

    /// Every line a round can hold: each variant on each of its footprints (60 lines).
    public static var allLines: [OrientedLine] {
        OrientedLineVariant.allCases.flatMap { variant in
            (variant.isHorizontal ? OrientedLineFootprint.allHorizontal : OrientedLineFootprint.allDiagonal)
                .map { OrientedLine(variant: variant, footprint: $0) }
        }
    }

    /// Every variant sequence a (線形, 方向) pair can deal (design §3.2–3.3).
    public static func compositions(_ shape: OrientedLineShapeSetting,
                                    _ direction: OrientedLineDirectionSetting) -> [[OrientedLineVariant]] {
        var out: [[OrientedLineVariant]] = []
        for shapes in shape.patterns {
            for directions in direction.patterns {
                out.append((0..<linesPerRound).map { OrientedLineVariant(horizontal: shapes[$0], rightward: directions[$0]) })
            }
        }
        return out
    }
}

// MARK: - Child copy (HK Traditional + ASCII English; design §7)

/// Side words always name the actual green end; direction words follow the actual way. Keys: `lines.*` take the
/// variant (`lines.prompt.right`); `trace.*` take the oriented kind, so → keeps today's `trace.start.across` and
/// `trace.cue.across` lines exactly.
public enum OrientedLineCopy {
    public static let mixedPromptTraditionalChinese = "由綠色起點，跟住箭嘴畫去紅色終點！"
    public static let mixedPromptEnglish = "Start at green and follow the arrows to the red finish!"

    /// `lines.prompt.<v>` when every line shares one variant, else Carter's phrase `lines.prompt.mixed`.
    public static func prompt(_ variants: [OrientedLineVariant]) -> SpokenPrompt {
        guard let first = variants.first, variants.allSatisfy({ $0 == first }) else {
            return SpokenPrompt(key: "lines.prompt.mixed", traditionalChinese: mixedPromptTraditionalChinese,
                                english: mixedPromptEnglish)
        }
        return SpokenPrompt(key: "lines.prompt.\(first.rawValue)",
                            traditionalChinese: "由綠色起點，\(first.wayTraditionalChinese)畫去紅色終點！",
                            english: "Start at green and draw \(first.wayEnglish) to the red finish!")
    }

    /// `trace.start.<kind>`: a line appears (no demo).
    public static func start(_ v: OrientedLineVariant) -> SpokenPrompt {
        let zh: String, en: String
        switch v {
        case .right: zh = "打橫，向右！"; en = "Across, to the right!"
        case .left: zh = "打橫，向左！"; en = "Across, to the left!"
        case .upRight: zh = "斜斜，向右上！"; en = "Slant up to the right!"
        case .downLeft: zh = "斜斜，向左下！"; en = "Slant down to the left!"
        }
        return SpokenPrompt(key: "trace.start.\(v.factToken)", traditionalChinese: zh, english: en)
    }

    public static let demoWatch = SpokenPrompt(key: "lines.demo.watch", traditionalChinese: "睇住架車先！",
                                               english: "Watch the car first!")

    public static func demo(_ v: OrientedLineVariant) -> SpokenPrompt {
        SpokenPrompt(key: "lines.demo.\(v.rawValue)", traditionalChinese: "由起點\(v.wayTraditionalChinese)，去到終點。",
                     english: "From the start, go \(v.wayEnglish) to the finish.")
    }

    public static let demoTurn = SpokenPrompt(key: "lines.demo.turn", traditionalChinese: "到你喇！", english: "Your turn!")

    /// Not joined for 2 s with nothing drawn yet: where the green start is.
    public static func wrongStart(_ v: OrientedLineVariant) -> SpokenPrompt {
        SpokenPrompt(key: "lines.wrongStart.\(v.rawValue)",
                     traditionalChinese: "綠色起點喺\(v.sideTraditionalChinese)，由嗰度開始啊！",
                     english: "The green start is \(v.sideEnglish). Start there!")
    }

    /// The red sign or the finish zone touched before the car has left the start.
    public static func reverse(_ v: OrientedLineVariant) -> SpokenPrompt {
        SpokenPrompt(key: "lines.reverse.\(v.rawValue)",
                     traditionalChinese: "紅色係終點；由\(v.sideTraditionalChinese)綠色起點開始啊！",
                     english: "Red is the finish. Start from the green start \(v.sideEnglish)!")
    }

    /// The red sign or the finish zone touched with the car mid-line.
    public static func earlyFinish(_ v: OrientedLineVariant) -> SpokenPrompt {
        SpokenPrompt(key: "lines.earlyFinish.\(v.rawValue)",
                     traditionalChinese: "由架車度繼續\(v.wayTraditionalChinese)畫，去紅色終點！",
                     english: "Keep drawing \(v.wayEnglish) from the car to the red finish!")
    }

    public static let lifted = SpokenPrompt(key: "lines.lifted", traditionalChinese: "架車等緊你，由架車度繼續畫！",
                                            english: "The car is waiting. Carry on from the car!")

    /// The pause next-arrow (and the ring when a touch has not joined, once something is drawn).
    public static func pause(_ v: OrientedLineVariant) -> SpokenPrompt {
        SpokenPrompt(key: "lines.pause.\(v.rawValue)", traditionalChinese: "\(v.wayTraditionalChinese)，畫去紅色終點！",
                     english: "Go \(v.wayEnglish), to the red finish!")
    }

    public static let arrive = SpokenPrompt(key: "lines.arrive", traditionalChinese: "到終點喇！", english: "At the finish!")

    /// After arrival: the Cantonese word, then the English word (spoken as a word cue).
    public static func cue(_ v: OrientedLineVariant) -> SpokenPrompt {
        let zh: String, en: String
        switch v {
        case .right: zh = "打橫"; en = "across"
        case .left: zh = "打橫向左"; en = "across to the left"
        case .upRight: zh = "斜斜向右上"; en = "up to the right"
        case .downLeft: zh = "斜斜向左下"; en = "down to the left"
        }
        return SpokenPrompt(key: "trace.cue.\(v.factToken)", traditionalChinese: zh, english: en)
    }

    public static func bubble(_ v: OrientedLineVariant) -> String {
        let c = cue(v)
        return "\(c.traditionalChinese)、\(c.english)"
    }

    public static let redemo = SpokenPrompt(key: "lines.redemo", traditionalChinese: "再睇多次架車點行！",
                                            english: "Watch the car once more!")

    public static let startSign = "起點"
    public static let finishSign = "終點"
    public static let startSignEnglish = "Start"
    public static let finishSignEnglish = "Finish"
    /// The board badge: the locked title, then the 方向 line.
    public static let badgeTitle = "畫直線・四方"
    public static let hint = "提示：由綠色起點開始，跟住條線畫去紅色終點。 / Hint: start at the green start and follow the line to the red finish."

    // Parent copy (design §3.2, §3.4, §6.3, §8.2). The card's own panel; never on 畫直線 · 熱身.
    public static let settingsTitle = "畫直線・四方設定"
    public static let settingsSubtitle = "Straight lines · Four ways settings · 只用喺呢張卡，唔影響畫直線 · 熱身；要試玩一次先開到星級 / this card only, Lines · Warm-up is not changed; playtest once before turning on a star"
    public static let shapeTitle = "線形 / Line shape"
    public static let directionTitle = "方向 / Direction"
    public static let helpTitle = "畫線提示 / Line help"
    public static let toleranceTitle = "畫線寬容度 / Tolerance"
    public static let changedAdvisory = "改咗線款，建議試玩 / Line set changed: a playtest is suggested"
    public static let nextRoundNote = "下一局先生效；畫緊嗰局唔變 / Applies from the next round; a round on screen keeps its settings"
    public static let toleranceNote = "只係呢張卡嘅寬容度（唔跟畫形狀設定，亦唔跟連一連） / This card's own tolerance (not the Shapes or Line Match one)"
    public static let thumbnailsTitle = "今個設定會出 / This choice deals"

    public static func helpDetail(_ level: TapCountGuidanceLevel) -> (zh: String, en: String) {
        switch level {
        case .more: return ("多啲：每條線之前都示範；停一秒就提示下一步。", "More: a demo before every line; the next-arrow after a 1 s pause.")
        case .standard: return ("標準（預設）：識咗之前先示範；畫緊有前方箭嘴，停兩秒提示下一步。",
                                "Standard (default): a demo until it is learned; headlight arrows, the next-arrow after 2 s.")
        case .less: return ("少啲：唔自動示範，冇前方箭嘴；停咗八秒先示範去終點。", "Less: no automatic demo, no headlights; a ghost to the finish after 8 s.")
        }
    }

    public static func helpLabel(_ level: TapCountGuidanceLevel) -> (zh: String, en: String) {
        switch level {
        case .more: return ("多啲", "More")
        case .standard: return ("標準", "Standard")
        case .less: return ("少啲", "Less")
        }
    }

    public static func toleranceNow(_ tolerance: LineMatchTolerance) -> String {
        let factor = String(format: "%.1f", tolerance.roadWidthFactor)
        return "而家：\(tolerance.labelTraditionalChinese)，路面 ×\(factor)（出咗界都唔算錯，架車會等） / Now: corridor ×\(factor); off the road is never wrong"
    }

    public static var allTraditionalLines: [String] {
        var lines = [mixedPromptTraditionalChinese, demoWatch.traditionalChinese, demoTurn.traditionalChinese,
                     lifted.traditionalChinese, arrive.traditionalChinese, redemo.traditionalChinese, startSign, finishSign,
                     badgeTitle, hint.components(separatedBy: " / ").first ?? "", settingsTitle, shapeTitle, directionTitle,
                     helpTitle, toleranceTitle, changedAdvisory, nextRoundNote, toleranceNote, thumbnailsTitle,
                     settingsSubtitle, toleranceNow(.standard)]
        for v in OrientedLineVariant.allCases {
            lines += [prompt([v, v, v]).traditionalChinese, start(v).traditionalChinese, demo(v).traditionalChinese,
                      wrongStart(v).traditionalChinese, reverse(v).traditionalChinese, earlyFinish(v).traditionalChinese,
                      pause(v).traditionalChinese, cue(v).traditionalChinese, bubble(v), v.sideTraditionalChinese,
                      v.wayTraditionalChinese]
        }
        for shape in OrientedLineShapeSetting.allCases { lines.append(shape.labelTraditionalChinese) }
        for direction in OrientedLineDirectionSetting.allCases {
            lines += [direction.labelTraditionalChinese, direction.badgeTraditionalChinese]
        }
        for level in TapCountGuidanceLevel.allCases { lines += [helpDetail(level).zh, helpLabel(level).zh] }
        return lines
    }

    public static var allEnglishLines: [String] {
        var lines = [mixedPromptEnglish, demoWatch.english, demoTurn.english, lifted.english, arrive.english, redemo.english,
                     startSignEnglish, finishSignEnglish, hint.components(separatedBy: " / ").last ?? ""]
        for v in OrientedLineVariant.allCases {
            lines += [prompt([v, v, v]).english, start(v).english, demo(v).english, wrongStart(v).english,
                      reverse(v).english, earlyFinish(v).english, pause(v).english, cue(v).english, v.sideEnglish,
                      v.wayEnglish]
        }
        for shape in OrientedLineShapeSetting.allCases { lines.append(shape.labelEnglish) }
        for direction in OrientedLineDirectionSetting.allCases { lines.append(direction.labelEnglish) }
        for level in TapCountGuidanceLevel.allCases { lines += [helpDetail(level).en, helpLabel(level).en] }
        return lines
    }
}
