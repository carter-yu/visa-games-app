import Foundation
import VisaCore

/// v0.23.0 連一連 / Line Match (design §1.6, §1.7, §6, §8.6; D1 ★ = tier, D2 off-path is not a
/// miss, D3 judge only at 完成 + eraser, D7 new kinds default off). All offline.
final class LineMatchTests {
    private let seeds = (0..<1_000).map { "round-\($0)" }

    private func board(_ level: ActivityLevel, seed: String = "board",
                       tolerance: LineMatchTolerance = .standard) -> LineMatchBoard {
        LineMatchBoard(question: LineMatchGenerator.make(seed: seed, level: level, avoidingItem: nil),
                       tolerance: tolerance)
    }

    /// A slot that is wrong for `row` (never the right one).
    private func wrongSlot(_ board: LineMatchBoard, row: Int) -> Int {
        let right = board.question.correctSlot(forRow: row) ?? 0
        return (right + 1) % board.question.pairCount
    }

    @discardableResult
    private func draw(_ board: inout LineMatchBoard, row: Int, slot: Int) -> LineMatchDropOutcome {
        _ = board.beginDrag(at: board.layout.leftDots[row])
        return board.endDrag(at: board.layout.rightDots[slot])
    }

    // MARK: Generator

    func testGeneratorIsAPureFunctionOfSeedLevelAndWeights() {
        for level in ActivityLevel.allCases {
            let a = LineMatchGenerator.make(seed: "same", level: level, avoidingItem: nil)
            expectEqual(a, LineMatchGenerator.make(seed: "same", level: level, avoidingItem: nil))
            expectEqual(a.level, level)
            var items = Set<String>()
            for seed in seeds.prefix(200) {
                items.insert(LineMatchGenerator.make(seed: seed, level: level, avoidingItem: nil).itemID)
            }
            expectTrue(items.count >= 20, "\(level.code) only \(items.count) distinct items")
        }
        let onlyBody = LineMatchSettings(weights: [.numbers: 0, .body: 30, .animals: 0, .zodiac: 0])
        let body = LineMatchGenerator.make(seed: "same", level: .l2, avoidingItem: nil, settings: onlyBody)
        expectEqual(body.category, .body)
        expectEqual(body, LineMatchGenerator.make(seed: "same", level: .l2, avoidingItem: nil, settings: onlyBody))
        expectTrue(body.itemID.hasPrefix("lineMatch.L2.body."))
        // Same kind never deals the same item twice in a row.
        for seed in seeds.prefix(300) {
            let first = LineMatchGenerator.make(seed: seed, level: .l2, avoidingItem: nil)
            let next = LineMatchGenerator.make(seed: seed, level: .l2, avoidingItem: first.itemID)
            expectTrue(next.itemID != first.itemID, "repeat \(first.itemID)")
        }
        expectEqual(ActivityCatalog.lineMatchQuestion(seed: "x", level: .l3),
                    LineMatchGenerator.make(seed: "x", level: .l3, avoidingItem: nil))
    }

    func testTiersAreWellFormedAndTerminateForThousandsOfSeeds() {
        expectEqual(ActivityLevel.allCases.map(LineMatchGenerator.pairCount), [2, 3, 4])
        for level in ActivityLevel.allCases {
            for seed in seeds {
                let q = LineMatchGenerator.make(seed: seed, level: level, avoidingItem: nil)
                expectTrue(q.isWellFormed, "\(seed) \(level.code) \(q.itemID)")
                expectEqual(q.pairCount, LineMatchGenerator.pairCount(level))
                // No pair straight across.
                for row in 0..<q.pairCount { expectTrue(q.correctSlot(forRow: row) != row) }
                expectTrue(q.itemID.hasPrefix("lineMatch.\(level.code).\(q.category.rawValue)"))
                let avoided = LineMatchGenerator.make(seed: seed, level: level, avoidingItem: q.itemID)
                expectTrue(avoided.isWellFormed)
            }
            // Every candidate list the generator picks from is finite and non-empty.
            expectFalse(LineMatchGenerator.numberSets(level).isEmpty)
            for category in LineMatchCategory.allCases where category != .numbers && category.isDealt(at: level) {
                expectFalse(LineMatchGenerator.wordSets(category, level: level).isEmpty)
            }
        }
        expectTrue(LineMatchGenerator.reference.isWellFormed)
    }

