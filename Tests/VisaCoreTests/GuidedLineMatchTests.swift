import Foundation
import VisaCore

/// v0.24.0 / v0.24.1 guided 連一連 (ADR 0013): straight (沿路送) and bridge (沿路過橋) kinds,
/// forwards-only truck, off-road never a miss, tolerance widens the road corridor, practice
/// only in stats. Free match is its own card (自己配). All offline.
final class GuidedLineMatchTests {
    private let seeds = (0..<1_000).map { "guided-\($0)" }
    private let guidedOn = LineMatchSettings.defaults

    private func guided(_ level: ActivityLevel, seed: String = "g", settings: LineMatchSettings? = nil) -> LineMatchQuestion {
        LineMatchGenerator.make(seed: seed, level: level, avoidingItem: nil, settings: settings ?? guidedOn,
                                mode: .guided)
    }

    private func board(_ level: ActivityLevel, seed: String = "g",
                       tolerance: LineMatchTolerance = .standard) -> LineMatchGuidedBoard {
        LineMatchGuidedBoard(question: guided(level, seed: seed), tolerance: tolerance)
    }

    /// Drives the current road with small steps along its centre line. Returns events used.
    @discardableResult
    private func drive(_ b: inout LineMatchGuidedBoard, now: Double = 0, step: Double = 20) -> Int {
        guard let row = b.currentRow, let truck = b.truckPoint else { return 0 }
        expectEqual(b.penDown(at: truck, now: now), .grabbed(row: row))
        let road = b.roads[row]
        var s = b.progress[row]
        var events = 0
        while b.currentRow == row, events < 500 {
            s = min(s + step, road.endDistance)
            _ = b.penMove(to: road.point(at: s), now: now)
            events += 1
        }
        b.penUp()
        return events
    }

    // MARK: Generator

    func testGuidedGeneratorIsDeterministicAndLabelled() {
        for level in [ActivityLevel.l1, .l2] {
            let a = guided(level, seed: "same")
            expectEqual(a, guided(level, seed: "same"))
            expectTrue(a.isGuided)
            expectEqual(a.mode, .guided)
            expectTrue(a.itemID.hasPrefix("lineMatch.G\(level.rawValue).\(a.category.rawValue)"), a.itemID)
            var items = Set<String>()
            for seed in seeds.prefix(300) { items.insert(guided(level, seed: seed).itemID) }
            expectTrue(items.count >= 20, "\(level.code) only \(items.count) guided items")
            // Same kind never repeats an item back to back.
            for seed in seeds.prefix(200) {
                let first = guided(level, seed: seed)
                let next = LineMatchGenerator.make(seed: seed, level: level, avoidingItem: first.itemID,
                                                   settings: guidedOn, mode: .guided)
                expectTrue(next.itemID != first.itemID, "repeat \(first.itemID)")
            }
        }
        // ★★ ids carry the right-column permutation; ★ ones do not (identity).
        expectTrue(guided(.l2).itemID.contains(".p"))
        expectFalse(guided(.l1).itemID.contains(".p"))
        // ★★★ is always free match, even with guided on.
        let three = LineMatchGenerator.make(seed: "same", level: .l3, avoidingItem: nil, settings: guidedOn, mode: .guided)
        expectFalse(three.isGuided)
        expectEqual(three, LineMatchGenerator.make(seed: "same", level: .l3, avoidingItem: nil, settings: guidedOn))
        expectTrue(three.itemID.hasPrefix("lineMatch.L3."))
        // v0.24.1: ActivityKind decides guided vs free (not a settings toggle).
        expectEqual(ActivityKind.lineMatchGuidedStraight.lineMatchDeal(missionLevel: .l3)?.mode, .guided)
        expectEqual(ActivityKind.lineMatchGuidedStraight.lineMatchDeal(missionLevel: .l3)?.level, .l1)
        expectEqual(ActivityKind.lineMatchGuidedBridge.lineMatchDeal(missionLevel: .l1)?.level, .l2)
        expectEqual(ActivityKind.lineMatch.lineMatchDeal(missionLevel: .l3)?.mode, .free)
        expectEqual(ActivityKind.lineMatch.lineMatchDeal(missionLevel: .l2)?.level, .l2)
        // Free questions are unchanged by guided kinds (same draw order).
        expectEqual(ActivityCatalog.lineMatchQuestion(seed: "x", level: .l1),
                    LineMatchGenerator.make(seed: "x", level: .l1, avoidingItem: nil))
        expectEqual(ActivityCatalog.lineMatchQuestion(seed: "x", level: .l2, settings: guidedOn, mode: .guided),
                    guided(.l2, seed: "x"))
    }

