import Foundation

// 跟住排 · 接落去 (patterns-sorting P0, design §3.2): the finite pattern grammar with its evidence (G1), one-answer
// (G2) and choice (G3) rules, and a seeded deal. The UI is P2; P0 is the pure contract and its tests.

/// The repeating units (design §3.2), with period p = 2, 3, 3, 3, 4.
public enum PatternUnit: String, CaseIterable, Sendable, Codable, Hashable {
    case ab = "AB", aab = "AAB", abb = "ABB", abc = "ABC", aabb = "AABB"

    /// Letter of each unit position (0 = A).
    public var letters: [Int] {
        switch self {
        case .ab: return [0, 1]
        case .aab: return [0, 0, 1]
        case .abb: return [0, 1, 1]
        case .abc: return [0, 1, 2]
        case .aabb: return [0, 0, 1, 1]
        }
    }

    public var period: Int { letters.count }
    /// How many different pieces the unit has (2, or 3 for ABC).
    public var distinct: Int { Set(letters).count }
}

public enum PatternTask: String, CaseIterable, Sendable, Codable, Hashable {
    case add1, add2, fill
}

/// One row of the grammar: slots 0…n−1 hold unit[(i + φ) mod p]; the blanks are {n−1} (add 1), {n−2, n−1} (add 2)
/// or {g}, 1 ≤ g ≤ n−2 (fill).
public struct PatternRow: Hashable, Sendable {
    public let unit: PatternUnit
    public let n: Int
    public let phase: Int
    public let task: PatternTask
    /// The fill gap (nil for add 1 / add 2).
    public let gap: Int?

    public init(unit: PatternUnit, n: Int, phase: Int, task: PatternTask, gap: Int? = nil) {
        self.unit = unit
        self.n = n
        self.phase = phase
        self.task = task
        self.gap = task == .fill ? gap : nil
    }

    public var blanks: [Int] {
        switch task {
        case .add1: return [n - 1]
        case .add2: return [n - 2, n - 1]
        case .fill: return gap.map { [$0] } ?? []
        }
    }

    public func letter(at slot: Int) -> Int { unit.letters[((slot + phase) % unit.period + unit.period) % unit.period] }
    public var letters: [Int] { (0..<n).map(letter(at:)) }
    public var visible: [Int] { (0..<n).filter { !blanks.contains($0) } }

    /// The row as text, `_` for a blank: `A B A B A _`.
    public var text: String {
        (0..<n).map { blanks.contains($0) ? "_" : String(UnicodeScalar(UInt8(65 + letter(at: $0)))) }.joined(separator: " ")
    }
}

public enum PatternGrammar {
    /// Rows never exceed 8 slots, blanks included (D13).
    public static let maxSlots = 8

    /// The row's shape is one the grammar allows (n, phase and the blanks in range).
    public static func isWellFormed(_ row: PatternRow) -> Bool {
        guard row.n >= 2, row.n <= maxSlots, row.phase >= 0, row.phase < row.unit.period else { return false }
        switch row.task {
        case .add1, .add2: return row.n > row.blanks.count
        case .fill: return row.gap.map { $0 >= 1 && $0 <= row.n - 2 } ?? false
        }
    }

    /// G1, enough evidence: each unit position (slot index mod p) is visible at least twice; a fill gap's own
    /// position needs one visible copy.
    public static func hasEnoughEvidence(_ row: PatternRow) -> Bool {
        let p = row.unit.period
        for r in 0..<p {
            let shown = row.visible.filter { $0 % p == r }.count
            let needed = row.task == .fill && row.gap.map({ $0 % p == r }) == true ? 1 : 2
            if shown < needed { return false }
        }
        return true
    }

    /// Readings of period q ≤ ⌊n/2⌋ (admissible) whose visible slots agree on every class mod q (consistent).
    public static func consistentPeriods(_ row: PatternRow) -> [Int] {
        guard row.n >= 2 else { return [] }
        let letters = row.letters
        return (1...(row.n / 2)).filter { q in
            var seen: [Int: Int] = [:]
            for slot in row.visible {
                if let known = seen[slot % q], known != letters[slot] { return false }
                seen[slot % q] = letters[slot]
            }
            return true
        }
    }

