import Foundation

// 跟住排 + 分類 (patterns-sorting P0, 0.41.0; design §3.3, §4.2, §4.4, §5.5, D7, D8): the look catalogue the generators,
// the uniqueness checks and the boards share. It is built on the app's own art: the tap-count vector vehicles
// (`TapCountArt`, recoloured from each model's own body palette `TapCountModel.palette`), the four prop PNGs in
// `Resources/Props`, and the new shape blocks on a cart (`ShapeBlockArt`). No hero PNG, emoji or licensed asset.

/// The 分類方法 a round may ask about (design §7). Stored raw values; `group` is 類別 (the named categories).
public enum PatternSortMethod: String, CaseIterable, Sendable, Codable, Hashable, Comparable {
    case colour, size, shape, kind, group, facing

    /// 顏色・大細・形狀: every tier of both 分類 cards has a step that needs only one of these, so at least one stays on.
    public static let perceptual: [PatternSortMethod] = [.colour, .size, .shape]

    public var zh: String {
        switch self {
        case .colour: return "顏色"
        case .size: return "大細"
        case .shape: return "形狀"
        case .kind: return "車款"
        case .group: return "類別"
        case .facing: return "車頭方向"
        }
    }

    public var en: String {
        switch self {
        case .colour: return "Colour"
        case .size: return "Size"
        case .shape: return "Shape"
        case .kind: return "Kind of vehicle"
        case .group: return "Group"
        case .facing: return "Facing"
        }
    }

    public static func < (lhs: PatternSortMethod, rhs: PatternSortMethod) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Body colours: the tap-count palette (`TapCountModel.palette`, design §3.3) plus the fire engine's red, and the
/// traffic light's grey. `rgb` is what the app paints and what the colour-vision check simulates.
public enum PatternSortColour: String, CaseIterable, Sendable, Codable, Hashable {
    case blue, yellow, orange, purple, pink, teal, green, red, grey

    public var rgb: UInt32 {
        switch self {
        case .blue: return 0x4C8FE0
        case .yellow: return 0xFFC93C
        case .orange: return 0xF5963C
        case .purple: return 0xA98BE0
        case .pink: return 0xF49AB0
        case .teal: return 0x2E9FA6
        case .green: return 0x58AE72
        case .red: return 0xE8473C
        // The traffic light PNG's body (sampled, dominant opaque bin).
        case .grey: return 0x464652
        }
    }

    public init?(rgb: UInt32) {
        guard let match = Self.allCases.first(where: { $0.rgb == rgb }) else { return nil }
        self = match
    }

    public var zh: String {
        switch self {
        case .blue: return "藍色"
        case .yellow: return "黃色"
        case .orange: return "橙色"
        case .purple: return "紫色"
        case .pink: return "粉紅色"
        case .teal: return "藍綠色"
        case .green: return "綠色"
        case .red: return "紅色"
        case .grey: return "灰色"
        }
    }

    public var en: String { rawValue }
}

public enum PatternSortShape: String, CaseIterable, Sendable, Codable, Hashable {
    case circle, square, triangle, rectangle

    public var zh: String {
        switch self {
        case .circle: return "圓形"
        case .square: return "正方形"
        case .triangle: return "三角形"
        case .rectangle: return "長方形"
        }
    }

    public var en: String { rawValue }
    /// 長方形 is new art (NEL 4.1) and appears only at ★★★ (design §3.2, Q10).
    public static let belowTopTier: [PatternSortShape] = [.circle, .square, .triangle]
}

/// The four 唔係車 props (design §4.4) and the body colour each PNG shows (viewed in design R2; sampled by the P0
/// session from the PNGs: cone ≈ 0xF06A10, toolbox ≈ 0xD81A20, sun ≈ 0xF0D458, traffic light body ≈ 0x464652).
public enum PatternSortProp: String, CaseIterable, Sendable, Codable, Hashable {
    case cone, toolbox, sun, trafficLight

    public var assetID: String {
        switch self {
        case .cone: return "prop.trafficCone"
        case .toolbox: return "prop.toolbox"
        case .sun: return "prop.sun"
        case .trafficLight: return "prop.trafficLight"
        }
    }

    public var zh: String {
        switch self {
        case .cone: return "雪糕筒"
        case .toolbox: return "工具箱"
        case .sun: return "太陽"
        case .trafficLight: return "紅綠燈"
        }
    }

