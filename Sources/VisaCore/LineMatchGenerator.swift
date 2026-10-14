import Foundation

// MARK: - Parent settings (design §1.7 寬容度, §6 類別比例)

/// How close the pen must land to a dot (design §1.7, D2 A+). Only the hit radius changes;
/// the drawn dots look the same at every setting.
public enum LineMatchTolerance: String, CaseIterable, Sendable, Codable, Hashable {
    case narrow
    case standard
    case wide

    /// Dot hit radius in stage units (drawn dots are 22u).
    public var dotRadius: Double {
        switch self {
        case .narrow: return 40
        case .standard: return 60
        case .wide: return 90
        }
    }

    /// Guided roads (design §1.7 路面判定闊度): the judged corridor is the drawn road width
    /// times this. The road itself is drawn the same at every setting.
    public var roadWidthFactor: Double {
        switch self {
        case .narrow: return 1.0
        case .standard: return 1.5
        case .wide: return 2.2
        }
    }

    /// Guided roads (design §1.7 「到咗終點」誤差): a road counts as driven once the truck is
    /// this close to the red dot (or past 97% of the road, whichever comes first).
    public var arrivalSlack: Double {
        switch self {
        case .narrow: return 30
        case .standard: return 50
        case .wide: return 80
        }
    }

    public var labelTraditionalChinese: String {
        switch self {
        case .narrow: return "窄"
        case .standard: return "標準"
        case .wide: return "闊"
        }
    }

    public var labelEnglish: String {
        switch self {
        case .narrow: return "Narrow"
        case .standard: return "Standard"
        case .wide: return "Wide"
        }
    }
}

/// 連一連 parent settings: hit tolerance, category weights and guided mode. UserDefaults, not
/// the reward snapshot. Weights are relative (0–100 in steps of 5); 0 = never dealt; at least
/// one stays > 0.
public struct LineMatchSettings: Equatable, Sendable {
    public static let weightStep = 5
    public static let maxWeight = 100
    /// v0.24.0 (Carter 2026-10-14 21:26): ★ and ★★ are guided roads, ★★★ stays free match.
    /// The parent can switch guided off (then every star is free match, as in v0.23).
    public static let defaultGuided = true

    public var tolerance: LineMatchTolerance
    public private(set) var weights: [LineMatchCategory: Int]
    /// 引導連線: ★ / ★★ deal guided roads instead of free matching.
    public var guided: Bool

    public init(tolerance: LineMatchTolerance = .standard, weights: [LineMatchCategory: Int] = [:],
                guided: Bool = LineMatchSettings.defaultGuided) {
        self.tolerance = tolerance
        self.guided = guided
        var filled: [LineMatchCategory: Int] = [:]
        for category in LineMatchCategory.allCases {
            let raw = weights[category] ?? category.defaultWeight
            filled[category] = min(max(raw, 0), Self.maxWeight)
        }
        if filled.values.allSatisfy({ $0 == 0 }) {
            for category in LineMatchCategory.allCases { filled[category] = category.defaultWeight }
        }
        self.weights = filled
    }

    public static let defaults = LineMatchSettings()

    public func weight(_ category: LineMatchCategory) -> Int {
        weights[category] ?? category.defaultWeight
    }

    public var hasDefaultMix: Bool {
        LineMatchCategory.allCases.allSatisfy { weight($0) == $0.defaultWeight }
    }

    /// One step up or down. Returns nil when the change would turn every category off.
    public func adjusting(_ category: LineMatchCategory, steps: Int) -> LineMatchSettings? {
        var next = weights
        let value = min(max(weight(category) + steps * Self.weightStep, 0), Self.maxWeight)
        next[category] = value
        if next.values.allSatisfy({ $0 == 0 }) { return nil }
        return LineMatchSettings(tolerance: tolerance, weights: next, guided: guided)
    }

    public func withTolerance(_ value: LineMatchTolerance) -> LineMatchSettings {
        LineMatchSettings(tolerance: value, weights: weights, guided: guided)
    }

    public func withDefaultMix() -> LineMatchSettings {
        LineMatchSettings(tolerance: tolerance, guided: guided)
    }

    public func withGuided(_ value: Bool) -> LineMatchSettings {
        LineMatchSettings(tolerance: tolerance, weights: weights, guided: value)
    }

