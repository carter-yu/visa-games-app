import Foundation

// 連一連 / Line Match content (design §6, D12 A+): one category per question, school-worksheet
// pictures joined to Hong Kong Traditional words, or groups of objects joined to numerals.

/// Question category. Exactly one per question; picked by the parent-adjustable weights.
public enum LineMatchCategory: String, CaseIterable, Sendable, Codable, Hashable {
    case numbers
    case body
    case animals
    case zodiac

    /// Design §6 「類別比例」 defaults (2026-10-14): 數字 35 / 身體 30 / 動物 20 / 生肖 15.
    public var defaultWeight: Int {
        switch self {
        case .numbers: return 35
        case .body: return 30
        case .animals: return 20
        case .zodiac: return 15
        }
    }

    public var titleTraditionalChinese: String {
        switch self {
        case .numbers: return "數字"
        case .body: return "身體部位"
        case .animals: return "小動物"
        case .zodiac: return "十二生肖"
        }
    }

    public var titleEnglish: String {
        switch self {
        case .numbers: return "Numbers"
        case .body: return "Body parts"
        case .animals: return "Animals"
        case .zodiac: return "Zodiac"
        }
    }

    /// ★ never deals the zodiac; its share goes to the other categories (design §6 類別比例).
    public func isDealt(at level: ActivityLevel) -> Bool {
        !(self == .zodiac && level == .l1)
    }
}

/// One picture ↔ word pair of a word category.
public struct LineMatchItem: Sendable, Equatable, Codable, Hashable {
    /// Pairing key, unique inside its category (`eye`, `rabbit`).
    public var id: String
    /// `LineMatchArt` icon key. Zodiac 兔 / 猴 / 狗 share the small-animal icon (design note).
    public var iconKey: String
    public var labelTraditionalChinese: String
    public var labelEnglish: String
    /// ★ pool: the easiest-to-recognise pictures (design §6 難度).
    public var isStarter: Bool

    public init(id: String, iconKey: String, labelTraditionalChinese: String, labelEnglish: String,
                isStarter: Bool) {
        self.id = id
        self.iconKey = iconKey
        self.labelTraditionalChinese = labelTraditionalChinese
        self.labelEnglish = labelEnglish
        self.isStarter = isStarter
    }
}

/// Confusion-safe groups (design §6 易混組): at most one member of a group per question.
public struct LineMatchConfusionGroup: Sendable, Equatable, Hashable {
    public var code: String
    public var category: LineMatchCategory
    /// Item ids (word categories) or numerals as strings (`"6"`, `"9"`).
    public var members: Set<String>

    public init(code: String, category: LineMatchCategory, members: Set<String>) {
        self.code = code
        self.category = category
        self.members = members
    }
}

/// The objects counted on numbers cards (design §6 數字類別). One kind per question.
public enum LineMatchCountObject: String, CaseIterable, Sendable, Codable, Hashable {
    case chick
    case minifire
    case apple

    public var iconKey: String { rawValue }

    /// Cantonese measure word: 小雞「隻」、消防車「架」、蘋果「個」.
    public var measureWord: String {
        switch self {
        case .chick: return "隻"
        case .minifire: return "架"
        case .apple: return "個"
        }
    }

    public var nameTraditionalChinese: String {
        switch self {
        case .chick: return "小雞"
        case .minifire: return "消防車"
        case .apple: return "蘋果"
        }
    }

    public var pluralEnglish: String {
        switch self {
        case .chick: return "chicks"
        case .minifire: return "fire engines"
        case .apple: return "apples"
        }
    }

    /// Size of the artwork box (`LineMatchArt`), so layout and drawing agree.
    public var artSize: (width: Double, height: Double) {
        switch self {
        case .chick: return (50, 50)
        case .minifire: return (56, 40)
        case .apple: return (44, 48)
        }
    }
}