    func testGuidedTiersAreWellFormedForThousandsOfSeeds() {
        var categories: [LineMatchCategory: Int] = [:]
        var orders = Set<[Int]>()
        var bridges = Set<Int>()
        for level in [ActivityLevel.l1, .l2] {
            for seed in seeds {
                let q = guided(level, seed: seed)
                expectTrue(q.isWellFormed, "\(seed) \(q.itemID)")
                expectEqual(q.pairCount, LineMatchGenerator.pairCount(level))
                expectTrue(q.category.isDealt(at: level))
                if q.category != .numbers {
                    expectTrue(LineMatchCatalog.isConfusionSafe(q.pairs.map(\.key), in: q.category))
                } else {
                    expectTrue(LineMatchGenerator.isValidNumberSet(q.pairs.compactMap(\.numeral), level: level))
                }
                guard let plan = q.guided else { preconditionFailure("guided plan") }
                expectEqual(Set(plan.colorIndices).count, q.pairCount)
                if level == .l1 {
                    expectEqual(q.rightOrder, [0, 1])
                    expectTrue(plan.bridgeOverRow == nil)
                    expectTrue(q.category != .zodiac)
                } else {
                    expectEqual(LineMatchGuidedGeometry.invertedRows(rightOrder: q.rightOrder).count, 1)
                    orders.insert(q.rightOrder)
                    bridges.insert(plan.bridgeOverRow ?? -1)
                    categories[q.category, default: 0] += 1
                }
                let avoided = LineMatchGenerator.make(seed: seed, level: level, avoidingItem: q.itemID,
                                                      settings: guidedOn, mode: .guided)
                expectTrue(avoided.isWellFormed)
            }
        }
        expectEqual(orders, Set([[1, 0, 2], [0, 2, 1]]))
        expectEqual(bridges, Set([0, 1, 2]))
        // Zodiac is dealt at ★★ (same weights as free match).
        expectEqual(Set(categories.keys), Set(LineMatchCategory.allCases))
        // Parent weights apply.
        let onlyAnimals = LineMatchSettings(weights: [.numbers: 0, .body: 0, .animals: 10, .zodiac: 0])
        for seed in seeds.prefix(100) { expectEqual(guided(.l2, seed: seed, settings: onlyAnimals).category, .animals) }
        // A free question is never accepted as guided and vice versa.
        var broken = guided(.l2)
        broken.guided = LineMatchGuidedPlan(colorIndices: broken.guided!.colorIndices, bridgeOverRow: nil)
        expectFalse(broken.isWellFormed)
        var straightAcross = guided(.l2)
        straightAcross.rightOrder = [0, 1, 2]
        expectFalse(straightAcross.isWellFormed)
    }

    // MARK: Geometry

    func testStarOneRoadsAreStraightSameRowAndWide() {
        for seed in seeds.prefix(50) {
            let b = board(.l1, seed: seed)
            expectEqual(b.layout.style, .straight)
            expectTrue(b.layout.chevrons)
            expectEqual(b.roads.count, 2)
            for road in b.roads {
                expectTrue(road.isHorizontal)
                expectEqual(road.width, 100)
                expectEqual(road.slot, road.row, "★ joins each word to the picture on its own row")
                expectTrue(road.points.allSatisfy { abs($0.y - b.layout.goDots[road.row].y) < 0.001 })
                expectEqual(b.layout.leftCards[road.row].midY, b.layout.rightCards[road.slot].midY)
                expectTrue(road.goDistance < road.endDistance)
            }
            expectTrue(LineMatchGuidedGeometry.allCrossings(b.roads).isEmpty)
            expectEqual(b.layout.leftCards.map(\.width), [240, 240])
            expectEqual(b.layout.leftCards.map(\.height), [140, 140])
        }
    }