    /// G2, one answer within the bound: every admissible, consistent reading that shows an item at a blank's class
    /// predicts the true item, and the true unit is the shortest consistent reading.
    public static func hasOneAnswer(_ row: PatternRow) -> Bool {
        let letters = row.letters
        let periods = consistentPeriods(row)
        guard periods.first == row.unit.period else { return false }
        for q in periods {
            for blank in row.blanks {
                if let shown = row.visible.first(where: { $0 % q == blank % q }), letters[shown] != letters[blank] {
                    return false
                }
            }
        }
        return true
    }

    public static func isLegal(_ row: PatternRow) -> Bool {
        isWellFormed(row) && hasEnoughEvidence(row) && hasOneAnswer(row)
    }

    /// Every unit × phase × blank of a task and length, legal or not (T2 enumerates these).
    public static func allRows(unit: PatternUnit, task: PatternTask, n: Int) -> [PatternRow] {
        (0..<unit.period).flatMap { phase -> [PatternRow] in
            task == .fill
                ? (1...max(1, n - 2)).map { PatternRow(unit: unit, n: n, phase: phase, task: task, gap: $0) }
                : [PatternRow(unit: unit, n: n, phase: phase, task: task)]
        }
    }
}

/// What tells the units of a row apart (design §3.2 last column). Colour is never alone (D8).
public enum PatternAttribute: String, CaseIterable, Sendable, Codable, Hashable {
    case kindColour = "kind+colour", shapeColour = "shape+colour", kind, shape, size
}

/// The step table of design §3.2.
public struct PatternStepSpec: Sendable, Equatable {
    public let units: [PatternUnit]
    public let task: PatternTask
    public let lengths: [Int]
    /// Choice cards: 2 at ★ 1a, 3 elsewhere.
    public let choices: Int

    public static func of(_ step: PatternSortStep) -> PatternStepSpec {
        switch (step.level, step.index) {
        case (.l1, 0): return PatternStepSpec(units: [.ab], task: .add1, lengths: [6], choices: 2)
        case (.l1, _): return PatternStepSpec(units: [.ab], task: .add1, lengths: [6, 7], choices: 3)
        case (.l2, 0): return PatternStepSpec(units: [.ab], task: .fill, lengths: [7], choices: 3)
        case (.l2, 1): return PatternStepSpec(units: [.aab, .abb], task: .add1, lengths: [7, 8], choices: 3)
        case (.l2, _): return PatternStepSpec(units: [.ab], task: .add2, lengths: [6, 7, 8], choices: 3)
        case (.l3, 0): return PatternStepSpec(units: [.abc], task: .add1, lengths: [7, 8], choices: 3)
        case (.l3, 1): return PatternStepSpec(units: [.aabb, .abc], task: .fill, lengths: [8], choices: 3)
        default: return PatternStepSpec(units: [.aab, .abb], task: .add2, lengths: [8], choices: 3)
        }
    }

    /// What may differ between units for a material (design §3.2): two attributes at ★, one at ★★ and ★★★
    /// (3a: one or two). Size needs a two-piece unit.
    public static func attributes(_ step: PatternSortStep, material: PatternSortMaterial,
                                  unit: PatternUnit) -> [PatternAttribute] {
        let piece: PatternAttribute = material == .vehicles ? .kind : .shape
        let two: PatternAttribute = material == .vehicles ? .kindColour : .shapeColour
        let list: [PatternAttribute]
        switch (step.level, step.index) {
        case (.l1, _): list = [two]
        case (.l3, 0): list = [piece, two]
        default: list = [piece, .size]
        }
        return list.filter { $0 != .size || unit.distinct == 2 }
    }

    /// Legal rows of the step (G1, G2), across its units, lengths, phases and gaps.
    public func rows() -> [PatternRow] {
        units.flatMap { unit in
            lengths.flatMap { n in PatternGrammar.allRows(unit: unit, task: task, n: n).filter(PatternGrammar.isLegal) }
        }
    }
}

