import Foundation

// 一架一架數 / Tap & Count content (v0.28.0, design number-quantity §2–§10, ADR 0017).
// Three independent cards: ★ 點一點 (`tapCountAll`), ★★ 數完畫 (`tapCountTrace`), ★★★ 揀啱數
// (`tapCountPick`). One numeral per round (Q1). Scenes and vehicles follow the Opus mockups 01–08;
// geometry lives here, art in `TapCountArt`.

// MARK: - Numbers

public enum TapCountNumber {
    public static let traditionalChinese = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
    public static let english = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]

    public static func zh(_ n: Int) -> String { traditionalChinese.indices.contains(n) ? traditionalChinese[n] : String(n) }
    public static func en(_ n: Int) -> String { english.indices.contains(n) ? english[n] : String(n) }
    public static func enCapitalised(_ n: Int) -> String { en(n).prefix(1).uppercased() + en(n).dropFirst() }
}

// MARK: - Scenes and vehicles

/// Where a round happens (design §2.3). v1 builds the five scenes the mockups draw; the taxi rank,
/// MTR depot, rocket base and pier wait for their art (design §12 N4).
public enum TapCountScene: String, CaseIterable, Sendable, Codable, Hashable {
    /// 電車廠 (mockups 01, 02): trams.
    case tramDepot
    /// 消防局 (mockups 03, 04): fire engines.
    case fireStation
    /// 地盤 (mockups 05, 06): diggers; ★★★ mixes the whole site fleet.
    case site
    /// 機場 (mockup 07): planes.
    case airport
    /// 巴士總站 (mockup 08): buses.
    case busTerminus

    /// The one vehicle of ★ / ★★ rounds.
    public var vehicle: TapCountModel {
        switch self {
        case .tramDepot: return .tram
        case .fireStation: return .fireEngine
        case .site: return .digger
        case .airport: return .plane
        case .busTerminus: return .bus
        }
    }

    /// ★★★ fleet (design §7.4). Scenes without more drawn models use colour variety only.
    public var fleet: [TapCountModel] {
        switch self {
        case .site: return [.digger, .dumper, .mixer, .dozer, .roller, .craneTruck]
        default: return [vehicle]
        }
    }

    /// 「點一點每架叮叮！」 vehicle word.
    public var vehicleTraditionalChinese: String {
        switch self {
        case .tramDepot: return "叮叮"
        case .fireStation: return "消防車"
        case .site: return "挖泥車"
        case .airport: return "飛機"
        case .busTerminus: return "巴士"
        }
    }

    public var vehicleEnglishSingular: String {
        switch self {
        case .tramDepot: return "tram"
        case .fireStation: return "fire engine"
        case .site: return "digger"
        case .airport: return "plane"
        case .busTerminus: return "bus"
        }
    }

    public var vehicleEnglishPlural: String {
        switch self {
        case .busTerminus: return "buses"
        default: return vehicleEnglishSingular + "s"
        }
    }

    /// Classifier (Q9: 架 for every v1 scene).
    public var classifier: String { "架" }

    /// Sign over the scene (mockups 01 「電車廠」, 08 「巴士總站」; drawn by the app, never in the art).
    public var signTraditionalChinese: String {
        switch self {
        case .tramDepot: return "電車廠"
        case .fireStation: return "消防局"
        case .site: return "地盤"
        case .airport: return "機場"
        case .busTerminus: return "巴士總站"
        }
    }
}

/// A drawn vehicle model (mockup `<defs>` ids in comments).
public enum TapCountModel: String, CaseIterable, Sendable, Codable, Hashable {
    case tram          // #tram (01)
    case fireEngine    // #fire-engine (03)
    case digger        // #digger (05)
    case dumper        // #dumper (05)
    case mixer         // #mixer (05)
    case dozer         // #dozer (05)
    case roller        // #roller (05)
    case craneTruck    // #crane-truck (05)
    case plane         // #plane (07)
    case bus           // #bus (08)

    /// Body colours this model is painted in (`currentColor` in the mockups). The fire engine is
    /// always red: its art has no `currentColor`.
    public var palette: [UInt32] {
        switch self {
        case .tram: return [0x58AE72, 0xA98BE0, 0x4C8FE0, 0xFFC93C]
        case .fireEngine: return [0xE8473C]
        case .digger, .dumper, .mixer, .dozer, .roller, .craneTruck:
            return [0xFFC93C, 0xF5963C, 0x58AE72, 0x4C8FE0, 0xA98BE0]
        case .plane: return [0x4C8FE0, 0xF49AB0, 0x2E9FA6, 0xA98BE0, 0xFFC93C]
        case .bus: return [0x4C8FE0, 0x2E9FA6, 0xF49AB0, 0xA98BE0, 0xFFC93C]
        }
    }
}

