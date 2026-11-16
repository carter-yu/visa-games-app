import Foundation

// 分類 · 分車房 (patterns-sorting P0, design §4.3): a seeded deal by step, validated by the sorting invariant. The
// UI is P4; P0 is the pure contract (generator, `SortGaragesCheck`, the board in `PatternSortBoards.swift`).

/// What decides a garage.
public enum SortRule: Hashable, Sendable {
    case colour, size, shape, kind
    /// 車 vs 唔係車 (★★ a) or 地盤車 vs 載人車 (★★★ b): garage 0 holds the first category.
    case category(PatternSortCategory, PatternSortCategory)

    /// `sort_attr` value and item-id part.
    public var code: String {
        switch self {
        case .colour: return "colour"
        case .size: return "size"
        case .shape: return "shape"
        case .kind: return "kind"
        case .category(let first, _): return first == .site ? "site" : "vehicle"
        }
    }

    public var method: PatternSortMethod {
        switch self {
        case .colour: return .colour
        case .size: return .size
        case .shape: return .shape
        case .kind: return .kind
        case .category: return .group
        }
    }
}

/// A dealt 分車房 round. Garage 0 is drawn on the left.
public struct SortGaragesQuestion: Sendable, Equatable {
    public let step: PatternSortStep
    public let rule: SortRule
    /// ★ a: the second attribute that agrees with the rule (the doubled cue).
    public let helper: PatternSortMethod?
    /// ★★★ a: what varies on purpose (mixed colours, or mixed sizes when the rule is colour).
    public let noise: PatternSortMethod?
    /// One example parked in each garage (★ and ★★); empty at ★★★ (signs only).
    public let examples: [PatternSortLook]
    /// The vehicles to sort, front first.
    public let queue: [PatternSortLook]
    /// The right garage of each queue item.
    public let garages: [Int]

    public init(step: PatternSortStep, rule: SortRule, helper: PatternSortMethod?, noise: PatternSortMethod?,
                examples: [PatternSortLook], queue: [PatternSortLook], garages: [Int]) {
        self.step = step
        self.rule = rule
        self.helper = helper
        self.noise = noise
        self.examples = examples
        self.queue = queue
        self.garages = garages
    }

    public var level: ActivityLevel { step.level }

    /// Every item of a garage, parked examples included (they count as items, design §4.3).
    public func items(in garage: Int) -> [PatternSortLook] {
        (examples.indices.contains(garage) ? [examples[garage]] : []) + queue.indices.filter { garages[$0] == garage }.map { queue[$0] }
    }

    /// The sign value of each garage: the rule's value (ids, words and the sign art).
    public var signs: [String] {
        (0..<2).map { garage in
            guard let look = items(in: garage).first else { return "" }
            switch rule {
            case .colour: return look.colour.rawValue
            case .size: return look.size.rawValue
            case .shape, .kind: return look.piece.code
            case .category(let first, let second): return (garage == 0 ? first : second).rawValue
            }
        }
    }

    /// `sortGarages.L1.a.shape+colour.circle@yellow-triangle@blue.n4` (design §6.1): each garage's distinct looks
    /// (sorted, `+`-joined), so the id names the content, not just the rule (and `avoidingItem` can work).
    public var itemID: String {
        let extra = helper ?? noise
        let rulePart = rule.code + (extra.map { "+\($0.rawValue)" } ?? "")
        let garagePart = (0..<2).map { Set(items(in: $0).map(\.code)).sorted().joined(separator: "+") }.joined(separator: "-")
        return "sortGarages.\(step.code).\(rulePart).\(garagePart).n\(queue.count)"
    }

    /// 1/2ⁿ: guessing every vehicle's garage right first time.
    public var chance: Double { pow(0.5, Double(queue.count)) }
    public var choiceIDs: [String] { ["garage-0", "garage-1"] }
}

