import Foundation

// 分類 · 邊個唔同類 (patterns-sorting P0, design §4.2): enumerated items per step and target, a uniqueness check by
// attribute role, and a seeded deal. A question is a pure function of (seed, step, the methods that are on,
// avoidingItem), so the performance log can rebuild what the child saw.

/// What the odd card differs in.
public enum OddOneOutTarget: Hashable, Sendable {
    case colour, size, shape, kind, facing
    /// A named category: 車 (`.vehicle`) or 地盤車 (`.site`).
    case category(PatternSortCategory)

    /// `odd_attr` value and item-id part.
    public var code: String {
        switch self {
        case .colour: return "colour"
        case .size: return "size"
        case .shape: return "shape"
        case .kind: return "kind"
        case .facing: return "facing"
        case .category(let category): return category.rawValue
        }
    }

    /// The 分類方法 that lets a round ask about it.
    public var method: PatternSortMethod {
        switch self {
        case .colour: return .colour
        case .size: return .size
        case .shape: return .shape
        case .kind: return .kind
        case .facing: return .facing
        case .category: return .group
        }
    }

    public var isCategory: Bool { if case .category = self { return true } else { return false } }
}

/// One dealable item: the group (n − 1 cards, sorted by code) and the odd card.
public struct OddOneOutItem: Hashable, Sendable {
    public let step: PatternSortStep
    public let target: OddOneOutTarget
    /// `.colour` (colours all different) or `.size` (sizes 2 + 2); nil when the other cards are identical.
    public let noise: PatternSortMethod?
    public let group: [PatternSortLook]
    public let odd: PatternSortLook

    public init(step: PatternSortStep, target: OddOneOutTarget, noise: PatternSortMethod?, group: [PatternSortLook],
                odd: PatternSortLook) {
        self.step = step
        self.target = target
        self.noise = noise
        self.group = group.sorted { $0.code < $1.code }
        self.odd = odd
    }

    /// `oddOneOut.L3.a.site+colour.craneTruck@purple-dumper@orange-mixer@yellow.vs.plane@teal` (design §6.1).
    public var itemID: String {
        let targetPart = target.code + (noise.map { "+\($0.rawValue)" } ?? "")
        return "oddOneOut.\(step.code).\(targetPart).\(group.map(\.code).joined(separator: "-")).vs.\(odd.code)"
    }
}

/// A dealt round: the cards left to right and the answer's position.
public struct OddOneOutQuestion: Sendable, Equatable {
    public let item: OddOneOutItem
    public let cards: [PatternSortLook]
    public let answer: Int

    public init(item: OddOneOutItem, cards: [PatternSortLook], answer: Int) {
        self.item = item
        self.cards = cards
        self.answer = answer
    }

    public var step: PatternSortStep { item.step }
    public var level: ActivityLevel { item.step.level }
    public var target: OddOneOutTarget { item.target }
    public var itemID: String { item.itemID }
    /// Choice ids left to right (`card-0` …).
    public var slots: [String] { cards.indices.map { "card-\($0)" } }
    public var correctChoice: String { "card-\(answer)" }
    /// Guessing a first-try answer: 1/3 at ★, 1/4 at ★★ / ★★★.
    public var chance: Double { 1.0 / Double(max(cards.count, 1)) }

    /// Design §4.2 / §5.2: category rounds and every ★★★ round name the target at every coach level; at ★ / ★★
    /// (the other cards identical) only 多啲 names it.
    public func isNamed(_ guidance: TapCountGuidanceLevel) -> Bool {
        target.isCategory || level == .l3 || guidance == .more
    }
}

/// The uniqueness invariant of design §4.2, by attribute role. Empty = legal.
public enum OddOneOutCheck {
    /// The card alone on `values` while all the others share one value; nil otherwise (all equal, all different,
    /// 2 + 2, 2 + 1 + 1, …).
    public static func singledOut(_ values: [String]) -> Int? {
        guard values.count >= 3 else { return nil }
        let counts = Dictionary(grouping: values.indices, by: { values[$0] })
        guard counts.count == 2, let alone = counts.values.first(where: { $0.count == 1 }) else { return nil }
        return alone[0]
    }

    /// Every way the colours can be read (a prop card also as its PNG's own shade).
    static func colourReadings(_ cards: [PatternSortLook]) -> [[String]] {
        cards.reduce([[]]) { partial, card in partial.flatMap { prefix in card.colourReadings.map { prefix + [$0] } } }
    }