    func testStarTwoEveryLayoutHasExactlyOneCrossing() {
        let layout = LineMatchGuidedLayout.make(level: .l2, pairCount: 3)
        expectEqual(layout.style, .staggered)
        expectFalse(layout.chevrons)
        expectEqual(layout.roadWidth, 64)
        // The picture column sits half a row lower: no picture shares a word's row.
        for left in layout.leftCards {
            for right in layout.rightCards { expectTrue(abs(left.midY - right.midY) >= 70) }
        }
        // Every permutation: crossings drawn == inversions (validates the geometry), and the
        // generator's orders are exactly those with one crossing.
        let all = LineMatchGuidedGeometry.permutations(count: 3)
        expectEqual(all.count, 6)
        var single: [[Int]] = []
        for order in all {
            let q = LineMatchQuestion(level: .l2, category: .body, countObject: nil, pairs: guided(.l2).pairs,
                                      rightOrder: order, itemID: "t", promptTraditionalChinese: "", promptEnglish: "",
                                      hintTraditionalChinese: "")
            let roads = layout.roads(for: q)
            expectEqual(roads.count, 3)
            let crossings = LineMatchGuidedGeometry.allCrossings(roads)
            let inversions = LineMatchGuidedGeometry.invertedRows(rightOrder: order)
            expectEqual(crossings.count, inversions.count, "order \(order)")
            if crossings.count == 1 { single.append(order) }
            for road in roads {
                expectFalse(road.isHorizontal, "no ★★ road is horizontal")
                expectTrue(zip(road.points, road.points.dropFirst()).allSatisfy { $0.x < $1.x }, "x-monotone")
            }
        }
        expectEqual(Set(single), Set(LineMatchGuidedGeometry.singleCrossingOrders(count: 3)))
        // Every layout the generator can deal: one crossing, between the inverted pair, mid-road;
        // non-crossing roads keep a clear gap; the bridge road is one of the crossing pair.
        for order in LineMatchGuidedGeometry.singleCrossingOrders(count: 3) {
            let q = LineMatchQuestion(level: .l2, category: .body, countObject: nil, pairs: guided(.l2).pairs,
                                      rightOrder: order, itemID: "t", promptTraditionalChinese: "", promptEnglish: "",
                                      hintTraditionalChinese: "",
                                      guided: LineMatchGuidedPlan(colorIndices: [0, 1, 2], bridgeOverRow: nil))
            let roads = layout.roads(for: q)
            let crossings = LineMatchGuidedGeometry.allCrossings(roads)
            expectEqual(crossings.count, 1)
            guard let crossing = crossings.first, let pair = LineMatchGuidedGeometry.invertedRows(rightOrder: order).first
            else { preconditionFailure("crossing") }
            expectEqual(crossing.upper, pair.upper)
            expectEqual(crossing.lower, pair.lower)
            // Far from both cards, so the bridge deck (≈156u) fits between the dots.
            expectTrue(crossing.crossing.point.x > layout.goDots[0].x + 120)
            expectTrue(crossing.crossing.point.x < layout.endDots[0].x - 120)
            for i in roads.indices {
                for j in roads.indices where j > i && !(i == pair.upper && j == pair.lower) {
                    expectTrue(roads[i].minimumSeparation(to: roads[j]) >= layout.roadWidth + 12,
                               "roads \(i) and \(j) touch in \(order)")
                }
            }
        }
        for seed in seeds.prefix(200) {
            let b = board(.l2, seed: seed)
            let crossings = LineMatchGuidedGeometry.allCrossings(b.roads)
            expectEqual(crossings.count, 1)
            let over = b.question.guided?.bridgeOverRow
            expectTrue(over == crossings.first?.upper || over == crossings.first?.lower)
        }
    }

    private func labels(_ level: ActivityLevel) -> [(String, String)] {
        var result = LineMatchGenerator.numberRange(level).map {
            (LineMatchCatalog.chineseNumeral($0), LineMatchCatalog.englishNumber($0))
        }
        for category in LineMatchCategory.allCases where category.isDealt(at: level) {
            for item in LineMatchCatalog.items(category) { result.append((item.labelTraditionalChinese, item.labelEnglish)) }
        }
        return result
    }

    func testLayoutKeepsParentZoneBubblesAndStatusClear() {
        let zone = LineMatchGuidedLayout.parentZone
        expectEqual(zone, LineMatchRect(x: 1080, y: 580, width: 200, height: 140))
        for level in [ActivityLevel.l1, .l2] {
            let layout = LineMatchGuidedLayout.make(level: level, pairCount: LineMatchGenerator.pairCount(level))
            for rect in layout.allRects {
                expectFalse(rect.intersects(zone), "\(level.code) \(rect) in the parent zone")
                expectFalse(rect.intersects(LineMatchLayout.parentCornerKeepOut))
                expectTrue(rect.x >= 0 && rect.maxX <= 1280 && rect.maxY <= 720)
            }
            // Picture column ends by x 1040 at ★★ (design); ★ cards stay above the zone.
            if level == .l2 { expectTrue(layout.rightCards.allSatisfy { $0.maxX <= 1040 }) }
            let cards = layout.leftCards + layout.rightCards
            for (slot, bubble) in layout.bubbles.enumerated() {
                expectFalse(bubble.intersects(LineMatchLayout.header), "bubble under the header")
                expectFalse(bubble.intersects(layout.status))
                for card in cards { expectFalse(bubble.intersects(card), "\(level.code) bubble \(slot) on a card") }
                for (other, rect) in layout.bubbles.enumerated() where other != slot {
                    expectFalse(bubble.intersects(rect), "bubbles \(slot) / \(other) overlap")
                }
                // Every label of the level fits (zh 34 / 32pt, English ≈ 0.58 em per letter).
                for (zh, en) in labels(level) {
                    let zhCount: Double = Double(zh.count)
                    let enCount: Double = Double(en.count)
                    let stackedText: Double = max(zhCount * 32.0, enCount * 0.58 * 24.0)
                    let stackedWidth: Double = 74.0 + stackedText
                    let inlineZh: Double = (zhCount + 1.0) * 34.0
                    let inlineEn: Double = enCount * 0.58 * 30.0
                    let inlineWidth: Double = 98.0 + inlineZh + inlineEn
                    let text: Double = layout.bubbleStacked[slot] ? stackedWidth : inlineWidth
                    expectTrue(text <= bubble.width, "bubble \(slot) too narrow for \(zh) \(en)")
                }
                expectTrue(layout.bubbleTails[slot].distance(to: LineMatchPoint(x: bubble.midX, y: bubble.midY)) < 260)
            }
            for card in cards { expectFalse(card.intersects(layout.status)) }
            expectTrue(cards.allSatisfy { $0.height >= 120 })
            expectTrue(layout.wordChineseSize >= 48)
            // Bubbles never sit on a road (any deal).
            for seed in seeds.prefix(40) {
                let b = board(level, seed: seed)
                for bubble in layout.bubbles {
                    for road in b.roads {
                        let clear = road.points.allSatisfy { point in
                            let near = LineMatchRect(x: point.x - road.width / 2 - 6, y: point.y - road.width / 2 - 6,
                                                     width: road.width + 12, height: road.width + 12)
                            return !near.intersects(bubble) || point.x < bubble.x || point.x > bubble.maxX
                        }
                        expectTrue(clear, "\(level.code) bubble on road \(road.row)")
                    }
                }
            }
        }
        // Road colours: distinct, never the dot / tick green or the red dot.
        let fulls = LineMatchRoadPalette.roads.map(\.full)
        expectEqual(Set(fulls).count, 5)
        expectFalse(fulls.contains(LineMatchRoadPalette.goGreen))
        expectFalse(fulls.contains(LineMatchRoadPalette.endRed))
        expectEqual(LineMatchRoadPalette.roads.map(\.name), ["teal", "pink", "yellow", "purple", "blue"])
    }

