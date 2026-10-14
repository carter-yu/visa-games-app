import Foundation

/// How the vehicles to count are arranged (design §7: L1 one row, L2 two rows, L3 scattered).
public enum CountLayout: String, Sendable, Codable, Hashable {
    case row
    case twoRows = "rows2"
    case scatter
}

/// One vehicle on the count stimulus: centre and size in `CountCanvas` units.
public struct CountPlacement: Sendable, Codable, Equatable, Hashable {
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

    public var minX: Double { x - width / 2 }
    public var maxX: Double { x + width / 2 }
    public var minY: Double { y - height / 2 }
    public var maxY: Double { y + height / 2 }

    /// Rectangles at least `gap` apart on one axis (they never touch or overlap).
    public func isSeparated(from other: CountPlacement, gap: Double) -> Bool {
        maxX + gap <= other.minX || other.maxX + gap <= minX
            || maxY + gap <= other.minY || other.maxY + gap <= minY
    }
}

/// Drawing space of the count stimulus (the app scales it into the enlarged stimulus panel).
public enum CountCanvas {
    public static let width: Double = 820
    public static let height: Double = 220
    /// Minimum clear space between two vehicles (design §6 rule: never overlap).
    public static let minGap: Double = 4

    /// Scatter grid (L3): 5 × 3 cells, `count` of them used.
    static let scatterColumns = 5
    static let scatterRows = 3
}

/// Generated facts behind a count question (nil on the fixed v0 catalog item).
public struct CountVariant: Sendable, Codable, Equatable {
    public var level: ActivityLevel
    public var vehicle: HeroVehicle
    public var layout: CountLayout
    public var placements: [CountPlacement]
    /// Stable item id, e.g. `countVehicles.L2.n5.articulatedBus.rows2` (design §1.4).
    public var itemID: String
    public var hintTraditionalChinese: String

    public init(level: ActivityLevel, vehicle: HeroVehicle, layout: CountLayout, placements: [CountPlacement],
                itemID: String, hintTraditionalChinese: String) {
        self.level = level
        self.vehicle = vehicle
        self.layout = layout
        self.placements = placements
        self.itemID = itemID
        self.hintTraditionalChinese = hintTraditionalChinese
    }
}

/// countVehicles variants (design §7). Stays the "test" version: no counting scaffold,
/// one vehicle kind per question, three numeral cards n−1 / n / n+1 (narrowed at 1 and 10).
public enum CountVehiclesGenerator: ActivityQuestionGenerator {
    public static let kind: ActivityKind = .countVehicles
    public static let maxCount = 10

    /// N per tier: L1 1–3 (one row), L2 2–6 (two rows), L3 4–10 (scattered).
    public static func countRange(_ level: ActivityLevel) -> ClosedRange<Int> {
        switch level {
        case .l1: return 1...3
        case .l2: return 2...6
        case .l3: return 4...10
        }
    }

    public static func layout(_ level: ActivityLevel) -> CountLayout {
        switch level {
        case .l1: return .row
        case .l2: return .twoRows
        case .l3: return .scatter
        }
    }

    /// Three consecutive numerals containing `n`, centred on `n` when possible, inside 1...10.
    /// Consecutive windows never hold both 6 and 9 (numeral confusion pair N1).
    public static func choiceCounts(for n: Int) -> [Int] {
        let low = min(max(n - 1, 1), maxCount - 2)
        return [low, low + 1, low + 2]
    }

    public static func make(seed: String, level: ActivityLevel, avoidingItem: String?) -> CountQuestion {
        avoiding(seed: seed, avoidingItem: avoidingItem) { build(seed: $0, level: level) }
    }

    public static func itemID(of question: CountQuestion) -> String {
        question.variant?.itemID ?? question.completionID
    }

    static func build(seed: String, level: ActivityLevel) -> CountQuestion {
        var rng = QuestionRNG(seed: seed, salt: "gen.countVehicles.\(level.code)")
        let n = rng.int(in: countRange(level))
        let vehicle = rng.pick(HeroVehicle.allCases)
        let arrangement = Self.layout(level)
        let spots = Self.placements(count: n, layout: arrangement, rng: &rng)
        let itemID = "countVehicles.\(level.code).n\(n).\(vehicle.rawValue).\(arrangement.rawValue)"
        let zh = vehicle.nameTraditionalChinese
        let variant = CountVariant(
            level: level,
            vehicle: vehicle,
            layout: arrangement,
            placements: spots,
            itemID: itemID,
            hintTraditionalChinese: "提示：一架一架數\(zh)。 / Hint: count the \(vehicle.pluralEnglish) one by one."
        )
        return CountQuestion(
            promptTraditionalChinese: "數一數有幾多架\(zh)呀？撳個數字！",
            promptEnglish: "How many \(vehicle.pluralEnglish)? Tap the number!",
            vehicleAssetIDs: Array(repeating: vehicle.assetID, count: n),
            correctCount: n,
            choiceCounts: choiceCounts(for: n),
            completionID: itemID,
            variant: variant
        )
    }

