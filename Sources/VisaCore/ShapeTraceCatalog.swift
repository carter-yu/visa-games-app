import Foundation

// 畫線畫形 / Lines & Shapes content (v0.25.0 / v0.26.0, design shape-trace §3–§5, ADR 0014).
// Phase 1: `traceLines` (畫直線 · 熱身) and `traceShapesDotted` (畫形狀 · 跟虛線).
// Phase 2: `traceShapesArrows` (畫形狀 · 跟箭嘴, L2) and `traceShapesFree` (畫形狀 · 自己畫, L3).
// Scenes follow the Opus mockups 01 (fire station), 02 (castle towers), 03 (snow town),
// 04 (castle windows), 05 (build-a-car) and 06 (free towers); geometry here, art in `ShapeTraceArt`.

// MARK: - Shapes

/// What one traced thing is. Lines belong to 畫直線; the rest to the shape cards.
public enum ShapeTraceShapeKind: String, CaseIterable, Sendable, Codable, Hashable {
    case across
    case down
    case slant
    case circle
    case square
    /// ∧ — a tower spire without its base (★ triangles, design D6).
    case spire
    /// ▲ — full triangle: ① 撇 apex → bottom left, ② 捺 apex → bottom right, ③ 一 base (★★ on).
    case triangle
    /// ◁ — pennant 「<」 in one stroke: top → left tip (stop, turn) → bottom; the pole is drawn (D13).
    case pennant
    /// ▽ — ice-cream cone: ① 一 top, ② 捺 top left → tip, ③ 撇 top right → tip (D13, ★★ on).
    case cone

    public var isLine: Bool { self == .across || self == .down || self == .slant }

    /// The shape-mix group this belongs to (nil for lines).
    public var mixGroup: ShapeTraceMixShape? {
        switch self {
        case .circle: return .circle
        case .square: return .square
        case .spire, .triangle, .pennant, .cone: return .triangle
        case .across, .down, .slant: return nil
        }
    }

    /// Spoken after the shape is drawn: Cantonese word, then English word (design §2.7, §4.4).
    public var cueTraditionalChinese: String {
        switch self {
        case .across: return "打橫"
        case .down: return "打直"
        case .slant: return "斜斜"
        case .circle: return "圓形"
        case .square: return "正方形"
        case .spire, .triangle, .pennant, .cone: return "三角形"
        }
    }

    public var cueEnglish: String {
        switch self {
        case .across: return "across"
        case .down: return "down"
        case .slant: return "slant"
        case .circle: return "circle"
        case .square: return "square"
        case .spire, .triangle, .pennant, .cone: return "triangle"
        }
    }

    /// Said when the stroke becomes the current one (lines only; design §3 「幾時講」).
    public var startTraditionalChinese: String? {
        switch self {
        case .across: return "打橫，向右！"
        case .down: return "打直，向落！"
        case .slant: return "斜斜，向落！"
        case .circle: return "轉個圈！"
        case .square, .spire, .triangle, .pennant, .cone: return nil
        }
    }

    public var startEnglish: String? {
        switch self {
        case .across: return "Across, to the right!"
        case .down: return "Straight down!"
        case .slant: return "Slant down!"
        case .circle: return "Round you go!"
        case .square, .spire, .triangle, .pennant, .cone: return nil
        }
    }
}

/// Shape-mix groups the parent weighs (design §5 形狀比例: 圓 45 / 方 35 / 三角 20).
public enum ShapeTraceMixShape: String, CaseIterable, Sendable, Codable, Hashable {
    case circle
    case square
    case triangle

    public var defaultWeight: Int {
        switch self {
        case .circle: return 45
        case .square: return 35
        case .triangle: return 20
        }
    }

    public var titleTraditionalChinese: String {
        switch self {
        case .circle: return "圓形"
        case .square: return "正方形"
        case .triangle: return "三角形"
        }
    }

    public var titleEnglish: String {
        switch self {
        case .circle: return "Circle"
        case .square: return "Square"
        case .triangle: return "Triangle"
        }
    }
}

/// Where a round happens. One scene per round.
public enum ShapeTraceScene: String, CaseIterable, Sendable, Codable, Hashable {
    /// 消防局 (mockup 01): fire engine across, crane hook down, taxi down the hill / along the road.
    case fireStation
    /// 城堡高塔 (mockup 02): spires ∧ on two towers.
    case castleTowers
    /// 城堡窗 (mockup 04): square windows, 「口」 stroke order.
    case castleWindows
    /// 雪地小鎮 (mockup 03): sun and snowman body (★); sun, body, head and church clock (★★ / ★★★).
    case snowTown
    /// 城堡三座塔 (mockup 06): three open-topped towers, each roof a full ▲ (★★ / ★★★).
    case castleKeep
    /// 城堡大廳 (mockup 04 facade): three square windows (★★ / ★★★).
    case castleHall
    /// 砌車仔工場 (mockup 05): car body 口, back wheel, front wheel, then the topper (★★ / ★★★).
    case garage
}

/// 砌車仔 cars (design §4.1). The topper sits behind the body on a ready-made pole.
public enum ShapeTraceCar: String, CaseIterable, Sendable, Codable, Hashable {
    /// 旗仔車 (mockup 05): pennant ◁.
    case flagCar
    /// 風帆車: sail ▲.
    case sailCar
    /// 雪糕車: cone ▽ (the scoop is drawn).
    case coneCar

    public var topperSlot: String {
        switch self {
        case .flagCar: return "flag"
        case .sailCar: return "sail"
        case .coneCar: return "cone"
        }
    }

    public var topperTraditionalChinese: String {
        switch self {
        case .flagCar: return "旗仔"
        case .sailCar: return "帆"
        case .coneCar: return "雪糕筒"
        }
    }

    public var topperEnglish: String {
        switch self {
        case .flagCar: return "the flag"
        case .sailCar: return "the sail"
        case .coneCar: return "the cone"
        }
    }
}

/// One traced thing: its strokes in drawing order, its lane colour and the art frame around it.
public struct ShapeTraceShape: Sendable, Equatable {
    /// Scene slot (`across`, `down`, `third`, `spireA`, `windowB`, `sun`, `body` …).
    public let slot: String
    public let kind: ShapeTraceShapeKind
    public let strokes: [TracePath]
    /// Index into `LineMatchRoadPalette.roads` (never green or red).
    public let colorIndex: Int
    /// Square: the window; circle: the bounding box; spire: apex to base; line: the lane box.
    public let frame: LineMatchRect

    public init(slot: String, kind: ShapeTraceShapeKind, strokes: [TracePath], colorIndex: Int, frame: LineMatchRect) {
        self.slot = slot
        self.kind = kind
        self.strokes = strokes
        self.colorIndex = colorIndex
        self.frame = frame
    }

    public var isClosed: Bool { strokes.count == 1 && strokes[0].closed }
}

/// A dealt 畫線畫形 round. A pure function of (seed, kind, settings, avoidingItem).
public struct ShapeTraceQuestion: Sendable, Equatable {
    public let itemID: String
    public let kind: ActivityKind
    /// Pinned scaffold level (design §6 `shapeTraceLevel`): both phase-1 cards are L1.
    public let level: ActivityLevel
    public let scene: ShapeTraceScene
    /// Whole-scene horizontal shift (variety), stage units.
    public let shift: Double
    /// Big or slightly smaller shapes (L1 「2 款大細」).
    public let big: Bool
    /// 畫直線: the third line is a slant (parent switch) instead of a second across line.
    public let slant: Bool
    public let shapes: [ShapeTraceShape]
    /// Drawn lane width (100u lines, 80u dotted shapes). The judged corridor is this × tolerance.
    public let laneWidth: Double
    public let promptKey: String
    public let promptTraditionalChinese: String
    public let promptEnglish: String
    /// ★★ / ★★★: the shape group the parent's mix drew for this round (the scene features it).
    public let featured: ShapeTraceMixShape?
    /// 砌車仔: which car.
    public let car: ShapeTraceCar?
    /// ★★ / ★★★ size variant (0 smallest … 2 largest); scenery for undrawn slots uses it too.
    public let size: Int