    public static func problems(cards: [PatternSortLook], answer: Int, target: OddOneOutTarget,
                                level: ActivityLevel) -> [String] {
        guard cards.indices.contains(answer), cards.count >= 3 else { return ["cards"] }
        var problems: [String] = []
        let others = cards.indices.filter { $0 != answer }

        // 1. On the target the cards split exactly (n − 1) + 1, with the answer alone.
        func split(_ values: [String], _ name: String) {
            if singledOut(values) != answer { problems.append("target \(name) does not single out the answer") }
        }
        switch target {
        case .colour:
            split(cards.map(\.colour.rawValue), "colour")
            if !PatternSortColourVision.isSafePair(cards[answer].colour, cards[others[0]].colour) {
                problems.append("colour target is not a safe pair")
            }
        case .size: split(cards.map(\.size.rawValue), "size")
        case .shape:
            split(cards.map(\.piece.code), "shape")
            if cards.contains(where: { $0.piece.shape == nil }) { problems.append("shape round with a non-block") }
        case .kind:
            split(cards.map(\.piece.code), "kind")
            if cards.contains(where: { $0.piece.model == nil }) { problems.append("kind round with a non-vehicle") }
        case .facing: split(cards.map(\.facing.rawValue), "facing")
        case .category(let category):
            if category.contains(cards[answer].piece) { problems.append("the answer is a \(category.rawValue)") }
            if others.contains(where: { !category.contains(cards[$0].piece) }) {
                problems.append("a group card is not a \(category.rawValue)")
            }
            // Membership (design §4.2): 飛機 is in no 車 / 唔係車 round, on either side.
            if category == .vehicle, cards.contains(where: { $0.piece == .vehicle(.plane) }) {
                problems.append("飛機 in a 車 round")
            }
            if cards.contains(where: { $0.piece == .vehicle(.fireEngine) }) { problems.append("消防車 in a category round") }
            // Spread: at least two models, a 地盤車 group at least one wheeled vehicle, at most 2 of one kind (車).
            let models = others.map { cards[$0].piece.code }
            if Set(models).count < 2 { problems.append("one model stands in for the category") }
            if category == .site, !others.contains(where: { cards[$0].piece.features.contains(.wheels) }) {
                problems.append("地盤車 group with no wheeled vehicle")
            }
            if category == .vehicle, Dictionary(grouping: models, by: { $0 }).values.contains(where: { $0.count > 2 }) {
                problems.append("more than 2 of one kind")
            }
        }

        // 2. Incidental attributes never single out any card, the answer included.
        var incidental: [(String, [[String]])] = []
        if target != .colour { incidental.append(("colour", colourReadings(cards))) }
        if target != .size { incidental.append(("size", [cards.map(\.size.rawValue)])) }
        if target != .facing { incidental.append(("facing", [cards.map(\.facing.rawValue)])) }
        if target == .colour || target == .size || target == .facing {
            incidental.append(("piece", [cards.map(\.piece.code)]))
        }
        for (name, readings) in incidental where readings.contains(where: { singledOut($0) != nil }) {
            problems.append("incidental \(name) singles out a card")
        }

        // 3. An intrinsic feature may single out the answer, never another card. For a named category the members'
        //    models are intrinsic too.
        var intrinsic = PatternSortFeature.allCases.map { feature in
            (feature.rawValue, cards.map { $0.piece.features.contains(feature) ? "yes" : "no" })
        }
        if target.isCategory { intrinsic.append(("model", cards.map(\.piece.code))) }
        for (name, values) in intrinsic {
            if let alone = singledOut(values), alone != answer { problems.append("intrinsic \(name) singles out another card") }
        }

        // 4. Colour safety: every two different colours stay apart under simulated vision; never red with green.
        if !PatternSortColourVision.distinct(cards) { problems.append("colours too close or red with green") }

        // 5. Look-alikes that must be told apart (the kind or the shape) are guarded below ★★★.
        if target == .kind || target == .shape, let first = others.first,
           PatternSortCatalog.guardBlocks(cards[first].piece, cards[answer].piece, level: level) {
            problems.append("guarded look-alike pair")
        }
        return problems
    }

    public static func problems(_ question: OddOneOutQuestion) -> [String] {
        problems(cards: question.cards, answer: question.answer, target: question.target, level: question.level)
    }
}

public enum OddOneOutGenerator {
    public static let kind: ActivityKind = .oddOneOut

    /// 3 cards at ★, 4 at ★★ / ★★★ (design §4.2, T3).
    public static func cardCount(_ level: ActivityLevel) -> Int { level == .l1 ? 3 : 4 }