public enum LineMatchCatalog {
    public static let body: [LineMatchItem] = [
        LineMatchItem(id: "eye", iconKey: "eye", labelTraditionalChinese: "眼睛", labelEnglish: "eye", isStarter: true),
        LineMatchItem(id: "ear", iconKey: "ear", labelTraditionalChinese: "耳仔", labelEnglish: "ear", isStarter: true),
        LineMatchItem(id: "mouth", iconKey: "mouth", labelTraditionalChinese: "口", labelEnglish: "mouth", isStarter: false),
        LineMatchItem(id: "nose", iconKey: "nose", labelTraditionalChinese: "鼻", labelEnglish: "nose", isStarter: true),
        LineMatchItem(id: "hand", iconKey: "hand", labelTraditionalChinese: "手", labelEnglish: "hand", isStarter: true),
        LineMatchItem(id: "foot", iconKey: "foot", labelTraditionalChinese: "腳", labelEnglish: "foot", isStarter: false)
    ]

    public static let animals: [LineMatchItem] = [
        LineMatchItem(id: "cat", iconKey: "cat", labelTraditionalChinese: "貓仔", labelEnglish: "cat", isStarter: true),
        LineMatchItem(id: "dog", iconKey: "dog", labelTraditionalChinese: "狗仔", labelEnglish: "dog", isStarter: true),
        LineMatchItem(id: "calf", iconKey: "calf", labelTraditionalChinese: "牛仔", labelEnglish: "calf", isStarter: false),
        LineMatchItem(id: "rabbit", iconKey: "rabbit", labelTraditionalChinese: "兔仔", labelEnglish: "rabbit", isStarter: true),
        LineMatchItem(id: "fawn", iconKey: "fawn", labelTraditionalChinese: "鹿仔", labelEnglish: "fawn", isStarter: false),
        LineMatchItem(id: "monkey", iconKey: "monkey", labelTraditionalChinese: "馬騮仔", labelEnglish: "monkey", isStarter: true)
    ]

    public static let zodiac: [LineMatchItem] = [
        LineMatchItem(id: "rat", iconKey: "rat", labelTraditionalChinese: "鼠", labelEnglish: "rat", isStarter: false),
        LineMatchItem(id: "ox", iconKey: "ox", labelTraditionalChinese: "牛", labelEnglish: "ox", isStarter: false),
        LineMatchItem(id: "tiger", iconKey: "tiger", labelTraditionalChinese: "虎", labelEnglish: "tiger", isStarter: false),
        LineMatchItem(id: "rabbit", iconKey: "rabbit", labelTraditionalChinese: "兔", labelEnglish: "rabbit", isStarter: false),
        LineMatchItem(id: "dragon", iconKey: "dragon", labelTraditionalChinese: "龍", labelEnglish: "dragon", isStarter: false),
        LineMatchItem(id: "snake", iconKey: "snake", labelTraditionalChinese: "蛇", labelEnglish: "snake", isStarter: false),
        LineMatchItem(id: "horse", iconKey: "horse", labelTraditionalChinese: "馬", labelEnglish: "horse", isStarter: false),
        LineMatchItem(id: "goat", iconKey: "goat", labelTraditionalChinese: "羊", labelEnglish: "goat", isStarter: false),
        LineMatchItem(id: "monkey", iconKey: "monkey", labelTraditionalChinese: "猴", labelEnglish: "monkey", isStarter: false),
        LineMatchItem(id: "rooster", iconKey: "rooster", labelTraditionalChinese: "雞", labelEnglish: "rooster", isStarter: false),
        LineMatchItem(id: "dog", iconKey: "dog", labelTraditionalChinese: "狗", labelEnglish: "dog", isStarter: false),
        LineMatchItem(id: "pig", iconKey: "pig", labelTraditionalChinese: "豬", labelEnglish: "pig", isStarter: false)
    ]

