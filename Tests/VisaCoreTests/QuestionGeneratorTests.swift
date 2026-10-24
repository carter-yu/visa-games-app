import Foundation
import VisaCore

/// v0.22.0 S0 (design §1.4, §7, §8.6): seeded question generators for countVehicles and
/// findTheSame, ★ = question tier (D1), and the `gen` / `level` / `stats_marker` split
/// between fixed-question rounds and generated variants.
final class QuestionGeneratorTests {
    private let seeds = (0..<1_000).map { "round-\($0)" }
    private let base = PerfCodec.parseTimestamp("2026-10-14T04:00:00.000Z")!  // 12:00 HKT

    private func event(_ type: PerfEventType, _ fields: [String: PerfValue], at offset: TimeInterval = 0,
                       seq: Int, actor: PerfActor = .child) -> PerfEvent {
        PerfEvent(type: type, timestamp: base.addingTimeInterval(offset), tz: "+08:00", mono: offset,
                  launch: "L1", seq: seq, app: "0.22.0", actor: actor, mode: "lock", session: "s1",
                  fields: fields)
    }

    // MARK: Tier + RNG

    func testStarsAreTheQuestionTier() {
        expectEqual(ActivityLevel(.easy), .l1)
        expectEqual(ActivityLevel(.medium), .l2)
        expectEqual(ActivityLevel(.challenge), .l3)
        expectEqual(ActivityLevel(stars: 0), .l1)
        expectEqual(ActivityLevel(stars: 9), .l3)
        expectEqual(ActivityLevel.l3.code, "L3")
        expectEqual(ActivityLevel.l2.stars, "★★")
        expectEqual([ActivityLevel.l1.cycled, ActivityLevel.l2.cycled, ActivityLevel.l3.cycled], [.l2, .l3, .l1])
        // Visa length per star is unchanged.
        expectEqual(ChildDifficulty.allCases.map(\.minutes), [5, 10, 15])
        expectEqual(QuestionGeneration.generatedKinds,
                    [.countVehicles, .findTheSame, .lineMatchGuidedStraight, .lineMatchGuidedBridge, .lineMatch,
                     .traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree,
                     .tapCountAll, .tapCountTrace, .tapCountPick,
                     .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish, .tapLetterAll])
    }

    func testQuestionRNGIsDeterministicAndUniform() {
        var a = QuestionRNG(seed: "abc", salt: "x")
        var b = QuestionRNG(seed: "abc", salt: "x")
        var c = QuestionRNG(seed: "abc", salt: "y")
        let seqA = (0..<16).map { _ in a.next() }
        expectEqual(seqA, (0..<16).map { _ in b.next() })
        expectFalse(seqA == (0..<16).map { _ in c.next() }, "salt must change the stream")

        var rng = QuestionRNG(seed: "uniform", salt: "test")
        var buckets = [0, 0, 0]
        for _ in 0..<6_000 {
            let value = rng.below(3)
            expectTrue((0..<3).contains(value))
            buckets[value] += 1
        }
        expectTrue(buckets.allSatisfy { abs($0 - 2_000) < 200 }, "below(3) buckets \(buckets)")
        for _ in 0..<500 {
            expectTrue((4...10).contains(rng.int(in: 4...10)))
            let unit = rng.signedUnit()
            expectTrue(unit >= -1 && unit <= 1)
        }
        let deck = Array(0..<20)
        let shuffled = rng.shuffled(deck)
        expectEqual(shuffled.sorted(), deck)
        expectEqual(Set(rng.sample(deck, count: 7)).count, 7)
    }

    // MARK: countVehicles

    func testCountIsAPureFunctionOfSeedAndLevel() {
        for level in ActivityLevel.allCases {
            var distinct: Set<String> = []
            for seed in seeds.prefix(300) {
                let first = CountVehiclesGenerator.make(seed: seed, level: level, avoidingItem: nil)
                // Another deal in between must not disturb this seed (no global RNG).
                _ = CountVehiclesGenerator.make(seed: "other-\(seed)", level: level, avoidingItem: nil)
                expectEqual(first, CountVehiclesGenerator.make(seed: seed, level: level, avoidingItem: nil))
                expectEqual(first, ActivityCatalog.countQuestion(seed: seed, level: level))
                distinct.insert(first.itemID)
            }
            expectTrue(distinct.count > 20, "count \(level.code) only \(distinct.count) items")
        }
        // The level is part of the deal: the same seed differs across tiers.
        let seed = "same-seed"
        let tiers = ActivityLevel.allCases.map { CountVehiclesGenerator.make(seed: seed, level: $0, avoidingItem: nil) }
        expectEqual(Set(tiers.map(\.itemID)).count, 3)
    }