    // MARK: Reducer

    func testProgressIsMonotonicAndOffRoadIsNeverAMiss() {
        var b = board(.l1)
        guard let row = b.currentRow, let truck = b.truckPoint else { preconditionFailure("start") }
        expectEqual(row, 0)
        let road = b.roads[row]
        // Pen on the red dot / picture: wrong start, nothing moves.
        expectEqual(b.penDown(at: b.layout.endDots[0], now: 0), .wrongStart)
        expectEqual(b.penMove(to: road.point(at: road.endDistance), now: 0), .ignored)
        expectEqual(b.progress[row], road.goDistance)
        expectEqual(b.wrongStarts, 1)
        // Pen down far from the truck: it waits; the hint shows after 2 s.
        expectEqual(b.penDown(at: LineMatchPoint(x: 640, y: 650), now: 10), .notNearTruck)
        expectFalse(b.showsHint(now: 11.9))
        expectTrue(b.showsHint(now: 12.1))
        b.penUp()
        expectFalse(b.showsHint(now: 20))
        // Grab and drive forward; each event moves at most 60u.
        expectEqual(b.penDown(at: truck, now: 20), .grabbed(row: 0))
        expectEqual(b.penMove(to: road.point(at: road.goDistance + 100), now: 20), .drove(row: 0))
        expectEqual(b.progress[row], road.goDistance + LineMatchGuidedBoard.maxStep, accuracy: 0.001)
        _ = b.penMove(to: road.point(at: road.goDistance + 100), now: 20)
        let mid = b.progress[row]
        // Backwards never moves the truck back.
        expectEqual(b.penMove(to: road.point(at: road.goDistance + 10), now: 20), .waiting(row: 0))
        expectEqual(b.progress[row], mid)
        // Off the road: the truck waits, `off_path` counted once per excursion, no miss anywhere.
        let off = LineMatchPoint(x: road.point(at: mid).x + 30, y: road.point(at: mid).y + 120)
        expectEqual(b.penMove(to: off, now: 21), .away(row: 0))
        expectEqual(b.penMove(to: LineMatchPoint(x: off.x + 10, y: off.y), now: 21.5), .away(row: 0))
        expectEqual(b.offPathCount, 1)
        expectEqual(b.progress[row], mid)
        expectFalse(b.showsHint(now: 22.9))
        expectTrue(b.showsHint(now: 23.1))
        // Back on the road: carries on from where it stopped; the hint clears.
        expectEqual(b.penMove(to: road.point(at: mid + 30), now: 24), .drove(row: 0))
        expectFalse(b.showsHint(now: 30))
        expectEqual(b.progress[row], mid + 30, accuracy: 0.001)
        // Pen jumps far ahead along the road: the truck waits (no chasing to the end).
        let held = b.progress[row]
        expectEqual(b.penMove(to: road.point(at: road.endDistance), now: 25), .away(row: 0))
        expectEqual(b.progress[row], held)
        // Lift mid-road: counted, truck stays; pen down near it carries on.
        b.penUp()
        expectEqual(b.lifts, 1)
        expectEqual(b.progress[row], held)
        expectEqual(b.penDown(at: road.point(at: road.endDistance), now: 26), .wrongStart)
        expectEqual(b.penDown(at: b.truckPoint!, now: 27), .grabbed(row: 0))
        var s = held
        var result = LineMatchGuidedMove.ignored
        var guardCount = 0
        while b.currentRow == 0, guardCount < 100 {
            s += 25
            result = b.penMove(to: road.point(at: s), now: 28)
            guardCount += 1
        }
        expectEqual(result, .completed(row: 0))
        expectEqual(b.doneRows, [0])
        expectTrue(b.isDone(slot: b.question.correctSlot(forRow: 0)!))
        expectEqual(b.progress[0], road.endDistance)
        // The rest of that stroke is ignored; the next road needs a fresh pen-down.
        expectEqual(b.penMove(to: b.roads[1].point(at: b.roads[1].goDistance + 30), now: 28), .ignored)
        expectEqual(b.currentRow, 1)
        // Nothing here knows about fuel, misses or a Think Pause: there is no wrong answer.
        let fields = b.resultFields
        for banned in ["misses", "submit_attempts", "eraser_uses", "wrong_lines"] { expectTrue(fields[banned] == nil) }
        expectEqual(fields["off_path_count"], .int(1))
        expectEqual(fields["lifts"], .int(1))
        expectEqual(fields["wrong_start"], .int(2))
        expectEqual(fields["match_mode"], .string("guided"))
    }

