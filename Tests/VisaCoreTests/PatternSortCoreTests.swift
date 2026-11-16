import Foundation
import VisaCore

/// patterns-sorting P0 (0.41.0): the pure core of 跟住排 and 分類 (design §3–§8, §10.1 T1–T5, T7, T11, T12, T15).
/// Offline: no art files, no app source. The expectations come from the design text and the session's independent
/// references (`pattern-grammar-reference.py`, `cvd-palette.py`), not from the code under test.
final class PatternSortCoreTests {
    private static let sortKinds: [ActivityKind] = [.oddOneOut, .sortGarages]

    /// The 56 permitted 分類方法 sets: 2⁶ minus the 8 with 顏色, 大細 and 形狀 all off (design §5.3, T7).
    static let permittedMethodSets: [Set<PatternSortMethod>] = (0..<64).compactMap { mask in
        let set = Set(PatternSortMethod.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
        return set.contains(where: PatternSortMethod.perceptual.contains) ? set : nil
    }

    private static func looks(_ codes: [String]) -> [PatternSortLook] { codes.compactMap(PatternSortLook.init(code:)) }

    static func dealt(_ kind: ActivityKind, _ fields: [String: PerfValue] = [:]) -> PerfEvent {
        PerfEvent(type: .gameDealt, timestamp: Date(timeIntervalSince1970: 1_800_000_000), tz: "Asia/Hong_Kong", mono: 0,
                  launch: "l", seq: 0, app: "0.41.0", actor: .child, mode: "lock", session: "s",
                  fields: fields.merging(["kind": .string(kind.rawValue)]) { current, _ in current })
    }

    // MARK: T11 catalogue

    /// T11: four kinds, default OFF, playtest-gated, `.boardTwo`, area 其他 until P3; only 邊個唔同類 is playable (P1);
    /// the board after-pause step for the three quiz kinds only; the unbuilt 形狀分類 row stays until P4.
    func testCatalogueKindsAreOffGatedAndBoardTwo() {
        let new: [ActivityKind] = [.patternNext, .patternMake, .oddOneOut, .sortGarages]
        expectEqual(Array(ActivityKind.allCases.suffix(4)), new)
        expectEqual(ActivityCatalog.playableKinds.filter(new.contains), [.oddOneOut])
        for kind in new {
            expectTrue(ActivityCatalog.defaultOffKinds.contains(kind), kind.rawValue)
            expectFalse(ActivityCatalog.defaultOnKinds.contains(kind), kind.rawValue)
            expectTrue(kind.requiresPlaytestBeforeStars, kind.rawValue)
            expectEqual(MissionGameAssignment.defaultStars(for: kind), [])
            expectEqual(StatusRoute(board: kind), .boardTwo)
            expectEqual(WeeklyArea.of(kind: kind.rawValue), .other)
            expectFalse(kind.parentHeroAssetIDs.isEmpty)
            expectTrue(kind.isPatternFamily != kind.isSortFamily, kind.rawValue)
        }
        expectEqual(ActivityKind.allCases.filter(\.usesBoardAfterPause), [.patternNext, .oddOneOut, .sortGarages])
        expectEqual(ActivityKind.allCases.filter(\.isPatternFamily), [.patternNext, .patternMake])
        expectEqual(ActivityKind.allCases.filter(\.isSortFamily), [.oddOneOut, .sortGarages])
        for kind in [ActivityKind.patternNext, .oddOneOut, .sortGarages] { expectTrue(QuestionGeneration.isGenerated(kind)) }
        expectFalse(QuestionGeneration.isGenerated(.patternMake))
        expectTrue(PerfQuestionGeneration.isPracticeOnly(Self.dealt(.patternMake)))
        for kind in [ActivityKind.patternNext, .oddOneOut, .sortGarages] {
            expectFalse(PerfQuestionGeneration.isPracticeOnly(Self.dealt(kind)), kind.rawValue)
        }
        expectEqual([PerfChoiceCatalog.chance(for: .patternNext), PerfChoiceCatalog.chance(for: .oddOneOut),
                     PerfChoiceCatalog.chance(for: .sortGarages), PerfChoiceCatalog.chance(for: .patternMake)],
                    [1.0 / 3, 1.0 / 4, 1.0 / 16, 1])
        expectEqual(ActivityCatalog.unbuiltParentActivities.map(\.traditionalChinese), ["迷宮", "形狀分類", "連點"])
        print("  pattern sort: 4 kinds default OFF, playtest-gated, board 2, area 其他; only 邊個唔同類 playable")
    }

    // MARK: T1 determinism

    /// T1: a question is a pure function of its inputs; `avoidingItem` is honoured within 8 re-rolls.
    func testDealsAreDeterministicAndAvoidTheLastItem() {
        let methods = SortSettings.defaultMethods
        var avoided = 0
        for level in ActivityLevel.allCases {
            for step in PatternSortLadder.steps(.oddOneOut, level) {
                let a = OddOneOutGenerator.make(seed: "seed-\(step.code)", step: step, methods: methods.union([.facing]))
                expectEqual(a, OddOneOutGenerator.make(seed: "seed-\(step.code)", step: step, methods: methods.union([.facing])))
                let b = OddOneOutGenerator.make(seed: "seed-\(step.code)", step: step, methods: methods.union([.facing]),
                                                avoidingItem: a.itemID)
                expectTrue(b.itemID != a.itemID, step.code)
                avoided += 1
            }
            for step in PatternSortLadder.steps(.sortGarages, level) {
                let a = SortGaragesGenerator.make(seed: "s-\(step.code)", step: step, methods: methods)
                expectEqual(a, SortGaragesGenerator.make(seed: "s-\(step.code)", step: step, methods: methods))
                let b = SortGaragesGenerator.make(seed: "s-\(step.code)", step: step, methods: methods, avoidingItem: a.itemID)
                expectTrue(b.itemID != a.itemID, step.code)
                avoided += 1
            }
            for step in PatternSortLadder.steps(.patternNext, level) {
                let a = PatternGenerator.make(seed: "p-\(step.code)", step: step, materials: .both)
                expectEqual(a, PatternGenerator.make(seed: "p-\(step.code)", step: step, materials: .both))
                let b = PatternGenerator.make(seed: "p-\(step.code)", step: step, materials: .both, avoidingItem: a.itemID)
                expectTrue(b.itemID != a.itemID, step.code)
                avoided += 1
            }
        }
        expectEqual(PatternMakeGenerator.palette(seed: "m", materials: .both), PatternMakeGenerator.palette(seed: "m", materials: .both))
        // Fixed outputs (astra R1): the same inputs give the same question in every process, not only twice in one. A
        // set's order (the safe pairs' once) can change from one process to the next, so deals are pinned literally:
        // one 邊個唔同類 ★ a and one 分車房 ★★ b deal (both built from a safe pair), and a digest of 20 seeds at every
        // step of the 3 generators plus 自己排's palette.
        let all = methods.union([.facing])
        var digest = ""
        for index in 0..<20 {
            for level in ActivityLevel.allCases {
                for step in PatternSortLadder.steps(.oddOneOut, level) {
                    let q = OddOneOutGenerator.make(seed: "pin-\(index)", step: step, methods: all)
                    digest += "\(q.itemID) \(q.answer)\n"
                }
                for step in PatternSortLadder.steps(.sortGarages, level) {
                    let q = SortGaragesGenerator.make(seed: "pin-\(index)", step: step, methods: methods)
                    digest += "\(q.itemID) \(q.garages)\n"
                }
                for step in PatternSortLadder.steps(.patternNext, level) {
                    let q = PatternGenerator.make(seed: "pin-\(index)", step: step, materials: .both)
                    digest += "\(q.itemID) \(q.choices.map(\.code))\n"
                }
            }
            digest += PatternMakeGenerator.palette(seed: "pin-\(index)", materials: .both).itemID + "\n"
        }
        let odd = OddOneOutGenerator.make(seed: "pin", step: PatternSortStep(.l1, 0), methods: all)
        let sort = SortGaragesGenerator.make(seed: "pin", step: PatternSortStep(.l2, 1), methods: [.colour])
        expectEqual([odd.cards.map(\.code).joined(separator: " "), sort.queue.map(\.code).joined(separator: " "),
                     String(Self.fnv(digest), radix: 16)],
                    ["bus@purple bus@yellow bus@purple",
                     "triangle@orange triangle@orange triangle@blue triangle@orange triangle@blue triangle@blue",
                     "3f3add300a416279"])
        print("  pattern sort: same inputs → same question for all 3 generators (pinned across processes); the last item avoided at \(avoided) steps")
    }

    /// FNV-1a 64 of the UTF-8 bytes: a digest that stays the same in every process (`hashValue` does not).
    private static func fnv(_ text: String) -> UInt64 {
        text.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01b3 }
    }