    /// Guided roads at ★ / ★★ when 引導連線 is on; ★★★ is always free match.
    public func mode(for level: ActivityLevel) -> LineMatchMode {
        guided && LineMatchMode.isGuidedLevel(level) ? .guided : .free
    }

    /// Categories and weights a question of `level` is drawn from, in `allCases` order.
    /// ★ skips the zodiac (its share goes to the others). If nothing is left, the design
    /// defaults for that level are used, so a deal never fails.
    public func dealWeights(for level: ActivityLevel) -> [(category: LineMatchCategory, weight: Int)] {
        let dealt = LineMatchCategory.allCases.filter { $0.isDealt(at: level) }
        let chosen = dealt.map { (category: $0, weight: weight($0)) }
        if chosen.contains(where: { $0.weight > 0 }) { return chosen }
        return dealt.map { (category: $0, weight: $0.defaultWeight) }
    }

    /// Share of `category` among the questions of `level` (0…1).
    public func share(of category: LineMatchCategory, at level: ActivityLevel) -> Double {
        let mix = dealWeights(for: level)
        let total = mix.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return 0 }
        return Double(mix.first { $0.category == category }?.weight ?? 0) / Double(total)
    }

    /// `numbers:35,body:30,animals:20,zodiac:15` — written to `game_dealt.category_mix`.
    public var mixDescription: String {
        LineMatchCategory.allCases.map { "\($0.rawValue):\(weight($0))" }.joined(separator: ",")
    }
}

/// UserDefaults store beside `MissionGameAssignmentStore`. Missing or corrupt → defaults.
public struct LineMatchSettingsStore {
    public static let key = "VisaGames.lineMatchSettings.v1"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> LineMatchSettings {
        guard let data = defaults.data(forKey: Self.key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return .defaults }
        return payload.settings
    }

    public func save(_ settings: LineMatchSettings) {
        guard let data = try? JSONEncoder().encode(Payload(settings: settings)) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private struct Payload: Codable {
        var tolerance: String?
        var weights: [String: Int]?
        /// v0.24.0. Missing (a v0.23 store) → `LineMatchSettings.defaultGuided`.
        var guided: Bool?

        init(settings: LineMatchSettings) {
            tolerance = settings.tolerance.rawValue
            guided = settings.guided
            var map: [String: Int] = [:]
            for category in LineMatchCategory.allCases { map[category.rawValue] = settings.weight(category) }
            weights = map
        }

        var settings: LineMatchSettings {
            var parsed: [LineMatchCategory: Int] = [:]
            for (raw, value) in weights ?? [:] {
                guard let category = LineMatchCategory(rawValue: raw) else { continue }
                parsed[category] = value
            }
            let level = tolerance.flatMap(LineMatchTolerance.init(rawValue:)) ?? .standard
            return LineMatchSettings(tolerance: level, weights: parsed, guided: guided ?? LineMatchSettings.defaultGuided)
        }
    }
}

// MARK: - Question

/// One left ↔ right pair. Words: picture → 「眼睛 / eye」. Numbers: N objects → 「5 五」.
public struct LineMatchPair: Sendable, Equatable, Codable, Hashable {
    /// Pairing key: item id (`eye`) or `n5`.
    public var key: String
    /// Left-card picture (numbers: the counted object).
    public var iconKey: String
    /// Objects on the left card (numbers); 1 for picture cards.
    public var count: Int
    /// Right card: the word, or the Chinese numeral.
    public var labelTraditionalChinese: String
    /// Right card English subtitle (words), or the English number (spoken subtitle only).
    public var labelEnglish: String
    /// Numbers: the digit on the right card.
    public var numeral: Int?