    public var en: String {
        switch self {
        case .cone: return "cone"
        case .toolbox: return "toolbox"
        case .sun: return "sun"
        case .trafficLight: return "traffic light"
        }
    }

    /// The named colour the PNG reads as (design §4.2: cone orange, toolbox red, sun yellow, traffic light grey).
    public var colour: PatternSortColour {
        switch self {
        case .cone: return .orange
        case .toolbox: return .red
        case .sun: return .yellow
        case .trafficLight: return .grey
        }
    }

    /// The PNG's own shade (sampled). A prop's shade may read as a colour of its own beside a painted vehicle, so
    /// the odd-one-out check reads every prop card both ways (`PatternSortLook.colourReadings`).
    public var shadeRGB: UInt32 {
        switch self {
        case .cone: return 0xF06A10
        case .toolbox: return 0xD81A20
        case .sun: return 0xF0D458
        case .trafficLight: return 0x464652
        }
    }
}

/// Look features a model brings with it (design §4.2 "Intrinsic features", from the real art: digger and dozer run
/// on tracks, the plane has wings, 巴士 and 叮叮 are the tall boxes, every other v1 vehicle stands on wheels; a prop
/// is a glossy PNG with no wheels; a shape block rides a two-wheel cart).
public enum PatternSortFeature: String, CaseIterable, Sendable, Codable, Hashable {
    case wheels, tracks, wings, tallBox, propArt
}

public enum PatternSortMaterial: String, CaseIterable, Sendable, Codable, Hashable {
    case vehicles, shapes
}

/// One thing on a card or in a row.
public enum PatternSortPiece: Hashable, Sendable {
    case vehicle(TapCountModel)
    case block(PatternSortShape)
    case prop(PatternSortProp)

    /// Stable code (`bus`, `circle`, `cone`), part of every item id.
    public var code: String {
        switch self {
        case .vehicle(let model): return model.rawValue
        case .block(let shape): return shape.rawValue
        case .prop(let prop): return prop.rawValue
        }
    }

    public init?(code: String) {
        if let model = TapCountModel(rawValue: code) { self = .vehicle(model) }
        else if let shape = PatternSortShape(rawValue: code) { self = .block(shape) }
        else if let prop = PatternSortProp(rawValue: code) { self = .prop(prop) }
        else { return nil }
    }

    public var material: PatternSortMaterial? {
        switch self {
        case .vehicle: return .vehicles
        case .block: return .shapes
        case .prop: return nil
        }
    }

    public var model: TapCountModel? { if case .vehicle(let model) = self { return model } else { return nil } }
    public var shape: PatternSortShape? { if case .block(let shape) = self { return shape } else { return nil } }
    public var prop: PatternSortProp? { if case .prop(let prop) = self { return prop } else { return nil } }

    public var features: Set<PatternSortFeature> {
        switch self {
        case .vehicle(let model):
            switch model {
            case .digger, .dozer: return [.tracks]
            case .bus, .tram: return [.wheels, .tallBox]
            case .plane: return [.wheels, .wings]
            case .fireEngine, .dumper, .mixer, .roller, .craneTruck: return [.wheels]
            }
        case .block: return [.wheels]
        case .prop: return [.propArt]
        }
    }

    /// Colours this piece can be painted in. Vehicles: their own art palette (the fire engine is always red);
    /// blocks: the body palette without red; props: their fixed PNG colour.
    public var palette: [PatternSortColour] {
        switch self {
        case .vehicle(let model): return model.palette.compactMap(PatternSortColour.init(rgb:))
        case .block: return [.blue, .yellow, .orange, .purple, .pink, .teal, .green]
        case .prop(let prop): return [prop.colour]
        }
    }

    public var zh: String {
        switch self {
        case .vehicle(let model): return model.patternSortWord.zh
        case .block(let shape): return shape.zh
        case .prop(let prop): return prop.zh
        }
    }

    public var en: String {
        switch self {
        case .vehicle(let model): return model.patternSortWord.en
        case .block(let shape): return shape.en
        case .prop(let prop): return prop.en
        }
    }