/// The sorting invariant of design §4.3 (roles as in §4.2). Empty = legal.
public enum SortGaragesCheck {
    /// Never three in a row for one garage, and never strict alternation for 4 or more.
    public static func orderIsFair(_ garages: [Int]) -> Bool {
        var run = 0
        var alternating = true
        for index in garages.indices {
            let same = index > 0 && garages[index] == garages[index - 1]
            run = same ? run + 1 : 1
            if run >= 3 { return false }
            if same { alternating = false }
        }
        return !(garages.count >= 4 && alternating)
    }

    /// The value a look has on `method` (`group` reads the piece: the category's members are intrinsic).
    static func value(_ look: PatternSortLook, _ method: PatternSortMethod) -> String {
        switch method {
        case .colour: return look.colour.rawValue
        case .size: return look.size.rawValue
        case .facing: return look.facing.rawValue
        case .shape, .kind, .group: return look.piece.code
        }
    }

    public static func problems(_ q: SortGaragesQuestion) -> [String] {
        var problems: [String] = []
        let per = q.level == .l1 ? 2 : 3
        if q.queue.count != 2 * per || q.garages.count != q.queue.count { problems.append("queue size") }
        if q.garages.filter({ $0 == 0 }).count != per || q.garages.filter({ $0 == 1 }).count != per {
            problems.append("garages not split evenly")
        }
        if (q.level == .l3) != q.examples.isEmpty || (!q.examples.isEmpty && q.examples.count != 2) {
            problems.append("examples: parked at ★ and ★★, none at ★★★")
        }
        let left = q.items(in: 0), right = q.items(in: 1)
        let all = left + right
        guard !left.isEmpty, !right.isEmpty else { return problems + ["empty garage"] }

        // Every item belongs to exactly one garage under the rule.
        switch q.rule {
        case .category(let first, let second):
            if !left.allSatisfy({ first.contains($0.piece) && !second.contains($0.piece) })
                || !right.allSatisfy({ second.contains($0.piece) && !first.contains($0.piece) }) {
                problems.append("an item is not in exactly one category")
            }
            if all.contains(where: { $0.piece == .vehicle(.plane) }), first == .vehicle || second == .vehicle {
                problems.append("飛機 in a 車 round")
            }
            if all.contains(where: { $0.piece == .vehicle(.fireEngine) }) { problems.append("消防車 in a category round") }
            // Spread: each category garage at least two models; the 地盤車 garage at least one wheeled vehicle.
            for (garage, category) in [(left, first), (right, second)] {
                if Set(garage.map(\.piece)).count < 2 { problems.append("one model stands in for \(category.rawValue)") }
                if category == .site, !garage.contains(where: { $0.piece.features.contains(.wheels) }) {
                    problems.append("地盤車 garage with no wheeled vehicle")
                }
            }
        default:
            let method = q.rule.method
            let lv = Set(left.map { value($0, method) }), rv = Set(right.map { value($0, method) })
            if lv.count != 1 || rv.count != 1 || lv == rv { problems.append("the rule does not split the garages") }
            if q.rule == .shape, all.contains(where: { $0.piece.shape == nil }) { problems.append("shape rule with a non-block") }
            if q.rule == .kind, all.contains(where: { $0.piece.model == nil }) { problems.append("kind rule with a non-vehicle") }
        }

        // Incidental attributes never tell the garages apart: equal on every item, or sharing a value across the
        // two garages. The ★ a helper is the one deliberate exception and must follow the rule exactly.
        // The piece is incidental only under a colour or size rule (it is the rule itself for shape and kind, and
        // intrinsic for a category); it reads as 形狀 for blocks and 車款 for vehicles.
        let pieceMethod: PatternSortMethod = all.allSatisfy { $0.piece.shape != nil } ? .shape : .kind
        var incidental: [PatternSortMethod] = [.colour, .size, .facing]
        if q.rule == .colour || q.rule == .size { incidental.append(pieceMethod) }
        incidental.removeAll { $0 == q.rule.method }
        for method in incidental {
            let lv = Set(left.map { value($0, method) }), rv = Set(right.map { value($0, method) })
            let equal = lv.count == 1 && lv == rv
            if method == q.helper {
                if lv.count != 1 || rv.count != 1 || lv == rv { problems.append("the helper does not follow the rule") }
            } else if !equal && lv.isDisjoint(with: rv) {
                problems.append("incidental \(method.rawValue) tells the garages apart")
            }
        }
        if q.helper != nil && q.level != .l1 { problems.append("a helper above ★") }
        // Noise (design §4.3): ★★★ always mixes sizes under a colour rule and colours otherwise, and a declared noise
        // really varies (astra R1: independent draws could give every item one colour).
        if q.level == .l3, q.noise != (q.rule == .colour ? .size : .colour) { problems.append("★★★ without its noise") }
        if let noise = q.noise, Set(all.map { value($0, noise) }).count < 2 {
            problems.append("declared \(noise.rawValue) noise does not vary")
        }

        // Colours: a colour that decides a garage (the rule or the helper) is a safe pair; all colours stay apart.
        if q.rule == .colour || q.helper == .colour,
           !PatternSortColourVision.isSafePair(left[0].colour, right[0].colour) {
            problems.append("garage colours are not a safe pair")
        }
        // Named colours: a prop's own PNG shade merging with a colour cannot make colour tell the garages apart.
        if !PatternSortColourVision.distinct(all, shades: false) { problems.append("colours too close or red with green") }
        // Look-alikes below ★★★ (T5), whether the kind or shape is the rule or the ★ a helper that doubles it (astra R2).
        if q.rule == .kind || q.rule == .shape || q.helper == .kind || q.helper == .shape,
           PatternSortCatalog.guardBlocks(left[0].piece, right[0].piece, level: q.level) {
            problems.append("guarded look-alike pair")
        }
        if !orderIsFair(q.garages) { problems.append("unfair order") }
        return problems
    }
}