    func testCategoryWeightsHoldWithinTwoPercent() {
        let samples = (0..<10_000).map { "weights-\($0)" }
        func shares(_ level: ActivityLevel, _ settings: LineMatchSettings) -> [LineMatchCategory: Double] {
            var counts: [LineMatchCategory: Int] = [:]
            for seed in samples {
                counts[LineMatchGenerator.category(seed: seed, level: level, settings: settings), default: 0] += 1
            }
            return counts.mapValues { Double($0) / Double(samples.count) }
        }
        let defaults = LineMatchSettings.defaults
        expectEqual(LineMatchCategory.allCases.map(\.defaultWeight), [35, 30, 20, 15])
        for level in [ActivityLevel.l2, .l3] {
            let seen = shares(level, defaults)
            for category in LineMatchCategory.allCases {
                expectEqual(seen[category] ?? 0, Double(category.defaultWeight) / 100, accuracy: 0.02)
            }
        }
        // ★ never deals the zodiac; its share is spread over the others.
        let one = shares(.l1, defaults)
        expectEqual(one[.zodiac] ?? 0, 0)
        expectEqual(one[.numbers] ?? 0, 35.0 / 85.0, accuracy: 0.02)
        expectEqual(one[.body] ?? 0, 30.0 / 85.0, accuracy: 0.02)
        expectEqual(defaults.share(of: .animals, at: .l1), 20.0 / 85.0, accuracy: 0.0001)
        // 0 = never dealt.
        let noNumbers = LineMatchSettings(weights: [.numbers: 0, .body: 50, .animals: 50, .zodiac: 0])
        let custom = shares(.l3, noNumbers)
        expectEqual(custom[.numbers] ?? 0, 0)
        expectEqual(custom[.zodiac] ?? 0, 0)
        expectEqual(custom[.body] ?? 0, 0.5, accuracy: 0.02)
        // All zero falls back to the defaults; the parent cannot turn the last one off.
        let allZero = LineMatchSettings(weights: [.numbers: 0, .body: 0, .animals: 0, .zodiac: 0])
        expectTrue(allZero.hasDefaultMix)
        let lastOn = LineMatchSettings(weights: [.numbers: 5, .body: 0, .animals: 0, .zodiac: 0])
        expectNil(lastOn.adjusting(.numbers, steps: -1))
        expectEqual(lastOn.adjusting(.body, steps: 1)?.weight(.body), 5)
        expectEqual(LineMatchSettings.defaults.adjusting(.numbers, steps: 20)?.weight(.numbers), 100)
        // Zodiac only: ★ still deals (defaults without the zodiac).
        let zodiacOnly = LineMatchSettings(weights: [.numbers: 0, .body: 0, .animals: 0, .zodiac: 40])
        expectEqual(zodiacOnly.dealWeights(for: .l1).map { $0.category }, [.numbers, .body, .animals])
        expectEqual(LineMatchGenerator.make(seed: "z", level: .l2, avoidingItem: nil, settings: zodiacOnly).category,
                    .zodiac)
        expectEqual(defaults.mixDescription, "numbers:35,body:30,animals:20,zodiac:15")
    }

    func testNumberRulesPerTier() {
        expectEqual(LineMatchGenerator.numberSets(.l1).count, 6)  // {1,3}{1,4}{1,5}{2,4}{2,5}{3,5}
        for set in LineMatchGenerator.numberSets(.l1) {
            expectTrue(set.allSatisfy { (1...5).contains($0) })
            expectTrue(abs(set[0] - set[1]) >= 2)
        }
        for set in LineMatchGenerator.numberSets(.l2) {
            expectTrue(set.allSatisfy { (1...7).contains($0) })
            let sorted = set.sorted()
            expectTrue(zip(sorted, sorted.dropFirst()).contains { $1 - $0 == 1 })
        }
        for level in ActivityLevel.allCases {
            for set in LineMatchGenerator.numberSets(level) {
                expectEqual(Set(set).count, LineMatchGenerator.pairCount(level))
                expectFalse(set.contains(6) && set.contains(9), "6 and 9 together")
            }
        }
        let numbersOnly = LineMatchSettings(weights: [.numbers: 100, .body: 0, .animals: 0, .zodiac: 0])
        var objects = Set<LineMatchCountObject>()
        for level in ActivityLevel.allCases {
            for seed in seeds {
                let q = LineMatchGenerator.make(seed: seed, level: level, avoidingItem: nil, settings: numbersOnly)
                expectEqual(q.category, .numbers)
                guard let object = q.countObject else { preconditionFailure("numbers without an object") }
                objects.insert(object)
                let numbers = q.pairs.compactMap(\.numeral)
                expectFalse(numbers.contains(6) && numbers.contains(9))
                expectTrue(numbers.allSatisfy { LineMatchGenerator.numberRange(level).contains($0) })
                for pair in q.pairs {
                    expectEqual(pair.count, pair.numeral ?? -1)
                    expectEqual(pair.iconKey, object.iconKey)
                    expectEqual(pair.labelTraditionalChinese, LineMatchCatalog.chineseNumeral(pair.count))
                }
                expectTrue(q.promptTraditionalChinese.contains(object.measureWord))
            }
        }
        expectEqual(objects, Set(LineMatchCountObject.allCases))
        expectEqual(LineMatchCountObject.allCases.map(\.measureWord), ["隻", "架", "個"])
        expectEqual((1...10).map(LineMatchCatalog.chineseNumeral).joined(), "一二三四五六七八九十")
    }