    public init(key: String, iconKey: String, count: Int, labelTraditionalChinese: String, labelEnglish: String,
                numeral: Int? = nil) {
        self.key = key
        self.iconKey = iconKey
        self.count = count
        self.labelTraditionalChinese = labelTraditionalChinese
        self.labelEnglish = labelEnglish
        self.numeral = numeral
    }
}

public struct LineMatchQuestion: Sendable, Equatable, Codable {
    public var level: ActivityLevel
    public var category: LineMatchCategory
    /// Numbers only: the one object kind counted on every left card.
    public var countObject: LineMatchCountObject?
    /// Left column, top → bottom.
    public var pairs: [LineMatchPair]
    /// Right column: slot `j` shows `pairs[rightOrder[j]]`. Never a pair on its own row.
    public var rightOrder: [Int]
    /// e.g. `lineMatch.L2.numbers.minifire.5-3-6` (design §6).
    public var itemID: String
    public var promptTraditionalChinese: String
    public var promptEnglish: String
    public var hintTraditionalChinese: String
    /// v0.24.0 guided roads (★ / ★★): road colours and the bridge. Nil = free match.
    /// Guided boards show the word on the LEFT and the picture on the RIGHT (school worksheet),
    /// so `pairs` / `rightOrder` keep their meaning: left row `i` → the slot showing `pairs[i]`.
    public var guided: LineMatchGuidedPlan?

    public init(level: ActivityLevel, category: LineMatchCategory, countObject: LineMatchCountObject?,
                pairs: [LineMatchPair], rightOrder: [Int], itemID: String, promptTraditionalChinese: String,
                promptEnglish: String, hintTraditionalChinese: String, guided: LineMatchGuidedPlan? = nil) {
        self.level = level
        self.category = category
        self.countObject = countObject
        self.pairs = pairs
        self.rightOrder = rightOrder
        self.itemID = itemID
        self.promptTraditionalChinese = promptTraditionalChinese
        self.promptEnglish = promptEnglish
        self.hintTraditionalChinese = hintTraditionalChinese
        self.guided = guided
    }

    public var mode: LineMatchMode { guided == nil ? .free : .guided }
    public var isGuided: Bool { guided != nil }

    public var completionID: String { itemID }
    public var pairCount: Int { pairs.count }

    /// Pair drawn in right slot `slot`.
    public func rightPair(atSlot slot: Int) -> LineMatchPair? {
        guard rightOrder.indices.contains(slot), pairs.indices.contains(rightOrder[slot]) else { return nil }
        return pairs[rightOrder[slot]]
    }

    /// The right slot that completes left row `row`.
    public func correctSlot(forRow row: Int) -> Int? {
        rightOrder.firstIndex(of: row)
    }

    public func isCorrect(row: Int, slot: Int) -> Bool {
        rightOrder.indices.contains(slot) && rightOrder[slot] == row
    }

    /// Right column keys top → bottom (what the child saw; `game_dealt.slots`).
    public var rightKeys: [String] {
        rightOrder.compactMap { pairs.indices.contains($0) ? pairs[$0].key : nil }
    }

    public var isWellFormed: Bool {
        let n = pairs.count
        guard n == LineMatchGenerator.pairCount(level), !itemID.isEmpty else { return false }
        guard Set(pairs.map(\.key)).count == n else { return false }
        guard rightOrder.count == n, Set(rightOrder) == Set(0..<n) else { return false }
        if let guided {
            // Guided (design "Guided level"): ★ straight same-row roads; ★★ staggered picture
            // column with exactly one crossing. Never ★★★.
            guard LineMatchMode.isGuidedLevel(level), guided.isWellFormed(rightOrder: rightOrder, level: level)
            else { return false }
        } else {
            // Design §6: no pair is straight across.
            guard rightOrder.indices.allSatisfy({ rightOrder[$0] != $0 }) else { return false }
        }
        guard pairs.allSatisfy({ !$0.iconKey.isEmpty && !$0.labelTraditionalChinese.isEmpty
                                 && !$0.labelEnglish.isEmpty && $0.count >= 1 }) else { return false }
        guard category.isDealt(at: level) else { return false }
        switch category {
        case .numbers:
            guard let countObject else { return false }
            let numbers = pairs.compactMap(\.numeral)
            guard numbers.count == n, pairs.allSatisfy({ $0.numeral == $0.count && $0.iconKey == countObject.iconKey })
            else { return false }
            return LineMatchGenerator.isValidNumberSet(numbers, level: level)
        default:
            guard countObject == nil, pairs.allSatisfy({ $0.count == 1 && $0.numeral == nil }) else { return false }
            let ids = pairs.map(\.key)
            guard ids.allSatisfy({ LineMatchCatalog.item($0, in: category) != nil }) else { return false }
            if level == .l1, !pairs.allSatisfy({ LineMatchCatalog.item($0.key, in: category)?.isStarter == true }) {
                return false
            }
            return LineMatchCatalog.isConfusionSafe(ids, in: category)
        }
    }
}

// MARK: - Generator

/// 連一連 questions (design §6). A pure function of (seed, level, avoidingItem, category weights):
/// weighted category draw → one confusion-safe set from every valid set of that tier →
/// shuffled left order → right order with no pair straight across. Every step picks from a
/// finite, pre-enumerated list, so generation always terminates.
public enum LineMatchGenerator: ActivityQuestionGenerator {
    public static let kind: ActivityKind = .lineMatch