public enum SortGaragesGenerator {
    public static let kind: ActivityKind = .sortGarages

    /// The rules a step can ask about (design §4.3 table); the rule needs its method on (a 類別 rule needs 類別).
    public static func rules(_ step: PatternSortStep) -> [PatternSortMethod] {
        switch (step.level, step.index) {
        case (.l1, 0): return [.colour, .shape, .kind]
        case (.l1, _): return [.size]
        case (.l2, 0): return [.kind, .shape, .group]
        case (.l2, _): return [.colour, .size]
        case (.l3, 0): return [.colour, .size, .shape, .kind]
        default: return [.group]
        }
    }

    public static func make(seed: String, step: PatternSortStep, methods: Set<PatternSortMethod>,
                            avoidingItem: String? = nil) -> SortGaragesQuestion {
        var question = build(seed: seed, step: step, methods: methods)
        guard let avoidingItem else { return question }
        var attempt = 0
        while question.itemID == avoidingItem, attempt < QuestionGeneration.maxRerolls {
            attempt += 1
            question = build(seed: "\(seed)#\(attempt)", step: step, methods: methods)
        }
        return question
    }

    /// Draws candidates on one seeded stream until one passes `SortGaragesCheck` (bounded). The bound is never
    /// reached for the v1 tables (T7 sweeps every eligible step and method set); past it, the tier's 形狀 deal.
    static func build(seed: String, step: PatternSortStep, methods: Set<PatternSortMethod>) -> SortGaragesQuestion {
        var rng = QuestionRNG(seed: seed, salt: "gen.sortGarages.\(step.code)")
        let allowed = rules(step).filter(methods.contains)
        let rule = allowed.isEmpty ? rules(step)[0] : allowed[rng.below(allowed.count)]
        for _ in 0..<400 {
            if let candidate = draw(step: step, rule: rule, rng: &rng), SortGaragesCheck.problems(candidate).isEmpty {
                return candidate
            }
        }
        return fallback(step.level)
    }