    func testCountTierRangesLayoutsAndChoices() {
        for level in ActivityLevel.allCases {
            let range = CountVehiclesGenerator.countRange(level)
            var counts: Set<Int> = []
            var vehicles: Set<HeroVehicle> = []
            var items: Set<String> = []
            for seed in seeds {
                let q = CountVehiclesGenerator.make(seed: seed, level: level, avoidingItem: nil)
                guard let variant = q.variant else { preconditionFailure("count variant missing") }
                expectTrue(q.isWellFormed, "malformed \(q.itemID)")
                expectTrue(range.contains(q.correctCount), "\(q.itemID) outside \(range)")
                expectEqual(variant.level, level)
                expectEqual(variant.layout, CountVehiclesGenerator.layout(level))
                expectEqual(q.vehicleAssetIDs, Array(repeating: variant.vehicle.assetID, count: q.correctCount))
                // Options: three consecutive numerals with the answer, inside 1...10, distinct.
                expectEqual(q.choiceCounts.count, 3)
                expectEqual(Set(q.choiceCounts).count, 3)
                expectTrue(q.choiceCounts.contains(q.correctCount))
                expectEqual(q.choiceCounts, Array(q.choiceCounts[0]...(q.choiceCounts[0] + 2)))
                expectTrue(q.choiceCounts.allSatisfy { (1...10).contains($0) })
                expectFalse(q.choiceCounts.contains(6) && q.choiceCounts.contains(9), "6 and 9 together")
                if q.correctCount > 1 && q.correctCount < 10 {
                    expectEqual(q.choiceCounts, [q.correctCount - 1, q.correctCount, q.correctCount + 1])
                }
                // Vehicles never overlap and stay inside the stimulus.
                expectTrue(q.placementsAreClear, "overlap in \(q.itemID)")
                expectEqual(variant.placements.count, q.correctCount)
                // Prompt / hint name the vehicle being counted.
                expectTrue(q.promptTraditionalChinese.contains(variant.vehicle.nameTraditionalChinese))
                expectTrue(q.promptEnglish.contains(variant.vehicle.pluralEnglish))
                expectTrue(q.hintTraditionalChinese.contains(variant.vehicle.nameTraditionalChinese))
                expectTrue(q.itemID.hasPrefix("countVehicles.\(level.code).n\(q.correctCount).\(variant.vehicle.rawValue)."))
                expectEqual(q.completionID, q.itemID)
                counts.insert(q.correctCount)
                vehicles.insert(variant.vehicle)
                items.insert(q.itemID)
            }
            expectEqual(counts, Set(range))
            expectEqual(vehicles, Set(HeroVehicle.allCases))
            // Every (n, vehicle) pair of the tier is reachable: L1 30, L2 50, L3 70.
            expectEqual(items.count, range.count * HeroVehicle.allCases.count)
        }
        expectEqual(CountVehiclesGenerator.countRange(.l1), 1...3)
        expectEqual(CountVehiclesGenerator.countRange(.l2), 2...6)
        expectEqual(CountVehiclesGenerator.countRange(.l3), 4...10)
        expectEqual(CountVehiclesGenerator.choiceCounts(for: 1), [1, 2, 3])
        expectEqual(CountVehiclesGenerator.choiceCounts(for: 10), [8, 9, 10])
        expectEqual(CountVehiclesGenerator.choiceCounts(for: 6), [5, 6, 7])
    }

    func testCountPlacementsAreRowsThenScatter() {
        for seed in seeds.prefix(200) {
            let l1 = CountVehiclesGenerator.make(seed: seed, level: .l1, avoidingItem: nil).variant!
            expectEqual(Set(l1.placements.map(\.y)).count, 1)  // one row
            let l2 = CountVehiclesGenerator.make(seed: seed, level: .l2, avoidingItem: nil).variant!
            expectEqual(Set(l2.placements.map(\.y)).count, 2)  // two rows (n ≥ 2)
            let top = l2.placements.filter { $0.y < CountCanvas.height / 2 }.count
            expectEqual(top, (l2.placements.count + 1) / 2)
            let l3 = CountVehiclesGenerator.make(seed: seed, level: .l3, avoidingItem: nil).variant!
            expectTrue(Set(l3.placements.map(\.y)).count >= 2, "scatter should not be one row")
        }
        // Hand-made overlap is rejected by isWellFormed.
        var q = CountVehiclesGenerator.make(seed: "overlap", level: .l3, avoidingItem: nil)
        q.variant!.placements[1] = q.variant!.placements[0]
        expectFalse(q.isWellFormed)
        var outside = CountVehiclesGenerator.make(seed: "outside", level: .l2, avoidingItem: nil)
        outside.variant!.placements[0].x = CountCanvas.width
        expectFalse(outside.isWellFormed)
    }