    /// The targets a step can ask about (design §4.2 table); multi-target steps use only the methods that are on.
    public static func targets(_ step: PatternSortStep) -> [OddOneOutTarget] {
        switch (step.level, step.index) {
        case (.l1, 0): return [.colour]
        case (.l1, 1): return [.size]
        case (.l1, 2): return [.shape]
        case (.l2, 0): return [.kind]
        case (.l2, 1): return [.category(.vehicle)]
        case (.l2, _): return [.colour, .size, .shape]
        case (.l3, 0): return [.category(.site)]
        case (.l3, 1): return [.colour, .size, .shape]
        default: return [.facing]
        }
    }

    public static func targets(_ step: PatternSortStep, methods: Set<PatternSortMethod>) -> [OddOneOutTarget] {
        targets(step).filter { methods.contains($0.method) }
    }

    /// Deal one round. `methods` empty or not covering the step falls back to the step's first target.
    public static func make(seed: String, step: PatternSortStep, methods: Set<PatternSortMethod>,
                            avoidingItem: String? = nil) -> OddOneOutQuestion {
        var question = build(seed: seed, step: step, methods: methods)
        guard let avoidingItem else { return question }
        var attempt = 0
        while question.itemID == avoidingItem, attempt < QuestionGeneration.maxRerolls {
            attempt += 1
            question = build(seed: "\(seed)#\(attempt)", step: step, methods: methods)
        }
        return question
    }

    static func build(seed: String, step: PatternSortStep, methods: Set<PatternSortMethod>) -> OddOneOutQuestion {
        var rng = QuestionRNG(seed: seed, salt: "gen.oddOneOut.\(step.code)")
        let allowed = targets(step, methods: methods)
        let target = allowed.isEmpty ? targets(step)[0] : allowed[rng.below(allowed.count)]
        let pool = items(step, target)
        precondition(!pool.isEmpty, "no 邊個唔同類 item for \(step.code) \(target.code)")
        return question(for: pool[rng.below(pool.count)], rng: &rng)
    }

    /// The item's cards in a seeded order; the answer lands on any slot.
    static func question(for item: OddOneOutItem, rng: inout QuestionRNG) -> OddOneOutQuestion {
        let order = rng.shuffled(Array(0...item.group.count))
        let all = item.group + [item.odd]
        let cards = order.map { all[$0] }
        return OddOneOutQuestion(item: item, cards: cards, answer: order.firstIndex(of: item.group.count) ?? 0)
    }

    /// Every legal item of a step and target (enumerated on first use, then cached).
    public static func items(_ step: PatternSortStep, _ target: OddOneOutTarget) -> [OddOneOutItem] {
        guard targets(step).contains(target) else { return [] }
        return cache.value(for: "\(step.code).\(target.code)") { enumerate(step, target) }
    }

    static let cache = PatternSortMemo<[OddOneOutItem]>()