    func testConfusionGroupsNeverShareAQuestion() {
        let codes = Set(LineMatchCatalog.confusionGroups.map(\.code))
        expectEqual(codes, ["B1", "B2", "A1", "A2", "A3", "A4", "A5", "A6", "N1"])
        func group(_ code: String, _ category: LineMatchCategory) -> Set<String> {
            LineMatchCatalog.confusionGroups.first { $0.code == code && $0.category == category }?.members ?? []
        }
        expectEqual(group("B1", .body), ["hand", "foot"])
        expectEqual(group("B2", .body), ["eye", "mouth"])
        expectEqual(group("A3", .zodiac), ["tiger"])
        expectEqual(group("A6", .zodiac), ["snake", "dragon"])
        expectEqual(group("N1", .numbers), ["6", "9"])
        // Every set the generator can pick from is confusion-safe …
        for level in ActivityLevel.allCases {
            for category in [LineMatchCategory.body, .animals, .zodiac] {
                for set in LineMatchGenerator.wordSets(category, level: level) {
                    expectTrue(LineMatchCatalog.isConfusionSafe(set.map(\.id), in: category))
                    if level == .l1 { expectTrue(set.allSatisfy(\.isStarter)) }
                }
            }
        }
        // … and so is every dealt question.
        for level in ActivityLevel.allCases {
            for seed in seeds {
                let q = LineMatchGenerator.make(seed: seed, level: level, avoidingItem: nil)
                if q.category != .numbers {
                    expectTrue(LineMatchCatalog.isConfusionSafe(q.pairs.map(\.key), in: q.category))
                }
                if level == .l1 { expectTrue(q.category != .zodiac) }
            }
        }
        expectFalse(LineMatchCatalog.isConfusionSafe(["hand", "foot"], in: .body))
        expectFalse(LineMatchCatalog.isConfusionSafe(["calf", "fawn"], in: .animals))
        expectFalse(LineMatchCatalog.isConfusionSafe(["ox", "goat"], in: .zodiac))
        expectTrue(LineMatchCatalog.isConfusionSafe(["hand", "eye", "ear", "nose"], in: .body))
        // ★★★ body has exactly the 4 safe sets (one of 手/腳 × one of 眼睛/口 + 耳仔 + 鼻).
        expectEqual(LineMatchGenerator.wordSets(.body, level: .l3).count, 4)
    }

    func testCopyIsHongKongTraditionalAndASCIIEnglish() {
        // Design §8.6 blacklist of common Simplified-only characters (+ the ones this game could hit).
        let simplified: Set<Character> = [
            "车", "个", "们", "数", "线", "书", "画", "门", "马", "见", "说", "话", "这", "发", "头", "脚", "图",
            "连", "认", "读", "写", "听", "点", "绿", "红", "后", "里", "扰", "辆", "几", "货", "铁", "龙",
            "鸡", "猪", "骝", "将", "闪", "紧", "鸟", "试", "错", "对"
        ]
        func checkChinese(_ text: String) {
            expectFalse(text.isEmpty)
            expectFalse(text.contains(where: { simplified.contains($0) }), "Simplified character in \(text)")
            expectTrue(isTraditionalChineseOnly(text) && perfTraditionalOnly(text), text)
        }
        func checkEnglish(_ text: String) {
            expectFalse(text.isEmpty)
            expectTrue(text.unicodeScalars.allSatisfy { $0.isASCII }, "non-ASCII English: \(text)")
        }
        for category in LineMatchCategory.allCases {
            checkChinese(category.titleTraditionalChinese)
            checkEnglish(category.titleEnglish)
            for item in LineMatchCatalog.items(category) {
                checkChinese(item.labelTraditionalChinese)
                checkEnglish(item.labelEnglish)
            }
        }
        for tolerance in LineMatchTolerance.allCases {
            checkChinese(tolerance.labelTraditionalChinese)
            checkEnglish(tolerance.labelEnglish)
        }
        for level in ActivityLevel.allCases {
            for seed in seeds.prefix(300) {
                let q = LineMatchGenerator.make(seed: seed, level: level, avoidingItem: nil)
                checkChinese(q.promptTraditionalChinese)
                checkEnglish(q.promptEnglish)
                let hint = q.hintTraditionalChinese.components(separatedBy: " / ")
                expectEqual(hint.count, 2)
                checkChinese(hint[0])
                checkEnglish(hint[1])
                expectTrue(hint[0].hasPrefix("提示："))
                for pair in q.pairs {
                    checkChinese(pair.labelTraditionalChinese)
                    checkEnglish(pair.labelEnglish)
                }
            }
        }
        for line in LineMatchCopy.allTraditionalLines { checkChinese(line) }
        for line in LineMatchCopy.allEnglishLines { checkEnglish(line) }
        checkChinese(ActivityKind.lineMatch.parentCardTitle + ActivityKind.lineMatch.parentHelpTraditionalChinese)
        expectEqual(ActivityKind.lineMatch.parentCardTitle, "連一連")
        expectEqual(LineMatchCatalog.body.map(\.labelTraditionalChinese), ["眼睛", "耳仔", "口", "鼻", "手", "腳"])
        expectEqual(LineMatchCatalog.animals.map(\.labelTraditionalChinese), ["貓仔", "狗仔", "牛仔", "兔仔", "鹿仔", "馬騮仔"])
        expectEqual(LineMatchCatalog.zodiac.map(\.labelTraditionalChinese),
                    ["鼠", "牛", "虎", "兔", "龍", "蛇", "馬", "羊", "猴", "雞", "狗", "豬"])
    }

    // MARK: Layout + art