    func testCountTagsDistanceAndNumeralConfusion() {
        expectEqual(CountVehiclesGenerator.tags(chosen: 3, correct: 3), [])
        expectEqual(CountVehiclesGenerator.tags(chosen: 2, correct: 3), ["under_by_1"])
        expectEqual(CountVehiclesGenerator.tags(chosen: 4, correct: 3), ["over_by_1"])
        expectEqual(CountVehiclesGenerator.tags(chosen: 3, correct: 1), ["off_by_2plus"])
        expectEqual(CountVehiclesGenerator.tags(chosen: 9, correct: 6), ["off_by_2plus", "numeral_confusion:6-9"])
        expectEqual(CountVehiclesGenerator.tags(chosen: 1, correct: 7), ["off_by_2plus", "numeral_confusion:1-7"])
        // The fixed v0 item keeps its v0.20 tags.
        expectEqual(PerfChoiceCatalog.tags(kind: .countVehicles, choice: "count-2"), ["under_by_1"])
    }

    // MARK: findTheSame

    func testFindSameIsAPureFunctionOfSeedAndLevel() {
        for level in ActivityLevel.allCases {
            var distinct: Set<String> = []
            for seed in seeds.prefix(300) {
                let first = FindTheSameGenerator.make(seed: seed, level: level, avoidingItem: nil)
                _ = FindTheSameGenerator.make(seed: "other-\(seed)", level: level, avoidingItem: nil)
                expectEqual(first, FindTheSameGenerator.make(seed: seed, level: level, avoidingItem: nil))
                expectEqual(first, ActivityCatalog.findSameQuestion(seed: seed, level: level))
                distinct.insert(first.itemID)
            }
            expectTrue(distinct.count > 20, "findSame \(level.code) only \(distinct.count) items")
        }
    }

    func testFindSameExactlyOneMatchAndWellFormed() {
        let evaluator = ActivityEvaluator()
        for level in ActivityLevel.allCases {
            for seed in seeds {
                let q = FindTheSameGenerator.make(seed: seed, level: level, avoidingItem: nil)
                guard let variant = q.variant else { preconditionFailure("findSame variant missing") }
                expectTrue(q.isWellFormed, "malformed \(q.itemID)")
                expectEqual(q.options.count, FindTheSameGenerator.optionCount)
                expectTrue(q.hasExactlyOneMatch)
                expectEqual(Set(q.options.map(\.id)).count, 3)
                expectEqual(Set(q.options.map(\.assetID)).count, 3)
                expectEqual(q.targetAssetID, variant.target.assetID)
                expectEqual(variant.level, level)
                let correct = q.options.filter { $0.assetID == q.targetAssetID }
                expectEqual(correct.map(\.id), [q.correctOptionID])
                expectEqual(evaluator.evaluate(question: q, selectedOptionID: q.correctOptionID, hintUsed: false),
                            .correct(assisted: false))
                for wrong in q.options where wrong.id != q.correctOptionID {
                    expectEqual(evaluator.evaluate(question: q, selectedOptionID: wrong.id, hintUsed: true), .incorrect)
                }
                // Every option asset resolves to a drawable look.
                expectTrue(q.options.allSatisfy { VehicleLook(assetID: $0.assetID) != nil })
            }
        }
    }

    func testFindSameDistractorSimilarityRisesWithTier() {
        for item in FindTheSameGenerator.items(.l1) {
            for other in item.distractors {
                expectEqual(other.vehicle.sharedSalientFeatures(with: item.target.vehicle), 0, item.itemID)
                expectFalse(other.mirrored || other.decor != nil, "L1 uses plain heroes")
            }
        }
        for item in FindTheSameGenerator.items(.l2) {
            for other in item.distractors {
                // 同色唔同款 or 同款唔同色: exactly one salient feature shared.
                expectEqual(other.vehicle.sharedSalientFeatures(with: item.target.vehicle), 1, item.itemID)
                expectFalse(other.mirrored || other.decor != nil, "L2 uses plain heroes")
            }
        }
        for item in FindTheSameGenerator.items(.l3) {
            for other in item.distractors {
                // Same vehicle; exactly one detail differs.
                expectEqual(other.vehicle, item.target.vehicle)
                let diffs = other.differences(from: item.target)
                expectEqual(diffs.count, 1, item.itemID)
                expectTrue(diffs[0] == .facing || diffs[0] == .decor)
            }
        }
        // L2 really mixes the two contrasts the v0 item had (same colour vs same shape).
        let l2 = FindTheSameGenerator.items(.l2)
        expectTrue(l2.contains { item in item.distractors.contains { $0.vehicle.paint == item.target.vehicle.paint } })
        expectTrue(l2.contains { item in item.distractors.contains { $0.vehicle.body == item.target.vehicle.body } })
        expectTrue(l2.contains { $0.target.vehicle == .hkTaxi && $0.distractors.map(\.vehicle).contains(.nyTaxi) })
    }