    public init(itemID: String, kind: ActivityKind, level: ActivityLevel, scene: ShapeTraceScene, shift: Double,
                big: Bool, slant: Bool, shapes: [ShapeTraceShape], laneWidth: Double, promptKey: String,
                promptTraditionalChinese: String, promptEnglish: String, featured: ShapeTraceMixShape? = nil,
                car: ShapeTraceCar? = nil, size: Int = 1) {
        self.featured = featured
        self.car = car
        self.size = size
        self.itemID = itemID
        self.kind = kind
        self.level = level
        self.scene = scene
        self.shift = shift
        self.big = big
        self.slant = slant
        self.shapes = shapes
        self.laneWidth = laneWidth
        self.promptKey = promptKey
        self.promptTraditionalChinese = promptTraditionalChinese
        self.promptEnglish = promptEnglish
    }

    /// Mix group of a shape round (nil for 畫直線): the featured group on ★★ / ★★★.
    public var mixShape: ShapeTraceMixShape? { featured ?? shapes.first?.kind.mixGroup }

    /// ★★★: the child's own crayon ink, corner dots, model card and 擦晒.
    public var isFree: Bool { level == .l3 }

    /// ★★ / ★★★ outlined rounds (no lanes, no dots).
    public var isOutlined: Bool { level != .l1 }

    /// One kind for every shape (「仲有 2 個圓形」), or nil for a mixed round (「仲有 2 個形狀」).
    public var uniformKind: ShapeTraceShapeKind? {
        guard let first = shapes.first?.kind, shapes.allSatisfy({ $0.kind == first }) else { return nil }
        return first
    }

    public var hintTraditionalChinese: String { ShapeTraceCopy.hint }

    /// Every stroke goes down or right (circles excepted: top start, anticlockwise), shapes sit in
    /// the workspace, nothing enters the parent corner, and each shape has its strokes.
    public var isWellFormed: Bool {
        guard !itemID.isEmpty, !shapes.isEmpty, laneWidth > 0 else { return false }
        for shape in shapes {
            guard !shape.strokes.isEmpty, LineMatchRoadPalette.roads.indices.contains(shape.colorIndex) else {
                return false
            }
            for stroke in shape.strokes {
                guard stroke.length > 20 else { return false }
                if stroke.closed {
                    guard stroke.signedArea < 0, stroke.start.y <= stroke.points.map(\.y).min()! + 0.5 else { return false }
                } else if !ShapeTraceGeometry.goesDownOrRight(stroke) {
                    return false
                }
                let half = laneWidth / 2
                let box = stroke.bounds
                guard box.x - half >= 0, box.maxX + half <= 1280, box.y - half >= ShapeTraceLayout.workspaceTop,
                      box.maxY <= ShapeTraceLayout.workspaceBottom else { return false }
                guard !ShapeTraceLayout.entersParentCorner(stroke, halfWidth: half) else { return false }
            }
        }
        return true
    }
}

// MARK: - Layout and geometry rules

public enum ShapeTraceLayout {
    /// Work area under the header (design §2.8: y 120–540; lanes may dip into the tray edge).
    public static let workspaceTop: Double = 118
    public static let workspaceBottom: Double = 540
    /// Bottom-right parent long-press corner (design §2.8: x ≥ 1060, y ≥ 560). Nothing drawn here.
    public static let parentZone = LineMatchRect(x: 1060, y: 560, width: 220, height: 160)
    /// Progress dots + status line (tray, centre).
    public static let status = LineMatchRect(x: 440, y: 580, width: 400, height: 120)
    /// Link card (「好似人字」 / 「好似口字」 / 「好似寫 o」), tray right of centre.
    public static let linkCard = LineMatchRect(x: 790, y: 566, width: 250, height: 128)
    /// ★★★ 「照住畫」 model card (mockup 06), tray right; ends left of the parent corner.
    public static let modelCard = LineMatchRect(x: 824, y: 566, width: 216, height: 128)
    /// ★★★ 擦晒 (mockup 06 `btn-eraser`), tray bottom-left.
    public static let eraser = LineMatchRect(x: 24, y: 548, width: 200, height: 160)
    /// ★★★ status sits between the eraser and the model card.
    public static let freeStatus = LineMatchRect(x: 500, y: 580, width: 300, height: 120)
    public static let markerRadius: Double = 28
    public static let tickRadius: Double = 20

    public static func entersParentCorner(_ path: TracePath, halfWidth: Double) -> Bool {
        path.points.contains { $0.x + halfWidth >= parentZone.x && $0.y + halfWidth >= parentZone.y }
    }
}

public enum ShapeTraceGeometry {
    /// Design §7.6: every piece goes down (dy > 0) or right (dy = 0, dx > 0).
    public static func goesDownOrRight(_ path: TracePath) -> Bool {
        for index in 0..<(path.points.count - 1) {
            let a = path.points[index], b = path.points[index + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            if dy > 1e-6 { continue }
            if abs(dy) <= 1e-6, dx > 1e-6 { continue }
            return false
        }
        return true
    }
}

// MARK: - Parent settings (design §5 「畫形狀設定」, shared by the shape-trace cards)

public enum ShapeTraceDotStyle: String, CaseIterable, Sendable, Codable, Hashable {
    /// 粗圓點 (default).
    case dots
    /// 短虛線, like some school worksheets.
    case dashes

    public var labelTraditionalChinese: String { self == .dots ? "粗圓點" : "短虛線" }
    public var labelEnglish: String { self == .dots ? "Dots" : "Dashes" }
}

public struct ShapeTraceSettings: Equatable, Sendable {
    public static let weightStep = 5
    public static let maxWeight = 100

    public private(set) var weights: [ShapeTraceMixShape: Int]
    /// Nil = follow the 連一連 tolerance (「跟連一連」).
    public var tolerance: LineMatchTolerance?
    /// On (D8 A): only the arrow direction is accepted; reverse starts get a gentle prompt.
    public var directionHint: Bool
    /// On: the corner stop sign shows and Stampy says 「停！轉彎！」. The vehicle stops either way.
    public var cornerStop: Bool
    /// 畫直線 third line is a slant (off by default; about 4½ years, design §1.1).
    public var slantLines: Bool
    public var dotStyle: ShapeTraceDotStyle

    public init(weights: [ShapeTraceMixShape: Int] = [:], tolerance: LineMatchTolerance? = nil,
                directionHint: Bool = true, cornerStop: Bool = true, slantLines: Bool = false,
                dotStyle: ShapeTraceDotStyle = .dots) {
        var filled: [ShapeTraceMixShape: Int] = [:]
        for shape in ShapeTraceMixShape.allCases {
            filled[shape] = min(max(weights[shape] ?? shape.defaultWeight, 0), Self.maxWeight)
        }
        if filled.values.allSatisfy({ $0 == 0 }) {
            for shape in ShapeTraceMixShape.allCases { filled[shape] = shape.defaultWeight }
        }
        self.weights = filled
        self.tolerance = tolerance
        self.directionHint = directionHint
        self.cornerStop = cornerStop
        self.slantLines = slantLines
        self.dotStyle = dotStyle
    }

    public static let defaults = ShapeTraceSettings()

    public func weight(_ shape: ShapeTraceMixShape) -> Int { weights[shape] ?? shape.defaultWeight }

    public var hasDefaultMix: Bool { ShapeTraceMixShape.allCases.allSatisfy { weight($0) == $0.defaultWeight } }

    /// One step up or down. Nil when every shape would be off.
    public func adjusting(_ shape: ShapeTraceMixShape, steps: Int) -> ShapeTraceSettings? {
        var next = weights
        next[shape] = min(max(weight(shape) + steps * Self.weightStep, 0), Self.maxWeight)
        if next.values.allSatisfy({ $0 == 0 }) { return nil }
        var copy = self
        copy.weights = next
        return copy
    }