    // MARK: T2 uniqueness: patterns

    /// T2 (patterns): G1–G2 over every unit × phase × task × n × blank, the §3.2 fixtures, AABB fill at n = 7 rejected.
    func testPatternGrammarAndFixtures() {
        // Legal rows per step (the independent reference `pattern-grammar-reference.py`).
        let expected = ["L1.a": 2, "L1.b": 4, "L2.a": 10, "L2.b": 12, "L2.c": 6, "L3.a": 6, "L3.b": 42, "L3.c": 6]
        for level in ActivityLevel.allCases {
            for step in PatternSortLadder.steps(.patternNext, level) {
                let rows = PatternStepSpec.of(step).rows()
                expectEqual(rows.count, expected[step.code] ?? -1, step.code)
                expectTrue(rows.allSatisfy(PatternGrammar.isLegal), step.code)
            }
        }
        // The worked examples of design §3.2 (`_` = blank) and their answers.
        let fixtures: [(PatternUnit, Int, Int, PatternTask, Int?, String, [Int])] = [
            (.ab, 6, 0, .add1, nil, "A B A B A _", [1]), (.ab, 7, 1, .add1, nil, "B A B A B A _", [1]),
            (.ab, 7, 0, .fill, 4, "A B A B _ B A", [0]), (.aab, 7, 0, .add1, nil, "A A B A A B _", [0]),
            (.abb, 8, 0, .add1, nil, "A B B A B B A _", [1]), (.ab, 6, 0, .add2, nil, "A B A B _ _", [0, 1]),
            (.abc, 7, 0, .add1, nil, "A B C A B C _", [0]), (.aabb, 8, 0, .fill, 5, "A A B B A _ B B", [0]),
            (.abc, 8, 0, .fill, 4, "A B C A _ C A B", [1]), (.aab, 8, 0, .add2, nil, "A A B A A B _ _", [0, 0])
        ]
        for (unit, n, phase, task, gap, text, answers) in fixtures {
            let row = PatternRow(unit: unit, n: n, phase: phase, task: task, gap: gap)
            expectEqual(row.text, text)
            expectTrue(PatternGrammar.isLegal(row), text)
            expectEqual(row.blanks.map(row.letter(at:)), answers, text)
        }
        // AABB needs all 8 slots for two units: no fill row of 7 passes, on either rule.
        for row in PatternGrammar.allRows(unit: .aabb, task: .fill, n: 7) {
            expectFalse(PatternGrammar.hasEnoughEvidence(row), row.text)
            expectFalse(PatternGrammar.hasOneAnswer(row), row.text)
        }
        // G2 on its own: a unit longer than ⌊n/2⌋, or a row too short to show its unit twice, has no single reading.
        for row in [PatternRow(unit: .aab, n: 4, phase: 0, task: .add1), PatternRow(unit: .ab, n: 3, phase: 0, task: .add1),
                    PatternRow(unit: .abc, n: 5, phase: 0, task: .fill, gap: 2)] {
            expectFalse(PatternGrammar.hasOneAnswer(row), row.text)
        }
        // G1 on its own: a fill gap's position needs one visible copy, every other position two.
        expectFalse(PatternGrammar.hasEnoughEvidence(PatternRow(unit: .abb, n: 6, phase: 0, task: .add1)))
        expectTrue(PatternGrammar.hasEnoughEvidence(PatternRow(unit: .aabb, n: 8, phase: 0, task: .fill, gap: 5)))
        // A rival reading that fits the visible slots but predicts another item makes a row illegal.
        expectEqual(PatternGrammar.consistentPeriods(PatternRow(unit: .ab, n: 6, phase: 0, task: .add1)), [2])
        print("  pattern sort: grammar G1/G2 — 88 legal rows over 8 steps, 10 design fixtures, AABB fill at 7 rejected")
    }