/// How the vehicles stand (design §7.3).
public enum TapCountLayout: String, CaseIterable, Sendable, Codable, Hashable {
    /// ★ / ★★ with 1–5: one row of bays (mockup 01).
    case row
    /// ★ / ★★ with 6–10: a ten-frame, top row of 5 then the bottom row from the left.
    case tenFrame
    /// ★★★: the 2 × 5 yard, N cells at random, cones in the empty ones (mockup 05).
    case yard

    public var code: String {
        switch self {
        case .row: return "row"
        case .tenFrame: return "tenframe"
        case .yard: return "yard"
        }
    }
}

public struct TapCountVehicle: Sendable, Equatable, Hashable {
    /// Bay index: 0…n−1 in a row, 0…9 (row-major) on the ten-frame / yard.
    public let bay: Int
    public let model: TapCountModel
    public let color: UInt32
    /// Small horizontal offset in its bay (±8u, design §7.3).
    public let jitter: Double

    public init(bay: Int, model: TapCountModel, color: UInt32, jitter: Double) {
        self.bay = bay
        self.model = model
        self.color = color
        self.jitter = jitter
    }
}

// MARK: - Layout geometry (stage units; mockups 01, 03, 05, 08)

public enum TapCountLayoutGeometry {
    public static let rowSpacing: Double = 244
    public static let rowGround: Double = 326
    public static let rowBayTop: Double = 140
    public static let rowBayHeight: Double = 200
    public static let cellWidth: Double = 214
    public static let cellHeight: Double = 120
    public static let cellOriginX: Double = 81
    public static let cellStepX: Double = 226
    public static let cellYs: [Double] = [130, 262]
    public static let cellGrounds: [Double] = [242, 374]
    /// The yard panel behind the cells (mockup 05).
    public static let yardPanel = LineMatchRect(x: 62, y: 120, width: 1156, height: 270)
    /// Taps within this distance of a bay count as that bay (design D1).
    public static let gapSnap: Double = 20
    /// Pale / target numeral tile under the vehicles (mockup 01: 260 × 138 at 510,392).
    public static let tile = LineMatchRect(x: 510, y: 392, width: 260, height: 138)
    /// ★★★ works sign (mockup 05: 184 × 128 at 548,398).
    public static let sign = LineMatchRect(x: 548, y: 398, width: 184, height: 128)
    /// Parking strip after the count (mockups 03 / 07 / 08): ground y 214, centred on x 640.
    public static let stripGround: Double = 214
    public static let stripMaxSpacing: Double = 157
    public static let stripMinSpacing: Double = 106
    /// ★★★ 擦晒 and OK (mockup 05: eraser 200 × 160 at 24,548; OK 240 × 160 at 800,548).
    public static let eraser = LineMatchRect(x: 24, y: 548, width: 200, height: 160)
    public static let ok = LineMatchRect(x: 800, y: 548, width: 240, height: 160)

    public static func rowCentreX(_ index: Int, count: Int) -> Double {
        640 + (Double(index) - Double(count - 1) / 2) * rowSpacing
    }

    public static func cell(_ bay: Int) -> LineMatchRect {
        let column = bay % 5, row = bay / 5
        return LineMatchRect(x: cellOriginX + Double(column) * cellStepX, y: cellYs[min(row, 1)],
                             width: cellWidth, height: cellHeight)
    }

    /// Strip x of the i-th of n counted vehicles.
    public static func stripX(_ index: Int, count: Int) -> Double {
        guard count > 1 else { return 640 }
        let spacing = min(stripMaxSpacing, stripMinSpacing * 9 / Double(count - 1))
        return 640 + (Double(index) - Double(count - 1) / 2) * spacing
    }

    public static func stripSpacing(count: Int) -> Double {
        count > 1 ? min(stripMaxSpacing, stripMinSpacing * 9 / Double(count - 1)) : stripMaxSpacing
    }
}

// MARK: - Question

/// A dealt 一架一架數 round. A pure function of (seed, kind, settings, recent targets, avoided item).
public struct TapCountQuestion: Sendable, Equatable {
    public let itemID: String
    public let kind: ActivityKind
    public let level: ActivityLevel
    /// The numeral (1–10; 0 is reserved and never dealt in v1).
    public let target: Int
    public let scene: TapCountScene
    public let layout: TapCountLayout
    /// Every vehicle on the stage, by bay. ★ / ★★: exactly `target`; ★★★: N > target (N = 10 at 10).
    public let vehicles: [TapCountVehicle]
    /// Colour set of ★ / ★★ (`c` in the item id) or model set of ★★★ (`v`).
    public let variant: Int

    public init(itemID: String, kind: ActivityKind, level: ActivityLevel, target: Int, scene: TapCountScene,
                layout: TapCountLayout, vehicles: [TapCountVehicle], variant: Int) {
        self.itemID = itemID
        self.kind = kind
        self.level = level
        self.target = target
        self.scene = scene
        self.layout = layout
        self.vehicles = vehicles.sorted { $0.bay < $1.bay }
        self.variant = variant
    }