    func testCountCardsHoldExactlyNObjectsWithoutOverlap() {
        let numbersOnly = LineMatchSettings(weights: [.numbers: 100, .body: 0, .animals: 0, .zodiac: 0])
        for level in ActivityLevel.allCases {
            for seed in seeds.prefix(400) {
                let q = LineMatchGenerator.make(seed: seed, level: level, avoidingItem: nil, settings: numbersOnly)
                let b = LineMatchBoard(question: q)
                var sizes = Set<Double>()
                for row in 0..<q.pairCount {
                    let card = b.layout.leftCards[row]
                    let spots = b.objectPlacements(row: row)
                    expectEqual(spots.count, q.pairs[row].count)
                    expectTrue(LineMatchCountLayout.isClear(spots, cardWidth: card.width, cardHeight: card.height),
                               "\(q.itemID) row \(row)")
                    for spot in spots {
                        expectTrue(max(spot.width, spot.height) >= 38 && max(spot.width, spot.height) <= 55)
                        sizes.insert((spot.width * 100).rounded())
                    }
                    // At most 5 per row.
                    let rowsY = Dictionary(grouping: spots, by: { ($0.y * 10).rounded() })
                    expectTrue(rowsY.values.allSatisfy { $0.count <= 5 })
                }
                expectEqual(sizes.count, 1, "one object size per question")
            }
        }
        // Ten frame: 7 = 5 on top + 2 from the left underneath.
        let seven = LineMatchCountLayout.placements(count: 7, object: .apple, scale: 0.9, cardWidth: 240, cardHeight: 120)
        let top = seven.filter { $0.y < 60 }.sorted { $0.x < $1.x }
        let bottom = seven.filter { $0.y > 60 }.sorted { $0.x < $1.x }
        expectEqual(top.count, 5)
        expectEqual(bottom.count, 2)
        expectEqual(bottom[0].x, top[0].x, accuracy: 0.001)
        expectEqual(bottom[1].x, top[1].x, accuracy: 0.001)
    }

    func testLayoutKeepsButtonsClearOfCardsAndTheParentCorner() {
        let stage = LineMatchRect(x: 0, y: 0, width: 1280, height: 720)
        for pairs in 2...4 {
            for category in LineMatchCategory.allCases {
                let layout = LineMatchLayout.make(pairCount: pairs, category: category)
                expectEqual(layout.style, pairs == 2 ? .wide : .side)
                let cards = layout.leftCards + layout.rightCards
                expectEqual(cards.count, pairs * 2)
                let buttons = [layout.eraser, layout.done]
                expectTrue(layout.eraser.width >= 160 && layout.eraser.height >= 160)
                expectTrue(layout.done.width >= 160 && layout.done.height >= 160)
                for card in cards {
                    expectTrue(card.height >= 120, "cards ≥ 120u")
                    expectTrue(card.width >= 120)
                    expectFalse(card.intersects(LineMatchLayout.header))
                    expectFalse(card.intersects(LineMatchLayout.parentCornerKeepOut))
                    expectTrue(stage.contains(LineMatchPoint(x: card.x, y: card.y))
                               && stage.contains(LineMatchPoint(x: card.maxX, y: card.maxY)))
                    for button in buttons {
                        expectTrue(button.gap(to: card) >= 80, "button \(button) vs card \(card)")
                    }
                }
                for index in 0..<(cards.count - 1) {
                    for other in (index + 1)..<cards.count { expectFalse(cards[index].intersects(cards[other])) }
                }
                for button in buttons {
                    expectFalse(button.intersects(LineMatchLayout.parentCornerKeepOut), "button in parent corner")
                    expectTrue(stage.contains(LineMatchPoint(x: button.maxX, y: button.maxY)))
                }
                expectFalse(layout.eraser.intersects(layout.done))
                // Drop zones (widest tolerance) never reach the parent corner or a button.
                let radius = LineMatchTolerance.wide.dotRadius
                for dot in layout.leftDots + layout.rightDots {
                    let zone = LineMatchRect(x: dot.x - radius, y: dot.y - radius, width: 2 * radius, height: 2 * radius)
                    expectFalse(zone.intersects(LineMatchLayout.parentCornerKeepOut))
                    expectFalse(zone.intersects(layout.done))
                }
                for row in 0..<pairs {
                    expectTrue(layout.leftDots[row].x < layout.rightDots[row].x - 200)
                }
            }
        }
        // ★ completes in the bottom bar but its right edge stops at 1080 (mockup 05a).
        expectEqual(LineMatchLayout.make(pairCount: 2, category: .body).done.maxX, 1080)
    }

    func testToleranceChangesOnlyTheHitRadius() {
        expectEqual(LineMatchTolerance.allCases.map(\.dotRadius), [40, 60, 90])
        expectEqual(LineMatchSettings.defaults.tolerance, .standard)
        let q = LineMatchGenerator.make(seed: "tol", level: .l2, avoidingItem: nil)
        let layout = LineMatchLayout.make(pairCount: 3, category: q.category)
        let dot = layout.leftDots[1]
        let near = LineMatchPoint(x: dot.x + 50, y: dot.y)
        let far = LineMatchPoint(x: dot.x + 75, y: dot.y)
        expectNil(layout.leftRow(at: near, radius: LineMatchTolerance.narrow.dotRadius))
        expectEqual(layout.leftRow(at: near, radius: LineMatchTolerance.standard.dotRadius), 1)
        expectNil(layout.leftRow(at: far, radius: LineMatchTolerance.standard.dotRadius))
        expectEqual(layout.leftRow(at: far, radius: LineMatchTolerance.wide.dotRadius), 1)
        // The whole card is a target at every tolerance.
        let card = layout.rightCards[2]
        expectEqual(layout.rightSlot(at: LineMatchPoint(x: card.midX, y: card.midY), radius: 40), 2)
        // Narrow: a drop 50u short of the red dot springs back; wide: it joins.
        for (tolerance, joins) in [(LineMatchTolerance.narrow, false), (LineMatchTolerance.wide, true)] {
            var b = LineMatchBoard(question: q, tolerance: tolerance)
            _ = b.beginDrag(at: b.layout.leftDots[0])
            let target = b.layout.rightDots[1]
            let outcome = b.endDrag(at: LineMatchPoint(x: target.x - 50, y: target.y))
            if joins {
                expectEqual(outcome, .joined(row: 0, slot: 1, replaced: 0))
            } else {
                expectEqual(outcome, .retracted(row: 0))
            }
        }
        // Layout is the same at every tolerance (only hit testing changes).
        expectEqual(LineMatchBoard(question: q, tolerance: .narrow).layout, LineMatchBoard(question: q, tolerance: .wide).layout)
    }