    public func withDefaultMix() -> ShapeTraceSettings {
        var copy = self
        copy.weights = Dictionary(uniqueKeysWithValues: ShapeTraceMixShape.allCases.map { ($0, $0.defaultWeight) })
        return copy
    }

    /// Share of `shape` among shape rounds (0…1).
    public func share(of shape: ShapeTraceMixShape) -> Double {
        let total = ShapeTraceMixShape.allCases.reduce(0) { $0 + weight($1) }
        return total > 0 ? Double(weight(shape)) / Double(total) : 0
    }

    public func effectiveTolerance(lineMatch: LineMatchTolerance) -> LineMatchTolerance {
        tolerance ?? lineMatch
    }

    /// `circle:45,square:35,triangle:20` — written to `game_dealt.shape_mix`.
    public var mixDescription: String {
        ShapeTraceMixShape.allCases.map { "\($0.rawValue):\(weight($0))" }.joined(separator: ",")
    }
}

/// UserDefaults store (not the reward snapshot). Missing or corrupt → defaults.
public struct ShapeTraceSettingsStore {
    public static let key = "VisaGames.shapeTraceSettings.v1"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ShapeTraceSettings {
        guard let data = defaults.data(forKey: Self.key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return .defaults }
        return payload.settings
    }

    public func save(_ settings: ShapeTraceSettings) {
        guard let data = try? JSONEncoder().encode(Payload(settings: settings)) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private struct Payload: Codable {
        var weights: [String: Int]
        var tolerance: String?
        var directionHint: Bool
        var cornerStop: Bool
        var slantLines: Bool
        var dotStyle: String

        init(settings: ShapeTraceSettings) {
            weights = Dictionary(uniqueKeysWithValues: ShapeTraceMixShape.allCases.map { ($0.rawValue, settings.weight($0)) })
            tolerance = settings.tolerance?.rawValue
            directionHint = settings.directionHint
            cornerStop = settings.cornerStop
            slantLines = settings.slantLines
            dotStyle = settings.dotStyle.rawValue
        }

        var settings: ShapeTraceSettings {
            var parsed: [ShapeTraceMixShape: Int] = [:]
            for (raw, value) in weights {
                if let shape = ShapeTraceMixShape(rawValue: raw) { parsed[shape] = value }
            }
            return ShapeTraceSettings(weights: parsed, tolerance: tolerance.flatMap(LineMatchTolerance.init(rawValue:)),
                                      directionHint: directionHint, cornerStop: cornerStop, slantLines: slantLines,
                                      dotStyle: ShapeTraceDotStyle(rawValue: dotStyle) ?? .dots)
        }
    }
}

// MARK: - Playtest before stars (D11)

/// Which cards a parent has played through in 試玩, and when (D11: the shape-trace cards cannot
/// get a star before one full playtest). UserDefaults, not the reward snapshot.
public struct ParentPlaytestLog: Equatable, Sendable {
    public private(set) var dates: [ActivityKind: Date]

    public init(dates: [ActivityKind: Date] = [:]) {
        self.dates = dates
    }

    public func playtestedOn(_ kind: ActivityKind) -> Date? { dates[kind] }

    /// False only for a card that needs a playtest first and has not had one.
    public func allowsStars(for kind: ActivityKind) -> Bool {
        !kind.requiresPlaytestBeforeStars || dates[kind] != nil
    }

    public func recording(_ kind: ActivityKind, on date: Date) -> ParentPlaytestLog {
        var copy = self
        copy.dates[kind] = date
        return copy
    }

    public static let needsPlaytestBanner = "試玩一次先開 / Playtest once before turning on a star"
}

public struct ParentPlaytestLogStore {
    public static let key = "VisaGames.playtestedKinds.v1"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ParentPlaytestLog {
        guard let data = defaults.data(forKey: Self.key),
              let raw = try? JSONDecoder().decode([String: Double].self, from: data) else { return ParentPlaytestLog() }
        var dates: [ActivityKind: Date] = [:]
        for (key, value) in raw {
            if let kind = ActivityKind(rawValue: key) { dates[kind] = Date(timeIntervalSince1970: value) }
        }
        return ParentPlaytestLog(dates: dates)
    }