/// A dealt 接落去 round.
public struct PatternQuestion: Sendable, Equatable {
    public let step: PatternSortStep
    public let row: PatternRow
    public let material: PatternSortMaterial
    public let attribute: PatternAttribute
    /// Look of each letter (A, B, C).
    public let units: [PatternSortLook]
    /// The piece that is not in the row (nil when the choices are exactly the units, as at ★ 1a and for ABC).
    public let outside: PatternSortLook?
    /// Choice cards left to right.
    public let choices: [PatternSortLook]

    public init(step: PatternSortStep, row: PatternRow, material: PatternSortMaterial, attribute: PatternAttribute,
                units: [PatternSortLook], outside: PatternSortLook?, choices: [PatternSortLook]) {
        self.step = step
        self.row = row
        self.material = material
        self.attribute = attribute
        self.units = units
        self.outside = outside
        self.choices = choices
    }

    public var level: ActivityLevel { step.level }
    /// The row, nil at the blanks.
    public var slots: [PatternSortLook?] { (0..<row.n).map { row.blanks.contains($0) ? nil : units[row.letter(at: $0)] } }
    /// The right choice for each blank, left to right.
    public var answers: [Int] { row.blanks.compactMap { blank in choices.firstIndex(of: units[row.letter(at: blank)]) } }
    public var choiceIDs: [String] { choices.indices.map { "choice-\($0)" } }

    /// `patternNext.L2.b.AAB.add1.vehicles.bus@blue-digger@blue` (design §6.1).
    public var itemID: String {
        "patternNext.\(step.code).\(row.unit.rawValue).\(row.task.rawValue).\(material.rawValue).\(units.map(\.code).joined(separator: "-"))"
    }

    /// 1/2 (★ 1a), 1/3, 1/9 for add 2 (design §6.1).
    public var chance: Double {
        let per = 1.0 / Double(max(choices.count, 1))
        return row.task == .add2 ? per * per : per
    }
}

/// G3 and the look rules of design §3.2 / D8 / T4 / T5 for one dealt question. Empty = legal.
public enum PatternCheck {
    public static func problems(_ q: PatternQuestion) -> [String] {
        var problems: [String] = []
        if !PatternGrammar.isLegal(q.row) { problems.append("row breaks G1 / G2") }
        // G3: distinct choices, every unit among them, exactly one right per blank, the outside piece never a unit.
        if Set(q.choices).count != q.choices.count { problems.append("choices repeat") }
        if !q.units.allSatisfy(q.choices.contains) { problems.append("a unit is missing from the choices") }
        for blank in q.row.blanks where q.choices.filter({ $0 == q.units[q.row.letter(at: blank)] }).count != 1 {
            problems.append("blank \(blank) has no single right choice")
        }
        if let outside = q.outside, q.units.contains(outside) || !q.choices.contains(outside) {
            problems.append("outside piece is a unit or missing")
        }
        if q.units.count != q.row.unit.distinct || Set(q.units).count != q.units.count { problems.append("unit looks") }
        // Colour is never the only difference (D8), between units and between the outside piece and each unit.
        let shown = q.units + (q.outside.map { [$0] } ?? [])
        for i in shown.indices {
            for j in shown.indices where j > i {
                if shown[i].piece == shown[j].piece && shown[i].size == shown[j].size {
                    problems.append("colour is the only difference")
                }
                if PatternSortCatalog.guardBlocks(shown[i].piece, shown[j].piece, level: q.level) {
                    problems.append("guarded look-alike pair")
                }
            }
        }
        if !PatternSortColourVision.distinct(shown) { problems.append("colours too close or red with green") }
        if q.level < .l3, shown.contains(where: { $0.piece == .block(.rectangle) }) { problems.append("長方形 below ★★★") }
        if shown.contains(where: { $0.piece.material != q.material }) { problems.append("mixed materials") }
        return problems
    }
}