    func testLineMatchArtCoversEveryIcon() {
        var keys = Set(["minitruck"])
        for category in LineMatchCategory.allCases {
            for item in LineMatchCatalog.items(category) { keys.insert(item.iconKey) }
        }
        for object in LineMatchCountObject.allCases { keys.insert(object.iconKey) }
        expectEqual(keys.count, 25)
        for key in keys {
            guard let art = LineMatchArt.icon(key) else { preconditionFailure("no art for \(key)") }
            expectTrue(art.width > 0 && art.height > 0)
            expectFalse(art.elements.isEmpty)
            for element in art.elements {
                if case let .path(commands) = element.geometry { expectFalse(commands.isEmpty, key) }
                if case let .path(commands)? = element.clip { expectFalse(commands.isEmpty, key) }
                expectTrue(element.style.fill != nil || element.style.stroke != nil)
                expectTrue(element.style.opacity > 0 && element.style.opacity <= 1)
            }
        }
        expectEqual(Set(LineMatchArt.all.map(\.name)).count, LineMatchArt.all.count)
        for item in LineMatchCatalog.body + LineMatchCatalog.animals + LineMatchCatalog.zodiac {
            expectEqual(LineMatchArt.icon(item.iconKey)?.width, 200)
        }
        // Count objects keep the box the layout assumes.
        for object in LineMatchCountObject.allCases {
            expectEqual(LineMatchArt.icon(object.iconKey)?.width, object.artSize.width)
            expectEqual(LineMatchArt.icon(object.iconKey)?.height, object.artSize.height)
        }
        expectNil(LineMatchArt.icon("unicorn"))
    }

    // MARK: Board state machine

    func testDragJoinsReplacesAndRetractsWithoutPenalty() {
        var b = board(.l2)
        expectEqual(b.beginDrag(at: b.layout.leftDots[0]), .started(row: 0))
        expectEqual(b.activeRow, 0)
        expectEqual(b.endDrag(at: b.layout.rightDots[1]), .joined(row: 0, slot: 1, replaced: 0))
        expectEqual(b.lines, [0: 1])
        // Off-path / empty-space drop: the line springs back, the old line stays, no miss.
        expectEqual(b.beginDrag(at: b.layout.leftDots[0]), .started(row: 0))
        expectEqual(b.visibleLines.count, 0, "old line lifts while redrawing")
        expectEqual(b.endDrag(at: LineMatchPoint(x: 640, y: 300)), .retracted(row: 0))
        expectEqual(b.lines, [0: 1])
        expectEqual(b.incompleteStrokes, 1)
        // Redraw replaces this row's line.
        expectEqual(draw(&b, row: 0, slot: 2), .joined(row: 0, slot: 2, replaced: 1))
        expectEqual(b.lines, [0: 2])
        // One line per red dot: drawing into a taken slot moves it.
        expectEqual(draw(&b, row: 1, slot: 2), .joined(row: 1, slot: 2, replaced: 1))
        expectEqual(b.lines, [1: 2])
        expectEqual(b.preSubmitChanges, 2)
        expectEqual(draw(&b, row: 1, slot: 2), .unchanged(row: 1, slot: 2))
        // Starting on the right side is a motor slip (`wrong_direction`), never a line.
        expectEqual(b.beginDrag(at: b.layout.rightDots[0]), .wrongDirection)
        expectEqual(b.wrongDirections, 1)
        expectNil(b.activeRow)
        expectEqual(b.beginDrag(at: LineMatchPoint(x: 640, y: 40)), .ignored)
        // Cancel (Think Pause) changes nothing else.
        _ = b.beginDrag(at: b.layout.leftDots[2])
        b.cancelDrag()
        expectNil(b.activeRow)
        expectEqual(b.endDrag(at: b.layout.rightDots[0]), .ignored)
        expectEqual(b.lines, [1: 2])
        expectEqual(b.submits, 0)
    }