    /// Centred rows (L1 / L2) or a jittered 5 × 3 grid (L3). Cells never overlap, so no
    /// two vehicles touch whatever the jitter.
    public static func placements(count n: Int, layout: CountLayout, rng: inout QuestionRNG) -> [CountPlacement] {
        let width = CountCanvas.width
        let height = CountCanvas.height
        func row(_ count: Int, y: Double, itemWidth: Double, itemHeight: Double, gap: Double) -> [CountPlacement] {
            guard count > 0 else { return [] }
            let total = Double(count) * itemWidth + Double(count - 1) * gap
            let start = (width - total) / 2 + itemWidth / 2
            return (0..<count).map { index in
                CountPlacement(x: start + Double(index) * (itemWidth + gap), y: y,
                               width: itemWidth, height: itemHeight)
            }
        }
        switch layout {
        case .row:
            return row(n, y: height / 2, itemWidth: 230, itemHeight: 170, gap: 40)
        case .twoRows:
            let top = (n + 1) / 2
            return row(top, y: 56, itemWidth: 170, itemHeight: 96, gap: 36)
                + row(n - top, y: 164, itemWidth: 170, itemHeight: 96, gap: 36)
        case .scatter:
            let columns = CountCanvas.scatterColumns
            let rows = CountCanvas.scatterRows
            let cellWidth = width / Double(columns)
            let cellHeight = height / Double(rows)
            let itemWidth = 136.0
            let itemHeight = 62.0
            let slackX = (cellWidth - itemWidth) / 2 - CountCanvas.minGap / 2
            let slackY = (cellHeight - itemHeight) / 2 - CountCanvas.minGap / 2
            let cells = rng.sample(Array(0..<(columns * rows)), count: min(n, columns * rows))
            return cells.map { cell in
                let column = Double(cell % columns)
                let rowIndex = Double(cell / columns)
                let dx = rng.signedUnit() * max(0, slackX)
                let dy = rng.signedUnit() * max(0, slackY)
                return CountPlacement(x: (column + 0.5) * cellWidth + dx, y: (rowIndex + 0.5) * cellHeight + dy,
                                      width: itemWidth, height: itemHeight)
            }
        }
    }

    /// Wrong-numeral tags (design §3 / §7): distance plus numeral-shape confusion.
    public static func tags(chosen: Int, correct: Int) -> [String] {
        guard chosen != correct else { return [] }
        var tags: [String]
        switch chosen - correct {
        case -1: tags = ["under_by_1"]
        case 1: tags = ["over_by_1"]
        default: tags = ["off_by_2plus"]
        }
        let pair = Set([chosen, correct])
        for confusion in [[6, 9], [1, 7], [2, 5]] where pair == Set(confusion) {
            tags.append("numeral_confusion:\(confusion[0])-\(confusion[1])")
        }
        return tags
    }
}

extension CountQuestion {
    /// Hint line for this question (generated variants name the vehicle).
    public var hintTraditionalChinese: String {
        variant?.hintTraditionalChinese ?? ActivityCatalog.hintTraditionalChinese(for: .countVehicles)
    }

    /// Item id written to `game_dealt.item`.
    public var itemID: String { variant?.itemID ?? completionID }

    /// Placements are inside the canvas and at least `CountCanvas.minGap` apart.
    public var placementsAreClear: Bool {
        guard let variant else { return true }
        let spots = variant.placements
        guard spots.count == correctCount else { return false }
        for spot in spots {
            guard spot.width > 0, spot.height > 0,
                  spot.minX >= 0, spot.minY >= 0,
                  spot.maxX <= CountCanvas.width, spot.maxY <= CountCanvas.height else { return false }
        }
        for i in spots.indices {
            for j in spots.indices where j > i {
                if !spots[i].isSeparated(from: spots[j], gap: CountCanvas.minGap) { return false }
            }
        }
        return true
    }
}