    func testFindSameIsConfusionSafeAndHasEnoughItems() {
        for level in ActivityLevel.allCases {
            let items = FindTheSameGenerator.items(level)
            expectEqual(Set(items.map(\.itemID)).count, items.count)
            for item in items {
                let looks = [item.target] + item.distractors
                expectEqual(Set(looks).count, 3, item.itemID)
                expectEqual(looks.filter { $0 == item.target }.count, 1)
                // The yellow taxi / yellow toy car lookalikes never share a question.
                let vehicles = Set(looks.map(\.vehicle))
                expectFalse(vehicles.contains(.nyTaxi) && vehicles.contains(.toyCar), item.itemID)
                expectTrue(FindTheSameGenerator.question(for: item).isWellFormed, item.itemID)
            }
        }
        // Design §7 asset-limited counts: L1 ≥ 50, L2 ≈ 50, L3 1,000+ is the twinCars space; here 180.
        expectEqual(FindTheSameGenerator.items(.l1).count, 131)
        expectEqual(FindTheSameGenerator.items(.l2).count, 47)
        expectEqual(FindTheSameGenerator.items(.l3).count, 180)
        expectTrue(HeroVehicle.nyTaxi.isLookalike(of: .toyCar))
        expectFalse(HeroVehicle.hkTaxi.isLookalike(of: .nyTaxi))
    }

    func testFindSameTagsComeFromTheDifference() {
        let taxi = VehicleLook(vehicle: .hkTaxi)
        expectEqual(FindTheSameGenerator.tags(option: taxi, target: taxi), [])
        expectEqual(FindTheSameGenerator.tags(option: VehicleLook(vehicle: .nyTaxi), target: taxi),
                    ["diff:color", "diff:type", "same_shape"])
        expectEqual(FindTheSameGenerator.tags(option: VehicleLook(vehicle: .fireEngine), target: taxi),
                    ["diff:type", "same_color"])
        expectEqual(FindTheSameGenerator.tags(option: VehicleLook(vehicle: .tanker), target: taxi),
                    ["diff:color", "diff:type"])
        let starred = VehicleLook(vehicle: .hkTaxi, decor: .star)
        expectEqual(FindTheSameGenerator.tags(option: VehicleLook(vehicle: .hkTaxi, mirrored: true, decor: .star),
                                              target: starred), ["diff:facing", "same_type"])
        expectEqual(FindTheSameGenerator.tags(option: taxi, target: starred), ["diff:decor:star", "same_type"])
        expectEqual(FindTheSameGenerator.tags(option: VehicleLook(vehicle: .hkTaxi, decor: .flag), target: starred),
                    ["diff:decor:flag", "same_type"])
    }

    func testVehicleLookAssetIDsRoundTripAndFailClosed() {
        for vehicle in HeroVehicle.allCases {
            expectEqual(HeroVehicle(assetID: vehicle.assetID), vehicle)
            for mirrored in [false, true] {
                for decor in [nil] + VehicleDecor.allCases.map({ Optional($0) }) {
                    let look = VehicleLook(vehicle: vehicle, mirrored: mirrored, decor: decor)
                    expectEqual(VehicleLook(assetID: look.assetID), look)
                }
            }
        }
        // The default look is the plain v0 asset id the views already draw.
        expectEqual(VehicleLook(vehicle: .fireEngine).assetID, "silhouette.fireEngine")
        expectEqual(VehicleLook(vehicle: .crane, mirrored: true, decor: .flag).assetID, "silhouette.crane+mirror+flag")
        for bad in ["silhouette.bogus", "prop.sun", "silhouette.hkTaxi+", "silhouette.hkTaxi+mirror+mirror",
                    "silhouette.hkTaxi+star+flag", "silhouette.hkTaxi+wings", ""] {
            expectTrue(VehicleLook(assetID: bad) == nil, "accepted \(bad)")
        }
    }

    // MARK: Rules kept