    func testDoneNeedsEveryDotAndJudgesOncePerSubmit() {
        var b = board(.l3)
        let n = b.question.pairCount
        expectFalse(b.canSubmit)
        expectEqual(b.submit(), .notReady(missing: n))
        expectEqual(b.submits, 0, "not-ready 完成 is never judged")
        // Rows 0 and 1 wrong, the rest right (no slot shared: swap the right answers of 0 and 1).
        let right0 = b.question.correctSlot(forRow: 0)!
        let right1 = b.question.correctSlot(forRow: 1)!
        draw(&b, row: 0, slot: right1)
        draw(&b, row: 1, slot: right0)
        for row in 2..<n { draw(&b, row: row, slot: b.question.correctSlot(forRow: row)!) }
        expectTrue(b.canSubmit)
        guard case .judged(let judgement) = b.submit() else { preconditionFailure("judged") }
        expectEqual(judgement.wrong.map(\.row), [0, 1])
        expectEqual(judgement.correct.count, n - 2)
        expectFalse(judgement.solved)
        // Right lines lock green; wrong lines are cleared and ringed.
        expectEqual(b.locked.count, n - 2)
        expectTrue(b.lines.isEmpty)
        expectEqual(b.rejectedRows, [0, 1])
        expectEqual(Set(b.rejectedSlots), Set([right0, right1]))
        expectFalse(b.canSubmit)
        expectEqual(b.hintRow, 0)
        // ONE miss per submit, however many lines were wrong (existing policy).
        var pending = 15
        var misses = 0
        if !judgement.solved {
            pending = WrongAnswerPolicy.halvedPendingMinutes(pending)
            misses += 1
        }
        expectEqual(pending, 7)
        // Locked rows cannot be redrawn or targeted.
        expectEqual(b.beginDrag(at: b.layout.leftDots[2]), .lockedRow)
        _ = b.beginDrag(at: b.layout.leftDots[0])
        expectEqual(b.endDrag(at: b.layout.rightDots[b.question.correctSlot(forRow: 2)!]), .retracted(row: 0))
        // Second wrong 完成 → hint after 2 misses.
        draw(&b, row: 0, slot: right1)
        draw(&b, row: 1, slot: right0)
        guard case .judged(let second) = b.submit() else { preconditionFailure("judged") }
        expectFalse(second.solved)
        misses += 1
        expectTrue(ActivityHintPolicy.shouldAutoHint(afterMissCount: misses))
        expectEqual(b.wrongSubmits, 2)
        // Fix them: solved; locked green kept.
        draw(&b, row: 0, slot: right0)
        draw(&b, row: 1, slot: right1)
        guard case .judged(let last) = b.submit() else { preconditionFailure("judged") }
        expectTrue(last.solved)
        expectTrue(b.solved)
        expectEqual(b.locked.count, n)
        expectEqual(b.submits, 3)
        expectEqual(b.submit(), .ignored)
        expectEqual(b.beginDrag(at: b.layout.leftDots[0]), .ignored)
    }

    func testEraserCooldownNudgeAndHide() {
        var b = board(.l2)
        var now = 1_000.0
        expectEqual(b.eraserState(now: now), .empty)
        expectEqual(b.erase(now: now), .ignored(.empty))
        // Row 0 right (locks green), rows 1 and 2 swapped (wrong, cleared).
        let r0 = b.question.correctSlot(forRow: 0)!
        let r1 = b.question.correctSlot(forRow: 1)!
        let r2 = b.question.correctSlot(forRow: 2)!
        draw(&b, row: 0, slot: r0)
        draw(&b, row: 1, slot: r2)
        draw(&b, row: 2, slot: r1)
        guard case .judged(let first) = b.submit() else { preconditionFailure("judged") }
        expectEqual(first.wrong.count, 2)
        expectEqual(b.locked, [0: r0])
        for use in 1...6 {
            draw(&b, row: 1, slot: r1)
            expectEqual(b.eraserState(now: now), .ready)
            guard case .cleared(let cleared, let nudge, let hidden) = b.erase(now: now) else {
                preconditionFailure("erase \(use)")
            }
            expectEqual(cleared, 1)
            expectEqual(nudge, use == 4, "nudge only on the 4th use")
            expectEqual(hidden, use >= 6, "hidden from the 6th use")
            expectEqual(b.locked, [0: r0], "eraser never clears locked green lines")
            expectTrue(b.lines.isEmpty)
            if use == 4 { expectTrue(b.submitNudge) }
            if use < 6 {
                // 3 s cooldown: a second press inside it does nothing.
                if case .coolingDown = b.eraserState(now: now + 2.9) {} else { preconditionFailure("cooldown") }
                if case .ignored = b.erase(now: now + 2.9) {} else { preconditionFailure("erased in cooldown") }
                expectEqual(b.eraserState(now: now + 3), .empty)
                now += 3
            }
        }
        expectEqual(b.eraserUses, 6)
        expectEqual(b.eraserState(now: now + 100), .hidden)
        expectTrue(b.eraserEverHidden)
        expectEqual(b.resultFields["eraser_locked"], .bool(true))
        // 完成 brings it back (no penalty, still the same question) …
        draw(&b, row: 1, slot: r2)
        draw(&b, row: 2, slot: r1)
        guard case .judged(let second) = b.submit() else { preconditionFailure("judged") }
        expectFalse(second.solved)
        expectFalse(b.submitNudge)
        expectEqual(b.eraserState(now: now + 100), .empty)
        // … and the next use puts it away again until the next 完成.
        draw(&b, row: 1, slot: r1)
        guard case .cleared(_, _, let hiddenAgain) = b.erase(now: now + 100) else { preconditionFailure("7th") }
        expectTrue(hiddenAgain)
        expectEqual(LineMatchBoard.eraserCooldownSeconds, 3)
        expectEqual(LineMatchBoard.eraserNudgeUse, 4)
        expectEqual(LineMatchBoard.eraserHideUse, 6)
    }