    public var count: Int { vehicles.count }
    public var bayCount: Int { layout == .row ? vehicles.count : 10 }
    /// The game this card plays (the English twins play their Cantonese card's game exactly).
    public var base: ActivityKind { kind.tapCountBase ?? kind }
    public var language: TapCountLanguage { kind.tapCountLanguage ?? .cantonese }
    public var tracesNumeral: Bool { base == .tapCountTrace || base == .tapCountPick }
    public var isPick: Bool { base == .tapCountPick }
    public var occupiedBays: [Int] { vehicles.map(\.bay) }

    public func vehicle(atBay bay: Int) -> TapCountVehicle? { vehicles.first { $0.bay == bay } }

    /// Hit rectangle of a bay (row: 232 × 200 around the vehicle; cells: 214 × 120).
    public func bayRect(_ bay: Int) -> LineMatchRect {
        switch layout {
        case .row:
            let cx = TapCountLayoutGeometry.rowCentreX(bay, count: bayCount)
            return LineMatchRect(x: cx - 116, y: TapCountLayoutGeometry.rowBayTop, width: 232,
                                 height: TapCountLayoutGeometry.rowBayHeight)
        case .tenFrame, .yard:
            return TapCountLayoutGeometry.cell(bay)
        }
    }

    /// Where a vehicle's wheels touch the ground (bottom-centre anchor of its art).
    public func ground(_ vehicle: TapCountVehicle) -> LineMatchPoint {
        switch layout {
        case .row:
            return LineMatchPoint(x: TapCountLayoutGeometry.rowCentreX(vehicle.bay, count: bayCount) + vehicle.jitter,
                                  y: TapCountLayoutGeometry.rowGround)
        case .tenFrame, .yard:
            let cell = TapCountLayoutGeometry.cell(vehicle.bay)
            return LineMatchPoint(x: cell.midX + vehicle.jitter, y: TapCountLayoutGeometry.cellGrounds[min(vehicle.bay / 5, 1)])
        }
    }

    /// The bay a tap lands in: inside a bay, or within 20u of the nearest one (design D1).
    public func bay(at point: LineMatchPoint) -> Int? {
        var best: (bay: Int, distance: Double)?
        for bay in 0..<bayCount {
            let r = bayRect(bay)
            let dx = max(r.x - point.x, 0, point.x - r.maxX)
            let dy = max(r.y - point.y, 0, point.y - r.maxY)
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance <= TapCountLayoutGeometry.gapSnap, distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (bay, distance)
            }
        }
        return best?.bay
    }

    /// Reading order (left → right, top → bottom) = bay order.
    public var readingOrder: [Int] { occupiedBays }

    /// The round's opening prompt in the card's language.
    public var prompt: SpokenPrompt {
        let lines = TapCountLines(language)
        return isPick ? lines.pickPrompt(target) : lines.allPrompt(scene)
    }

    public var hintTraditionalChinese: String { TapCountCopy.hint }

    /// Design §11.4: target in 1…10, the count rule per card, bays distinct and in range, nothing
    /// in the parent corner, and the layout matching the card.
    public var isWellFormed: Bool {
        guard !itemID.isEmpty, (1...10).contains(target), kind.isTapCountFamily, level == kind.tapCountLevel else {
            return false
        }
        let bays = occupiedBays
        guard Set(bays).count == bays.count, bays.allSatisfy({ (0..<bayCount).contains($0) }) else { return false }
        switch base {
        case .tapCountPick:
            guard layout == .yard, count <= 10 else { return false }
            guard target == 10 ? count == 10 : (count > target && count >= 3) else { return false }
        default:
            guard count == target, layout == (target <= 5 ? .row : .tenFrame) else { return false }
            if layout == .tenFrame, bays != Array(0..<target) { return false }
        }
        for vehicle in vehicles {
            guard vehicle.model.palette.contains(vehicle.color), abs(vehicle.jitter) <= 8 else { return false }
            let r = bayRect(vehicle.bay)
            guard r.y >= 118, r.maxY <= 392, r.x >= 0, r.maxX <= 1280 else { return false }
            guard !r.intersects(ShapeTraceLayout.parentZone) else { return false }
        }
        return true
    }
}

// MARK: - Parent settings (design §9 「數字設定」, shared by the three cards)

public enum TapCountRange: Int, CaseIterable, Sendable, Codable, Hashable {
    case upTo5 = 5
    case upTo7 = 7
    case upTo10 = 10

    public var label: String { "1–\(rawValue)" }
    public var numbers: ClosedRange<Int> { 1...rawValue }
}

public enum TapCountBadgeStyle: String, CaseIterable, Sendable, Codable, Hashable {
    /// 1 2 3 (Q11 default).
    case numbers
    /// ✓ only: the child keeps the count in mind (a challenge).
    case ticks

    public var labelTraditionalChinese: String { self == .numbers ? "1 2 3" : "✓ 剔號" }
}

public enum TapCountTraceScaffold: String, CaseIterable, Sendable, Codable, Hashable {
    /// 虛線路: pale lane + grey dots (Q12 default; shape-trace L1).
    case dots
    /// 淡框 + 箭嘴: faint outline + arrows (shape-trace L2).
    case outline