    func testToleranceWidensOnlyTheJudgedCorridor() {
        expectEqual(LineMatchTolerance.allCases.map(\.roadWidthFactor), [1.0, 1.5, 2.2])
        expectEqual(LineMatchTolerance.allCases.map(\.arrivalSlack), [30, 50, 80])
        let narrow = board(.l1, tolerance: .narrow)
        let standard = board(.l1, tolerance: .standard)
        let wide = board(.l1, tolerance: .wide)
        expectEqual(narrow.corridorHalfWidth(row: 0), 50)
        expectEqual(standard.corridorHalfWidth(row: 0), 75)
        expectEqual(wide.corridorHalfWidth(row: 0), 110, accuracy: 0.001)
        // Drawn road and layout are identical at every setting.
        expectEqual(narrow.roads, wide.roads)
        expectEqual(narrow.layout, wide.layout)
        expectEqual(board(.l2, tolerance: .narrow).corridorHalfWidth(row: 0), 32)
        // A pen 60u off the centre line: off-road at 窄, on-road at 標準.
        for (tolerance, onRoad) in [(LineMatchTolerance.narrow, false), (.standard, true), (.wide, true)] {
            var b = board(.l1, tolerance: tolerance)
            let road = b.roads[0]
            _ = b.penDown(at: b.truckPoint!, now: 0)
            let p = road.point(at: road.goDistance + 40)
            let result = b.penMove(to: LineMatchPoint(x: p.x, y: p.y + 60), now: 0)
            expectEqual(result == .drove(row: 0), onRoad, "\(tolerance)")
        }
        // Arrival: within the slack of the red dot (or 97%).
        for tolerance in LineMatchTolerance.allCases {
            let b = board(.l2, tolerance: tolerance)
            let road = b.roads[0]
            let span = road.endDistance - road.goDistance
            expectEqual(b.arrivalDistance(row: 0), road.endDistance - max(span * 0.03, tolerance.arrivalSlack),
                        accuracy: 0.001)
            expectTrue(b.arrivalDistance(row: 0) > road.goDistance + span * 0.8)
        }
    }

    func testEveryDealCompletesTopToBottomAndTerminates() {
        for level in [ActivityLevel.l1, .l2] {
            for seed in seeds.prefix(100) {
                var b = board(level, seed: seed)
                var rounds = 0
                while !b.isComplete, rounds < 10 {
                    let events = drive(&b, now: Double(rounds))
                    expectTrue(events > 3 && events < 200, "\(seed) road took \(events) events")
                    rounds += 1
                }
                expectTrue(b.isComplete, "\(seed) \(level.code)")
                expectEqual(b.doneRows, Array(0..<b.roads.count), "top → bottom, one row at a time")
                expectEqual(b.exposures, b.question.pairs.map(\.key))
                expectTrue(b.currentRow == nil)
                expectEqual(b.penDown(at: b.layout.goDots[0], now: 99), .ignored)
                expectEqual(b.resultFields["roads"], .int(b.roads.count))
                expectTrue(b.resultFields["duration_ms"] != nil)
            }
        }
        // The model only takes boards that grew from the one it has.
        let start = board(.l2, seed: "m")
        var later = start
        drive(&later)
        expectTrue(later.isMonotonicSuccessor(of: start))
        expectFalse(start.isMonotonicSuccessor(of: later), "a stale copy cannot undo a finished road")
        expectFalse(board(.l2, seed: "other").isMonotonicSuccessor(of: start))
        expectTrue(start.isMonotonicSuccessor(of: start))
    }