    public func save(_ log: ParentPlaytestLog) {
        let raw = Dictionary(uniqueKeysWithValues: log.dates.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

// MARK: - Generator

public enum ShapeTraceGenerator {
    /// 畫直線 lanes are 100u; 跟虛線 lanes are 80u (design §2.3, §3).
    public static let lineLaneWidth: Double = 100
    public static let dottedLaneWidth: Double = 80

    // 畫直線 · fire station (mockup 01). Each line has three variants.
    public static let acrossStartXs: [Double] = [326, 376, 426]
    public static let acrossYs: [Double] = [200, 214]
    public static let acrossEndX: Double = 918
    public static let downXs: [Double] = [150, 170, 190]
    public static let downTop: Double = 204
    public static let downBottom: Double = 458
    public static let lowStartXs: [Double] = [500, 530, 560]
    public static let lowY: Double = 478
    public static let lowEndX: Double = 1010
    public static let slantShifts: [Double] = [-16, 0, 16]
    public static let slantStart = LineMatchPoint(x: 612, y: 344)
    public static let slantEnd = LineMatchPoint(x: 792, y: 470)

    // 跟虛線 scenes (mockups 02, 03, 04).
    public static let sceneShifts: [Double] = [-24, 0, 24]
    public static let slotChoices: [[Int]] = [[0], [1], [0, 1]]

    /// Reference item (placeholder before the first deal; per-kind perf facts).
    public static func reference(kind: ActivityKind) -> ShapeTraceQuestion {
        switch kind {
        case .traceShapesDotted:
            return dotted(seed: "reference", mix: .square, big: true, shift: 0, slots: [0, 1])
        case .traceShapesArrows, .traceShapesFree:
            return garage(level: level(for: kind), featured: nil, car: .flagCar, big: true, shift: 1)
        default:
            return lines(acrossX: 0, acrossY: 0, down: 1, third: 0, slant: false)
        }
    }

    /// Pinned scaffold level (design §6 `shapeTraceLevel`).
    public static func level(for kind: ActivityKind) -> ActivityLevel {
        switch kind {
        case .traceShapesArrows: return .l2
        case .traceShapesFree: return .l3
        default: return .l1
        }
    }

    public static func make(seed: String, kind: ActivityKind, settings: ShapeTraceSettings = .defaults,
                            avoidingItem: String? = nil) -> ShapeTraceQuestion {
        var question = build(seed: seed, kind: kind, settings: settings)
        guard let avoidingItem else { return question }
        var attempt = 0
        while question.itemID == avoidingItem, attempt < QuestionGeneration.maxRerolls {
            attempt += 1
            question = build(seed: "\(seed)#\(attempt)", kind: kind, settings: settings)
        }
        return question
    }

    static func build(seed: String, kind: ActivityKind, settings: ShapeTraceSettings) -> ShapeTraceQuestion {
        var rng = QuestionRNG(seed: seed, salt: kind.rawValue)
        switch kind {
        case .traceShapesDotted:
            let mix = pickMix(&rng, settings: settings)
            let big = rng.below(2) == 0
            let shift = rng.pick(sceneShifts.indices.map { $0 })
            let slots = rng.pick(slotChoices)
            return dotted(seed: seed, mix: mix, big: big, shift: shift, slots: slots)
        case .traceShapesArrows, .traceShapesFree:
            let tier = level(for: kind)
            let featured = pickMix(&rng, settings: settings)
            if rng.below(3) == 0 {
                let car = rng.pick(ShapeTraceCar.allCases)
                return garage(level: tier, featured: featured, car: car, big: rng.below(2) == 0, shift: rng.below(3))
            }
            switch featured {
            case .circle:
                return snowTown(level: tier, subset: rng.below(snowSubsets.count), size: rng.below(3),
                                shift: rng.below(sceneShifts.count))
            case .square:
                return castleHall(level: tier, size: rng.below(3), row: rng.below(hallRows.count))
            case .triangle:
                return castleKeep(level: tier, heights: [rng.below(3), rng.below(3), rng.below(3)])
            }
        default:
            let acrossX = rng.below(acrossStartXs.count)
            let acrossY = rng.below(acrossYs.count)
            let down = rng.below(downXs.count)
            let third = rng.below(3)
            return lines(acrossX: acrossX, acrossY: acrossY, down: down, third: third, slant: settings.slantLines)
        }
    }

    /// Weighted draw over the parent's shape mix.
    static func pickMix(_ rng: inout QuestionRNG, settings: ShapeTraceSettings) -> ShapeTraceMixShape {
        let weights = ShapeTraceMixShape.allCases.map { (shape: $0, weight: settings.weight($0)) }
        let total = weights.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return .circle }
        var roll = rng.below(total)
        for entry in weights {
            if roll < entry.weight { return entry.shape }
            roll -= entry.weight
        }
        return .circle
    }

    // MARK: 畫直線 · 熱身 (fire station)

    static func lines(acrossX: Int, acrossY: Int, down: Int, third: Int, slant: Bool) -> ShapeTraceQuestion {
        let y = acrossYs[acrossY]
        let ax = acrossStartXs[acrossX]
        let across = ShapeTraceShape(
            slot: "across", kind: .across,
            strokes: [.line(LineMatchPoint(x: ax, y: y), LineMatchPoint(x: acrossEndX, y: y))],
            colorIndex: 0, frame: LineMatchRect(x: ax - 30, y: y - 50, width: acrossEndX + 34 - (ax - 30), height: 100))
        let dx = downXs[down]
        let downShape = ShapeTraceShape(
            slot: "down", kind: .down,
            strokes: [.line(LineMatchPoint(x: dx, y: downTop), LineMatchPoint(x: dx, y: downBottom))],
            colorIndex: 3, frame: LineMatchRect(x: dx - 50, y: downTop - 32, width: 100, height: downBottom - downTop + 60))
        let thirdShape: ShapeTraceShape
        let thirdCode: String
        if slant {
            let s = slantShifts[third]
            let len = slantStart.distance(to: slantEnd)
            let ux = (slantEnd.x - slantStart.x) / len, uy = (slantEnd.y - slantStart.y) / len
            let a = LineMatchPoint(x: slantStart.x + ux * s, y: slantStart.y + uy * s)
            let b = LineMatchPoint(x: slantEnd.x + ux * s, y: slantEnd.y + uy * s)
            thirdShape = ShapeTraceShape(slot: "slant", kind: .slant, strokes: [.line(a, b)], colorIndex: 4,
                                         frame: LineMatchRect(x: a.x - 50, y: a.y - 50, width: b.x - a.x + 100,
                                                              height: b.y - a.y + 100))
            thirdCode = "s\(third + 1)"
        } else {
            let lx = lowStartXs[third]
            thirdShape = ShapeTraceShape(
                slot: "low", kind: .across,
                strokes: [.line(LineMatchPoint(x: lx, y: lowY), LineMatchPoint(x: lowEndX, y: lowY))],
                colorIndex: 4, frame: LineMatchRect(x: lx - 30, y: lowY - 50, width: lowEndX + 34 - (lx - 30), height: 100))
            thirdCode = "l\(third + 1)"
        }
        let item = "traceLines.fireStation.across-down-\(slant ? "slant" : "across").a\(acrossX + 1)y\(acrossY + 1)-d\(down + 1)-\(thirdCode)"
        return ShapeTraceQuestion(
            itemID: item, kind: .traceLines, level: .l1, scene: .fireStation, shift: 0, big: true, slant: slant,
            shapes: [across, downShape, thirdShape], laneWidth: lineLaneWidth, promptKey: "traceLines.prompt",
            promptTraditionalChinese: ShapeTraceCopy.linesPromptTraditionalChinese,
            promptEnglish: ShapeTraceCopy.linesPromptEnglish)
    }

    // MARK: 畫形狀 · 跟虛線 (castle towers / castle windows / snow town)

    static func dotted(seed: String, mix: ShapeTraceMixShape, big: Bool, shift shiftIndex: Int,
                       slots: [Int]) -> ShapeTraceQuestion {
        let shift = sceneShifts[min(max(shiftIndex, 0), sceneShifts.count - 1)]
        let scene: ShapeTraceScene
        var shapes: [ShapeTraceShape] = []
        let prompt: (key: String, zh: String, en: String)
        switch mix {
        case .triangle:
            scene = .castleTowers
            prompt = ("shapes.prompt.spire", ShapeTraceCopy.spirePromptTraditionalChinese, ShapeTraceCopy.spirePromptEnglish)
            for slot in slots { shapes.append(spire(slot: slot, big: big, shift: shift)) }
        case .square:
            scene = .castleWindows
            prompt = ("shapes.prompt.square", ShapeTraceCopy.squarePromptTraditionalChinese, ShapeTraceCopy.squarePromptEnglish)
            for slot in slots { shapes.append(window(slot: slot, big: big, shift: shift)) }
        case .circle:
            scene = .snowTown
            prompt = ("shapes.prompt.circle", ShapeTraceCopy.circlePromptTraditionalChinese, ShapeTraceCopy.circlePromptEnglish)
            for slot in slots { shapes.append(snowCircle(slot: slot, big: big, shift: shift)) }
        }
        shapes.sort { $0.frame.x < $1.frame.x }
        let slotCode = shapes.map(\.slot).joined(separator: "-")
        let item = "traceShapes.L1.\(scene.rawValue).\(slotCode).\(big ? "big" : "mid").x\(shiftIndex + 1)"
        return ShapeTraceQuestion(
            itemID: item, kind: .traceShapesDotted, level: .l1, scene: scene, shift: shift, big: big, slant: false,
            shapes: shapes, laneWidth: dottedLaneWidth, promptKey: prompt.key,
            promptTraditionalChinese: prompt.zh, promptEnglish: prompt.en)
    }

    /// Tower spire ∧ (★: two strokes from the apex; the tower top is the base). Slot 0 = left
    /// tower (base 145–355 at y 430), slot 1 = middle tower (535–745 at y 380). Mockup 02.
    public static func spire(slot: Int, big: Bool, shift: Double) -> ShapeTraceShape {
        let base: (left: Double, right: Double, y: Double) = slot == 0 ? (145, 355, 430) : (535, 745, 380)
        let height: Double = big ? 200 : 180
        let apex = LineMatchPoint(x: (base.left + base.right) / 2 + shift, y: base.y - height)
        let left = LineMatchPoint(x: base.left + shift, y: base.y)
        let right = LineMatchPoint(x: base.right + shift, y: base.y)
        return ShapeTraceShape(slot: slot == 0 ? "spireA" : "spireB", kind: .spire,
                               strokes: [.line(apex, left), .line(apex, right)],
                               colorIndex: slot == 0 ? 0 : 1,
                               frame: LineMatchRect(x: left.x, y: apex.y, width: right.x - left.x, height: height))
    }

    /// Castle window 口: ① 丨 left side down, ② 𠃍 top across then right side down, ③ 一 bottom.
    /// Slot 0 = window A (x 250), slot 1 = window B (x 740), side 200 (big) or 180. Mockup 04.
    public static func window(slot: Int, big: Bool, shift: Double) -> ShapeTraceShape {
        let side: Double = big ? 200 : 180
        let inset = (200 - side) / 2
        let x0 = (slot == 0 ? 250 : 740) + inset + shift
        let y0 = 244 + inset
        let x1 = x0 + side, y1 = y0 + side
        let tl = LineMatchPoint(x: x0, y: y0), tr = LineMatchPoint(x: x1, y: y0)
        let bl = LineMatchPoint(x: x0, y: y1), br = LineMatchPoint(x: x1, y: y1)
        return ShapeTraceShape(slot: slot == 0 ? "windowA" : "windowB", kind: .square,
                               strokes: [.line(tl, bl), .polyline([tl, tr, br]), .line(bl, br)],
                               colorIndex: slot == 0 ? 0 : 3,
                               frame: LineMatchRect(x: x0, y: y0, width: side, height: side))
    }

    /// Snow town circles from 12 o'clock, anticlockwise. Slot 0 = snowman body (600, 400),
    /// slot 1 = sun (980, 272); radius 110 (big) or 100. Mockup 03.
    public static func snowCircle(slot: Int, big: Bool, shift: Double) -> ShapeTraceShape {
        let r: Double = big ? 110 : 100
        let center = slot == 0 ? LineMatchPoint(x: 600 + shift, y: 400) : LineMatchPoint(x: 980 + shift, y: 272)
        return ShapeTraceShape(slot: slot == 0 ? "body" : "sun", kind: .circle,
                               strokes: [.circle(center: center, radius: r)],
                               colorIndex: slot == 0 ? 4 : 2,
                               frame: LineMatchRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    }

    // MARK: 畫形狀 · 跟箭嘴 / 自己畫 (★★ / ★★★; design §4.1–4.3)

    /// ★★ / ★★★ judged lane (design §2.3: 64u × tolerance; nothing is drawn at that width).
    public static let outlinedLaneWidth: Double = 64

    /// Snow-town slot sets, in mockup 03 order (① sun ② body ③ head ④ clock).
    public static let snowSubsets: [[String]] = [
        ["sun", "body", "head", "clock"], ["sun", "body", "head"], ["body", "head", "clock"],
        ["sun", "body", "clock"], ["sun", "head", "clock"]
    ]
    public static let snowSunRadii: [Double] = [64, 70, 76]
    public static let snowBodyRadii: [Double] = [80, 88, 94]
    public static let snowHeadRadii: [Double] = [48, 52, 56]
    public static let snowClockRadii: [Double] = [50, 54, 58]
    /// Room between head and body for the scarf.
    public static let snowNeck: Double = 56
    public static let snowBodyCenterY: Double = 446
    public static let churchClockCenter = LineMatchPoint(x: 205, y: 300)

    /// One snow-town circle at ★★ / ★★★ (also used to draw an undrawn slot as scenery).
    public static func snowShape(slot: String, size: Int, shift: Double) -> ShapeTraceShape {
        let i = min(max(size, 0), 2)
        let bodyR = snowBodyRadii[i]
        let center: LineMatchPoint
        let r: Double
        let color: Int
        switch slot {
        case "sun":
            center = LineMatchPoint(x: 990 + shift, y: 250); r = snowSunRadii[i]; color = 2
        case "head":
            r = snowHeadRadii[i]
            center = LineMatchPoint(x: 600 + shift, y: snowBodyCenterY - bodyR - snowNeck - r); color = 1
        case "clock":
            center = churchClockCenter; r = snowClockRadii[i]; color = 3
        default:
            center = LineMatchPoint(x: 600 + shift, y: snowBodyCenterY); r = bodyR; color = 4
        }
        return ShapeTraceShape(slot: slot, kind: .circle, strokes: [.circle(center: center, radius: r)], colorIndex: color,
                               frame: LineMatchRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    }

    static func snowTown(level: ActivityLevel, subset: Int, size: Int, shift shiftIndex: Int) -> ShapeTraceQuestion {
        let slots = snowSubsets[min(max(subset, 0), snowSubsets.count - 1)]
        let shift = sceneShifts[min(max(shiftIndex, 0), sceneShifts.count - 1)]
        let shapes = slots.map { snowShape(slot: $0, size: size, shift: shift) }
        let free = level == .l3
        return ShapeTraceQuestion(
            itemID: "traceShapes.\(level.code).snowTown.\(slots.joined(separator: "-")).s\(size + 1).x\(shiftIndex + 1)",
            kind: kind(for: level), level: level, scene: .snowTown, shift: shift, big: size == 2, slant: false,
            shapes: shapes, laneWidth: outlinedLaneWidth, promptKey: free ? "shapes.prompt.free.circle" : "shapes.prompt.circle",
            promptTraditionalChinese: free ? ShapeTraceCopy.freeCirclePromptTraditionalChinese : ShapeTraceCopy.circlePromptTraditionalChinese,
            promptEnglish: free ? ShapeTraceCopy.freeCirclePromptEnglish : ShapeTraceCopy.circlePromptEnglish,
            featured: .circle, size: size)
    }

    /// Mockup 06 towers: (left, right, base y, apex x) and three roof heights each.
    public static let keepTowers: [(left: Double, right: Double, base: Double, apex: Double)] = [
        (145, 355, 432, 250), (535, 745, 382, 640), (880, 1050, 402, 965)
    ]
    public static let keepHeights: [[Double]] = [[150, 165, 180], [160, 175, 190], [130, 145, 160]]

    /// Tower roof ▲ in three strokes: ① 撇 apex → bottom left, ② 捺 apex → bottom right, ③ 一 base.
    public static func keepRoof(tower: Int, height: Int) -> ShapeTraceShape {
        let t = keepTowers[tower]
        let h = keepHeights[tower][min(max(height, 0), 2)]
        let apex = LineMatchPoint(x: t.apex, y: t.base - h)
        let left = LineMatchPoint(x: t.left, y: t.base)
        let right = LineMatchPoint(x: t.right, y: t.base)
        return ShapeTraceShape(slot: ["spireA", "spireB", "spireC"][tower], kind: .triangle,
                               strokes: [.line(apex, left), .line(apex, right), .line(left, right)],
                               colorIndex: [3, 1, 0][tower],
                               frame: LineMatchRect(x: t.left, y: apex.y, width: t.right - t.left, height: h))
    }

    static func castleKeep(level: ActivityLevel, heights: [Int]) -> ShapeTraceQuestion {
        let shapes = (0..<3).map { keepRoof(tower: $0, height: heights[$0]) }
        let free = level == .l3
        return ShapeTraceQuestion(
            itemID: "traceShapes.\(level.code).castleKeep.spireA-spireB-spireC.h\(heights.map { String($0 + 1) }.joined())",
            kind: kind(for: level), level: level, scene: .castleKeep, shift: 0, big: true, slant: false,
            shapes: shapes, laneWidth: outlinedLaneWidth, promptKey: free ? "shapes.prompt.free" : "shapes.prompt.spire",
            promptTraditionalChinese: free ? ShapeTraceCopy.freeSpirePromptTraditionalChinese : ShapeTraceCopy.spirePromptTraditionalChinese,
            promptEnglish: free ? ShapeTraceCopy.freeSpirePromptEnglish : ShapeTraceCopy.spirePromptEnglish,
            featured: .triangle, size: 1)
    }

    /// Facade windows (mockup 04 castle): three in a row, centred on these x; sides 150–170.
    public static let hallCenters: [Double] = [330, 640, 950]
    public static let hallSides: [Double] = [150, 160, 170]
    public static let hallRows: [Double] = [214, 224, 234]

    public static func hallWindow(_ index: Int, size: Int, row: Int) -> ShapeTraceShape {
        let side = hallSides[min(max(size, 0), 2)]
        let x0 = hallCenters[index] - side / 2
        let y0 = hallRows[min(max(row, 0), hallRows.count - 1)]
        let x1 = x0 + side, y1 = y0 + side
        let tl = LineMatchPoint(x: x0, y: y0), tr = LineMatchPoint(x: x1, y: y0)
        let bl = LineMatchPoint(x: x0, y: y1), br = LineMatchPoint(x: x1, y: y1)
        return ShapeTraceShape(slot: ["windowA", "windowB", "windowC"][index], kind: .square,
                               strokes: [.line(tl, bl), .polyline([tl, tr, br]), .line(bl, br)],
                               colorIndex: [0, 3, 4][index], frame: LineMatchRect(x: x0, y: y0, width: side, height: side))
    }

    static func castleHall(level: ActivityLevel, size: Int, row: Int) -> ShapeTraceQuestion {
        let shapes = (0..<3).map { hallWindow($0, size: size, row: row) }
        let free = level == .l3
        return ShapeTraceQuestion(
            itemID: "traceShapes.\(level.code).castleHall.windowA-windowB-windowC.s\(size + 1).y\(row + 1)",
            kind: kind(for: level), level: level, scene: .castleHall, shift: 0, big: size == 2, slant: false,
            shapes: shapes, laneWidth: outlinedLaneWidth, promptKey: free ? "shapes.prompt.free.square" : "shapes.prompt.square",
            promptTraditionalChinese: free ? ShapeTraceCopy.freeSquarePromptTraditionalChinese : ShapeTraceCopy.squarePromptTraditionalChinese,
            promptEnglish: free ? ShapeTraceCopy.freeSquarePromptEnglish : ShapeTraceCopy.squarePromptEnglish,
            featured: .square, size: size)
    }

    /// 砌車仔 (mockup 05). Body 口 bottom at y 376, wheels r 50 at y 476, topper on a pole 40u
    /// behind the body. Order: body → back wheel → front wheel → topper (design §4.1).
    public static let garageShifts: [Double] = [-30, 0, 30]
    public static let carBodyBottom: Double = 376
    public static let wheelCenterY: Double = 476
    public static let wheelRadius: Double = 50

    public static func carPoleX(big: Bool, shift: Double) -> Double { 400 + shift - 40 }

    public static func carShapes(car: ShapeTraceCar, big: Bool, shift: Double) -> [ShapeTraceShape] {
        let side: Double = big ? 190 : 170
        let x0 = 400 + shift
        let y1 = carBodyBottom, y0 = y1 - side
        let x1 = x0 + side
        let tl = LineMatchPoint(x: x0, y: y0), tr = LineMatchPoint(x: x1, y: y0)
        let bl = LineMatchPoint(x: x0, y: y1), br = LineMatchPoint(x: x1, y: y1)
        let body = ShapeTraceShape(slot: "carBody", kind: .square,
                                   strokes: [.line(tl, bl), .polyline([tl, tr, br]), .line(bl, br)], colorIndex: 4,
                                   frame: LineMatchRect(x: x0, y: y0, width: side, height: side))
        func wheel(_ slot: String, _ cx: Double, _ color: Int) -> ShapeTraceShape {
            let c = LineMatchPoint(x: cx, y: wheelCenterY)
            return ShapeTraceShape(slot: slot, kind: .circle, strokes: [.circle(center: c, radius: wheelRadius)],
                                   colorIndex: color,
                                   frame: LineMatchRect(x: cx - wheelRadius, y: wheelCenterY - wheelRadius,
                                                        width: 2 * wheelRadius, height: 2 * wheelRadius))
        }
        let back = wheel("backWheel", x0 + 10, 0)
        let front = wheel("frontWheel", x1 - 10, 0)
        let pole = carPoleX(big: big, shift: shift)
        let topper: ShapeTraceShape
        switch car {
        case .flagCar:
            let top = LineMatchPoint(x: pole, y: 160), tip = LineMatchPoint(x: pole - 84, y: 194)
            let bottom = LineMatchPoint(x: pole, y: 228)
            topper = ShapeTraceShape(slot: "flag", kind: .pennant, strokes: [.polyline([top, tip, bottom])], colorIndex: 2,
                                     frame: LineMatchRect(x: tip.x, y: top.y, width: pole - tip.x, height: bottom.y - top.y))
        case .sailCar:
            let apex = LineMatchPoint(x: pole - 70, y: 170)
            let left = LineMatchPoint(x: pole - 140, y: 330), right = LineMatchPoint(x: pole, y: 330)
            topper = ShapeTraceShape(slot: "sail", kind: .triangle,
                                     strokes: [.line(apex, left), .line(apex, right), .line(left, right)], colorIndex: 1,
                                     frame: LineMatchRect(x: left.x, y: apex.y, width: right.x - left.x, height: left.y - apex.y))
        case .coneCar:
            let a = LineMatchPoint(x: pole - 130, y: 200), b = LineMatchPoint(x: pole - 10, y: 200)
            let tip = LineMatchPoint(x: pole - 70, y: 340)
            topper = ShapeTraceShape(slot: "cone", kind: .cone, strokes: [.line(a, b), .line(a, tip), .line(b, tip)],
                                     colorIndex: 2, frame: LineMatchRect(x: a.x, y: a.y, width: b.x - a.x, height: tip.y - a.y))
        }
        return [body, back, front, topper]
    }

    static func garage(level: ActivityLevel, featured: ShapeTraceMixShape?, car: ShapeTraceCar, big: Bool,
                       shift shiftIndex: Int) -> ShapeTraceQuestion {
        let shift = garageShifts[min(max(shiftIndex, 0), garageShifts.count - 1)]
        let free = level == .l3
        return ShapeTraceQuestion(
            itemID: "traceShapes.\(level.code).garage.\(car.rawValue).\(big ? "big" : "mid").x\(shiftIndex + 1)",
            kind: kind(for: level), level: level, scene: .garage, shift: shift, big: big, slant: false,
            shapes: carShapes(car: car, big: big, shift: shift), laneWidth: outlinedLaneWidth,
            promptKey: free ? "shapes.prompt.free.build" : "shapes.prompt.build",
            promptTraditionalChinese: ShapeTraceCopy.buildPromptTraditionalChinese(car, free: free),
            promptEnglish: ShapeTraceCopy.buildPromptEnglish(car, free: free),
            featured: featured, car: car, size: big ? 2 : 1)
    }

    static func kind(for level: ActivityLevel) -> ActivityKind {
        switch level {
        case .l1: return .traceShapesDotted
        case .l2: return .traceShapesArrows
        case .l3: return .traceShapesFree
        }
    }

    /// Every item a kind can deal (tests: counts, well-formedness).
    public static func allItems(kind: ActivityKind, slant: Bool = false) -> [ShapeTraceQuestion] {
        switch kind {
        case .traceShapesDotted:
            var result: [ShapeTraceQuestion] = []
            for mix in ShapeTraceMixShape.allCases {
                for big in [true, false] {
                    for shift in sceneShifts.indices {
                        for slots in slotChoices {
                            result.append(dotted(seed: "all", mix: mix, big: big, shift: shift, slots: slots))
                        }
                    }
                }
            }
            return result
        case .traceShapesArrows, .traceShapesFree:
            let tier = level(for: kind)
            var result: [ShapeTraceQuestion] = []
            for subset in snowSubsets.indices {
                for size in 0..<3 {
                    for shift in sceneShifts.indices {
                        result.append(snowTown(level: tier, subset: subset, size: size, shift: shift))
                    }
                }
            }
            for a in 0..<3 {
                for b in 0..<3 {
                    for c in 0..<3 { result.append(castleKeep(level: tier, heights: [a, b, c])) }
                }
            }
            for size in 0..<3 {
                for row in hallRows.indices { result.append(castleHall(level: tier, size: size, row: row)) }
            }
            for car in ShapeTraceCar.allCases {
                for big in [true, false] {
                    for shift in garageShifts.indices {
                        result.append(garage(level: tier, featured: nil, car: car, big: big, shift: shift))
                    }
                }
            }
            return result
        default:
            var result: [ShapeTraceQuestion] = []
            for a in acrossStartXs.indices {
                for y in acrossYs.indices {
                    for d in downXs.indices {
                        for t in 0..<3 { result.append(lines(acrossX: a, acrossY: y, down: d, third: t, slant: slant)) }
                    }
                }
            }
            return result
        }
    }
}

// MARK: - Child copy (HK Traditional + ASCII English; design §3, §4.4)

public enum ShapeTraceCopy {
    public static let linesPromptTraditionalChinese = "由綠色箭嘴畫去紅色箭嘴！"
    public static let linesPromptEnglish = "Draw from the green arrow to the red arrow!"
    public static let circlePromptTraditionalChinese = "畫圓圈！由綠色箭嘴開始，轉一個圈"
    public static let circlePromptEnglish = "Draw the circles! Start at the green arrow and go round."
    public static let squarePromptTraditionalChinese = "畫窗！到角位停一停，再轉彎"
    public static let squarePromptEnglish = "Draw the windows! Stop at each corner, then turn."
    public static let spirePromptTraditionalChinese = "畫尖頂！由綠色箭嘴畫去紅色箭嘴"
    public static let spirePromptEnglish = "Draw the pointy roofs, from green arrow to red arrow!"
    public static let hint = "提示：由綠色箭嘴開始，跟住條線畫。 / Hint: start at the green arrow and follow the line."

    // ★★★ 自己畫 prompts and 砌車仔 (design §4.4).
    public static let freeCirclePromptTraditionalChinese = "自己畫圓圈！由綠色箭嘴開始"
    public static let freeCirclePromptEnglish = "Draw the circles yourself! Start at the green arrow."
    public static let freeSquarePromptTraditionalChinese = "自己畫窗！由綠色箭嘴開始"
    public static let freeSquarePromptEnglish = "Draw the windows yourself! Start at the green arrow."
    public static let freeSpirePromptTraditionalChinese = "自己畫尖頂！由綠色箭嘴開始"
    public static let freeSpirePromptEnglish = "Draw the roofs yourself! Start at the green arrow."
    public static func buildPromptTraditionalChinese(_ car: ShapeTraceCar, free: Bool) -> String {
        free ? "自己砌車仔！由綠色箭嘴開始" : "砌車仔！畫車身、車轆同\(car.topperTraditionalChinese)"
    }
    public static func buildPromptEnglish(_ car: ShapeTraceCar, free: Bool) -> String {
        free ? "Build the car yourself! Start at the green arrow." : "Build a car! Draw the body, the wheels and \(car.topperEnglish)."
    }
    public static let buildDoneTraditionalChinese = "砌好喇！嘟嘟，出發！"
    public static let buildDoneEnglish = "Built! Beep beep, off we go!"
    public static let buildDonePrompt = SpokenPrompt(key: "shapes.build.done", traditionalChinese: buildDoneTraditionalChinese,
                                                     english: buildDoneEnglish)
    public static let eraserNudgeTraditionalChinese = "唔使擦都得，慢慢畫就得㗎！"
    public static let eraserNudgeEnglish = "No need to clear. Just go slowly!"
    public static let eraserNudgePrompt = SpokenPrompt(key: "shapes.eraser.nudge", traditionalChinese: eraserNudgeTraditionalChinese,
                                                       english: eraserNudgeEnglish)
    public static let eraserTraditionalChinese = "擦晒"
    public static let eraserEnglish = "Clear"
    public static let modelCardTraditionalChinese = "照住畫"
    public static let modelCardEnglish = "Copy this"
    public static let todayBuildTraditionalChinese = "今日砌"
    public static let todayBuildEnglish = "Today's build"
    public static let garageSign = "砌車仔工場"
    public static let arrowsBadgeSubTraditionalChinese = "跟箭嘴 · Arrows"
    public static let freeBadgeSubTraditionalChinese = "自己畫 · Free"
    /// Model-card stroke words (「三筆：撇 捺 橫」).
    public static func strokeWords(_ kind: ShapeTraceShapeKind) -> (count: String, words: String)? {
        switch kind {
        case .triangle: return ("三筆：", "撇 捺 橫")
        case .square: return ("三筆：", "口字筆順")
        case .circle: return ("一筆：", "轉個圈")
        case .pennant: return ("一筆：", "停一停再轉")
        case .cone: return ("三筆：", "橫 捺 撇")
        case .spire: return ("兩筆：", "撇 捺")
        case .across, .down, .slant: return nil
        }
    }

    public static let linesBadgeTraditionalChinese = "畫直線"
    public static let linesBadgeSubTraditionalChinese = "熱身 · Warm-up"
    public static let shapesBadgeTraditionalChinese = "畫形狀"
    public static let shapesBadgeSubTraditionalChinese = "跟虛線 · Dots"

    public static let stopTraditionalChinese = "停！"
    public static let stopEnglish = "Stop!"
    public static let cornerTraditionalChinese = "停！轉彎！"
    public static let cornerEnglish = "Stop! Now turn."
    public static let offPathTraditionalChinese = "架車等緊你，返嚟條線度啦！"
    public static let offPathEnglish = "The car is waiting. Come back to the line!"
    public static let wrongStartTraditionalChinese = "由綠色箭嘴開始啊！"
    public static let wrongStartEnglish = "Start from the green arrow!"
    public static let reverseTraditionalChinese = "跟住箭嘴方向畫啊！"
    public static let reverseEnglish = "Follow the arrow!"
    public static let doneTraditionalChinese = "全部畫好！好叻呀！"
    public static let doneEnglish = "All drawn! Well done!"
    public static let stopSign = "停"

    public static let arriveFireStationTraditionalChinese = "消防車返到消防局喇！"
    public static let arriveFireStationEnglish = "The fire engine is home!"
    public static let arriveHookTraditionalChinese = "勾到個箱喇！"
    public static let arriveHookEnglish = "Got the box!"
    public static let arriveTaxiTraditionalChinese = "的士到站喇！"
    public static let arriveTaxiEnglish = "The taxi is here!"
    public static let fireStationLabel = "消防局"

    public static let linkCircleTraditionalChinese = "圓形好似寫 o！"
    public static let linkCircleEnglish = "A circle is like the letter o!"
    public static let linkSquareTraditionalChinese = "正方形好似「口」字！"
    public static let linkSquareEnglish = "A square is like the word for mouth!"
    public static let linkSpireTraditionalChinese = "尖頂好似「人」字！"
    public static let linkSpireEnglish = "A spire is like the word for person!"
    /// Link card glyph and its two short lines (「好似」「口字」).
    public static func linkCard(_ kind: ShapeTraceShapeKind) -> (glyph: String, top: String, bottom: String, english: String)? {
        switch kind {
        case .square: return ("口", "好似", "口字", "square = like the character for mouth")
        case .spire: return ("人", "好似", "人字", "spire = like the character for person")
        case .circle: return ("o", "好似", "寫 o", "circle = like writing o")
        case .triangle: return ("人", "好似", "人字", "triangle = like the character for person")
        case .across, .down, .slant, .pennant, .cone: return nil
        }
    }

    public static func remainingTraditionalChinese(_ n: Int, kind: ShapeTraceShapeKind?) -> String {
        switch kind {
        case .circle?: return "仲有 \(n) 個圓形"
        case .square?: return "仲有 \(n) 個正方形"
        case .spire?: return "仲有 \(n) 個尖頂"
        case .triangle?: return "仲有 \(n) 個三角形"
        case .pennant?, .cone?: return "仲有 \(n) 個形狀"
        default: return "仲有 \(n) 條線"
        }
    }

    public static func remainingEnglish(_ n: Int, kind: ShapeTraceShapeKind?) -> String {
        let noun: String
        switch kind {
        case .circle?: noun = n == 1 ? "circle" : "circles"
        case .square?: noun = n == 1 ? "square" : "squares"
        case .spire?: noun = n == 1 ? "roof" : "roofs"
        case .triangle?: noun = n == 1 ? "triangle" : "triangles"
        case .pennant?, .cone?: noun = n == 1 ? "shape" : "shapes"
        default: noun = n == 1 ? "line" : "lines"
        }
        return "\(n) more \(noun) to go"
    }

    /// Mixed rounds (砌車仔): 「仲有 N 個形狀」.
    public static func remainingShapesTraditionalChinese(_ n: Int) -> String { "仲有 \(n) 個形狀" }
    public static func remainingShapesEnglish(_ n: Int) -> String { "\(n) more \(n == 1 ? "shape" : "shapes") to go" }

    public static func link(_ kind: ShapeTraceShapeKind) -> SpokenPrompt? {
        switch kind {
        case .circle: return SpokenPrompt(key: "shapes.link.circle", traditionalChinese: linkCircleTraditionalChinese,
                                          english: linkCircleEnglish)
        case .square: return SpokenPrompt(key: "shapes.link.square", traditionalChinese: linkSquareTraditionalChinese,
                                          english: linkSquareEnglish)
        case .spire, .triangle: return SpokenPrompt(key: "shapes.link.triangle", traditionalChinese: linkSpireTraditionalChinese,
                                                    english: linkSpireEnglish)
        case .across, .down, .slant, .pennant, .cone: return nil
        }
    }

    /// 「三角形、triangle」: spoken Cantonese word then English word, and the bubble text.
    public static func cue(_ kind: ShapeTraceShapeKind) -> SpokenPrompt {
        SpokenPrompt(key: "trace.cue.\(kind.rawValue)", traditionalChinese: kind.cueTraditionalChinese,
                     english: kind.cueEnglish)
    }

    public static func bubble(_ kind: ShapeTraceShapeKind) -> String {
        "\(kind.cueTraditionalChinese)、\(kind.cueEnglish)"
    }

    /// Arrival line for a 畫直線 slot (design §2.7).
    public static func arrival(slot: String) -> SpokenPrompt? {
        switch slot {
        case "across": return SpokenPrompt(key: "traceLines.arrive.fireStation",
                                           traditionalChinese: arriveFireStationTraditionalChinese,
                                           english: arriveFireStationEnglish)
        case "down": return SpokenPrompt(key: "traceLines.arrive.hook", traditionalChinese: arriveHookTraditionalChinese,
                                         english: arriveHookEnglish)
        case "low", "slant": return SpokenPrompt(key: "traceLines.arrive.taxi", traditionalChinese: arriveTaxiTraditionalChinese,
                                                 english: arriveTaxiEnglish)
        default: return nil
        }
    }

    public static func start(_ kind: ShapeTraceShapeKind) -> SpokenPrompt? {
        guard let zh = kind.startTraditionalChinese, let en = kind.startEnglish else { return nil }
        return SpokenPrompt(key: "trace.start.\(kind.rawValue)", traditionalChinese: zh, english: en)
    }

    public static let stopPrompt = SpokenPrompt(key: "trace.stop", traditionalChinese: stopTraditionalChinese, english: stopEnglish)
    public static let cornerPrompt = SpokenPrompt(key: "shapes.corner", traditionalChinese: cornerTraditionalChinese,
                                                  english: cornerEnglish)
    public static let offPathPrompt = SpokenPrompt(key: "trace.offroad", traditionalChinese: offPathTraditionalChinese,
                                                   english: offPathEnglish)
    public static let wrongStartPrompt = SpokenPrompt(key: "trace.wrongStart", traditionalChinese: wrongStartTraditionalChinese,
                                                      english: wrongStartEnglish)
    public static let reversePrompt = SpokenPrompt(key: "trace.reverse", traditionalChinese: reverseTraditionalChinese,
                                                   english: reverseEnglish)
    public static let donePrompt = SpokenPrompt(key: "trace.done", traditionalChinese: doneTraditionalChinese,
                                                english: doneEnglish)

    // Parent copy.
    public static let settingsTitle = "畫形狀設定"
    public static let settingsSubtitle = "Lines & Shapes settings · 畫線畫形卡共用；每張卡要試玩一次先開到星級 / shared by the Lines & Shapes cards; playtest each card once before turning on a star"
    public static let parentTip = "每日用蠟筆喺紙上畫一次同樣嘅形狀；先用手指喺板上描一次都好。 / Each day, draw the same shape once with a crayon on paper; tracing it once on the tablet with a finger first helps too."
    public static let notPlaytested = "未試玩 / Not playtested"
    public static func playtested(_ date: String) -> String { "✓ 試玩咗 \(date) / Playtested" }
    public static let toleranceFollow = "跟連一連"
    public static let toleranceFollowEnglish = "Same as Line Match"

    public static var allTraditionalLines: [String] {
        var lines = [linesPromptTraditionalChinese, circlePromptTraditionalChinese, squarePromptTraditionalChinese,
                     spirePromptTraditionalChinese, hint.components(separatedBy: " / ").first ?? "",
                     linesBadgeTraditionalChinese, shapesBadgeTraditionalChinese, stopTraditionalChinese,
                     cornerTraditionalChinese, offPathTraditionalChinese, wrongStartTraditionalChinese,
                     reverseTraditionalChinese, doneTraditionalChinese, stopSign, arriveFireStationTraditionalChinese,
                     arriveHookTraditionalChinese, arriveTaxiTraditionalChinese, fireStationLabel,
                     linkCircleTraditionalChinese, linkSquareTraditionalChinese, linkSpireTraditionalChinese,
                     settingsTitle, settingsSubtitle, parentTip, notPlaytested, playtested("10/17"), toleranceFollow,
                     ParentPlaytestLog.needsPlaytestBanner, freeCirclePromptTraditionalChinese,
                     freeSquarePromptTraditionalChinese, freeSpirePromptTraditionalChinese, buildDoneTraditionalChinese,
                     eraserNudgeTraditionalChinese, eraserTraditionalChinese, modelCardTraditionalChinese,
                     todayBuildTraditionalChinese, garageSign, arrowsBadgeSubTraditionalChinese,
                     freeBadgeSubTraditionalChinese, remainingShapesTraditionalChinese(3)]
        for car in ShapeTraceCar.allCases {
            lines += [car.topperTraditionalChinese, buildPromptTraditionalChinese(car, free: false),
                      buildPromptTraditionalChinese(car, free: true)]
        }
        for kind in ShapeTraceShapeKind.allCases {
            lines.append(kind.cueTraditionalChinese)
            lines.append(remainingTraditionalChinese(2, kind: kind))
            if let start = kind.startTraditionalChinese { lines.append(start) }
            if let card = linkCard(kind) { lines += [card.glyph, card.top, card.bottom] }
            if let words = strokeWords(kind) { lines += [words.count, words.words] }
        }
        for shape in ShapeTraceMixShape.allCases { lines.append(shape.titleTraditionalChinese) }
        for style in ShapeTraceDotStyle.allCases { lines.append(style.labelTraditionalChinese) }
        return lines
    }

    public static var allEnglishLines: [String] {
        var lines = [linesPromptEnglish, circlePromptEnglish, squarePromptEnglish, spirePromptEnglish,
                     hint.components(separatedBy: " / ").last ?? "", stopEnglish, cornerEnglish, offPathEnglish,
                     wrongStartEnglish, reverseEnglish, doneEnglish, arriveFireStationEnglish, arriveHookEnglish,
                     arriveTaxiEnglish, linkCircleEnglish, linkSquareEnglish, linkSpireEnglish, toleranceFollowEnglish,
                     freeCirclePromptEnglish, freeSquarePromptEnglish, freeSpirePromptEnglish, buildDoneEnglish,
                     eraserNudgeEnglish, eraserEnglish, modelCardEnglish, todayBuildEnglish, remainingShapesEnglish(1),
                     remainingShapesEnglish(3)]
        for car in ShapeTraceCar.allCases {
            lines += [car.topperEnglish, buildPromptEnglish(car, free: false), buildPromptEnglish(car, free: true)]
        }
        for kind in ShapeTraceShapeKind.allCases {
            lines.append(kind.cueEnglish)
            lines.append(remainingEnglish(1, kind: kind))
            lines.append(remainingEnglish(2, kind: kind))
            if let start = kind.startEnglish { lines.append(start) }
            if let card = linkCard(kind) { lines.append(card.english) }
        }
        return lines
    }
}