    func testNoBackToBackRepeatOfAnItem() {
        for level in ActivityLevel.allCases {
            var lastCount: String?
            var lastFind: String?
            for seed in seeds.prefix(400) {
                let count = CountVehiclesGenerator.make(seed: seed, level: level, avoidingItem: lastCount)
                expectFalse(count.itemID == lastCount, "count repeated \(count.itemID)")
                lastCount = count.itemID
                let find = FindTheSameGenerator.make(seed: seed, level: level, avoidingItem: lastFind)
                expectFalse(find.itemID == lastFind, "findSame repeated \(find.itemID)")
                lastFind = find.itemID
            }
            // Avoiding an unrelated item leaves the deal unchanged (still a pure function).
            let plain = CountVehiclesGenerator.make(seed: "pure", level: level, avoidingItem: nil)
            expectEqual(CountVehiclesGenerator.make(seed: "pure", level: level, avoidingItem: "nope"), plain)
            expectFalse(CountVehiclesGenerator.make(seed: "pure", level: level, avoidingItem: plain.itemID).itemID
                        == plain.itemID)
        }
    }

    func testOptionShuffleStillAppliesToGeneratedQuestions() {
        var findSlots: Set<Int> = []
        var countSlots: Set<Int> = []
        for seed in seeds.prefix(120) {
            let find = FindTheSameGenerator.make(seed: seed, level: .l2, avoidingItem: nil)
            let presented = find.presentedOptions(seed: seed)
            expectEqual(presented.map(\.id), find.presentedOptions(seed: seed).map(\.id))
            expectEqual(Set(presented.map(\.id)), Set(find.options.map(\.id)))
            findSlots.insert(presented.firstIndex { $0.id == find.correctOptionID }!)
            let count = CountVehiclesGenerator.make(seed: seed, level: .l3, avoidingItem: nil)
            let numerals = count.presentedChoiceCounts(seed: seed)
            expectEqual(numerals.sorted(), count.choiceCounts)
            countSlots.insert(numerals.firstIndex(of: count.correctCount)!)
        }
        // The answer is not parked on one slot.
        expectEqual(findSlots, [0, 1, 2])
        expectEqual(countSlots, [0, 1, 2])
        // Wrong answers still halve pending fuel and the hint still comes after 2 misses.
        expectEqual(WrongAnswerPolicy.halvedPendingMinutes(10), 5)
        expectFalse(ActivityHintPolicy.shouldAutoHint(afterMissCount: 1))
        expectTrue(ActivityHintPolicy.shouldAutoHint(afterMissCount: 2))
        expectEqual(WrongAnswerPolicy.thinkPauseSeconds, 10)
    }

    // MARK: Language

    func testGeneratedCopyIsHongKongTraditionalAndASCIIEnglish() {
        // Design §8.6 blacklist of common Simplified-only characters.
        let simplified: Set<Character> = [
            "车", "个", "们", "数", "线", "书", "画", "门", "马", "见", "说", "话", "这", "发", "头", "脚", "图",
            "连", "认", "读", "写", "听", "点", "绿", "红", "后", "里", "扰", "辆", "几", "货", "铁", "龙"
        ]
        func checkChinese(_ text: String) {
            expectFalse(text.contains(where: { simplified.contains($0) }), "Simplified character in \(text)")
            expectTrue(isTraditionalChineseOnly(text) && perfTraditionalOnly(text), text)
        }
        func checkEnglish(_ text: String) {
            expectTrue(text.unicodeScalars.allSatisfy { $0.isASCII }, "non-ASCII English: \(text)")
            expectFalse(text.isEmpty)
        }
        func checkHint(_ hint: String) {
            let parts = hint.components(separatedBy: " / ")
            expectEqual(parts.count, 2, hint)
            checkChinese(parts[0])
            checkEnglish(parts[1])
            expectTrue(parts[0].hasPrefix("提示："))
            expectTrue(parts[1].hasPrefix("Hint: "))
        }
        var questions: [FindSameQuestion] = []
        for level in ActivityLevel.allCases {
            questions += FindTheSameGenerator.items(level).map(FindTheSameGenerator.question(for:))
        }
        for q in questions {
            checkChinese(q.promptTraditionalChinese)
            checkEnglish(q.promptEnglish)
            checkHint(q.hintTraditionalChinese)
            for option in q.options {
                checkChinese(option.labelTraditionalChinese)
                checkEnglish(option.labelEnglish)
            }
        }
        for level in ActivityLevel.allCases {
            for seed in seeds.prefix(300) {
                let q = CountVehiclesGenerator.make(seed: seed, level: level, avoidingItem: nil)
                checkChinese(q.promptTraditionalChinese)
                checkEnglish(q.promptEnglish)
                checkHint(q.hintTraditionalChinese)
            }
        }
        for vehicle in HeroVehicle.allCases {
            checkChinese(vehicle.nameTraditionalChinese)
            checkEnglish(vehicle.nameEnglish + vehicle.pluralEnglish)
        }
        checkChinese(ActivityKind.countVehicles.parentCardTitle + ActivityKind.countVehicles.parentHelpTraditionalChinese)
    }