    // MARK: Stats

    func testGuidedRoundsArePracticeOnlyInReviewAndRollups() {
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        var seq = 0
        func event(_ type: PerfEventType, _ fields: [String: PerfValue], at offset: Double) -> PerfEvent {
            seq += 1
            return PerfEvent(type: type, timestamp: base.addingTimeInterval(offset), tz: "+08:00", mono: offset,
                             launch: "L", seq: seq, app: "0.24.0", actor: .child, mode: "lock", session: "s",
                             fields: fields)
        }
        let free = PerfChoiceCatalog.facts(lineMatch: LineMatchGenerator.make(seed: "f", level: .l2, avoidingItem: nil),
                                           settings: guidedOn)
        let practice = PerfChoiceCatalog.facts(lineMatch: guided(.l2), settings: guidedOn)
        expectEqual(free.dealtFields["match_mode"], .string("free"))
        expectEqual(practice.dealtFields["match_mode"], .string("guided"))
        expectEqual(practice.chance, 1)
        expectTrue(practice.correctChoice == nil)
        var events: [PerfEvent] = []
        // 3 free rounds (one wrong 完成 in the first), 4 guided rounds, 1 old round with no match_mode.
        for i in 0..<3 {
            var dealt = free.dealtFields
            dealt["round"] = .string("free\(i)"); dealt["kind"] = .string("lineMatch"); dealt["stars"] = .int(2)
            events.append(event(.gameDealt, dealt, at: Double(i * 100)))
            if i == 0 {
                events.append(event(.answerAttempt, ["round": .string("free0"), "correct": .bool(false),
                                                     "tags": .strings(["wrong_target"])], at: 10))
            }
            events.append(event(.answerAttempt, ["round": .string("free\(i)"), "correct": .bool(true)], at: Double(i * 100 + 20)))
            events.append(event(.roundResult, ["round": .string("free\(i)"), "outcome": .string("solved"),
                                               "answers": .int(i == 0 ? 2 : 1), "first_try": .bool(i != 0),
                                               "misses": .int(i == 0 ? 1 : 0)], at: Double(i * 100 + 30)))
        }
        for i in 0..<4 {
            var dealt = practice.dealtFields
            dealt["round"] = .string("g\(i)"); dealt["kind"] = .string("lineMatch"); dealt["stars"] = .int(1)
            events.append(event(.gameDealt, dealt, at: Double(1_000 + i * 100)))
            // Even a stray attempt in a guided round must never count.
            events.append(event(.answerAttempt, ["round": .string("g\(i)"), "correct": .bool(false),
                                                 "tags": .strings(["off_path"])], at: Double(1_010 + i * 100)))
            events.append(event(.roundResult, ["round": .string("g\(i)"), "outcome": .string("solved"),
                                               "answers": .int(0), "misses": .int(0), "match_mode": .string("guided"),
                                               "roads": .int(3)], at: Double(1_030 + i * 100)))
        }
        events.append(event(.gameDealt, ["round": .string("old"), "kind": .string("lineMatch"), "stars": .int(1)], at: 2_000))
        events.append(event(.answerAttempt, ["round": .string("old"), "correct": .bool(true)], at: 2_010))
        events.append(event(.roundResult, ["round": .string("old"), "outcome": .string("solved"), "answers": .int(1),
                                           "first_try": .bool(true), "misses": .int(0)], at: 2_020))
        let report = PerfReportBuilder.build(events: events, rollup: PerfRollup(), videos: [],
                                             now: base.addingTimeInterval(3_000), window: .all)
        let row = report.games.first { $0.kind == .lineMatch }!
        expectEqual(row.deals, 4, "3 free + 1 old; guided rounds are not deals")
        expectEqual(row.answered, 4)
        expectEqual(row.firstTry, 3)
        expectEqual(row.evidence.rounds, 4)
        expectEqual(row.guidedPractice, 4)
        expectEqual(row.stars[0].rounds, 1, "★ guided rounds stay out of the per-star counts")
        expectEqual(row.dots.count, 4)
        expectEqual(row.topWrongTag, "wrong_target")
        expectEqual(row.topWrongTagShare ?? 0, 1, accuracy: 0.0001)
        expectTrue(row.hasAnyRounds)
        // Old lines read as free.
        expectEqual(PerfQuestionGeneration.matchMode(of: events.first { $0.string("round") == "old" }!), .free)
        // Rollup: guided rounds under their own key, folded back as practice only.
        let day = PerfClock.dayStamp(base, timeZone: PerfClock.hongKong)
        let summaries = PerfSummaries.daySummaries(events: events, days: [day], excluded: [], timeZone: PerfClock.hongKong)
        let games = summaries[day]?.games ?? [:]
        expectEqual(games["lineMatch|1|variants_v1|guided"]?.deals, 4)
        expectEqual(games["lineMatch|1|variants_v1|guided"]?.firstTry, 0)
        expectEqual(games["lineMatch|2|variants_v1"]?.deals, 3)
        expectTrue(PerfQuestionGeneration.isGuidedRollupKey("lineMatch|1|variants_v1|guided"))
        expectFalse(PerfQuestionGeneration.isGuidedRollupKey("lineMatch|1|variants_v1"))
        expectEqual(PerfQuestionGeneration.parseRollupKey("lineMatch|1|variants_v1|guided").gen, "variants_v1")
        let rollup = PerfRollup(foldedDays: [day], days: [day: summaries[day]!])
        let fromRollup = PerfReportBuilder.build(events: [], rollup: rollup, videos: [],
                                                 now: base.addingTimeInterval(3_000), window: .all)
        let rolled = fromRollup.games.first { $0.kind == .lineMatch }!
        expectEqual(rolled.guidedPractice, 4)
        expectEqual(rolled.deals, 4)
        expectEqual(rolled.evidence.rounds, 4)
        // CSV carries match_mode; every row stays the header's width.
        let files = PerfCSVExport.files(events: events, rollup: rollup, titles: [:], now: base)
        expectTrue(PerfCSVExport.roundsHeader.contains("match_mode"))
        expectTrue(PerfCSVExport.dailyGamesHeader.contains("match_mode"))
        expectTrue((files["rounds.csv"] ?? "").contains(",guided,"))
        expectTrue((files["daily_games.csv"] ?? "").contains(",guided,variants_v1"))
        let rows = PerfCSVExport.roundRows(PerfCodec.ordered(events), excluded: [], timeZone: PerfClock.hongKong)
        expectTrue(rows.allSatisfy { $0.count == PerfCSVExport.roundsHeader.count })
        expectFalse(PerfEvent.envelopeKeys.contains(LineMatchMode.fieldKey), "match_mode must not collide with mode")
    }