    /// 呢架 / 呢個: 架 for vehicles, 個 for blocks and props.
    public var classifier: String { model == nil ? "個" : "架" }
}

extension TapCountModel {
    /// Spoken and shown vehicle words (design §3.3; 泥頭車, 石屎車, 推土機, 壓路機 wait for Carter's check, Q11).
    public var patternSortWord: (zh: String, en: String) {
        switch self {
        case .tram: return ("叮叮", "tram")
        case .fireEngine: return ("消防車", "fire engine")
        case .digger: return ("挖泥車", "digger")
        case .dumper: return ("泥頭車", "dump truck")
        case .mixer: return ("石屎車", "cement mixer")
        case .dozer: return ("推土機", "bulldozer")
        case .roller: return ("壓路機", "road roller")
        case .craneTruck: return ("吊臂車", "crane truck")
        case .plane: return ("飛機", "plane")
        case .bus: return ("巴士", "bus")
        }
    }
}

/// 大 / 細 at the convoy's 1 : 0.62 (design §3.2, `SequenceActivityView`).
public enum PatternSortSize: String, CaseIterable, Sendable, Codable, Hashable {
    case big, small

    public var scale: Double { self == .big ? 1.0 : 0.62 }
    public var zh: String { self == .big ? "大" : "細" }
    public var en: String { rawValue }
}

/// 車頭方向: as drawn, or mirrored.
public enum PatternSortFacing: String, CaseIterable, Sendable, Codable, Hashable {
    case forward, mirrored
}

/// One card's or slot's look.
public struct PatternSortLook: Hashable, Sendable {
    public var piece: PatternSortPiece
    public var colour: PatternSortColour
    public var size: PatternSortSize
    public var facing: PatternSortFacing

    public init(_ piece: PatternSortPiece, _ colour: PatternSortColour, size: PatternSortSize = .big,
                facing: PatternSortFacing = .forward) {
        self.piece = piece
        self.colour = colour
        self.size = size
        self.facing = facing
    }

    /// A prop with its own colour.
    public init(prop: PatternSortProp) { self.init(.prop(prop), prop.colour) }

    /// `mixer@blue`, `bus@yellow_small`, `digger@orange_mirrored`: stable, no `.` (item ids use it as separator).
    public var code: String {
        var text = "\(piece.code)@\(colour.rawValue)"
        if size == .small { text += "_small" }
        if facing == .mirrored { text += "_mirrored" }
        return text
    }

    public init?(code: String) {
        let parts = code.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, let piece = PatternSortPiece(code: parts[0]) else { return nil }
        let flags = parts[1].split(separator: "_").map(String.init)
        guard let colour = flags.first.flatMap(PatternSortColour.init(rawValue:)),
              Set(flags.dropFirst()).isSubset(of: ["small", "mirrored"]), flags.count == Set(flags).count else { return nil }
        self.init(piece, colour, size: flags.contains("small") ? .small : .big,
                  facing: flags.contains("mirrored") ? .mirrored : .forward)
    }

    /// The painted RGB: a prop shows its PNG's own shade.
    public var rgb: UInt32 { piece.prop?.shadeRGB ?? colour.rgb }

    /// How the card's colour can be read: its named colour, and for a prop also its PNG's own shade (a deep-orange
    /// cone beside orange trucks may read as a colour of its own). Each reading is a colour key.
    public var colourReadings: [String] {
        if let prop = piece.prop { return [colour.rawValue, "shade.\(prop.rawValue)"] }
        return [colour.rawValue]
    }

    /// 「黃色挖泥車」 / "Yellow digger" (design §5.5 accessibility labels; size and facing added when they matter).
    public var labelZH: String {
        (size == .small ? "細" : "") + (piece.prop == nil ? colour.zh : "") + piece.zh
            + (facing == .mirrored ? "（車頭向另一邊）" : "")
    }

    public var labelEN: String {
        var words: [String] = []
        if size == .small { words.append("small") }
        if piece.prop == nil { words.append(colour.en) }
        words.append(piece.en)
        var text = words.joined(separator: " ")
        text = text.prefix(1).uppercased() + text.dropFirst()
        return facing == .mirrored ? text + " (facing the other way)" : text
    }
}

/// Named categories (design §4.2 membership table, Q11; provisional, not facts about how Cedric talks).
public enum PatternSortCategory: String, CaseIterable, Sendable, Codable, Hashable {
    /// 車: road and rail vehicles. 飛機 is never in a 車 / 唔係車 round, on either side.
    case vehicle
    /// 唔係車: the four props.
    case notVehicle
    /// 地盤車: the site fleet.
    case site
    /// 載人車 (分車房 ★★★ b only).
    case passenger