    // MARK: T3 / T4 / T5 patterns

    /// T3 + T4 + T5 for 接落去: one right choice per blank, distinct choices, both units present, the outside piece never
    /// a unit; 2 choices at ★ 1a and 3 elsewhere; colour never alone; look-alikes guarded below ★★★.
    func testPatternChoicesColourAndGuards() {
        var dealt = 0
        for materials in PatternSortMaterials.allCases {
            for level in ActivityLevel.allCases {
                for step in PatternSortLadder.steps(.patternNext, level) {
                    for index in 0..<50 {
                        let q = PatternGenerator.make(seed: "\(materials)-\(index)", step: step, materials: materials)
                        expectEqual(PatternCheck.problems(q), [], "\(step.code) \(q.itemID)")
                        expectEqual(q.choices.count, step.code == "L1.a" ? 2 : 3, step.code)
                        expectTrue(materials.allowed.contains(q.material))
                        expectEqual(q.answers.count, q.row.blanks.count)
                        dealt += 1
                    }
                }
            }
        }
        // A colour-only row is rejected (D8), and so is a ★★ bus / tram pair, a ★ 長方形 and red with green.
        let bus = PatternSortLook(.vehicle(.bus), .blue), busYellow = PatternSortLook(.vehicle(.bus), .yellow)
        let row = PatternRow(unit: .ab, n: 7, phase: 0, task: .fill, gap: 4)
        let colourOnly = PatternQuestion(step: PatternSortStep(.l2, 0), row: row, material: .vehicles, attribute: .kind,
                                         units: [bus, busYellow], outside: PatternSortLook(.vehicle(.digger), .blue),
                                         choices: [bus, busYellow, PatternSortLook(.vehicle(.digger), .blue)])
        expectTrue(PatternCheck.problems(colourOnly).contains("colour is the only difference"))
        let tram = PatternSortLook(.vehicle(.tram), .blue)
        let guarded = PatternQuestion(step: PatternSortStep(.l2, 0), row: row, material: .vehicles, attribute: .kind,
                                      units: [bus, tram], outside: PatternSortLook(.vehicle(.mixer), .blue),
                                      choices: [bus, tram, PatternSortLook(.vehicle(.mixer), .blue)])
        expectTrue(PatternCheck.problems(guarded).contains("guarded look-alike pair"))
        let atTop = PatternQuestion(step: PatternSortStep(.l3, 1), row: PatternRow(unit: .aabb, n: 8, phase: 0, task: .fill, gap: 5),
                                    material: .vehicles, attribute: .kind, units: [bus, tram],
                                    outside: PatternSortLook(.vehicle(.mixer), .blue),
                                    choices: [bus, tram, PatternSortLook(.vehicle(.mixer), .blue)])
        expectFalse(PatternCheck.problems(atTop).contains("guarded look-alike pair"))
        let fire = PatternSortLook(.vehicle(.fireEngine), .red), greenTram = PatternSortLook(.vehicle(.tram), .green)
        let redGreen = PatternQuestion(step: PatternSortStep(.l1, 0), row: PatternRow(unit: .ab, n: 6, phase: 0, task: .add1),
                                       material: .vehicles, attribute: .kindColour, units: [fire, greenTram], outside: nil,
                                       choices: [fire, greenTram])
        expectTrue(PatternCheck.problems(redGreen).contains("colours too close or red with green"))
        print("  pattern sort: \(dealt) 接落去 deals — one right choice per blank, 2 / 3 choices, colour never alone, guards")
    }

    // MARK: T2 / T3 odd one out

    /// The invariant re-checked here from the design text, independently of `OddOneOutCheck`.
    private func oddOneOutHolds(_ q: OddOneOutQuestion) -> Bool {
        let cards = q.cards, answer = q.answer
        let others = cards.indices.filter { $0 != answer }
        func value(_ look: PatternSortLook, _ target: OddOneOutTarget) -> String {
            switch target {
            case .colour: return look.colour.rawValue
            case .size: return look.size.rawValue
            case .facing: return look.facing.rawValue
            case .shape, .kind, .category: return look.piece.code
            }
        }
        func alone(_ values: [String]) -> Int? {
            let counts = Dictionary(grouping: values, by: { $0 })
            guard counts.count == 2 else { return nil }
            return values.firstIndex { counts[$0]?.count == 1 }
        }
        switch q.target {
        case .category(let category):
            guard !category.contains(cards[answer].piece), others.allSatisfy({ category.contains(cards[$0].piece) }) else { return false }
            if cards.contains(where: { $0.piece == .vehicle(.plane) }) && category == .vehicle { return false }
            if cards.contains(where: { $0.piece == .vehicle(.fireEngine) }) { return false }
            if Set(others.map { cards[$0].piece }).count < 2 { return false }
        default:
            guard alone(cards.map { value($0, q.target) }) == answer else { return false }
        }
        // No incidental attribute singles out anyone; no feature singles out another card.
        for target in [OddOneOutTarget.colour, .size, .facing] where target != q.target {
            if alone(cards.map { value($0, target) }) != nil { return false }
        }
        for feature in PatternSortFeature.allCases {
            if let one = alone(cards.map { $0.piece.features.contains(feature) ? "y" : "n" }), one != answer { return false }
        }
        return PatternSortColourVision.distinct(cards)
    }