public enum PatternGenerator {
    public static let kind: ActivityKind = .patternNext

    public static func make(seed: String, step: PatternSortStep, materials: PatternSortMaterials,
                            avoidingItem: String? = nil) -> PatternQuestion {
        var question = build(seed: seed, step: step, materials: materials)
        guard let avoidingItem else { return question }
        var attempt = 0
        while question.itemID == avoidingItem, attempt < QuestionGeneration.maxRerolls {
            attempt += 1
            question = build(seed: "\(seed)#\(attempt)", step: step, materials: materials)
        }
        return question
    }

    static func build(seed: String, step: PatternSortStep, materials: PatternSortMaterials) -> PatternQuestion {
        var rng = QuestionRNG(seed: seed, salt: "gen.patternNext.\(step.code)")
        let spec = PatternStepSpec.of(step)
        let rows = spec.rows()
        precondition(!rows.isEmpty, "no legal row for \(step.code)")
        let row = rows[rng.below(rows.count)]
        let material = materials.allowed[rng.below(materials.allowed.count)]
        let attributes = PatternStepSpec.attributes(step, material: material, unit: row.unit)
        let attribute = attributes[rng.below(attributes.count)]
        let sets = unitSets(step.level, material: material, attribute: attribute, count: row.unit.distinct,
                            outside: spec.choices > row.unit.distinct)
        precondition(!sets.isEmpty, "no unit set for \(step.code) \(material) \(attribute)")
        let set = sets[rng.below(sets.count)]
        let units = rng.shuffled(set.units)
        let outside = set.outside.isEmpty ? nil : set.outside[rng.below(set.outside.count)]
        let choices = rng.shuffled(units + (outside.map { [$0] } ?? []))
        return PatternQuestion(step: step, row: row, material: material, attribute: attribute, units: units,
                               outside: outside, choices: choices)
    }

    /// A unit set (unordered) and the outside pieces that may go with it.
    public struct UnitSet: Sendable, Equatable {
        public let units: [PatternSortLook]
        public let outside: [PatternSortLook]
    }

    /// Every legal unit set for a tier, material, attribute and unit size (cached).
    public static func unitSets(_ level: ActivityLevel, material: PatternSortMaterial, attribute: PatternAttribute,
                                count: Int, outside: Bool) -> [UnitSet] {
        memo.value(for: "\(level.code).\(material.rawValue).\(attribute.rawValue).\(count).\(outside)") {
            enumerate(level, material: material, attribute: attribute, count: count, outside: outside)
        }
    }

    static let memo = PatternSortMemo<[UnitSet]>()

    static func enumerate(_ level: ActivityLevel, material: PatternSortMaterial, attribute: PatternAttribute,
                          count: Int, outside: Bool) -> [UnitSet] {
        let pieces = PatternSortCatalog.pieces(material, level: level)
        var sets: [[PatternSortLook]] = []
        switch attribute {
        case .kindColour, .shapeColour:
            // Pieces and colours both differ.
            for chosen in combinations(pieces, count) {
                for colours in assignments(chosen.map(\.palette)) where Set(colours).count == count {
                    sets.append(zip(chosen, colours).map { PatternSortLook($0, $1) })
                }
            }
        case .kind, .shape:
            for chosen in combinations(pieces, count) {
                let shared = chosen.dropFirst().reduce(Set(chosen[0].palette)) { $0.intersection($1.palette) }
                for colour in PatternSortColour.allCases where shared.contains(colour) {
                    sets.append(chosen.map { PatternSortLook($0, colour) })
                }
            }
        case .size:
            for piece in pieces {
                for colour in piece.palette {
                    sets.append([PatternSortLook(piece, colour, size: .big), PatternSortLook(piece, colour, size: .small)])
                }
            }
        }
        return sets.compactMap { units in
            guard unitsLegal(units, level: level) else { return nil }
            guard outside else { return UnitSet(units: units, outside: []) }
            // The outside piece is a different piece (never only another colour), big, in a colour the row's
            // attribute allows: the shared colour for kind / shape / size rows, any for two-attribute rows.
            let fixedColour: PatternSortColour? = attribute == .kindColour || attribute == .shapeColour ? nil : units[0].colour
            let candidates = pieces.filter { piece in !units.contains { $0.piece == piece } }.flatMap { piece in
                piece.palette.filter { fixedColour == nil || $0 == fixedColour }.map { PatternSortLook(piece, $0) }
            }.filter { unitsLegal(units + [$0], level: level) }
            return candidates.isEmpty ? nil : UnitSet(units: units, outside: candidates)
        }
    }