    /// ★ 2 pairs, ★★ 3, ★★★ 4.
    public static func pairCount(_ level: ActivityLevel) -> Int {
        switch level {
        case .l1: return 2
        case .l2: return 3
        case .l3: return 4
        }
    }

    /// Numbers per tier: ★ 1–5, ★★ 1–7, ★★★ 1–10.
    public static func numberRange(_ level: ActivityLevel) -> ClosedRange<Int> {
        switch level {
        case .l1: return 1...5
        case .l2: return 1...7
        case .l3: return 1...10
        }
    }

    /// Default weights (protocol entry point).
    public static func make(seed: String, level: ActivityLevel, avoidingItem: String?) -> LineMatchQuestion {
        make(seed: seed, level: level, avoidingItem: avoidingItem, settings: .defaults)
    }

    public static func make(seed: String, level: ActivityLevel, avoidingItem: String?,
                            settings: LineMatchSettings) -> LineMatchQuestion {
        avoiding(seed: seed, avoidingItem: avoidingItem) { build(seed: $0, level: level, settings: settings) }
    }

    /// `mode` picks free matching or guided roads. Guided is only dealt at ★ / ★★; asking for
    /// it at ★★★ deals free match (the ★★★ level is always free).
    public static func make(seed: String, level: ActivityLevel, avoidingItem: String?,
                            settings: LineMatchSettings, mode: LineMatchMode) -> LineMatchQuestion {
        guard mode == .guided, LineMatchMode.isGuidedLevel(level) else {
            return make(seed: seed, level: level, avoidingItem: avoidingItem, settings: settings)
        }
        return avoiding(seed: seed, avoidingItem: avoidingItem) {
            buildGuided(seed: $0, level: level, settings: settings)
        }
    }

    public static func itemID(of question: LineMatchQuestion) -> String { question.itemID }

    /// The fixed reference item behind `PerfChoiceCatalog`'s per-kind facts (never dealt).
    public static let reference = build(seed: "lineMatch-reference", level: .l2, settings: .defaults)

    /// The category a seed draws (first step of `build`). Exposed for the weight tests.
    public static func category(seed: String, level: ActivityLevel, settings: LineMatchSettings) -> LineMatchCategory {
        var rng = QuestionRNG(seed: seed, salt: "gen.lineMatch.\(level.code)")
        return drawCategory(level: level, settings: settings, rng: &rng)
    }

    static func drawCategory(level: ActivityLevel, settings: LineMatchSettings,
                             rng: inout QuestionRNG) -> LineMatchCategory {
        let mix = settings.dealWeights(for: level)
        let total = mix.reduce(0) { $0 + $1.weight }
        guard total > 0, let first = mix.first else { return .numbers }
        var ticket = rng.below(total)
        for entry in mix {
            if ticket < entry.weight { return entry.category }
            ticket -= entry.weight
        }
        return first.category
    }