    public var labelTraditionalChinese: String { self == .dots ? "虛線路" : "淡框 + 箭嘴" }
    public var code: String { self == .dots ? "dots" : "outline" }
}

public struct TapCountSettings: Equatable, Sendable {
    public var range: TapCountRange
    /// 點車讀數: Stampy says 一、二、三 per tap.
    public var countVoice: Bool
    /// 加英文: 「三、three」.
    public var english: Bool
    public var badgeStyle: TapCountBadgeStyle
    public var traceScaffold: TapCountTraceScaffold
    /// Nil = follow 畫形狀設定 (「跟畫形狀」).
    public var tolerance: LineMatchTolerance?

    public init(range: TapCountRange = .upTo10, countVoice: Bool = true, english: Bool = true,
                badgeStyle: TapCountBadgeStyle = .numbers, traceScaffold: TapCountTraceScaffold = .dots,
                tolerance: LineMatchTolerance? = nil) {
        self.range = range
        self.countVoice = countVoice
        self.english = english
        self.badgeStyle = badgeStyle
        self.traceScaffold = traceScaffold
        self.tolerance = tolerance
    }

    public static let defaults = TapCountSettings()

    /// 「跟畫形狀」: the shape-trace tolerance, which itself may follow 連一連.
    public func effectiveTolerance(shapeTrace: ShapeTraceSettings, lineMatch: LineMatchTolerance) -> LineMatchTolerance {
        tolerance ?? shapeTrace.effectiveTolerance(lineMatch: lineMatch)
    }
}

/// UserDefaults store (not the reward snapshot). Missing or corrupt → defaults; a failed save
/// never blocks the child (the settings simply stay in memory).
public struct TapCountSettingsStore {
    public static let key = "VisaGames.tapCountSettings.v1"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> TapCountSettings {
        guard let data = defaults.data(forKey: Self.key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return .defaults }
        return payload.settings
    }

    public func save(_ settings: TapCountSettings) {
        guard let data = try? JSONEncoder().encode(Payload(settings: settings)) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private struct Payload: Codable {
        var range: Int
        var countVoice: Bool
        var english: Bool
        var badgeStyle: String
        var traceScaffold: String
        var tolerance: String?

        init(settings: TapCountSettings) {
            range = settings.range.rawValue
            countVoice = settings.countVoice
            english = settings.english
            badgeStyle = settings.badgeStyle.rawValue
            traceScaffold = settings.traceScaffold.rawValue
            tolerance = settings.tolerance?.rawValue
        }

        var settings: TapCountSettings {
            TapCountSettings(range: TapCountRange(rawValue: range) ?? .upTo10, countVoice: countVoice, english: english,
                             badgeStyle: TapCountBadgeStyle(rawValue: badgeStyle) ?? .numbers,
                             traceScaffold: TapCountTraceScaffold(rawValue: traceScaffold) ?? .dots,
                             tolerance: tolerance.flatMap(LineMatchTolerance.init(rawValue:)))
        }
    }
}

// MARK: - Generator (design §7)

public enum TapCountGenerator {
    /// The last 3 targets of the family are not dealt again (shared by the three cards).
    public static let recentWindow = 3

    /// 1 and 2 at half weight, 3–10 full (weights 1 / 2).
    public static func weight(_ n: Int) -> Int { n <= 2 ? 1 : 2 }

    /// Targets allowed now, with weights. Never empty: if the range is smaller than the recent
    /// window, the oldest recent targets are allowed again.
    public static func targetPool(range: TapCountRange, recentTargets: [Int]) -> [Int] {
        let numbers = Array(range.numbers)
        var recent = Array(recentTargets.suffix(recentWindow))
        while !recent.isEmpty, numbers.allSatisfy({ recent.contains($0) }) { recent.removeFirst() }
        let allowed = numbers.filter { !recent.contains($0) }
        return allowed.flatMap { Array(repeating: $0, count: weight($0)) }
    }

    /// ★★★ vehicle count: uniform in max(3, T + 1)…10; T = 10 → 10 (design §7.2).
    public static func carRange(target: Int) -> ClosedRange<Int> {
        target >= 10 ? 10...10 : max(3, target + 1)...10
    }

    public static func make(seed: String, kind: ActivityKind, settings: TapCountSettings = .defaults,
                            recentTargets: [Int] = [], avoidingItem: String? = nil,
                            avoidingScene: TapCountScene? = nil) -> TapCountQuestion {
        var question = deal(seed: seed, salt: 0, kind: kind, settings: settings, recentTargets: recentTargets,
                            avoidingScene: avoidingScene)
        var salt = 1
        while question.itemID == avoidingItem, salt <= QuestionGeneration.maxRerolls {
            question = deal(seed: seed, salt: salt, kind: kind, settings: settings, recentTargets: recentTargets,
                            avoidingScene: avoidingScene)
            salt += 1
        }
        return question
    }