    // MARK: Stats — facts, gen / level, marker, rollup

    func testDealFactsMatchWhatTheChildSaw() {
        for level in ActivityLevel.allCases {
            for seed in seeds.prefix(100) {
                let find = FindTheSameGenerator.make(seed: seed, level: level, avoidingItem: nil)
                let facts = PerfChoiceCatalog.facts(findSame: find, seed: seed)
                expectEqual(facts.slots, find.presentedOptions(seed: seed).map(\.id))
                expectEqual(facts.item, find.itemID)
                expectEqual(facts.gen, QuestionGeneration.variants)
                expectEqual(facts.level, level)
                expectEqual(facts.correctChoice, find.correctOptionID)
                expectEqual(facts.chance, 1.0 / 3.0, accuracy: 1e-12)
                expectEqual(facts.tags(for: find.correctOptionID), [])
                for option in find.options {
                    expectEqual(facts.asset(for: option.id), option.assetID)
                    if option.id != find.correctOptionID {
                        let tags = facts.tags(for: option.id)
                        expectFalse(tags.isEmpty, "no tags for \(option.id)")
                        expectTrue(tags.allSatisfy { !$0.contains(" ") && $0 == $0.lowercased() })
                    }
                }
                expectEqual(facts.dealtFields["gen"], .string("variants_v1"))
                expectEqual(facts.dealtFields["level"], .int(level.rawValue))

                let count = CountVehiclesGenerator.make(seed: seed, level: level, avoidingItem: nil)
                let countFacts = PerfChoiceCatalog.facts(count: count, seed: seed)
                expectEqual(countFacts.slots, count.presentedChoiceCounts(seed: seed).map { "count-\($0)" })
                expectEqual(countFacts.correctChoice, "count-\(count.correctCount)")
                expectEqual(countFacts.item, count.itemID)
                expectEqual(countFacts.level, level)
                for value in count.choiceCounts {
                    let tags = countFacts.tags(for: "count-\(value)")
                    expectEqual(tags.isEmpty, value == count.correctCount)
                }
                expectEqual(countFacts.asset(for: "count-\(count.correctCount)"), nil)
            }
        }
        // Fixed kinds keep the v0.20 catalog facts and say so.
        for kind in ActivityKind.allCases {
            let facts = PerfChoiceCatalog.facts(kind: kind, seed: "s")
            expectEqual(facts.gen, QuestionGeneration.fixed)
            expectEqual(facts.level, nil)
            expectEqual(facts.item, PerfChoiceCatalog.item(for: kind))
            expectEqual(facts.slots, PerfChoiceCatalog.slots(kind: kind, seed: "s"))
            expectEqual(facts.dealtFields, ["gen": .string("fixed_v0")])
        }
        let legacy = PerfChoiceCatalog.facts(findSame: ActivityCatalog.findSameQuestion(), seed: "abc")
        expectEqual(legacy.tags(for: "find-nytaxi"), ["same_shape", "diff_color"])
        expectEqual(legacy.slots, PerfChoiceCatalog.slots(kind: .findTheSame, seed: "abc"))
        let legacyCount = PerfChoiceCatalog.facts(count: ActivityCatalog.countQuestion(), seed: "abc")
        expectEqual(legacyCount.gen, QuestionGeneration.fixed)
        expectEqual(legacyCount.item, "entry-count-fire-3-v1")
        expectEqual(legacyCount.tags(for: "count-4"), ["over_by_1"])
    }