    /// T2 (odd one out) and T3: every enumerable item of every step and target keeps the invariant by role; the §4.2
    /// legal fixtures pass and the illegal ones fail; exactly 3 cards at ★ and 4 at ★★ / ★★★ for every eligible step ×
    /// the 56 method sets × 50 seeds.
    func testOddOneOutUniquenessFixturesAndCardCounts() {
        var items = 0
        for level in ActivityLevel.allCases {
            for step in PatternSortLadder.steps(.oddOneOut, level) {
                for target in OddOneOutGenerator.targets(step) {
                    let pool = OddOneOutGenerator.items(step, target)
                    expectFalse(pool.isEmpty, "\(step.code) \(target.code)")
                    for item in pool {
                        let q = OddOneOutQuestion(item: item, cards: item.group + [item.odd], answer: item.group.count)
                        expectTrue(oddOneOutHolds(q), item.itemID)
                        expectEqual(q.cards.count, OddOneOutGenerator.cardCount(level), item.itemID)
                    }
                    items += pool.count
                }
            }
        }
        // Design §4.2 fixtures, answer last.
        func check(_ codes: [String], _ target: OddOneOutTarget, _ level: ActivityLevel) -> [String] {
            let cards = Self.looks(codes)
            expectEqual(cards.count, codes.count, codes.joined(separator: " "))
            return OddOneOutCheck.problems(cards: cards, answer: cards.count - 1, target: target, level: level)
        }
        let car = OddOneOutTarget.category(.vehicle), site = OddOneOutTarget.category(.site)
        expectEqual(check(["mixer@blue", "dumper@yellow", "craneTruck@orange", "cone@orange"], car, .l2), [])
        expectEqual(check(["bus@yellow", "tram@blue", "mixer@blue", "sun@yellow"], car, .l2), [])
        expectTrue(check(["bus@blue", "mixer@yellow", "dumper@orange", "cone@orange"], car, .l2)
            .contains("intrinsic tallBox singles out another card"))
        expectTrue(check(["mixer@blue", "dumper@blue", "craneTruck@blue", "cone@orange"], car, .l2)
            .contains("incidental colour singles out a card"))
        expectTrue(check(["mixer@yellow", "dumper@orange", "craneTruck@purple", "plane@teal"], car, .l2).contains("飛機 in a 車 round"))
        expectTrue(check(["plane@blue", "mixer@yellow", "dumper@orange", "cone@orange"], car, .l2).contains("飛機 in a 車 round"))
        expectEqual(check(["mixer@yellow", "dumper@orange", "craneTruck@purple", "plane@teal"], site, .l3), [])
        expectEqual(check(["mixer@yellow", "dumper@orange", "craneTruck@purple", "bus@teal"], site, .l3), [])
        let premockup = check(["digger@yellow", "mixer@orange", "dumper@purple", "plane@teal"], site, .l3)
        expectTrue(premockup.contains("intrinsic tracks singles out another card"), premockup.joined(separator: "; "))
        // Two odd cards (2 + 2 on the target) never pass; nor does one model standing in for the category.
        expectTrue(check(["mixer@blue", "mixer@blue", "mixer@yellow", "mixer@yellow"], .colour, .l2)
            .contains("target colour does not single out the answer"))
        expectTrue(check(["mixer@blue", "mixer@blue", "mixer@orange", "mixer@yellow"], .colour, .l2)
            .contains("target colour does not single out the answer"), "a second odd card (2 + 1 + 1)")
        expectTrue(check(["mixer@yellow", "mixer@orange", "mixer@purple", "plane@teal"], site, .l3)
            .contains("one model stands in for the category"))
        // A deep-orange cone beside three orange trucks reads as its own colour: no false 3 + 1.
        expectTrue(check(["mixer@orange", "dumper@orange", "craneTruck@orange", "cone@orange"], car, .l2)
            .contains("incidental colour singles out a card"))

        var deals = 0
        for methods in Self.permittedMethodSets {
            for level in ActivityLevel.allCases {
                for step in PatternSortLadder.eligibleSteps(.oddOneOut, level, methods: methods) {
                    for index in 0..<50 {
                        let q = OddOneOutGenerator.make(seed: "odd-\(index)", step: step, methods: methods)
                        expectEqual(q.cards.count, level == .l1 ? 3 : 4, step.code)
                        expectTrue(methods.contains(q.target.method), "\(step.code) \(q.target.code)")
                        expectTrue(q.cards.indices.contains(q.answer))
                        deals += 1
                    }
                }
            }
        }
        expectEqual(Self.permittedMethodSets.count, 56)
        print("  pattern sort: 邊個唔同類 — \(items) items keep the role invariant; the 8 design fixture rows + 4 more; \(deals) deals of 3 / 4 cards")
    }

    // MARK: T2 sorting