    private static func deal(seed: String, salt: Int, kind: ActivityKind, settings: TapCountSettings,
                             recentTargets: [Int], avoidingScene: TapCountScene?) -> TapCountQuestion {
        // Seeded by the game, not the language: an English twin deals the very same round.
        var rng = QuestionRNG(seed: seed, salt: "tapCount.\((kind.tapCountBase ?? kind).rawValue).\(salt)")
        let target = rng.pick(targetPool(range: settings.range, recentTargets: recentTargets))
        let scenes = TapCountScene.allCases.filter { $0 != avoidingScene }
        let scene = rng.pick(scenes.isEmpty ? TapCountScene.allCases : scenes)
        return build(kind: kind, target: target, scene: scene, rng: &rng)
    }

    private static func jitter(_ rng: inout QuestionRNG) -> Double { Double(rng.int(in: -4...4)) * 2 }

    private static func build(kind: ActivityKind, target: Int, scene: TapCountScene,
                              rng: inout QuestionRNG) -> TapCountQuestion {
        let level = kind.tapCountLevel ?? .l1
        if kind.tapCountBase == .tapCountPick {
            let cars = rng.int(in: carRange(target: target))
            let bays = Array(rng.shuffled(Array(0..<10)).prefix(cars)).sorted()
            var vehicles: [TapCountVehicle] = []
            var models: [TapCountModel] = []
            var previous: UInt32?
            for bay in bays {
                let model = rng.pick(scene.fleet)
                var colors = model.palette.filter { $0 != previous }
                if colors.isEmpty { colors = model.palette }
                let color = rng.pick(colors)
                previous = color
                models.append(model)
                vehicles.append(TapCountVehicle(bay: bay, model: model, color: color, jitter: jitter(&rng)))
            }
            let variant = abs(models.map(\.rawValue).joined().hashValueStable) % 1000
            let bayCode = bays.map(String.init).joined()
            return TapCountQuestion(
                itemID: "tapCount.pick.\(scene.rawValue).t\(target).n\(cars).b\(bayCode).v\(variant)",
                kind: kind, level: level, target: target, scene: scene, layout: .yard, vehicles: vehicles,
                variant: variant)
        }
        let layout: TapCountLayout = target <= 5 ? .row : .tenFrame
        let model = scene.vehicle
        let palette = model.palette
        // Colour set c: a start colour, then the palette in order (neighbours differ).
        let variant = rng.below(palette.count)
        let vehicles = (0..<target).map { index -> TapCountVehicle in
            TapCountVehicle(bay: index, model: model, color: palette[(variant + index) % palette.count],
                            jitter: layout == .row ? 0 : jitter(&rng))
        }
        let prefix = kind.tapCountBase == .tapCountTrace ? "trace" : "all"
        return TapCountQuestion(itemID: "tapCount.\(prefix).\(scene.rawValue).n\(target).c\(variant)", kind: kind,
                                level: level, target: target, scene: scene, layout: layout, vehicles: vehicles,
                                variant: variant)
    }

    /// Fixed reference item per kind (performance catalog slots / parent previews).
    public static func reference(kind: ActivityKind) -> TapCountQuestion {
        let base = kind.tapCountBase ?? kind
        var rng = QuestionRNG(seed: "reference", salt: "tapCount.\(base.rawValue)")
        let scene: TapCountScene = base == .tapCountPick ? .site : (base == .tapCountTrace ? .fireStation : .tramDepot)
        return build(kind: kind, target: base == .tapCountAll ? 4 : 3, scene: scene, rng: &rng)
    }
}

extension String {
    /// FNV-1a — stable across launches (Swift's `hashValue` is seeded per process).
    var hashValueStable: Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(truncatingIfNeeded: hash >> 1)
    }
}

// MARK: - Copy (design §3–§5, §8.2, §10; mockups 01–09). HK Traditional + English only.

public enum TapCountCopy {
    public static let familyTitle = "一架一架數"
    public static let familyEnglish = "Tap & Count"
    public static let hint = "提示：一架一架數，數夠就撳 OK。 / Hint: count one by one and stop when you have enough."

    /// Child header chip second line (design §10).
    public static func chipSubtitle(_ kind: ActivityKind) -> String {
        switch kind.tapCountBase ?? kind {
        case .tapCountTrace: return "數完畫 · Count & trace"
        case .tapCountPick: return "揀啱數 · Just right"
        default: return "點一點 · Tap each"
        }
    }

    public static func allPrompt(_ scene: TapCountScene) -> SpokenPrompt {
        SpokenPrompt(key: "tapCount.all.prompt.\(scene.rawValue)",
                     traditionalChinese: "點一點每架\(scene.vehicleTraditionalChinese)！",
                     english: "Tap every \(scene.vehicleEnglishSingular)!")
    }

    /// Counting word per tap (Cantonese only, design §8.3).
    public static func number(_ n: Int) -> SpokenPrompt {
        SpokenPrompt(key: "number.\(n).yue", traditionalChinese: TapCountNumber.zh(n), english: "")
    }