    /// Canonical 形狀 deal of a tier (the empty-pool guard): circles vs triangles, yellow vs blue as the ★ doubled
    /// cue (design §4.3's own example), one colour at ★★, yellow and blue mixed in both garages at ★★★ (its noise).
    public static func fallback(_ level: ActivityLevel) -> SortGaragesQuestion {
        if level == .l3 {
            let circle = PatternSortLook(.block(.circle), .yellow), blueCircle = PatternSortLook(.block(.circle), .blue)
            let triangle = PatternSortLook(.block(.triangle), .yellow), blueTriangle = PatternSortLook(.block(.triangle), .blue)
            return SortGaragesQuestion(step: PatternSortStep(.l3, 0), rule: .shape, helper: nil, noise: .colour,
                                       examples: [], queue: [circle, blueCircle, blueTriangle, triangle, circle, blueTriangle],
                                       garages: [0, 0, 1, 1, 0, 1])
        }
        let per = level == .l1 ? 2 : 3
        let a = PatternSortLook(.block(.circle), .yellow)
        let b = PatternSortLook(.block(.triangle), level == .l1 ? .blue : .yellow)
        let order = per == 2 ? [0, 1, 1, 0] : [0, 0, 1, 1, 0, 1]
        return SortGaragesQuestion(step: PatternSortStep(level, 0), rule: .shape,
                                   helper: level == .l1 ? .colour : nil, noise: nil,
                                   examples: level == .l3 ? [] : [a, b], queue: order.map { $0 == 0 ? a : b },
                                   garages: order)
    }