    /// T2 (sorting): the role invariant, the §4.3 fixtures and the order rule; 飛機 never in 車 vs 唔係車.
    func testSortingInvariantFixturesAndOrder() {
        func q(_ step: String, _ rule: SortRule, left: [String], right: [String], examples: [String] = [],
               helper: PatternSortMethod? = nil) -> SortGaragesQuestion {
            let order = left.count == 2 ? [0, 0, 1, 1] : [0, 0, 1, 1, 0, 1]
            var l = Self.looks(left), r = Self.looks(right)
            let queue = order.map { $0 == 0 ? l.removeFirst() : r.removeFirst() }
            // ★★★ declares its noise: mixed sizes under a colour rule, mixed colours otherwise.
            let noise: PatternSortMethod? = step.hasPrefix("L3") ? (rule == .colour ? .size : .colour) : nil
            return SortGaragesQuestion(step: PatternSortStep(code: step)!, rule: rule, helper: helper, noise: noise,
                                       examples: Self.looks(examples), queue: queue, garages: order)
        }
        let carRule = SortRule.category(.vehicle, .notVehicle), siteRule = SortRule.category(.site, .passenger)
        let fixtureOK = q("L2.a", carRule, left: ["mixer@yellow", "tram@blue", "dumper@orange"],
                          right: ["cone@orange", "sun@yellow", "toolbox@red"], examples: ["tram@blue", "cone@orange"])
        expectEqual(SortGaragesCheck.problems(fixtureOK), [])
        let allBlue = q("L2.a", carRule, left: ["mixer@blue", "tram@blue", "dumper@blue"],
                        right: ["cone@orange", "sun@yellow", "toolbox@red"], examples: ["tram@blue", "cone@orange"])
        expectTrue(SortGaragesCheck.problems(allBlue).contains("incidental colour tells the garages apart"))
        let plane = q("L2.a", carRule, left: ["mixer@yellow", "plane@blue", "dumper@orange"],
                      right: ["cone@orange", "sun@yellow", "toolbox@red"], examples: ["tram@blue", "cone@orange"])
        expectTrue(SortGaragesCheck.problems(plane).contains("飛機 in a 車 round"))
        let kind = q("L2.a", .kind, left: ["bus@yellow", "bus@yellow", "bus@yellow"],
                     right: ["mixer@yellow", "mixer@yellow", "mixer@yellow"], examples: ["bus@yellow", "mixer@yellow"])
        expectEqual(SortGaragesCheck.problems(kind), [])
        // Design §4.3's ✓ row, with 叮叮 blue: the tram's art palette has no orange (`TapCountModel.palette`).
        let siteOK = q("L3.b", siteRule, left: ["digger@yellow", "mixer@blue", "craneTruck@orange"],
                       right: ["bus@yellow", "tram@blue", "bus@blue"])
        expectEqual(SortGaragesCheck.problems(siteOK), [])
        let siteColour = q("L3.b", siteRule, left: ["digger@yellow", "mixer@yellow", "craneTruck@yellow"],
                           right: ["bus@blue", "tram@blue", "bus@blue"])
        expectTrue(SortGaragesCheck.problems(siteColour).contains("incidental colour tells the garages apart"))
        let oneModel = q("L3.b", siteRule, left: ["digger@yellow", "mixer@blue", "craneTruck@orange"],
                         right: ["bus@yellow", "bus@purple", "bus@blue"])
        expectTrue(SortGaragesCheck.problems(oneModel).contains("one model stands in for passenger"))
        // Astra R1: ★★★'s declared noise really varies — one colour on every item is not "mixed colours" — and ★★★
        // always declares it (the old 形狀 fallback did not).
        let siteOneColour = q("L3.b", siteRule, left: ["digger@yellow", "mixer@yellow", "craneTruck@yellow"],
                              right: ["bus@yellow", "tram@yellow", "bus@yellow"])
        expectEqual(SortGaragesCheck.problems(siteOneColour), ["declared colour noise does not vary"])
        let kindOneColour = q("L3.a", .kind, left: ["bus@yellow", "bus@yellow", "bus@yellow"],
                              right: ["mixer@yellow", "mixer@yellow", "mixer@yellow"])
        expectEqual(SortGaragesCheck.problems(kindOneColour), ["declared colour noise does not vary"])
        let circle = PatternSortLook(.block(.circle), .yellow), triangle = PatternSortLook(.block(.triangle), .yellow)
        let quiet = SortGaragesQuestion(step: PatternSortStep(.l3, 0), rule: .shape, helper: nil, noise: nil, examples: [],
                                        queue: [circle, circle, triangle, triangle, circle, triangle], garages: [0, 0, 1, 1, 0, 1])
        expectEqual(SortGaragesCheck.problems(quiet), ["★★★ without its noise"])
        expectEqual(SortGaragesGenerator.fallback(.l3).noise, .colour)
        // The order rule: never three in a row, never strict alternation for 4 or more.
        expectFalse(SortGaragesCheck.orderIsFair([0, 1, 0, 1]))
        expectFalse(SortGaragesCheck.orderIsFair([0, 0, 0, 1, 1, 1]))
        expectTrue(SortGaragesCheck.orderIsFair([0, 0, 1, 1]))
        expectEqual(SortGaragesGenerator.fairOrders(2), [[0, 0, 1, 1], [0, 1, 1, 0], [1, 0, 0, 1], [1, 1, 0, 0]])
        expectEqual(SortGaragesGenerator.fairOrders(3).count, 12)
        for level in ActivityLevel.allCases { expectEqual(SortGaragesCheck.problems(SortGaragesGenerator.fallback(level)), []) }
        print("  pattern sort: 分車房 — 7 design fixtures by role, order rule, the 形狀 fallback legal at every tier")
    }

    // MARK: T4 colour

    /// T4: the simulated colour vision, the safe pairs, no red with green, and no colour-decided round while 顏色 is off.
    func testColourVisionSafePairsAndColourOff() {
        expectEqual(PatternSortColourVision.distance(PatternSortColour.blue.rgb, PatternSortColour.yellow.rgb), 66.8, accuracy: 0.1)
        expectEqual(PatternSortColourVision.distance(PatternSortColour.yellow.rgb, PatternSortColour.orange.rgb), 15.8, accuracy: 0.1)
        expectEqual(PatternSortColourVision.distance(PatternSortColour.purple.rgb, PatternSortColour.yellow.rgb), 34.8, accuracy: 0.1)
        expectEqual(PatternSortColourVision.distance(PatternSortColour.blue.rgb, PatternSortColour.orange.rgb), 87.3, accuracy: 0.1)
        for pair in PatternSortColourVision.safePairs {
            expectEqual(pair.count, 2)
            expectTrue(PatternSortColourVision.isSafePair(pair[0], pair[1]) && PatternSortColourVision.isSafePair(pair[1], pair[0]))
            expectFalse(pair.contains(.red) || pair.contains(.green))
        }
        expectFalse(PatternSortColourVision.isSafePair(.red, .green))
        expectFalse(PatternSortColourVision.isSafePair(.blue, .purple))
        expectFalse(PatternSortColourVision.distinct([PatternSortLook(.vehicle(.fireEngine), .red), PatternSortLook(.vehicle(.tram), .green)]))
        expectFalse(PatternSortColourVision.distinct([PatternSortLook(.vehicle(.bus), .blue), PatternSortLook(.vehicle(.bus), .purple)]))
        // No four body colours stay pairwise ≥ 20 (why the noise threshold is 15).
        let body: [PatternSortColour] = [.blue, .yellow, .orange, .purple, .pink, .teal, .green]
        var best = 0.0
        for a in body.indices { for b in body.indices where b > a { for c in body.indices where c > b { for d in body.indices where d > c {
            let set = [body[a], body[b], body[c], body[d]]
            var low = Double.infinity
            for i in set.indices { for j in set.indices where j > i { low = min(low, PatternSortColourVision.distance(set[i].rgb, set[j].rgb)) } }
            best = max(best, low)
        } } } }
        expectTrue(best < 20 && best >= PatternSortColourVision.noiseThreshold, "best 4-set \(best)")
        // 顏色 off: nothing a round asks about is colour (it may still vary, as noise or the ★ helper).
        for methods in Self.permittedMethodSets where !methods.contains(.colour) {
            for level in ActivityLevel.allCases {
                for step in PatternSortLadder.eligibleSteps(.oddOneOut, level, methods: methods) {
                    for index in 0..<10 {
                        expectTrue(OddOneOutGenerator.make(seed: "c\(index)", step: step, methods: methods).target != .colour)
                    }
                }
                for step in PatternSortLadder.eligibleSteps(.sortGarages, level, methods: methods) {
                    for index in 0..<10 {
                        expectTrue(SortGaragesGenerator.make(seed: "c\(index)", step: step, methods: methods).rule != .colour)
                    }
                }
            }
        }
        print("  pattern sort: colour — 3 safe pairs ≥ 30 under protan / deutan / tritan, noise ≥ 15, no red with green, 顏色 off asks no colour")
    }