    public var zh: String {
        switch self {
        case .vehicle: return "車"
        case .notVehicle: return "唔係車"
        case .site: return "地盤車"
        case .passenger: return "載人車"
        }
    }

    public var en: String {
        switch self {
        case .vehicle: return "vehicle"
        case .notVehicle: return "not a vehicle"
        case .site: return "construction vehicle"
        case .passenger: return "passenger vehicle"
        }
    }

    /// v1 members. 推土機 / 壓路機 join once their words are approved; the always-red 消防車 is left out of every v1
    /// category round (design §4.2), so it is listed under 車 but never dealt there (`roundMembers`).
    public var members: [PatternSortPiece] {
        switch self {
        case .vehicle: return [.bus, .tram, .fireEngine, .digger, .dumper, .mixer, .craneTruck].map(PatternSortPiece.vehicle)
        case .notVehicle: return PatternSortProp.allCases.map(PatternSortPiece.prop)
        case .site: return [.digger, .dumper, .mixer, .craneTruck].map(PatternSortPiece.vehicle)
        case .passenger: return [.bus, .tram].map(PatternSortPiece.vehicle)
        }
    }

    /// Members a v1 round may deal: no 消防車; 車 rounds use the wheeled road and rail vehicles only (2b: "vehicles
    /// all on wheels", so no tracked model stands out).
    public var roundMembers: [PatternSortPiece] {
        switch self {
        case .vehicle: return [.bus, .tram, .dumper, .mixer, .craneTruck].map(PatternSortPiece.vehicle)
        case .notVehicle, .site, .passenger: return members
        }
    }

    public func contains(_ piece: PatternSortPiece) -> Bool { members.contains(piece) }

    /// The grey model on the category sign (design §4.2 stimulus panel, §4.4): 巴士 for 車 and 載人車, 挖泥車 (the
    /// site scene's own vehicle) for 地盤車; 唔係車 has the cone.
    public var anchor: PatternSortPiece {
        switch self {
        case .vehicle, .passenger: return .vehicle(.bus)
        case .site: return .vehicle(.digger)
        case .notVehicle: return .prop(.cone)
        }
    }
}

/// A lock-guarded memo for the generators' enumerated pools (each pool is built once, on first use).
public final class PatternSortMemo<Value: Sendable>: @unchecked Sendable {
    private var store: [String: Value] = [:]
    private let lock = NSLock()

    public init() {}

    public func value(for key: String, _ make: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        if let known = store[key] { return known }
        let made = make()
        store[key] = made
        return made
    }
}

/// The v1 vehicles of both families (design §3.3).
public enum PatternSortCatalog {
    public static let vehicles: [TapCountModel] = [.bus, .tram, .digger, .dumper, .mixer, .craneTruck, .plane, .fireEngine]

    /// Every v1 piece of a material at a tier (長方形 only at ★★★).
    public static func pieces(_ material: PatternSortMaterial, level: ActivityLevel) -> [PatternSortPiece] {
        switch material {
        case .vehicles: return vehicles.map(PatternSortPiece.vehicle)
        case .shapes: return (level == .l3 ? PatternSortShape.allCases : PatternSortShape.belowTopTier).map(PatternSortPiece.block)
        }
    }

    /// Design §3.2 / T5 confusable guard [TO-VERIFY U1]: these two are never told apart below ★★★.
    public static let confusablePairs: [Set<PatternSortPiece>] = [
        [.vehicle(.tram), .vehicle(.bus)], [.vehicle(.mixer), .vehicle(.roller)],
        [.vehicle(.digger), .vehicle(.dozer)], [.block(.square), .block(.rectangle)]
    ]

    /// True when two pieces that must be told apart are a guarded pair below ★★★.
    public static func guardBlocks(_ a: PatternSortPiece, _ b: PatternSortPiece, level: ActivityLevel) -> Bool {
        level < .l3 && confusablePairs.contains([a, b])
    }
}

/// Design D8 / §5.5 / T4: simulated colour vision. Machado, Oliveira & Fernandes (2009) dichromat matrices at
/// severity 1.0 on linear sRGB, then CIELAB (D65) CIE76 distance. A pair's distance is its minimum over normal
/// vision and the three simulations. Thresholds (the P0 session's provisional choice, [TO-VERIFY] with Carter, U6):
/// a colour that decides an answer or a garage must be a listed safe pair ≥ `pairThreshold`; any two different
/// colours shown together must stay ≥ `noiseThreshold`. 15 is the most the palette allows: no four body colours
/// stay pairwise ≥ 20, so "colours all different" noise (★★★) needs a threshold ≤ 15.8 (yellow / orange, deutan).
public enum PatternSortColourVision {
    public enum Vision: String, CaseIterable, Sendable { case normal, protan, deutan, tritan }