    /// Design §6 易混組. A1 / A2 / A4 / A5 span small animals and the zodiac; both sides are
    /// listed so the rule holds inside whichever category is dealt.
    public static let confusionGroups: [LineMatchConfusionGroup] = [
        LineMatchConfusionGroup(code: "B1", category: .body, members: ["hand", "foot"]),
        LineMatchConfusionGroup(code: "B2", category: .body, members: ["eye", "mouth"]),
        LineMatchConfusionGroup(code: "A1", category: .animals, members: ["calf", "fawn"]),
        LineMatchConfusionGroup(code: "A2", category: .animals, members: ["fawn"]),
        LineMatchConfusionGroup(code: "A3", category: .animals, members: ["cat"]),
        LineMatchConfusionGroup(code: "A4", category: .animals, members: ["dog"]),
        LineMatchConfusionGroup(code: "A5", category: .animals, members: ["monkey"]),
        LineMatchConfusionGroup(code: "A1", category: .zodiac, members: ["ox", "goat"]),
        LineMatchConfusionGroup(code: "A2", category: .zodiac, members: ["horse", "goat"]),
        LineMatchConfusionGroup(code: "A3", category: .zodiac, members: ["tiger"]),
        LineMatchConfusionGroup(code: "A4", category: .zodiac, members: ["dog", "pig"]),
        LineMatchConfusionGroup(code: "A5", category: .zodiac, members: ["rat", "monkey"]),
        LineMatchConfusionGroup(code: "A6", category: .zodiac, members: ["snake", "dragon"]),
        LineMatchConfusionGroup(code: "N1", category: .numbers, members: ["6", "9"])
    ]

    public static func items(_ category: LineMatchCategory) -> [LineMatchItem] {
        switch category {
        case .numbers: return []
        case .body: return body
        case .animals: return animals
        case .zodiac: return zodiac
        }
    }

    public static func item(_ id: String, in category: LineMatchCategory) -> LineMatchItem? {
        items(category).first { $0.id == id }
    }

    /// Groups of `category` that contain `id`.
    public static func groups(of id: String, in category: LineMatchCategory) -> [LineMatchConfusionGroup] {
        confusionGroups.filter { $0.category == category && $0.members.contains(id) }
    }

    /// True when no confusion group holds two of `ids`.
    public static func isConfusionSafe(_ ids: [String], in category: LineMatchCategory) -> Bool {
        for group in confusionGroups where group.category == category {
            if ids.filter({ group.members.contains($0) }).count > 1 { return false }
        }
        return true
    }

    /// 「1 一」…「10 十」 Chinese numerals (HK Traditional; same characters in both scripts).
    public static func chineseNumeral(_ n: Int) -> String {
        let numerals = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        guard n >= 1, n <= numerals.count else { return "" }
        return numerals[n - 1]
    }

    public static func englishNumber(_ n: Int) -> String {
        let words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        guard n >= 1, n <= words.count else { return "" }
        return words[n - 1]
    }
}

/// One object on a numbers card: centre and size relative to the card's top-left corner.
public struct LineMatchObjectPlacement: Sendable, Equatable, Codable, Hashable {
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

    /// At least `gap` apart on one axis (never touching or overlapping).
    public func isSeparated(from other: LineMatchObjectPlacement, gap: Double) -> Bool {
        maxX + gap <= other.minX || other.maxX + gap <= minX
            || maxY + gap <= other.minY || other.maxY + gap <= minY
    }
}

/// Count-card arrangements (design §6 排法): 1 centred; 2 / 3 one row; 4 = 2 × 2; 5 = dice five;
/// 6 = two rows of 3; 7–10 = ten frame (5 on top, the rest from the left underneath).
/// Same object size, direction and colour on every card; only the count changes.
public enum LineMatchCountLayout {
    /// Clear space between two objects (design: ≥ 4u, never overlapping).
    public static let minGap: Double = 4
    /// Clear space to the card edge (design: ≥ 7u). The 6u card outline sits inside this.
    public static let edgeMargin: Double = 8
    /// Largest object side (design: 40–55u, countable on the TV).
    public static let maxObjectSide: Double = 54
    /// Pitch floor: object + gap + 1u slack, so rounding can never bring two objects under `minGap`.
    static let spacing: Double = minGap + 1