    // MARK: T5 guards

    /// T5: 叮叮 / 巴士, 石屎車 / 壓路機, 挖泥車 / 推土機, 正方形 / 長方形 are never told apart below ★★★.
    func testLookAlikesAreNeverPairedBelowTheTopTier() {
        for pair in PatternSortCatalog.confusablePairs.map(Array.init) {
            expectTrue(PatternSortCatalog.guardBlocks(pair[0], pair[1], level: .l2))
            expectFalse(PatternSortCatalog.guardBlocks(pair[0], pair[1], level: .l3))
        }
        let guardedPieces = Set(PatternSortCatalog.confusablePairs.flatMap { $0 })
        for level in [ActivityLevel.l1, .l2] {
            for step in PatternSortLadder.steps(.patternNext, level) {
                for index in 0..<50 {
                    let q = PatternGenerator.make(seed: "g\(index)", step: step, materials: .both)
                    let pieces = Set((q.units + (q.outside.map { [$0] } ?? [])).map(\.piece))
                    for pair in PatternSortCatalog.confusablePairs { expectFalse(pair.isSubset(of: pieces), q.itemID) }
                }
            }
            for item in OddOneOutGenerator.items(PatternSortStep(.l2, 0), .kind) {
                expectFalse(PatternSortCatalog.guardBlocks(item.group[0].piece, item.odd.piece, level: .l2), item.itemID)
            }
        }
        expectTrue(guardedPieces.contains(.block(.rectangle)))
        expectFalse(PatternSortCatalog.pieces(.shapes, level: .l2).contains(.block(.rectangle)))
        expectTrue(PatternSortCatalog.pieces(.shapes, level: .l3).contains(.block(.rectangle)))
        // 分車房 (astra R2): the guard holds whether the kind or shape is the rule or the ★ a helper that doubles a colour
        // rule, so blue 巴士 vs yellow 叮叮 and blue 正方形 vs yellow 長方形 by colour are refused; no ★ / ★★ deal tells
        // a guarded pair apart.
        func garages(_ rule: SortRule, helper: PatternSortMethod?, _ l: PatternSortLook, _ r: PatternSortLook) -> SortGaragesQuestion {
            SortGaragesQuestion(step: PatternSortStep(.l1, 0), rule: rule, helper: helper, noise: nil,
                                examples: [l, r], queue: [l, l, r, r], garages: [0, 0, 1, 1])
        }
        let bus = PatternSortLook(.vehicle(.bus), .blue), tram = PatternSortLook(.vehicle(.tram), .yellow)
        let square = PatternSortLook(.block(.square), .blue), rectangle = PatternSortLook(.block(.rectangle), .yellow)
        expectEqual(SortGaragesCheck.problems(garages(.colour, helper: .kind, bus, tram)), ["guarded look-alike pair"])
        expectEqual(SortGaragesCheck.problems(garages(.colour, helper: .shape, square, rectangle)), ["guarded look-alike pair"])
        expectEqual(SortGaragesCheck.problems(garages(.kind, helper: .colour, bus, tram)), ["guarded look-alike pair"], "the rule")
        expectEqual(SortGaragesCheck.problems(garages(.colour, helper: .kind, bus, PatternSortLook(.vehicle(.digger), .yellow))), [],
                    "a pair the child can tell apart")
        var sorted = 0
        for level in [ActivityLevel.l1, .l2] {
            for step in PatternSortLadder.steps(.sortGarages, level) {
                for methods in [SortSettings.defaultMethods, [.colour], [.kind], [.shape]] as [Set<PatternSortMethod>] {
                    for index in 0..<50 {
                        let q = SortGaragesGenerator.make(seed: "g\(index)", step: step, methods: methods)
                        expectFalse(PatternSortCatalog.guardBlocks(q.items(in: 0)[0].piece, q.items(in: 1)[0].piece, level: level),
                                    q.itemID)
                        sorted += 1
                    }
                }
            }
        }
        print("  pattern sort: look-alike guards — 4 pairs never told apart below ★★★ (also by a 分車房 helper; \(sorted) deals); 長方形 only at ★★★")
    }

    // MARK: T7 settings and eligibility