    func testGenAndLevelDecodeAndOldLinesStayFixed() throws {
        // A v0.21 line (no gen / level) still decodes, as the fixed generation.
        let oldLine = """
        {"actor":"child","app":"0.21.4","item":"entry-count-fire-3-v1","kind":"countVehicles","launch":"L0",\
        "mode":"lock","mono":1.5,"round":"r-old","seq":3,"session":"s0","slots":["count-2","count-3","count-4"],\
        "stars":2,"t":"game_dealt","ts":"2026-10-01T04:00:00.000Z","tz":"+08:00","v":1}
        """
        guard case .event(let old) = PerfCodec.decodeLine(Substring(oldLine)) else {
            preconditionFailure("old game_dealt line did not decode")
        }
        expectEqual(PerfQuestionGeneration.gen(of: old), "fixed_v0")
        expectEqual(PerfQuestionGeneration.level(of: old), nil)
        expectFalse(PerfQuestionGeneration.isVariant(old))

        let q = CountVehiclesGenerator.make(seed: "r-new", level: .l2, avoidingItem: nil)
        let facts = PerfChoiceCatalog.facts(count: q, seed: "r-new")
        var fields: [String: PerfValue] = ["round": .string("r-new"), "kind": .string("countVehicles"),
                                           "item": .string(facts.item), "stars": .int(2),
                                           "slots": .strings(facts.slots)]
        fields.merge(facts.dealtFields) { current, _ in current }
        let dealt = event(.gameDealt, fields, seq: 4)
        let line = try PerfCodec.encodeLine(dealt)
        expectTrue(line.contains("\"gen\":\"variants_v1\""))
        expectTrue(line.contains("\"level\":2"))
        guard case .event(let back) = PerfCodec.decodeLine(Substring(line)) else {
            preconditionFailure("new game_dealt line did not decode")
        }
        expectEqual(back, dealt)
        expectEqual(PerfQuestionGeneration.gen(of: back), "variants_v1")
        expectEqual(PerfQuestionGeneration.level(of: back), .l2)
        expectTrue(PerfQuestionGeneration.isVariant(back))
    }

    func testVariantsMarkerIsFoundAndOtherMarkersAreNot() throws {
        let cleared = event(.statsMarker, ["what": .string("cleared")], seq: 1, actor: .parent)
        expectEqual(PerfQuestionGeneration.variantsMarker(in: [cleared]), nil)
        let marker = event(.statsMarker, ["what": .string(PerfQuestionGeneration.markerWhat), "auto": .bool(true),
                                          "kinds": .strings(["countVehicles", "findTheSame"])],
                           at: 5, seq: 2, actor: .system)
        let later = event(.statsMarker, ["what": .string("variants_v1")], at: 50, seq: 9, actor: .system)
        let line = try PerfCodec.encodeLine(marker)
        guard case .event(let back) = PerfCodec.decodeLine(Substring(line)) else {
            preconditionFailure("marker line did not decode")
        }
        expectEqual(back.type, .statsMarker)
        expectEqual(PerfQuestionGeneration.variantsMarker(in: [later, cleared, back]), back)
        expectEqual(PerfQuestionGeneration.markerWhat, "variants_v1")
    }

    func testRollupKeepsFixedAndVariantRoundsApart() {
        expectEqual(PerfQuestionGeneration.rollupKey(kind: "findTheSame", stars: 2, gen: "fixed_v0"), "findTheSame|2")
        expectEqual(PerfQuestionGeneration.rollupKey(kind: "findTheSame", stars: 2, gen: "variants_v1"),
                    "findTheSame|2|variants_v1")
        let oldKey = PerfQuestionGeneration.parseRollupKey("findTheSame|2")
        expectEqual(oldKey.kind, "findTheSame")
        expectEqual(oldKey.stars, 2)
        expectEqual(oldKey.gen, "fixed_v0")
        expectEqual(PerfQuestionGeneration.parseRollupKey("countVehicles|3|variants_v1").gen, "variants_v1")

        // Same kind and stars on one day: an old fixed round and a generated one fold apart.
        let events = [
            event(.gameDealt, ["round": .string("a"), "kind": .string("findTheSame"), "stars": .int(2)], seq: 1),
            event(.roundResult, ["round": .string("a"), "outcome": .string("solved"), "first_try": .bool(false),
                                 "answers": .int(2), "active_ms": .int(3000)], at: 10, seq: 2),
            event(.gameDealt, ["round": .string("b"), "kind": .string("findTheSame"), "stars": .int(2),
                               "gen": .string("variants_v1"), "level": .int(2)], at: 20, seq: 3),
            event(.roundResult, ["round": .string("b"), "outcome": .string("solved"), "first_try": .bool(true),
                                 "answers": .int(1), "active_ms": .int(2000)], at: 30, seq: 4)
        ]
        let stamp = PerfClock.dayStamp(base, timeZone: PerfClock.hongKong)
        let summary = PerfSummaries.daySummaries(events: events, days: [stamp], excluded: [],
                                                 timeZone: PerfClock.hongKong)[stamp]!
        expectEqual(summary.games["findTheSame|2"]?.deals, 1)
        expectEqual(summary.games["findTheSame|2"]?.firstTry, 0)
        expectEqual(summary.games["findTheSame|2|variants_v1"]?.deals, 1)
        expectEqual(summary.games["findTheSame|2|variants_v1"]?.firstTry, 1)

        // Review still reads both keys (kind + stars) after the raw day is pruned.
        let rollup = PerfRollup(foldedDays: ["2026-06-01"], days: ["2026-06-01": summary])
        let report = PerfReportBuilder.build(events: [], rollup: rollup, videos: [], now: base, window: .all)
        let row = report.games.first { $0.kind == .findTheSame }!
        expectEqual(row.deals, 2)
        expectEqual(row.stars[1].rounds, 2)
        expectEqual(row.firstTry, 1)

        // CSV: rounds and daily rows carry the generation.
        let files = PerfCSVExport.files(events: events, rollup: rollup, titles: [:], now: base)
        let rounds = files["rounds.csv"] ?? ""
        expectTrue(PerfCSVExport.roundsHeader.contains("question_gen") && PerfCSVExport.roundsHeader.contains("level"))
        expectTrue(rounds.contains(",fixed_v0,,"))
        expectTrue(rounds.contains(",variants_v1,2,"))
        let daily = files["daily_games.csv"] ?? ""
        expectTrue(daily.contains("2026-06-01,findTheSame,搵同一個,2,1,"))
        expectTrue(daily.contains(",variants_v1\r\n"))
        expectTrue(daily.contains(",fixed_v0\r\n"))
        let roundRows = PerfCSVExport.roundRows(PerfCodec.ordered(events), excluded: [], timeZone: PerfClock.hongKong)
        expectTrue(roundRows.allSatisfy { $0.count == PerfCSVExport.roundsHeader.count })
    }