    /// The look rules every unit set (with its outside piece) keeps.
    static func unitsLegal(_ looks: [PatternSortLook], level: ActivityLevel) -> Bool {
        for i in looks.indices {
            for j in looks.indices where j > i {
                if looks[i].piece == looks[j].piece && looks[i].size == looks[j].size { return false }
                if PatternSortCatalog.guardBlocks(looks[i].piece, looks[j].piece, level: level) { return false }
            }
        }
        return PatternSortColourVision.distinct(looks)
    }

    static func combinations<T>(_ items: [T], _ count: Int) -> [[T]] {
        guard count > 0 else { return [[]] }
        guard items.count >= count else { return [] }
        var result: [[T]] = []
        for (i, item) in items.enumerated() {
            for rest in combinations(Array(items[(i + 1)...]), count - 1) { result.append([item] + rest) }
        }
        return result
    }

    static func assignments(_ palettes: [[PatternSortColour]]) -> [[PatternSortColour]] {
        palettes.reduce([[]]) { partial, palette in partial.flatMap { prefix in palette.map { prefix + [$0] } } }
    }
}

/// 自己排 (design §3.5): the palette Stampy offers, three different pieces of one material.
public struct PatternMakePalette: Sendable, Equatable {
    public let material: PatternSortMaterial
    public let pieces: [PatternSortLook]

    /// `patternMake.vehicles.bus@blue-digger@yellow-tram@green`.
    public var itemID: String { "patternMake.\(material.rawValue).\(pieces.map(\.code).joined(separator: "-"))" }
}

public enum PatternMakeGenerator {
    public static let slots = 8

    public static func palette(seed: String, materials: PatternSortMaterials) -> PatternMakePalette {
        var rng = QuestionRNG(seed: seed, salt: "gen.patternMake")
        let material = materials.allowed[rng.below(materials.allowed.count)]
        let sets = PatternGenerator.unitSets(.l2, material: material,
                                             attribute: material == .vehicles ? .kindColour : .shapeColour,
                                             count: 3, outside: false)
        let set = sets[rng.below(sets.count)]
        return PatternMakePalette(material: material, pieces: rng.shuffled(set.units))
    }
}

/// 自己排's readback (design §3.5, T12): the smallest period ≤ 4 with at least 2 full repeats from the first slot
/// (a partial last unit is fine), named AB, AAB, ABB, ABC or AABB. Letters follow first appearance in the row (A is
/// the row's first piece), and a row that starts inside its unit is read by rotating that unit, so A B A A B A A B
/// reads as AAB (A doubled) and B B A B B A as AAB too. A row of one piece, another unit, or no repeat names nothing.
public enum PatternDetector {
    public static func detect(_ row: [String]) -> PatternUnit? {
        guard row.count >= 4 else { return nil }
        var labels: [String: Int] = [:]
        let letters = row.map { piece -> Int in
            if let known = labels[piece] { return known }
            labels[piece] = labels.count
            return labels.count - 1
        }
        for p in 1...4 where row.count >= 2 * p {
            guard letters.indices.allSatisfy({ letters[$0] == letters[$0 % p] }) else { continue }
            guard p > 1 else { return nil }
            let unit = Array(letters.prefix(p))
            for shift in 0..<p {
                let rotated = Array(unit[shift...] + unit[..<shift])
                if let named = PatternUnit.allCases.first(where: { $0.letters == rotated }) { return named }
            }
            return nil
        }
        return nil
    }
}