    /// One candidate. Nil when the draw cannot meet the step (the caller draws again).
    static func draw(step: PatternSortStep, rule method: PatternSortMethod, rng: inout QuestionRNG) -> SortGaragesQuestion? {
        let level = step.level
        let per = level == .l1 ? 2 : 3
        let parked = level != .l3
        let order = rng.pick(fairOrders(per))
        func pieces(_ material: PatternSortMaterial) -> [PatternSortPiece] {
            PatternSortCatalog.pieces(material, level: level).filter { $0 != .vehicle(.fireEngine) }
        }
        func question(_ rule: SortRule, helper: PatternSortMethod? = nil, noise: PatternSortMethod? = nil,
                      left: [PatternSortLook], right: [PatternSortLook]) -> SortGaragesQuestion? {
            // left / right: `per` items plus the example (first) when parked.
            let need = per + (parked ? 1 : 0)
            guard left.count == need, right.count == need else { return nil }
            var l = left, r = right
            let examples = parked ? [l.removeFirst(), r.removeFirst()] : []
            var queue: [PatternSortLook] = []
            for garage in order { queue.append(garage == 0 ? l.removeFirst() : r.removeFirst()) }
            return SortGaragesQuestion(step: step, rule: rule, helper: helper, noise: noise, examples: examples,
                                       queue: queue, garages: order)
        }
        let need = per + (parked ? 1 : 0)
        func same(_ look: PatternSortLook) -> [PatternSortLook] { Array(repeating: look, count: need) }
        let pair = PatternSortColourVision.safePairs
        switch (level, step.index, method) {
        case (.l1, 0, _):
            // Doubled cue: the rule plus a second attribute that agrees with it (design §4.3 ★ a).
            let colours = rng.shuffled(rng.pick(pair))
            let material: PatternSortMaterial = method == .kind ? .vehicles : method == .shape ? .shapes
                : (rng.below(2) == 0 ? .vehicles : .shapes)
            let options = pieces(material)
            let a = rng.pick(options), b = rng.pick(options.filter { $0 != a })
            guard a.palette.contains(colours[0]), b.palette.contains(colours[1]) else { return nil }
            let helper: PatternSortMethod = method == .colour ? (material == .vehicles ? .kind : .shape) : .colour
            let rule: SortRule = method == .colour ? .colour : method == .shape ? .shape : .kind
            return question(rule, helper: helper, left: same(PatternSortLook(a, colours[0])),
                            right: same(PatternSortLook(b, colours[1])))
        case (_, _, .size) where !(level == .l3):
            let piece = rng.pick(pieces(rng.below(2) == 0 ? .vehicles : .shapes))
            let colour = rng.pick(piece.palette)
            return question(.size, left: same(PatternSortLook(piece, colour, size: .big)),
                            right: same(PatternSortLook(piece, colour, size: .small)))
        case (.l2, _, .colour):
            let colours = rng.shuffled(rng.pick(pair))
            let piece = rng.pick(pieces(rng.below(2) == 0 ? .vehicles : .shapes))
            guard colours.allSatisfy(piece.palette.contains) else { return nil }
            return question(.colour, left: same(PatternSortLook(piece, colours[0])), right: same(PatternSortLook(piece, colours[1])))
        case (.l2, 0, .kind), (.l2, 0, .shape):
            let options = pieces(method == .kind ? .vehicles : .shapes)
            let a = rng.pick(options), b = rng.pick(options.filter { $0 != a })
            let shared = a.palette.filter(b.palette.contains)
            guard !shared.isEmpty else { return nil }
            let colour = rng.pick(shared)
            return question(method == .kind ? .kind : .shape, left: same(PatternSortLook(a, colour)), right: same(PatternSortLook(b, colour)))
        case (.l2, 0, .group):
            // 車 vs 唔係車: three vehicles + three props (plus one example each); colours as drawn.
            let vehicles = PatternSortCategory.vehicle.roundMembers, props = PatternSortCategory.notVehicle.roundMembers
            let left = (0..<need).map { _ -> PatternSortLook in let p = rng.pick(vehicles); return PatternSortLook(p, rng.pick(p.palette)) }
            let right = (0..<need).map { _ in PatternSortLook(prop: rng.pick(props).prop ?? .cone) }
            return question(.category(.vehicle, .notVehicle), left: left, right: right)
        case (.l3, 0, .colour):
            // Noise: mixed sizes in both garages.
            let colours = rng.shuffled(rng.pick(pair))
            let piece = rng.pick(pieces(rng.below(2) == 0 ? .vehicles : .shapes))
            guard colours.allSatisfy(piece.palette.contains) else { return nil }
            func sizes() -> [PatternSortSize] { rng.shuffled([PatternSortSize.big, .small, rng.pick(PatternSortSize.allCases)]) }
            return question(.colour, noise: .size, left: sizes().map { PatternSortLook(piece, colours[0], size: $0) },
                            right: sizes().map { PatternSortLook(piece, colours[1], size: $0) })
        case (.l3, 0, _):
            // Noise: mixed colours (shared by both garages) under a size, shape or kind rule.
            let material: PatternSortMaterial = method == .kind ? .vehicles : method == .shape ? .shapes
                : (rng.below(2) == 0 ? .vehicles : .shapes)
            let options = pieces(material)
            let a = rng.pick(options)
            let b = method == .size ? a : rng.pick(options.filter { $0 != a })
            let shared = a.palette.filter(b.palette.contains)
            guard shared.count >= 2 else { return nil }
            let leftColours = (0..<per).map { _ in rng.pick(a.palette) }, rightColours = (0..<per).map { _ in rng.pick(b.palette) }
            let rule: SortRule = method == .size ? .size : method == .shape ? .shape : .kind
            return question(rule, noise: .colour, left: leftColours.map { PatternSortLook(a, $0) },
                            right: rightColours.map { PatternSortLook(b, $0, size: method == .size ? .small : .big) })
        case (.l3, _, _):
            // 地盤車 vs 載人車, mixed colours.
            let site = PatternSortCategory.site.roundMembers, passenger = PatternSortCategory.passenger.roundMembers
            let left = (0..<per).map { _ -> PatternSortLook in let p = rng.pick(site); return PatternSortLook(p, rng.pick(p.palette)) }
            let right = (0..<per).map { _ -> PatternSortLook in let p = rng.pick(passenger); return PatternSortLook(p, rng.pick(p.palette)) }
            return question(.category(.site, .passenger), noise: .colour, left: left, right: right)
        default:
            return nil
        }
    }

    /// Garage orders for `per` + `per` items that pass the order rule.
    public static func fairOrders(_ per: Int) -> [[Int]] {
        var result: [[Int]] = []
        func walk(_ chosen: [Int], _ zeros: Int, _ ones: Int) {
            if zeros == 0 && ones == 0 { if SortGaragesCheck.orderIsFair(chosen) { result.append(chosen) }; return }
            if zeros > 0 { walk(chosen + [0], zeros - 1, ones) }
            if ones > 0 { walk(chosen + [1], zeros, ones - 1) }
        }
        walk([], per, per)
        return result
    }
}