    /// Candidates by construction (design §4.2 table), kept only when `OddOneOutCheck` finds nothing wrong.
    static func enumerate(_ step: PatternSortStep, _ target: OddOneOutTarget) -> [OddOneOutItem] {
        let level = step.level
        let n = cardCount(level)
        let identical = n - 1
        let vehicles = PatternSortCatalog.vehicles.filter { $0 != .fireEngine }.map(PatternSortPiece.vehicle)
        let blocks = PatternSortCatalog.pieces(.shapes, level: level)
        var candidates: [OddOneOutItem] = []
        func add(_ noise: PatternSortMethod?, _ group: [PatternSortLook], _ odd: PatternSortLook) {
            candidates.append(OddOneOutItem(step: step, target: target, noise: noise, group: group, odd: odd))
        }
        let topNoise = level == .l3 && step.index == 1
        switch target {
        case .colour:
            for piece in vehicles + blocks {
                for pair in PatternSortColourVision.safePairs where pair.allSatisfy(piece.palette.contains) {
                    for (group, odd) in [(pair[0], pair[1]), (pair[1], pair[0])] {
                        if topNoise {
                            // ★★★ 3b: sizes 2 + 2 as noise (the answer big or small).
                            for oddSize in PatternSortSize.allCases {
                                let groupSizes: [PatternSortSize] = oddSize == .small ? [.big, .big, .small] : [.big, .small, .small]
                                add(.size, groupSizes.map { PatternSortLook(piece, group, size: $0) },
                                    PatternSortLook(piece, odd, size: oddSize))
                            }
                        } else {
                            add(nil, Array(repeating: PatternSortLook(piece, group), count: identical), PatternSortLook(piece, odd))
                        }
                    }
                }
            }
        case .size:
            for piece in PatternSortCatalog.vehicles.map(PatternSortPiece.vehicle) + blocks {
                for (group, odd) in [(PatternSortSize.big, PatternSortSize.small), (.small, .big)] {
                    if topNoise {
                        for colours in distinctSets(piece.palette, count: n) {
                            add(.colour, colours.dropLast().map { PatternSortLook(piece, $0, size: group) },
                                PatternSortLook(piece, colours[n - 1], size: odd))
                        }
                    } else {
                        for colour in piece.palette {
                            add(nil, Array(repeating: PatternSortLook(piece, colour, size: group), count: identical),
                                PatternSortLook(piece, colour, size: odd))
                        }
                    }
                }
            }
        case .shape:
            for a in blocks {
                for b in blocks where b != a {
                    if topNoise {
                        for colours in distinctSets(a.palette, count: n) {
                            add(.colour, colours.dropLast().map { PatternSortLook(a, $0) }, PatternSortLook(b, colours[n - 1]))
                        }
                    } else {
                        for colour in a.palette {
                            add(nil, Array(repeating: PatternSortLook(a, colour), count: identical), PatternSortLook(b, colour))
                        }
                    }
                }
            }
        case .kind:
            for a in vehicles {
                for b in vehicles where b != a {
                    for colour in a.palette where b.palette.contains(colour) {
                        add(nil, Array(repeating: PatternSortLook(a, colour), count: identical), PatternSortLook(b, colour))
                    }
                }
            }
        case .facing:
            for piece in vehicles {
                for colours in distinctSets(piece.palette, count: n) {
                    for odd in [PatternSortFacing.mirrored, .forward] {
                        let group: PatternSortFacing = odd == .mirrored ? .forward : .mirrored
                        add(.colour, colours.dropLast().map { PatternSortLook(piece, $0, facing: group) },
                            PatternSortLook(piece, colours[n - 1], facing: odd))
                    }
                }
            }
        case .category(let category):
            let odds: [PatternSortPiece] = category == .vehicle
                ? PatternSortCategory.notVehicle.roundMembers
                : [.vehicle(.bus), .vehicle(.tram), .vehicle(.plane)]
            let looks = category.roundMembers.flatMap { piece in piece.palette.map { PatternSortLook(piece, $0) } }
            for group in multisets(looks, count: identical) {
                for oddPiece in odds {
                    for colour in oddPiece.palette {
                        // 地盤車 (★★★ 3a): colours all different (noise); 車 (★★ 2b): colours as dealt.
                        if category == .site, Set(group.map(\.colour) + [colour]).count < n { continue }
                        add(category == .site ? .colour : nil, group, PatternSortLook(oddPiece, colour))
                    }
                }
            }
        }
        var seen = Set<String>()
        return candidates.filter { item in
            guard seen.insert(item.itemID).inserted else { return false }
            return OddOneOutCheck.problems(cards: item.group + [item.odd], answer: item.group.count, target: target,
                                           level: level).isEmpty
        }
    }

    /// Ordered selections of `count` different colours whose last colour is the odd card's (every rotation once).
    static func distinctSets(_ palette: [PatternSortColour], count: Int) -> [[PatternSortColour]] {
        var result: [[PatternSortColour]] = []
        func walk(_ chosen: [PatternSortColour], _ rest: [PatternSortColour]) {
            if chosen.count == count { result.append(chosen); return }
            for (i, colour) in rest.enumerated() {
                var remaining = rest
                remaining.remove(at: i)
                walk(chosen + [colour], remaining)
            }
        }
        walk([], palette)
        // The group is a set: keep one order per (group set, odd colour).
        var seen = Set<String>()
        return result.filter { colours in
            let key = colours.dropLast().map(\.rawValue).sorted().joined(separator: ",") + "|" + colours[count - 1].rawValue
            return seen.insert(key).inserted
        }
    }

    /// Multisets of `count` looks (combinations with repetition).
    static func multisets(_ looks: [PatternSortLook], count: Int) -> [[PatternSortLook]] {
        var result: [[PatternSortLook]] = []
        func walk(_ start: Int, _ chosen: [PatternSortLook]) {
            if chosen.count == count { result.append(chosen); return }
            for i in start..<looks.count { walk(i, chosen + [looks[i]]) }
        }
        walk(0, [])
        return result
    }
}