    /// 「四架！」: the whole set (cardinality).
    public static func total(_ n: Int, scene: TapCountScene = .tramDepot) -> SpokenPrompt {
        SpokenPrompt(key: "tapCount.total.\(n).\(scene.classifier == "架" ? "gaa" : scene.classifier)",
                     traditionalChinese: "\(TapCountNumber.zh(n))\(scene.classifier)！",
                     english: "\(TapCountNumber.enCapitalised(n))!")
    }

    /// 「四、four」 bubble (English part only when 加英文 is on).
    public static func cue(_ n: Int, english: Bool) -> String {
        english ? "\(TapCountNumber.zh(n))、\(TapCountNumber.en(n))" : TapCountNumber.zh(n)
    }

    public static func cuePrompt(_ n: Int) -> SpokenPrompt {
        SpokenPrompt(key: "number.\(n)", traditionalChinese: TapCountNumber.zh(n), english: TapCountNumber.en(n))
    }

    public static func remainingTraditionalChinese(_ n: Int) -> String { "仲有 \(n) 架" }
    public static func remainingEnglish(_ n: Int) -> String { "\(n) more to go" }

    public static func donePrompt(_ n: Int, scene: TapCountScene) -> SpokenPrompt {
        SpokenPrompt(key: "tapCount.done.\(n).\(scene.rawValue)",
                     traditionalChinese: "好叻呀！\(TapCountNumber.zh(n))\(scene.classifier)\(scene.vehicleTraditionalChinese)！",
                     english: "Well done! \(TapCountNumber.enCapitalised(n)) \(n == 1 ? scene.vehicleEnglishSingular : scene.vehicleEnglishPlural)!")
    }

    public static func tracePrompt(_ n: Int) -> SpokenPrompt {
        SpokenPrompt(key: "tapCount.trace.prompt.\(n)", traditionalChinese: "跟住箭嘴，畫 \(n)！",
                     english: "Follow the arrows and draw \(n)!")
    }

    /// After the count, before tracing (mockup 03 header; ★★★ `tapCount.pick.right.<n>`).
    public static func countedTracePrompt(_ n: Int, pick: Bool) -> SpokenPrompt {
        SpokenPrompt(key: pick ? "tapCount.pick.right.\(n)" : "tapCount.trace.counted.\(n)",
                     traditionalChinese: "\(TapCountNumber.zh(n))架！跟住箭嘴，畫 \(n)！",
                     english: "\(TapCountNumber.enCapitalised(n))! Follow the arrows and draw \(n)!")
    }

    public static let traceNext = SpokenPrompt(key: "tapCount.trace.next", traditionalChinese: "跟住畫第二筆！",
                                               english: "Now the second stroke!")
    /// Mockup 07: 5's second stroke.
    public static let lastStrokeHatTraditionalChinese = "最後一筆：戴帽！"

    public static func traceDonePrompt(_ n: Int) -> SpokenPrompt {
        SpokenPrompt(key: "tapCount.trace.done.\(n)", traditionalChinese: "好叻呀！畫好 \(n) 喇！",
                     english: "Great! You drew a \(n)!")
    }

    public static func pickPrompt(_ n: Int) -> SpokenPrompt {
        SpokenPrompt(key: "tapCount.pick.prompt.\(n)", traditionalChinese: "點 \(n) 架車，再撳 OK！",
                     english: "Tap \(n) \(n == 1 ? "vehicle" : "vehicles"), then press OK!")
    }

    public static let noneYet = SpokenPrompt(key: "tapCount.pick.noneYet", traditionalChinese: "未揀車喎！",
                                             english: "Pick some vehicles first!")

    /// 「一、二、三、四。四架。」 recount on OK.
    public static func recount(_ k: Int) -> SpokenPrompt {
        let words = (1...max(k, 1)).map(TapCountNumber.zh).joined(separator: "、")
        let english = (1...max(k, 1)).map(TapCountNumber.enCapitalised).joined(separator: ", ")
        return SpokenPrompt(key: "tapCount.pick.recount.\(k)",
                            traditionalChinese: "\(words)。\(TapCountNumber.zh(k))架。",
                            english: "\(english). \(TapCountNumber.enCapitalised(k)).")
    }

    public static func need(_ n: Int) -> SpokenPrompt {
        SpokenPrompt(key: "tapCount.pick.need.\(n)", traditionalChinese: "要\(TapCountNumber.zh(n))架喎！",
                     english: "We need \(TapCountNumber.en(n))!")
    }

    public static let over = SpokenPrompt(key: "tapCount.pick.over", traditionalChinese: "多咗喎！", english: "One too many!")
    public static let under = SpokenPrompt(key: "tapCount.pick.under", traditionalChinese: "仲未夠喎！",
                                           english: "Not enough yet!")
    public static let eraserNudge = SpokenPrompt(key: "tapCount.pick.eraserNudge", traditionalChinese: "試吓撳 OK 啦！",
                                                 english: "Try pressing OK!")