    func testRejectRingsShowThroughThePauseThenFlashBriefly() {
        var b = board(.l1)
        let wrong0 = wrongSlot(b, row: 0)
        draw(&b, row: 0, slot: wrong0)
        draw(&b, row: 1, slot: wrongSlot(b, row: 1))
        guard case .judged(let judgement) = b.submit() else { preconditionFailure("judged") }
        expectEqual(judgement.wrong.count, 2)
        expectTrue(b.showsRejectRings(now: 0, paused: true))
        expectFalse(b.showsRejectRings(now: 0, paused: false))
        b.noteUnlocked(now: 100)
        expectTrue(b.showsRejectRings(now: 101.4, paused: false))
        expectFalse(b.showsRejectRings(now: 101.6, paused: false))
        // The next drag clears them.
        _ = b.beginDrag(at: b.layout.leftDots[0])
        expectTrue(b.rejectedRows.isEmpty)
    }

    // MARK: Stats

    func testDealFactsTagsAndRecords() {
        let settings = LineMatchSettings(tolerance: .wide)
        let numbersOnly = LineMatchSettings(tolerance: .wide, weights: [.numbers: 100, .body: 0, .animals: 0, .zodiac: 0])
        let q = LineMatchGenerator.make(seed: "facts", level: .l3, avoidingItem: nil, settings: numbersOnly)
        let facts = PerfChoiceCatalog.facts(lineMatch: q, settings: settings)
        expectEqual(facts.item, q.itemID)
        expectEqual(facts.gen, QuestionGeneration.variants)
        expectEqual(facts.level, .l3)
        expectEqual(facts.chance, 1.0 / 24.0, accuracy: 0.000001)
        expectEqual(facts.slots, q.rightKeys)
        expectEqual(facts.correctChoice, LineMatchSubmit.choice)
        let fields = facts.dealtFields
        expectEqual(fields["gen"], .string("variants_v1"))
        expectEqual(fields["level"], .int(3))
        expectEqual(fields["category"], .string("numbers"))
        expectEqual(fields["pairs"], .int(4))
        expectEqual(fields["items"], .strings(q.pairs.map(\.key)))
        expectEqual(fields["tolerance"], .string("wide"))
        expectEqual(fields["category_mix"], .string(settings.mixDescription))
        expectEqual(fields["object"], .string(q.countObject?.rawValue ?? "?"))
        // Number tags: distance, 6-9 confusion, object.
        for row in 0..<q.pairCount {
            for slot in 0..<q.pairCount {
                let tags = LineMatchGenerator.tags(question: q, row: row, slot: slot)
                if q.isCorrect(row: row, slot: slot) {
                    expectEqual(tags, [])
                    continue
                }
                expectTrue(tags.contains("wrong_target"))
                expectTrue(tags.contains("category:numbers"))
                expectTrue(tags.contains("object:\(q.countObject!.rawValue)"))
                let off = abs((q.rightPair(atSlot: slot)?.numeral ?? 0) - q.pairs[row].count)
                expectTrue(tags.contains(off == 1 ? "count_off_by_1" : "count_off_by_2plus"))
            }
        }
        // Word tags name the pair (and a shared confusion group if there were one).
        let words = LineMatchGenerator.make(seed: "facts", level: .l2, avoidingItem: nil,
                                            settings: LineMatchSettings(weights: [.numbers: 0, .body: 0, .animals: 10, .zodiac: 0]))
        let wrong = (words.correctSlot(forRow: 0)! + 1) % 3
        let tags = LineMatchGenerator.tags(question: words, row: 0, slot: wrong)
        expectEqual(Array(tags.prefix(3)),
                    ["wrong_target", "category:animals", "pair:\(words.pairs[0].key)>\(words.rightPair(atSlot: wrong)!.key)"])
        // Submit record + round result.
        var b = LineMatchBoard(question: words, tolerance: .wide)
        draw(&b, row: 0, slot: wrong)
        let taken = Set(b.lines.values)
        for row in 1..<3 {
            let slot = (0..<3).first { !taken.contains($0) && !b.lines.values.contains($0) }!
            draw(&b, row: row, slot: slot)
        }
        guard case .judged(let judgement) = b.submit() else { preconditionFailure("judged") }
        let record = b.submitRecord(judgement)
        expectTrue(record.tags.contains("wrong_target"))
        expectEqual(record.fields["submit"], .int(1))
        expectEqual(record.fields["tolerance"], .string("wide"))
        expectEqual(record.fields["wrong_lines"]?.stringArray.count, judgement.wrong.count)
        let result = b.resultFields
        for key in ["eraser_uses", "eraser_locked", "submit_attempts", "pre_submit_changes",
                    "incomplete_strokes", "wrong_direction", "joins", "tolerance"] {
            expectTrue(result[key] != nil, key)
        }
        expectEqual(result["submit_attempts"], .int(1))
        // Old lines (no gen / category) still read as fixed_v0.
        let old = PerfEvent(type: .gameDealt, timestamp: Date(timeIntervalSince1970: 0), tz: "+08:00", mono: 0,
                            launch: "L", seq: 1, app: "0.22.4", actor: .child, mode: "lock", session: "s",
                            fields: ["kind": .string("countVehicles")])
        expectEqual(PerfQuestionGeneration.gen(of: old), QuestionGeneration.fixed)
        let dealt = PerfEvent(type: .gameDealt, timestamp: Date(timeIntervalSince1970: 0), tz: "+08:00", mono: 0,
                              launch: "L", seq: 2, app: "0.23.0", actor: .child, mode: "lock", session: "s",
                              fields: fields)
        expectTrue(PerfQuestionGeneration.isVariant(dealt))
        expectEqual(PerfQuestionGeneration.level(of: dealt), .l3)
    }