    /// Pattern positions in pitch units around the card centre.
    public static func pattern(_ n: Int) -> [(x: Double, y: Double)] {
        switch n {
        case 1: return [(0, 0)]
        case 2: return [(-0.5, 0), (0.5, 0)]
        case 3: return [(-1, 0), (0, 0), (1, 0)]
        case 4: return [(-0.5, -0.5), (0.5, -0.5), (-0.5, 0.5), (0.5, 0.5)]
        case 5: return [(-1, -0.5), (1, -0.5), (0, 0), (-1, 0.5), (1, 0.5)]
        case 6: return [(-1, -0.5), (0, -0.5), (1, -0.5), (-1, 0.5), (0, 0.5), (1, 0.5)]
        case 7...10:
            let top = (0..<5).map { (x: Double($0) - 2, y: -0.5) }
            let bottom = (0..<(n - 5)).map { (x: Double($0) - 2, y: 0.5) }
            return top + bottom
        default: return []
        }
    }

    /// One object size for every card of a question (so only the count differs between cards).
    public static func objectScale(object: LineMatchCountObject, counts: [Int],
                                   cardWidth: Double, cardHeight: Double) -> Double {
        let art = object.artSize
        var scale = maxObjectSide / max(art.width, art.height)
        for n in counts {
            let points = pattern(n)
            guard !points.isEmpty else { continue }
            let halfColumns = points.map { abs($0.x) }.max() ?? 0
            let halfRows = points.map { abs($0.y) }.max() ?? 0
            // Pitch ≥ object + spacing: halfColumns × (w + spacing) + w / 2 ≤ card / 2 − margin.
            let byWidth = (cardWidth / 2 - edgeMargin - halfColumns * spacing) / (art.width * (halfColumns + 0.5))
            let byHeight = (cardHeight / 2 - edgeMargin - halfRows * spacing) / (art.height * (halfRows + 0.5))
            scale = min(scale, byWidth, byHeight)
        }
        return max(0.1, scale)
    }

    /// Placements of `n` objects inside a card. Neighbours are spread a little when the card
    /// has room, but never closer than `minGap` and never nearer the edge than `edgeMargin`.
    public static func placements(count n: Int, object: LineMatchCountObject, scale: Double,
                                  cardWidth: Double, cardHeight: Double) -> [LineMatchObjectPlacement] {
        let points = pattern(n)
        guard !points.isEmpty else { return [] }
        let width = object.artSize.width * scale
        let height = object.artSize.height * scale
        let halfColumns = points.map { abs($0.x) }.max() ?? 0
        let halfRows = points.map { abs($0.y) }.max() ?? 0
        var pitchX = width + spacing
        var pitchY = height + spacing
        if halfColumns > 0 {
            let room = (cardWidth / 2 - edgeMargin - width / 2) / halfColumns
            pitchX = max(pitchX, min(width * 1.3, room))
        }
        if halfRows > 0 {
            let room = (cardHeight / 2 - edgeMargin - height / 2) / halfRows
            pitchY = max(pitchY, min(height * 1.25, room))
        }
        return points.map { point in
            LineMatchObjectPlacement(x: cardWidth / 2 + point.x * pitchX, y: cardHeight / 2 + point.y * pitchY,
                                     width: width, height: height)
        }
    }

    /// Placements are inside the card margin and pairwise separated.
    public static func isClear(_ spots: [LineMatchObjectPlacement], cardWidth: Double, cardHeight: Double) -> Bool {
        for spot in spots {
            guard spot.width > 0, spot.height > 0,
                  spot.minX >= edgeMargin - 1, spot.minY >= edgeMargin - 1,
                  spot.maxX <= cardWidth - edgeMargin + 1, spot.maxY <= cardHeight - edgeMargin + 1 else { return false }
        }
        for i in spots.indices {
            for j in spots.indices where j > i {
                if !spots[i].isSeparated(from: spots[j], gap: minGap) { return false }
            }
        }
        return true
    }
}