    /// T7: defaults, round-trip, broken blobs, `normalized()`, the last-perceptual switch, every permitted set ×
    /// tier × both 分類 cards (and 3 materials × tiers for 接落去) has a non-empty pool and valid deals, skipping, and a
    /// settings change never rewriting the stored step.
    func testSettingsEligibilityAndEveryPermittedSet() {
        expectEqual(SortSettings.defaults.methods, [.colour, .size, .shape, .kind, .group])
        expectEqual(SortSettings.defaults.guidance, .standard)
        expectTrue(SortSettings.defaults.audioEnabled)
        expectEqual(PatternSettings.defaults, PatternSettings(materials: .both, guidance: .standard, audioEnabled: true))
        let defaults = UserDefaults(suiteName: "VisaGames.patternSort.\(UUID().uuidString)")!
        let store = SortSettingsStore(defaults: defaults)
        expectEqual(store.load(), .defaults)
        let saved = SortSettings(methods: [.size, .facing], guidance: .more, audioEnabled: false)
        store.save(saved)
        expectEqual(store.load(), saved)
        for blob in ["{}", "[]", "nonsense", "{\"methods\":[\"colour\",\"smell\"],\"guidance\":\"standard\",\"audioEnabled\":true}",
                     "{\"methods\":[\"colour\"],\"guidance\":\"loud\",\"audioEnabled\":true}",
                     "{\"methods\":[\"colour\"],\"audioEnabled\":true}"] {
            defaults.set(Data(blob.utf8), forKey: SortSettingsStore.key)
            expectEqual(store.load(), .defaults, blob)
        }
        defaults.set(Data("{\"methods\":[\"kind\",\"group\"],\"guidance\":\"less\",\"audioEnabled\":true}".utf8),
                     forKey: SortSettingsStore.key)
        expectEqual(store.load().methods, [.kind, .group, .shape], "normalised on load: 形狀 back on")
        let patterns = PatternSettingsStore(defaults: defaults)
        expectEqual(patterns.load(), .defaults)
        patterns.save(PatternSettings(materials: .shapes, guidance: .less, audioEnabled: false))
        expectEqual(patterns.load(), PatternSettings(materials: .shapes, guidance: .less, audioEnabled: false))
        defaults.set(Data("{\"materials\":\"wood\"}".utf8), forKey: PatternSettingsStore.key)
        expectEqual(patterns.load(), .defaults)
        // The last of 顏色・大細・形狀 stays on.
        let one = SortSettings(methods: [.size, .kind])
        expectEqual(one.toggling(.size), .refusedLastPerceptual)
        guard case .updated(let more) = one.toggling(.colour), case .updated(let fewer) = more.toggling(.size) else {
            preconditionFailure("toggles")
        }
        expectEqual(fewer.methods, [.colour, .kind])
        expectEqual(SortSettings(methods: [.kind]).normalized().methods, [.kind, .shape])
        expectEqual(SortSettings(methods: [.size, .kind, .colour]).methodsCode, "colour kind size")

        var dealt = 0
        for methods in Self.permittedMethodSets {
            for level in ActivityLevel.allCases {
                for kind in Self.sortKinds {
                    let eligible = PatternSortLadder.eligibleSteps(kind, level, methods: methods)
                    expectFalse(eligible.isEmpty, "\(kind) \(level) \(methods)")
                    expectTrue(PatternSortProgress().liveStep(kind, level, methods: methods) != nil)
                    for step in eligible {
                        for index in 0..<50 {
                            if kind == .oddOneOut {
                                let q = OddOneOutGenerator.make(seed: "t7-\(index)", step: step, methods: methods)
                                expectEqual(OddOneOutCheck.problems(q), [], q.itemID)
                            } else {
                                let q = SortGaragesGenerator.make(seed: "t7-\(index)", step: step, methods: methods)
                                expectEqual(SortGaragesCheck.problems(q), [], q.itemID)
                                expectTrue(methods.contains(q.rule.method) || q == SortGaragesGenerator.fallback(level), q.itemID)
                            }
                            dealt += 1
                        }
                    }
                }
            }
        }
        for materials in PatternSortMaterials.allCases {
            for level in ActivityLevel.allCases {
                expectEqual(PatternSortLadder.eligibleSteps(.patternNext, level, methods: []).count,
                            PatternSortLadder.steps(.patternNext, level).count)
                for step in PatternSortLadder.steps(.patternNext, level) {
                    for index in 0..<50 {
                        let q = PatternGenerator.make(seed: "t7-\(index)", step: step, materials: materials)
                        expectEqual(PatternCheck.problems(q), [], q.itemID)
                        dealt += 1
                    }
                }
            }
        }
        // Skipping: the stored step if eligible, else the nearest below, else above; settings never rewrite it.
        var progress = PatternSortProgress(tiers: [PatternSortProgress.key(.oddOneOut, .l1): PatternSortTierProgress(step: 1)])
        expectEqual(progress.liveStep(.oddOneOut, .l1, methods: [.colour, .size, .shape])?.code, "L1.b")
        expectEqual(progress.liveStep(.oddOneOut, .l1, methods: [.colour, .shape])?.code, "L1.a", "below first")
        expectEqual(progress.liveStep(.oddOneOut, .l1, methods: [.shape])?.code, "L1.c", "then above")
        expectEqual(progress.state(.oddOneOut, .l1).step, 1, "a settings change never rewrites the stored step")
        progress.record(.oddOneOut, PatternSortStep(.l1, 2), outcome: .firstTry, methods: [.shape], now: Date())
        progress.record(.oddOneOut, PatternSortStep(.l1, 2), outcome: .firstTry, methods: [.shape], now: Date())
        expectEqual(progress.state(.oddOneOut, .l1).step, 2, "a sole eligible step stays (top of what is on)")
        expectEqual(PatternSortLadder.shapeFallback(.oddOneOut, .l2).code, "L2.c")
        expectTrue(OddOneOutGenerator.targets(PatternSortLadder.shapeFallback(.oddOneOut, .l3)).contains(.shape))
        print("  pattern sort: settings round-trip, 6 broken blobs, last-perceptual guard; 56 sets × 3 tiers × 2 cards and 3 materials — \(dealt) valid deals")
    }

    // MARK: T12 detector