    // MARK: Assignment + settings

    func testDefaultOffUntilParentEnablesAndSettingsPersist() {
        let defaults = MissionGameAssignment.defaults
        for star in ChildDifficulty.allCases {
            expectFalse(defaults.isEnabled(.lineMatch, star: star))
            expectFalse(defaults.pool(for: star).contains(.lineMatch))
        }
        // A v0.22 store (no lineMatch key) loads with 連一連 off.
        var old = defaults.enabledStars
        old.removeValue(forKey: .lineMatch)
        let migrated = MissionGameAssignment(enabledStars: old).normalized()
        expectEqual(migrated.enabledStars[.lineMatch] ?? [.easy], Set<ChildDifficulty>())
        expectTrue(migrated.isHiddenFromMissions(.lineMatch))
        // Parent turns ★★ on.
        guard case .updated(let on) = migrated.toggling(.lineMatch, star: .medium) else {
            preconditionFailure("enable")
        }
        expectTrue(on.pool(for: .medium).contains(.lineMatch))
        expectFalse(on.pool(for: .easy).contains(.lineMatch))
        let suite = "VisaGames.lineMatch.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
        MissionGameAssignmentStore(defaults: store).save(on)
        expectTrue(MissionGameAssignmentStore(defaults: store).load().isEnabled(.lineMatch, star: .medium))
        // Rotation without a pool never deals it.
        for i in 0..<500 { expectTrue(ActivityCatalog.kind(forRoundSeed: "r\(i)") != .lineMatch) }
        expectTrue(ActivityCatalog.kind(forRoundSeed: "r", pool: []) != .lineMatch)
        // Settings store.
        let settingsStore = LineMatchSettingsStore(defaults: store)
        expectEqual(settingsStore.load(), LineMatchSettings.defaults)
        let changed = LineMatchSettings.defaults.withTolerance(.narrow).adjusting(.zodiac, steps: -3)!
        settingsStore.save(changed)
        expectEqual(settingsStore.load(), changed)
        expectEqual(settingsStore.load().weight(.zodiac), 0)
        expectEqual(settingsStore.load().tolerance, .narrow)
        store.set(Data("nope".utf8), forKey: LineMatchSettingsStore.key)
        expectEqual(settingsStore.load(), LineMatchSettings.defaults)
        expectFalse(LineMatchSettingsStore.key == MissionGameAssignmentStore.key)
        store.removePersistentDomain(forName: suite)
    }

    // MARK: Source guards (no Swift UI test target)

    func testAppWiringSourceGuards() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        let board = try source("Sources/VisaGames/LineMatchBoardView.swift")
        expectTrue(board.contains("DragGesture(minimumDistance: 0)"))
        expectTrue(board.contains("LineMatchArt.miniTruck"))
        expectTrue(board.contains("ThinkPauseOverlay(remainingSeconds: thinkPauseRemaining)"))
        for banned in ["TextField", "contextMenu", "Link(", "openURL", "NSWorkspace", "WKWebView", "TextEditor"] {
            expectFalse(board.contains(banned), "LineMatchBoardView must not use \(banned)")
        }
        let settingsView = try source("Sources/VisaGames/ParentLineMatchSettingsView.swift")
        expectFalse(settingsView.contains("TextField"))
        let host = try source("Sources/VisaGames/CanvasActivityHost.swift")
        expectTrue(host.contains("LineMatchBoardView("))
        expectTrue(host.contains("board: model.currentLineMatchBoard"))
        let app = try source("Sources/VisaGames/AppDelegate.swift")
        expectTrue(app.contains("avoidingItem: lastDealtItem[.lineMatch], settings: lineMatchSettings"))
        expectTrue(app.contains("lineMatchSettings = LineMatchSettingsStore().load()"))
        expectTrue(app.contains("lineMatchBoard.cancelDrag()"))
        expectTrue(app.contains("playtestLineMatchBoard.cancelDrag()"))
        expectTrue(app.contains("handleEvaluation(evaluation, selectionLabel: LineMatchSubmit.choice)"))
        expectTrue(app.contains("playtestHandle(evaluation, selectionLabel: LineMatchSubmit.choice)"))
        expectTrue(app.contains("PerfChoiceCatalog.facts(lineMatch: lineMatch, settings: lineMatchSettings)"))
        let recorder = try source("Sources/VisaGames/PerformanceRecorder.swift")
        expectTrue(recorder.contains("fields.merge(roundExtra)"))
        expectTrue(recorder.contains("fields.merge(playtestExtra)"))
        expectTrue(recorder.contains("fields.merge(record.fields)"))
        let parent = try source("Sources/VisaGames/ParentSettingsView.swift")
        expectTrue(parent.contains("ParentLineMatchSettingsView("))
        let script = try source("scripts/svg_to_canvasart.py")
        expectTrue(script.contains("icons-sheet.svg"))
        let art = try source("Sources/VisaCore/LineMatchArt.swift")
        expectTrue(art.hasPrefix("// GENERATED by scripts/svg_to_canvasart.py"))
    }
}