    public static func demo(_ n: Int) -> SpokenPrompt {
        let words = (1...max(n, 1)).map(TapCountNumber.zh).joined(separator: "、")
        let english = (1...max(n, 1)).map(TapCountNumber.enCapitalised).joined(separator: ", ")
        return SpokenPrompt(key: "tapCount.pick.demo.\(n)",
                            traditionalChinese: "\(words)。\(TapCountNumber.zh(n))架就夠喇，撳 OK！",
                            english: "\(english). \(TapCountNumber.enCapitalised(n)) is enough. Press OK!")
    }

    // Tray and labels (mockups 01–08).
    public static let legendTapped = "點咗"
    public static let legendNotYet = "未點"
    public static let legendStart = "開始"
    public static let legendStop = "停"
    public static let legendStrokeNumber = "第幾筆"
    public static let legendStrokeDone = "畫好一筆"
    public static let stepTap = "點車"
    public static func stepPick(_ n: Int) -> String { "揀 \(n) 架" }
    public static func stepTrace(_ n: Int) -> String { "畫 \(n)" }
    public static let traceStatusTraditionalChinese = "跟住條路畫落去"
    public static let traceStatusEnglish = "keep going along the road"
    public static func countedChip(_ n: Int, pick: Bool) -> (top: String, bottom: String) {
        ("\(TapCountNumber.zh(n))架！", pick ? "\(n) picked" : "\(n) counted")
    }
    public static let allTappedTray = "點晒喇！"
    public static let stampNextTray = "跟住：蓋印！"
    public static let noMissTray = "★ 冇得錯，唔會扣油"
    public static let drawnTray = "畫好喇！"
    public static func visaTray(_ minutes: Int) -> String { "\(minutes) 分鐘簽證" }
    public static func strokesDoneTray(_ n: Int, scene: TapCountScene) -> String {
        "\(TapCountNumber.zh(n))架\(scene.vehicleTraditionalChinese)，畫好喇！"
    }
    public static func strokesDoneTrayEnglish(_ n: Int, scene: TapCountScene) -> String {
        "\(TapCountNumber.enCapitalised(n)) \(n == 1 ? scene.vehicleEnglishSingular : scene.vehicleEnglishPlural), all drawn!"
    }
    // English sub-lines of the tray (mockups 01–08, verbatim).
    public static let legendTappedEnglish = "lit + number = counted"
    public static let legendNotYetEnglish = "not counted yet"
    public static let legendStartEnglish = "green arrow = start"
    public static let legendStopEnglish = "red arrow = stop"
    public static let legendStrokeNumberEnglish = "stroke order"
    public static let legendStrokeDoneEnglish = "stroke done"
    public static let allTappedTrayEnglish = "All counted!"
    public static let stampNextTrayEnglish = "then the usual stamp"
    public static let noMissTrayEnglish = "nothing to get wrong"
    public static let drawnTrayEnglish = "All drawn!"
    public static func visaTrayEnglish(_ minutes: Int) -> String { "\(minutes)-minute visa" }
    public static let lastStrokeHatEnglish = "last stroke: the hat"
    public static let firstTryTrayEnglish = "first try: no fuel lost"
    /// Think Pause card in the tray (mockup 06): 「15 → 7 分鐘 · half the fuel gone」.
    public static func fuelDropLine(from before: Int, to after: Int) -> String { "\(before) → \(after) 分鐘 · half the fuel gone" }
    public static let pauseEnglish = "Pause and think!"
    public static let eraserTraditionalChinese = "擦晒"
    public static let eraserEnglish = "Clear"
    public static let okLabel = "OK"
    public static let okSub = "完成"

    // Parent settings (mockup 09, design §9).
    public static let parentGroupTitle = "一架一架數"
    public static func parentGroupSubtitle(_ range: TapCountRange) -> String { "Tap & Count · 3 張卡 + 3 張英文版 · 數字 \(range.label)" }
    public static let parentDefaultOff = "預設全部關閉。試玩一次，再揀邊個星級出呢張卡。"
    public static let parentDefaultOffEnglish = "Off by default. Try a card, then choose which tickets (★ / ★★ / ★★★) may deal it."
    public static let recommended = "建議"
    public static func recommendedStar(_ kind: ActivityKind) -> String {
        switch kind.tapCountBase ?? kind {
        case .tapCountTrace: return "建議 ★★"
        case .tapCountPick: return "建議 ★★★"
        default: return "建議 ★"
        }
    }
    public static let settingsTitle = "數字設定"
    public static let settingsSubtitle = "Shared by the 3 cards and their 3 English versions"
    public static let rangeTitle = "數字範圍"
    public static let rangeEnglish = "Numbers"
    public static let countVoiceTitle = "點車讀數"
    public static let countVoiceEnglish = "Count each tap aloud（一、二、三）"
    public static let englishTitle = "加英文"
    public static let englishEnglish = "「三、three」 English word"
    public static let badgeTitle = "★★★ 數字牌"
    public static let badgeEnglish = "Badges on picked vehicles"
    public static let scaffoldTitle = "描數字"
    public static let scaffoldEnglish = "Trace guide · ★★ ★★★"
    public static let toleranceTitle = "畫線寬容度"
    public static let toleranceEnglish = "Tolerance"
    public static let toleranceFollow = "跟畫形狀"
    public static let on = "開"
    public static let off = "關"
    public static let parentTip = "小貼士：玩完用真嘅玩具車再玩：「攞 3 架車俾我！」"
    public static let parentTipEnglish = "Tip: play it with real toy cars too — \"Give me 3 cars!\""