    static func build(seed: String, level: ActivityLevel, settings: LineMatchSettings) -> LineMatchQuestion {
        var rng = QuestionRNG(seed: seed, salt: "gen.lineMatch.\(level.code)")
        let (category, pairs, object) = drawPairs(level: level, settings: settings, rng: &rng)
        let order = derangement(count: pairs.count, rng: &rng)
        var idParts = ["lineMatch", level.code, category.rawValue]
        if let object { idParts.append(object.rawValue) }
        idParts.append(pairs.map { pair in pair.numeral.map { "\($0)" } ?? pair.key }.joined(separator: "-"))
        let prompt: (zh: String, en: String, hint: String)
        if let object {
            prompt = ("數吓有幾多\(object.measureWord)，拉線去啱嘅數字！",
                      "Count the \(object.pluralEnglish), then draw a line to the number!",
                      "提示：一個一個數，數完先拉線。 / Hint: count one by one, then draw the line.")
        } else {
            prompt = ("幫小貨車將圖仔連去啱嘅字！",
                      "Help the truck join each picture to its word!",
                      "提示：由綠點拉去閃緊嘅字卡。 / Hint: draw from the green dot to the shining word.")
        }
        return LineMatchQuestion(
            level: level, category: category, countObject: object, pairs: pairs, rightOrder: order,
            itemID: idParts.joined(separator: "."), promptTraditionalChinese: prompt.zh,
            promptEnglish: prompt.en, hintTraditionalChinese: prompt.hint
        )
    }

    /// Category → item set → shuffled left order → count object (numbers). Shared by free and
    /// guided deals. The draw order is the v0.23.0 one, so free questions are unchanged.
    static func drawPairs(level: ActivityLevel, settings: LineMatchSettings, rng: inout QuestionRNG)
        -> (category: LineMatchCategory, pairs: [LineMatchPair], object: LineMatchCountObject?) {
        var category = drawCategory(level: level, settings: settings, rng: &rng)
        if category != .numbers, wordSets(category, level: level).isEmpty { category = .numbers }
        switch category {
        case .numbers:
            let set = rng.pick(numberSets(level))
            let chosen = rng.shuffled(set)
            let counted = rng.pick(LineMatchCountObject.allCases)
            let pairs = chosen.map { n in
                LineMatchPair(key: "n\(n)", iconKey: counted.iconKey, count: n,
                              labelTraditionalChinese: LineMatchCatalog.chineseNumeral(n),
                              labelEnglish: LineMatchCatalog.englishNumber(n), numeral: n)
            }
            return (category, pairs, counted)
        default:
            let set = rng.pick(wordSets(category, level: level))
            let chosen = rng.shuffled(set)
            let pairs = chosen.map { item in
                LineMatchPair(key: item.id, iconKey: item.iconKey, count: 1,
                              labelTraditionalChinese: item.labelTraditionalChinese, labelEnglish: item.labelEnglish)
            }
            return (category, pairs, nil)
        }
    }

    /// Guided roads (design "Guided level"): same category weights, items and confusion rules
    /// as free match; ★ joins each word to the picture on its own row, ★★ picks one of the
    /// right-column orders with exactly one crossing (the picture column sits half a row lower,
    /// so no pair shares a row). Road colours and the bridge come from the seed.
    /// Item id: `lineMatch.G1.body.eye-hand`, `lineMatch.G2.numbers.chick.4-2-5.p213`.
    static func buildGuided(seed: String, level: ActivityLevel, settings: LineMatchSettings) -> LineMatchQuestion {
        var rng = QuestionRNG(seed: seed, salt: "gen.lineMatch.guided.\(level.code)")
        let (category, pairs, object) = drawPairs(level: level, settings: settings, rng: &rng)
        let n = pairs.count
        let order: [Int]
        switch LineMatchGuidedLayout.style(for: level) {
        case .straight: order = Array(0..<n)
        case .staggered: order = rng.pick(LineMatchGuidedGeometry.singleCrossingOrders(count: n))
        }
        let colors = rng.sample(Array(LineMatchRoadPalette.roads.indices), count: n)
        var bridgeOverRow: Int?
        if let crossing = LineMatchGuidedGeometry.invertedRows(rightOrder: order).first {
            bridgeOverRow = rng.below(2) == 0 ? crossing.upper : crossing.lower
        }
        var idParts = ["lineMatch", LineMatchMode.guidedCode(level), category.rawValue]
        if let object { idParts.append(object.rawValue) }
        idParts.append(pairs.map { pair in pair.numeral.map { "\($0)" } ?? pair.key }.joined(separator: "-"))
        if order != Array(0..<n) { idParts.append("p" + order.map { "\($0 + 1)" }.joined()) }
        let prompt = LineMatchGuidedCopy.prompt(object: object)
        return LineMatchQuestion(
            level: level, category: category, countObject: object, pairs: pairs, rightOrder: order,
            itemID: idParts.joined(separator: "."), promptTraditionalChinese: prompt.zh,
            promptEnglish: prompt.en, hintTraditionalChinese: LineMatchGuidedCopy.hint,
            guided: LineMatchGuidedPlan(colorIndices: colors, bridgeOverRow: bridgeOverRow)
        )
    }