    // MARK: Copy, voice, settings

    func testGuidedCopyAndCuesAreHongKongTraditional() {
        let simplified: Set<Character> = [
            "车", "个", "们", "数", "线", "书", "画", "门", "马", "见", "说", "话", "这", "发", "头", "脚", "图",
            "连", "认", "读", "写", "听", "点", "绿", "红", "后", "里", "辆", "几", "货", "铁", "龙", "鸡", "猪",
            "骝", "将", "闪", "紧", "试", "错", "对", "导", "条", "边", "过", "还", "开", "关", "从", "样"
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
        LineMatchGuidedCopy.allTraditionalLines.forEach(checkChinese)
        LineMatchGuidedCopy.allEnglishLines.forEach(checkEnglish)
        checkChinese(LineMatchGuidedCopy.offRoadPrompt.traditionalChinese)
        checkChinese(LineMatchGuidedCopy.wrongStartPrompt.traditionalChinese)
        expectEqual(LineMatchGuidedCopy.offRoadTraditionalChinese, "架車等緊你，返嚟條路度啦！")
        expectEqual(LineMatchGuidedCopy.remainingEnglish(1), "1 more road to go")
        for level in [ActivityLevel.l1, .l2] {
            for seed in seeds.prefix(300) {
                let q = guided(level, seed: seed)
                checkChinese(q.promptTraditionalChinese)
                checkEnglish(q.promptEnglish)
                for pair in q.pairs {
                    let cue = LineMatchGuidedCopy.cue(pair)
                    checkChinese(cue.traditionalChinese)
                    checkEnglish(cue.english)
                    expectEqual(LineMatchGuidedCopy.bubble(pair), "\(cue.traditionalChinese)、\(cue.english)")
                }
            }
        }
        let eye = LineMatchPair(key: "eye", iconKey: "eye", count: 1, labelTraditionalChinese: "眼睛", labelEnglish: "eye")
        expectEqual(LineMatchGuidedCopy.bubble(eye), "眼睛、eye")
        let four = LineMatchPair(key: "n4", iconKey: "chick", count: 4, labelTraditionalChinese: "四",
                                 labelEnglish: "four", numeral: 4)
        expectEqual(LineMatchGuidedCopy.bubble(four), "四、four")
        expectEqual(LineMatchGuidedCopy.prompt(object: .chick).zh, "數吓有幾多隻，沿住條路揸！")
        // English word voice: en-GB first, never a Chinese voice.
        let voices = [
            SpeechVoiceInfo(identifier: "zh.cn", name: "Tingting", language: "zh-CN", qualityRank: 3),
            SpeechVoiceInfo(identifier: "en.us", name: "Samantha", language: "en-US", qualityRank: 3),
            SpeechVoiceInfo(identifier: "en.gb", name: "Daniel", language: "en_GB", qualityRank: 1)
        ]
        expectEqual(EnglishVoicePicker.pick(from: voices)?.identifier, "en.gb")
        expectEqual(EnglishVoicePicker.pick(from: Array(voices.prefix(2)))?.identifier, "en.us")
        expectTrue(EnglishVoicePicker.pick(from: Array(voices.prefix(1))) == nil)
        expectTrue(CantoneseVoicePicker.pick(from: voices) == nil, "no Cantonese voice → no Mandarin either")
    }

    func testThreeLineMatchKindsDefaultOffAndSharedSettingsPersist() {
        // v0.24.1: three ActivityKinds, all default-off; settings are tolerance + weights only.
        for kind in [ActivityKind.lineMatchGuidedStraight, .lineMatchGuidedBridge, .lineMatch] {
            expectTrue(ActivityCatalog.defaultOffKinds.contains(kind))
            expectTrue(kind.isLineMatchFamily)
            for star in ChildDifficulty.allCases {
                expectFalse(MissionGameAssignment.defaults.isEnabled(kind, star: star))
            }
        }
        expectEqual(ActivityKind.lineMatchGuidedStraight.parentCardTitle, "連一連 · 沿路送")
        expectEqual(ActivityKind.lineMatchGuidedBridge.parentCardTitle, "連一連 · 沿路過橋")
        expectEqual(ActivityKind.lineMatch.parentCardTitle, "連一連 · 自己配")
        let suite = "VisaGames.guided.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
        let settingsStore = LineMatchSettingsStore(defaults: store)
        let wide = LineMatchSettings.defaults.withTolerance(.wide)
        expectEqual(wide.adjusting(.body, steps: 1)!.tolerance, .wide)
        settingsStore.save(wide)
        expectEqual(settingsStore.load().tolerance, .wide)
        // A v0.23 / v0.24.0 payload (optional `guided` key) still loads tolerance and weights.
        store.set(Data(#"{"tolerance":"wide","weights":{"numbers":35,"body":30,"animals":20,"zodiac":0},"guided":true}"#.utf8),
                  forKey: LineMatchSettingsStore.key)
        let migrated = settingsStore.load()
        expectEqual(migrated.tolerance, .wide)
        expectEqual(migrated.weight(.zodiac), 0)
        store.removePersistentDomain(forName: suite)
    }

    // MARK: Source guards (no UI test target)

    func testGuidedAppWiringSourceGuards() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        let view = try source("Sources/VisaGames/LineMatchGuidedBoardView.swift")
        expectTrue(view.contains("DragGesture(minimumDistance: 0)"))
        expectTrue(view.contains("LineMatchArt.miniTruck"))
        expectTrue(view.contains("penMove(to:"))
        for banned in ["TextField", "contextMenu", "Link(", "openURL", "NSWorkspace", "WKWebView", "TextEditor",
                       "ThinkPauseOverlay", "LineMatchCopy.doneTraditionalChinese", "LineMatchCopy.eraserTraditionalChinese",
                       "unowned", "assumeIsolated"] {
            expectFalse(view.contains(banned), "guided board must not use \(banned)")
        }
        let host = try source("Sources/VisaGames/CanvasActivityHost.swift")
        expectTrue(host.contains("LineMatchGuidedBoardView("))
        let app = try source("Sources/VisaGames/AppDelegate.swift")
        expectTrue(app.contains("kind.lineMatchDeal(missionLevel:"))
        expectTrue(app.contains("isMonotonicSuccessor(of:"))
        expectTrue(app.contains("guideVoice.speakWordCue("))
        expectFalse(app.contains("setLineMatchGuided"))
        expectFalse(app.contains("withGuided"))
        // Guided completion never goes through the wrong-answer path or an answer record.
        let finish = app.components(separatedBy: "func finishGuidedRound").last ?? ""
        let body = finish.components(separatedBy: "\n    }\n").first ?? ""
        expectTrue(body.contains("applyEntrySuccess(assisted: false)"))
        expectFalse(body.contains("handleEvaluation"))
        expectFalse(body.contains("roundAnswer"))
        expectFalse(app.contains("unowned"))
        let speech = try source("Sources/VisaGames/SystemSpeechPrompt.swift")
        expectTrue(speech.contains("func speakWordCue"))
        expectTrue(speech.contains("EnglishVoicePicker.pick(from: candidates)"))
        let settings = try source("Sources/VisaGames/ParentLineMatchSettingsView.swift")
        expectFalse(settings.contains("LineMatchGuidedCopy.parentToggleTraditionalChinese"))
        expectFalse(settings.contains("onGuided"))
        expectTrue(settings.contains("三個遊戲共用"))
        expectFalse(settings.contains("TextField"))
        expectEqual(ActivityCatalog.defaultOffKinds,
                    [.lineMatchGuidedStraight, .lineMatchGuidedBridge, .lineMatch])
        let review = try source("Sources/VisaGames/ParentReviewView.swift")
        expectTrue(review.contains("guidedPractice"))
    }
}