    public static let pairThreshold = 30.0
    public static let noiseThreshold = 15.0

    /// The colour-blind-safe pairs (design §5.5): blue↔yellow, purple↔yellow, blue↔orange. Red and green are never
    /// paired, and red never decides an answer. Ordered arrays, never sets: the seeded generators enumerate and shuffle
    /// them, and a set's order can change from one process to the next (astra R1).
    public static let safePairs: [[PatternSortColour]] = [[.blue, .yellow], [.purple, .yellow], [.blue, .orange]]

    public static func isSafePair(_ a: PatternSortColour, _ b: PatternSortColour) -> Bool {
        a != b && safePairs.contains { $0 == [a, b] || $0 == [b, a] } && distance(a.rgb, b.rgb) >= pairThreshold
    }

    private static let matrices: [Vision: [[Double]]] = [
        .protan: [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
        .deutan: [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
        .tritan: [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]]
    ]

    private static func linear(_ rgb: UInt32) -> [Double] {
        [Double((rgb >> 16) & 0xFF), Double((rgb >> 8) & 0xFF), Double(rgb & 0xFF)].map { value in
            let c = value / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
    }

    /// CIELAB of `rgb` as seen with `vision`.
    public static func lab(_ rgb: UInt32, vision: Vision) -> [Double] {
        var v = linear(rgb)
        if let m = matrices[vision] {
            v = (0..<3).map { row in min(1, max(0, (0..<3).reduce(0) { $0 + m[row][$1] * v[$1] })) }
        }
        let x = 0.4124 * v[0] + 0.3576 * v[1] + 0.1805 * v[2]
        let y = 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]
        let z = 0.0193 * v[0] + 0.1192 * v[1] + 0.9505 * v[2]
        func f(_ t: Double) -> Double { t > 216.0 / 24389.0 ? pow(t, 1.0 / 3.0) : (24389.0 / 27.0 * t + 16) / 116 }
        let fx = f(x / 0.95047), fy = f(y), fz = f(z / 1.08883)
        return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)]
    }

    /// Minimum CIE76 distance over normal vision and the three simulations (the app's colours come from a table).
    public static func distance(_ a: UInt32, _ b: UInt32) -> Double {
        if let known = table[key(a, b)] { return known }
        return measured(a, b)
    }

    private static func key(_ a: UInt32, _ b: UInt32) -> UInt64 { UInt64(min(a, b)) << 32 | UInt64(max(a, b)) }

    private static func measured(_ a: UInt32, _ b: UInt32) -> Double {
        Vision.allCases.map { vision in
            let p = lab(a, vision: vision), q = lab(b, vision: vision)
            return ((p[0] - q[0]) * (p[0] - q[0]) + (p[1] - q[1]) * (p[1] - q[1]) + (p[2] - q[2]) * (p[2] - q[2])).squareRoot()
        }.min() ?? 0
    }

    private static let table: [UInt64: Double] = {
        let rgbs = PatternSortColour.allCases.map(\.rgb) + PatternSortProp.allCases.map(\.shadeRGB)
        var result: [UInt64: Double] = [:]
        for a in rgbs { for b in rgbs { result[key(a, b)] = measured(a, b) } }
        return result
    }()

    /// Every two different named colours among `looks` stay ≥ `noiseThreshold` (props at their PNG shade unless
    /// `shades` is false), and red never shows with green.
    public static func distinct(_ looks: [PatternSortLook], shades: Bool = true) -> Bool {
        let colours = Set(looks.map(\.colour))
        if colours.contains(.red) && colours.contains(.green) { return false }
        for i in looks.indices {
            for j in looks.indices where j > i && looks[i].colour != looks[j].colour {
                let a = shades ? looks[i].rgb : looks[i].colour.rgb, b = shades ? looks[j].rgb : looks[j].colour.rgb
                if distance(a, b) < noiseThreshold { return false }
            }
        }
        return true
    }
}