    /// Every valid number set of the tier, ascending (design §6 數字類別出題規則):
    /// ★ two numbers 1–5 at least 2 apart; ★★ three distinct 1–7 with at least one pair 1 apart;
    /// ★★★ four distinct 1–10. Never 6 and 9 together (N1).
    public static func numberSets(_ level: ActivityLevel) -> [[Int]] {
        combinations(Array(numberRange(level)), choose: pairCount(level)).filter { isValidNumberSet($0, level: level) }
    }

    public static func isValidNumberSet(_ numbers: [Int], level: ActivityLevel) -> Bool {
        guard numbers.count == pairCount(level), Set(numbers).count == numbers.count else { return false }
        guard numbers.allSatisfy({ numberRange(level).contains($0) }) else { return false }
        guard !(numbers.contains(6) && numbers.contains(9)) else { return false }
        let sorted = numbers.sorted()
        let gaps = zip(sorted, sorted.dropFirst()).map { $1 - $0 }
        switch level {
        case .l1: return gaps.allSatisfy { $0 >= 2 }
        case .l2: return gaps.contains(1)
        case .l3: return true
        }
    }

    /// Every confusion-safe item set of the tier (★ uses the starter pictures only).
    public static func wordSets(_ category: LineMatchCategory, level: ActivityLevel) -> [[LineMatchItem]] {
        guard category != .numbers, category.isDealt(at: level) else { return [] }
        let pool = LineMatchCatalog.items(category).filter { level != .l1 || $0.isStarter }
        return combinations(pool, choose: pairCount(level)).filter {
            LineMatchCatalog.isConfusionSafe($0.map(\.id), in: category)
        }
    }

    /// Right-column order with no fixed point (no pair straight across). A few seeded
    /// shuffles, then a rotation, which is always a derangement for 2+ pairs.
    static func derangement(count n: Int, rng: inout QuestionRNG) -> [Int] {
        let identity = Array(0..<n)
        guard n >= 2 else { return identity }
        for _ in 0..<12 {
            let order = rng.shuffled(identity)
            if order.indices.allSatisfy({ order[$0] != $0 }) { return order }
        }
        return identity.map { ($0 + 1) % n }
    }

    /// All `k`-element subsets in input order.
    static func combinations<T>(_ items: [T], choose k: Int) -> [[T]] {
        guard k > 0 else { return [[]] }
        guard items.count >= k else { return [] }
        var result: [[T]] = []
        for (index, item) in items.enumerated() {
            let rest = Array(items[(index + 1)...])
            for tail in combinations(rest, choose: k - 1) {
                result.append([item] + tail)
            }
        }
        return result
    }

    // MARK: Tags (design §1.5 / §6 統計 tag)

    /// Tags of one wrong line (left `row` joined to right `slot`). Empty for a right line.
    public static func tags(question: LineMatchQuestion, row: Int, slot: Int) -> [String] {
        guard question.pairs.indices.contains(row), let right = question.rightPair(atSlot: slot),
              !question.isCorrect(row: row, slot: slot) else { return [] }
        let left = question.pairs[row]
        var tags = ["wrong_target", "category:\(question.category.rawValue)", "pair:\(left.key)>\(right.key)"]
        if let object = question.countObject, let numeral = right.numeral {
            let off = abs(numeral - left.count)
            tags.append(off == 1 ? "count_off_by_1" : "count_off_by_2plus")
            if Set([numeral, left.count]) == Set([6, 9]) { tags.append("numeral_confusion:6-9") }
            tags.append("object:\(object.rawValue)")
        } else {
            let leftGroups = Set(LineMatchCatalog.groups(of: left.key, in: question.category).map(\.code))
            let rightGroups = Set(LineMatchCatalog.groups(of: right.key, in: question.category).map(\.code))
            for code in leftGroups.intersection(rightGroups).sorted() { tags.append("confusion:\(code)") }
        }
        return tags
    }
}