    // MARK: App wiring (source guards; the app target has no unit tests)

    func testAppDealsByStarLevelAndDrawsVariantsSourceGuard() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        let app = try source("Sources/VisaGames/AppDelegate.swift")
        expectTrue(app.contains("let level = ActivityLevel(difficulty)"))
        expectTrue(app.contains("avoidingItem: lastDealtItem[.findTheSame]"))
        expectTrue(app.contains("avoidingItem: lastDealtItem[.countVehicles]"))
        expectTrue(app.contains("facts: facts)"))
        expectTrue(app.contains("hintText(for: kind, findSame: findSameQuestion, count: countQuestion)"))
        let host = try source("Sources/VisaGames/CanvasActivityHost.swift")
        expectTrue(host.contains("CountStimulusView(question: q)"))
        expectTrue(host.contains("model.currentPlaytestFindSameQuestion"))
        expectFalse(host.contains("TextField"))
        let assets = try source("Sources/VisaGames/ActivityAssetViews.swift")
        expectTrue(assets.contains("VehicleLook(assetID: assetID)"))
        expectTrue(assets.contains(".scaleEffect(x: mirrored ? -1 : 1, y: 1)"))
        let recorder = try source("Sources/VisaGames/PerformanceRecorder.swift")
        expectTrue(recorder.contains("markVariantsGoLiveOnce()"))
        expectTrue(recorder.contains("fields.merge(facts.dealtFields)"))
    }

    /// Generators must always finish: every tier × many seeds, including avoid-rerolls.
    /// `QuestionRNG.below` uses bounded rejection; pools are precomputed and non-empty.
    func testGeneratorsTerminateForEveryTierAndSeed() {
        expectTrue(QuestionGeneration.maxRerolls >= 1)
        for level in ActivityLevel.allCases {
            let findPool = FindTheSameGenerator.items(level)
            expectTrue(findPool.count >= 3, "findTheSame \(level.code) pool empty/tiny: \(findPool.count)")
            for seed in seeds {
                let countQ = CountVehiclesGenerator.make(seed: seed, level: level, avoidingItem: nil)
                expectTrue((CountVehiclesGenerator.countRange(level)).contains(countQ.correctCount))
                expectEqual(countQ.vehicleAssetIDs.count, countQ.correctCount)
                let findQ = FindTheSameGenerator.make(seed: seed, level: level, avoidingItem: nil)
                expectTrue(findQ.hasExactlyOneMatch)
                // Avoid path: re-roll stays bounded even when forced to skip the first item.
                let avoidedCount = CountVehiclesGenerator.make(
                    seed: seed, level: level, avoidingItem: countQ.itemID)
                expectTrue(!avoidedCount.itemID.isEmpty)
                let avoidedFind = FindTheSameGenerator.make(
                    seed: seed, level: level, avoidingItem: findQ.itemID)
                expectTrue(!avoidedFind.itemID.isEmpty)
            }
        }
        // Unbiased below() never hangs for common bounds used by the generators.
        var rng = QuestionRNG(seed: "term", salt: "below")
        for bound in [1, 2, 3, 10, HeroVehicle.allCases.count, 100, 2_001] {
            for _ in 0..<200 {
                let value = rng.below(bound)
                expectTrue((0..<bound).contains(value))
            }
        }
    }
}