    public static var allTraditionalLines: [String] {
        var lines = [familyTitle, hint.components(separatedBy: " / ").first ?? "", traceNext.traditionalChinese,
                     lastStrokeHatTraditionalChinese, noneYet.traditionalChinese, over.traditionalChinese,
                     under.traditionalChinese, eraserNudge.traditionalChinese, legendTapped, legendNotYet, legendStart,
                     legendStop, legendStrokeNumber, legendStrokeDone, stepTap, traceStatusTraditionalChinese,
                     allTappedTray, stampNextTray, noMissTray, drawnTray, visaTray(10), eraserTraditionalChinese, okSub,
                     parentGroupTitle, parentGroupSubtitle(.upTo10), parentDefaultOff, recommended, settingsTitle,
                     rangeTitle, countVoiceTitle, englishTitle, badgeTitle, scaffoldTitle, toleranceTitle,
                     toleranceFollow, on, off, parentTip, countVoiceEnglish, englishEnglish, scaffoldEnglish,
                     parentDefaultOffEnglish, parentTipEnglish, fuelDropLine(from: 15, to: 7)]
        for kind in [ActivityKind.tapCountAll, .tapCountTrace, .tapCountPick] {
            lines += [chipSubtitle(kind), recommendedStar(kind), kind.parentCardTitle, kind.parentShortLabel,
                      kind.parentHelpTraditionalChinese]
        }
        for scene in TapCountScene.allCases {
            lines += [scene.vehicleTraditionalChinese, scene.signTraditionalChinese, allPrompt(scene).traditionalChinese]
            for n in 1...10 {
                lines += [donePrompt(n, scene: scene).traditionalChinese, total(n, scene: scene).traditionalChinese,
                          strokesDoneTray(n, scene: scene)]
            }
        }
        for n in 0...10 { lines.append(TapCountNumber.zh(n)) }
        for n in 1...10 {
            lines += [tracePrompt(n).traditionalChinese, countedTracePrompt(n, pick: true).traditionalChinese,
                      traceDonePrompt(n).traditionalChinese, pickPrompt(n).traditionalChinese,
                      recount(n).traditionalChinese, need(n).traditionalChinese, demo(n).traditionalChinese,
                      remainingTraditionalChinese(n), stepPick(n), stepTrace(n), cue(n, english: false),
                      countedChip(n, pick: false).top]
        }
        for style in TapCountBadgeStyle.allCases { lines.append(style.labelTraditionalChinese) }
        for scaffold in TapCountTraceScaffold.allCases { lines.append(scaffold.labelTraditionalChinese) }
        return lines
    }

    public static var allEnglishLines: [String] {
        var lines = [familyEnglish, hint.components(separatedBy: " / ").last ?? "", traceNext.english, noneYet.english,
                     over.english, under.english, eraserNudge.english, traceStatusEnglish, eraserEnglish, okLabel,
                     settingsSubtitle, rangeEnglish, badgeEnglish, toleranceEnglish, legendTappedEnglish,
                     legendNotYetEnglish, legendStartEnglish, legendStopEnglish, legendStrokeNumberEnglish,
                     legendStrokeDoneEnglish, allTappedTrayEnglish, stampNextTrayEnglish, noMissTrayEnglish,
                     drawnTrayEnglish, visaTrayEnglish(10), lastStrokeHatEnglish, firstTryTrayEnglish, pauseEnglish]
        for kind in [ActivityKind.tapCountAll, .tapCountTrace, .tapCountPick] {
            lines += [kind.parentCardEnglish, kind.parentHelpEnglish]
        }
        for scene in TapCountScene.allCases {
            lines.append(allPrompt(scene).english)
            for n in 1...10 {
                lines += [donePrompt(n, scene: scene).english, total(n, scene: scene).english,
                          strokesDoneTrayEnglish(n, scene: scene)]
            }
        }
        for n in 1...10 {
            lines += [tracePrompt(n).english, countedTracePrompt(n, pick: true).english, traceDonePrompt(n).english,
                      pickPrompt(n).english, recount(n).english, need(n).english, demo(n).english, remainingEnglish(n),
                      countedChip(n, pick: true).bottom, countedChip(n, pick: false).bottom, TapCountNumber.en(n)]
        }
        return lines
    }
}