    /// T12: AB, AAB, ABB, ABC, AABB found (also from inside the unit); none for no repeat; a partial last unit is fine.
    func testDetectorNamesTheRepeat() {
        func row(_ text: String) -> [String] { text.map(String.init) }
        expectEqual(PatternDetector.detect(row("XYXYXYXY")), .ab)
        expectEqual(PatternDetector.detect(row("XXYXXYXX")), .aab)
        expectEqual(PatternDetector.detect(row("XYYXYYXY")), .abb)
        expectEqual(PatternDetector.detect(row("XYZXYZXY")), .abc)
        expectEqual(PatternDetector.detect(row("XXYYXXYY")), .aabb)
        expectEqual(PatternDetector.detect(row("XYXXYXXY")), .aab, "starts inside its unit")
        expectEqual(PatternDetector.detect(row("XYXYX")), .ab, "partial last unit")
        expectNil(PatternDetector.detect(row("XXXXXXXX")))
        expectNil(PatternDetector.detect(row("XYZZYXZY")))
        expectNil(PatternDetector.detect(row("XYZWXYZW")))  // ABCD is not a named unit
        var board = PatternMakeBoard(palette: PatternMakeGenerator.palette(seed: "d", materials: .vehicles), deal: "d")
        for piece in [0, 1, 0, 1, 0, 1, 0, 1] { _ = board.place(piece) }
        expectEqual(board.detected, .ab)
        print("  pattern sort: detector — AB, AAB, ABB, ABC, AABB (also from inside the unit), none for no repeat")
    }

    // MARK: T15 geometry

    /// T15: centred rows and garages, the strip pitch and piece widths with strokes, the queue inside the panel, the
    /// header cluster ≤ x 1164 for every new kind, nothing in K or the parent-corner keep-out.
    func testLayoutGeometry() {
        for (count, left, right) in [(2, 328.0, 952.0), (3, 166.0, 1114.0), (4, 124.0, 1156.0)] {
            let rects = PatternSortLayout.choiceRects(count)
            expectEqual(rects.count, count)
            expectEqual(rects.first!.x, left, accuracy: 0.5)
            expectEqual(rects.last!.maxX, right, accuracy: 0.5)
            expectEqual((rects.first!.x + rects.last!.maxX) / 2, 640, accuracy: 0.5)
            expectEqual(rects[0].width, count == 4 ? 240 : 300)
            expectEqual([rects[0].y, rects[0].maxY], [430, 640])
        }
        let garages = PatternSortLayout.garageRects()
        expectEqual([garages[0].x, garages[0].maxX, garages[1].x, garages[1].maxX], [200, 600, 680, 1080])
        expectEqual(PatternSortLayout.stripCentres(7).map { ($0 * 1000).rounded() / 1000 },
                    [293.714, 409.143, 524.571, 640, 755.429, 870.857, 986.286])
        expectEqual(PatternSortLayout.maxPieceWidth(6), 121.2, accuracy: 0.001)
        let widest = PatternSortCatalog.vehicles.compactMap { TapCountArt.named($0.rawValue)?.width }.max() ?? 0
        for n in 6...8 {
            let scale = PatternSortLayout.pieceScale(widestArt: widest, n: n)
            expectTrue(widest * scale <= PatternSortLayout.maxPieceWidth(n) + 1e-9)
            expectTrue(ShapeBlockArt.artwork(.rectangle).width * PatternSortLayout.pieceScale(widestArt: 200, n: n)
                       <= PatternSortLayout.maxPieceWidth(n) + 1e-9)
        }
        let waiting = PatternSortLayout.queueWaiting(5)
        expectEqual(waiting.count, 5)
        expectTrue(waiting.allSatisfy { $0.x >= 236 && $0.width <= 64 && PatternSortLayout.panel.contains(LineMatchPoint(x: $0.midX, y: $0.midY)) })
        var rects = PatternSortLayout.choiceRects(2) + PatternSortLayout.choiceRects(3) + PatternSortLayout.choiceRects(4)
            + garages + waiting + [PatternSortLayout.panel, PatternSortLayout.emblem]
        for kind in [ActivityKind.patternNext, .patternMake, .oddOneOut, .sortGarages] {
            expectEqual(PatternSortLayout.coneTotal(kind), 1)
            let header = PatternSortLayout.headerRect(kind)
            expectTrue(header.maxX <= 1164, "\(kind) header ends at \(header.maxX)")
            rects.append(header)
        }
        for rect in rects { for keep in PatternSortLayout.keepOuts { expectFalse(rect.intersects(keep), "\(rect)") } }
        expectEqual(PatternSortLayout.headerWidth(cones: 6), 236)
        expectEqual(PatternSortLayout.bubbleRightEdge(zh: String(repeating: "車", count: 18), en: ""), 806.05, accuracy: 0.01)
        expectFalse(PatternSortLayout.fitsBubble(zh: String(repeating: "車", count: 19), en: ""))
        expectFalse(PatternSortLayout.fitsBubble(zh: "車", en: String(repeating: "a", count: 53)))
        // Astra R2, the row as the screen lays it out (`canvasPlaced` left edge, `ChoiceCardChrome` widths and the row's
        // gap `rowGapPoints`, read inside the stage): centred at 640 u at the TV's 1920 × 1080 (scale 1.35) and at
        // 1280 × 720 (0.9). Control: the older boards' fixed 24-point gap would put 4 cards at 630.67 u / 644 u.
        for (width, height, scale) in [(1920.0, 1080.0, 1.35), (1280.0, 720.0, 0.9)] {
            let stage = DesignTokens.stageLayout(screenWidth: width, screenHeight: height)
            expectEqual(stage.scale, scale, accuracy: 1e-9)
            expectEqual(PatternSortLayout.rowGapPoints(scale: stage.scale), 24 * scale, accuracy: 1e-9)
            for count in [3, 4] {
                expectEqual(PatternSortLayout.screenRowCentre(count, scale: stage.scale,
                                                              gapPoints: PatternSortLayout.rowGapPoints(scale: stage.scale)),
                            640, accuracy: 1e-9)
            }
        }
        expectEqual(PatternSortLayout.screenRowCentre(4, scale: 1.35, gapPoints: 24), 630.67, accuracy: 0.01)
        expectEqual(PatternSortLayout.screenRowCentre(4, scale: 0.9, gapPoints: 24), 644, accuracy: 0.01)
        expectEqual(PatternSortLayout.screenRowCentre(3, scale: 1, gapPoints: PatternSortLayout.rowGapPoints(scale: 1)), 640,
                    accuracy: 1e-9)
        print("  pattern sort: geometry — centred 2 / 3 / 4-card rows (640 u at stage scales 1.35 and 0.9) and garages, strip pitch, one-cone header ≤ x 1164, K and the corner clear")
    }
}
