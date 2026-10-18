import Foundation
import VisaCore

/// v0.28.0 一架一架數 / Tap & Count (ADR 0017; design number-quantity §11.4): numeral strokes with
/// cubics, corners and cusps; the generator's count invariants; the tap / pick / OK reducer; the
/// default-off + playtest gate; settings; HK Traditional copy; and the app wiring.
final class TapCountTests {
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private let kinds: [ActivityKind] = [.tapCountAll, .tapCountTrace, .tapCountPick]

    /// Drives every stroke of a trace board along its centre line (optionally off-centre).
    @discardableResult
    private func drive(_ board: inout ShapeTraceBoard, clock: inout Double, offset: Double = 0) -> ShapeTraceMove {
        var last = ShapeTraceMove.ignored
        var guardSteps = 0
        while !board.isComplete, guardSteps < 10 {
            guardSteps += 1
            guard let path = board.currentPath else { break }
            clock += 0.1
            _ = board.penDown(at: path.start, now: clock)
            var d = 0.0
            while d <= path.length + 16 {
                let p = path.point(at: min(d, path.length))
                let angle = path.angle(at: min(d, path.length))
                let q = LineMatchPoint(x: p.x - sin(angle) * offset, y: p.y + cos(angle) * offset)
                clock += 0.02
                last = board.penMove(to: q, now: clock)
                if case .strokeDone = last { break }
                if case .shapeDone = last { break }
                if case .allDone = last { break }
                d += 6
            }
            board.penUp()
        }
        return last
    }

    // MARK: Numerals (stroke data 1–10)

    func testNumeralStrokeDataMatchesTheStrokeOrderSheet() {
        let expectedStrokes = [0: 1, 1: 1, 2: 1, 3: 1, 4: 2, 5: 2, 6: 1, 7: 1, 8: 1, 9: 1, 10: 2]
        let starts: [Int: (Double, Double)] = [1: (100, 30), 2: (40, 92), 3: (44, 64), 4: (62, 30), 5: (58, 32),
                                               6: (150, 42), 7: (32, 36), 8: (104, 30), 9: (164, 40), 10: (52, 30)]
        for n in 0...10 {
            let paths = NumeralGlyphs.paths(n, offset: LineMatchPoint(x: 0, y: 0), scale: 1)
            expectEqual(paths.count, expectedStrokes[n]!, "strokes of \(n)")
            for path in paths {
                expectTrue(path.length > 100, "stroke of \(n) parses")
                // Sampled ≤ 6u apart (cubics included).
                for i in 0..<(path.points.count - 1) {
                    let gap = path.points[i].distance(to: path.points[i + 1])
                    expectTrue(gap <= TracePath.sampleSpacing + 0.01, "gap \(gap) at \(i) of \(n): \(path.points[i])")
                }
            }
            if let start = starts[n] {
                expectEqual(paths[0].start.x, start.0, accuracy: 0.01)
                expectEqual(paths[0].start.y, start.1, accuracy: 0.01)
            }
        }
        // 0, 8 and 10's second stroke are closed; 0 runs anticlockwise from 12 o'clock.
        let zero = NumeralGlyphs.paths(0, offset: LineMatchPoint(x: 0, y: 0), scale: 1)[0]
        expectTrue(zero.closed && zero.signedArea < 0)
        expectTrue(NumeralGlyphs.paths(8, offset: LineMatchPoint(x: 0, y: 0), scale: 1)[0].closed)
        let ten = NumeralGlyphs.paths(10, offset: LineMatchPoint(x: 0, y: 0), scale: 1)
        expectTrue(ten[1].closed && ten[1].signedArea < 0)
        // 4 and 5 stroke ② start where the sheet says.
        let four = NumeralGlyphs.paths(4, offset: LineMatchPoint(x: 0, y: 0), scale: 1)
        expectEqual(four[1].start, LineMatchPoint(x: 120, y: 30))
        let five = NumeralGlyphs.paths(5, offset: LineMatchPoint(x: 0, y: 0), scale: 1)
        expectEqual(five[1].start, LineMatchPoint(x: 58, y: 32))
        expectEqual(five[1].end, LineMatchPoint(x: 168, y: 32))
    }

    func testNumeralCornersAndCuspsSitWhereTheSheetSays() {
        let corners: [Int: (Double, Double)] = [2: (34, 270), 3: (94, 144), 4: (24, 192), 5: (50, 132), 7: (170, 36),
                                                9: (164, 40)]
        for n in 1...10 {
            let first = NumeralGlyphs.paths(n, offset: LineMatchPoint(x: 0, y: 0), scale: 1)[0]
            if let corner = corners[n] {
                expectEqual(first.corners.count, 1, "one corner on \(n)")
                let p = first.point(at: first.corners[0])
                expectEqual(p.x, corner.0, accuracy: 0.5)
                expectEqual(p.y, corner.1, accuracy: 0.5)
            } else {
                expectTrue(first.corners.isEmpty, "\(n) has no corner")
            }
            expectEqual(first.cusps.count, (n == 3 || n == 9) ? 1 : 0, "cusps of \(n)")
        }
    }

    func testEveryNumeralCompletesAtEveryToleranceAndNeverAtPenDown() {
        for n in 1...10 {
            for tolerance in [LineMatchTolerance.narrow, .standard, .wide] {
                for offset in [0.0, 10.0, -10.0] {
                    let q = NumeralGlyphs.traceQuestion(n, itemID: "t\(n)", kind: .tapCountTrace, colorIndex: 0)
                    var board = ShapeTraceBoard(question: q, tolerance: tolerance, directionHint: true)
                    var clock = 0.0
                    drive(&board, clock: &clock, offset: offset)
                    expectTrue(board.isComplete, "\(n) completes (\(tolerance), offset \(offset)) progress \(board.progress) stroke \(board.strokeIndex) len \(board.currentPath?.length ?? -1) corners \(board.currentPath?.corners ?? []) cusps \(board.currentPath?.cusps ?? []) offPath \(board.offPathCount) overshoot \(board.cornerOvershoots)")
                }
            }
            // Pen down at the start does not finish a closed numeral (0, 8: start = end).
            let q = NumeralGlyphs.traceQuestion(n, itemID: "t\(n)", kind: .tapCountTrace, colorIndex: 0)
            var board = ShapeTraceBoard(question: q, directionHint: true)
            let path = board.currentPath!
            _ = board.penDown(at: path.start, now: 0)
            _ = board.penMove(to: path.end, now: 0.1)
            expectFalse(board.isComplete)
            expectTrue(board.progress < path.length * 0.5)
        }
    }

    func testCuspWindowNeverProjectsBehindTheTurnBack() {
        // 9: up to the corner, then straight down the same line.
        let q = NumeralGlyphs.traceQuestion(9, itemID: "t9", kind: .tapCountTrace, colorIndex: 0)
        var board = ShapeTraceBoard(question: q, directionHint: true)
        let path = board.currentPath!
        let cusp = path.cusps[0]
        var clock = 0.0
        _ = board.penDown(at: path.start, now: clock)
        var d = 0.0
        while d < cusp - 70 {
            clock += 0.02
            _ = board.penMove(to: path.point(at: d), now: clock)
            d += 6
            // Short of the cusp the window never reaches the down stroke.
            expectTrue(board.searchWindow(path).upperBound <= cusp + 0.001)
        }
        expectTrue(board.progress < cusp)
        // A pen on the down stroke while the vehicle is short of the corner never pulls it past.
        clock += 0.02
        _ = board.penMove(to: path.point(at: cusp + 30), now: clock)
        expectTrue(board.progress <= cusp + 0.001)
        while board.progress < cusp - 0.5, d < cusp + 40 {
            clock += 0.02
            _ = board.penMove(to: path.point(at: min(d, cusp)), now: clock)
            d += 6
        }
        expectEqual(board.progress, cusp, accuracy: 0.5)
        // At the cusp the window starts at the cusp: going down never slides back up.
        expectTrue(board.searchWindow(path).lowerBound >= cusp - 0.001)
        for step in 1...12 {
            clock += 0.02
            _ = board.penMove(to: path.point(at: cusp + Double(step) * 8), now: clock)
            expectTrue(board.progress >= cusp - 0.001)
        }
        expectTrue(board.progress > cusp + 40)
        // 8's crossing: driving straight through it never jumps ahead.
        let eight = NumeralGlyphs.traceQuestion(8, itemID: "t8", kind: .tapCountTrace, colorIndex: 0)
        var b8 = ShapeTraceBoard(question: eight, directionHint: true)
        let p8 = b8.currentPath!
        var last = 0.0
        _ = b8.penDown(at: p8.start, now: 0)
        var t = 0.0
        while t < p8.length * 0.8 {
            _ = b8.penMove(to: p8.point(at: t), now: t)
            expectTrue(b8.progress - last <= ShapeTraceBoard.maxStep + 0.01)
            last = b8.progress
            t += 6
        }
        expectTrue(b8.progress < p8.length)
    }

    func testCubicSupportLeavesShapeTraceStrokesUnchanged() {
        // Line-only strokes: corners still inferred from line→line joins; no cusps; same samples.
        let poly = TracePath.polyline([LineMatchPoint(x: 0, y: 0), LineMatchPoint(x: 100, y: 0), LineMatchPoint(x: 100, y: 90)])
        expectEqual(poly.corners.count, 1)
        expectEqual(poly.corners[0], 100, accuracy: 0.001)
        expectTrue(poly.cusps.isEmpty)
        let svg = TracePath(svg: "M0 0 H100 V90", corners: [LineMatchPoint(x: 100, y: 0)])
        expectEqual(svg.points, poly.points)
        expectEqual(svg.corners, poly.corners)
        let circle = TracePath.circle(center: LineMatchPoint(x: 0, y: 0), radius: 50)
        expectTrue(circle.cusps.isEmpty && circle.corners.isEmpty)
        // A stroke without cusps gets the old window: 40u behind, 210u ahead.
        let q = NumeralGlyphs.traceQuestion(1, itemID: "t1", kind: .tapCountTrace, colorIndex: 0)
        let board = ShapeTraceBoard(question: q)
        let w = board.searchWindow(board.currentPath!)
        expectEqual(w.lowerBound, -ShapeTraceBoard.windowBehind, accuracy: 0.001)
        expectEqual(w.upperBound, ShapeTraceBoard.leadLimit + ShapeTraceBoard.maxStep, accuracy: 0.001)
    }

    func testTraceBoardSitsInTheWorkspaceAndClearOfTheParentCorner() {
        for n in 1...10 {
            let q = NumeralGlyphs.traceQuestion(n, itemID: "t\(n)", kind: .tapCountTrace, colorIndex: 0)
            let board = NumeralGlyphs.traceBoard(n)
            for stroke in q.shapes[0].strokes {
                let b = stroke.bounds
                expectTrue(b.x - q.laneWidth / 2 >= board.x && b.maxX + q.laneWidth / 2 <= board.maxX, "\(n) inside board x")
                expectTrue(b.y - q.laneWidth / 2 >= board.y && b.maxY + q.laneWidth / 2 <= board.maxY + 4, "\(n) inside board y")
                expectFalse(ShapeTraceLayout.entersParentCorner(stroke, halfWidth: q.laneWidth / 2))
            }
        }
    }

    // MARK: Generator

    func testGeneratorInvariantsForThousandsOfSeeds() {
        for kind in kinds {
            for i in 0..<1000 {
                let q = TapCountGenerator.make(seed: "s\(i)", kind: kind)
                expectEqual(q, TapCountGenerator.make(seed: "s\(i)", kind: kind))
                expectTrue(q.isWellFormed, "well-formed \(q.itemID)")
                expectEqual(q.kind, kind)
                expectEqual(q.level, kind.tapCountLevel!)
                expectTrue(q.target >= 1 && q.target <= 10, "target in 1…10 (0 never)")
                expectTrue(q.count <= 10)
                if kind == .tapCountPick {
                    if q.target == 10 {
                        expectEqual(q.count, 10)
                    } else {
                        expectTrue(q.count > q.target, "more vehicles than the target")
                        expectTrue(q.count >= 3)
                    }
                    expectEqual(q.layout, .yard)
                } else {
                    expectEqual(q.count, q.target)
                    expectEqual(q.layout, q.target <= 5 ? .row : .tenFrame)
                }
            }
        }
    }

    func testRangeRecentTargetsAndWeights() {
        for range in TapCountRange.allCases {
            let settings = TapCountSettings(range: range)
            for i in 0..<400 {
                let q = TapCountGenerator.make(seed: "r\(i)", kind: .tapCountPick, settings: settings)
                expectTrue(range.numbers.contains(q.target))
            }
        }
        // The family's last 3 targets are not dealt again.
        var recent: [Int] = []
        for i in 0..<300 {
            let q = TapCountGenerator.make(seed: "x\(i)", kind: kinds[i % 3], recentTargets: recent)
            expectFalse(recent.suffix(3).contains(q.target), "recent target repeated")
            recent.append(q.target)
        }
        // Weights: 1 and 2 at half weight (≈5.6%), 3–10 ≈11.1% each, within ±2%.
        var counts = [Int: Int]()
        let total = 10_000
        for i in 0..<total { counts[TapCountGenerator.make(seed: "w\(i)", kind: .tapCountAll).target, default: 0] += 1 }
        for n in 1...10 {
            let expected = n <= 2 ? 1.0 / 18 : 2.0 / 18
            expectTrue(abs(Double(counts[n] ?? 0) / Double(total) - expected) < 0.02, "weight of \(n)")
        }
        // The item and the scene of the last round are avoided.
        for i in 0..<200 {
            let a = TapCountGenerator.make(seed: "a\(i)", kind: .tapCountPick)
            let b = TapCountGenerator.make(seed: "a\(i)", kind: .tapCountPick, avoidingItem: a.itemID, avoidingScene: a.scene)
            expectTrue(b.itemID != a.itemID)
            expectTrue(b.scene != a.scene)
        }
        expectEqual(TapCountGenerator.carRange(target: 3), 4...10)
        expectEqual(TapCountGenerator.carRange(target: 1), 3...10)
        expectEqual(TapCountGenerator.carRange(target: 9), 10...10)
        expectEqual(TapCountGenerator.carRange(target: 10), 10...10)
    }

    func testVehiclesStayInTheirBaysAndTapsHitTheNearestBay() {
        for kind in kinds {
            for i in 0..<300 {
                let q = TapCountGenerator.make(seed: "g\(i)", kind: kind)
                for v in q.vehicles {
                    let r = q.bayRect(v.bay)
                    let g = q.ground(v)
                    expectTrue(r.contains(LineMatchPoint(x: g.x, y: r.midY)))
                    expectEqual(q.bay(at: LineMatchPoint(x: r.midX, y: r.midY)), v.bay)
                }
                for a in 0..<q.bayCount {
                    for b in (a + 1)..<max(a + 1, q.bayCount) {
                        expectFalse(q.bayRect(a).intersects(q.bayRect(b)), "bays overlap")
                    }
                }
            }
        }
        // A tap in the 12u gap between two cells goes to the nearest one; far away is nothing.
        let q = TapCountGenerator.make(seed: "gap", kind: .tapCountPick)
        let left = TapCountLayoutGeometry.cell(0)
        expectEqual(q.bay(at: LineMatchPoint(x: left.maxX + 4, y: left.midY)), 0)
        expectEqual(q.bay(at: LineMatchPoint(x: left.maxX + 8, y: left.midY)), 1)
        expectNil(q.bay(at: LineMatchPoint(x: 640, y: 470)))
    }

    // MARK: Tap targets vs drawing (v0.28.1)

    /// UAT v0.28.0: in the 2-row layouts every tap landed one row below the drawn vehicle. The view
    /// now lays one tap target per vehicle on `TapCountVehicleLayout.hitRect`, in the same stage
    /// units the drawing uses. For every star, scene and vehicle count 1–10 (row and two-row
    /// layouts), each drawn vehicle must sit on its own target and on no other.
    func testHitTargetsMatchTheDrawnVehiclesForEveryCount() {
        var seen = Set<String>()
        var minCoverage = 1.0
        var worst = ""
        for kind in kinds {
            for i in 0..<6000 {
                let q = TapCountGenerator.make(seed: "hit\(i)", kind: kind)
                let key = "\(kind.rawValue)/\(q.scene.rawValue)/\(q.count)"
                guard seen.insert(key).inserted else { continue }
                let targets = TapCountVehicleLayout.hitTargets(q)
                expectEqual(targets.map(\.bay), q.occupiedBays, "one target per vehicle \(key)")
                for (a, ta) in targets.enumerated() {
                    for tb in targets[(a + 1)...] {
                        expectFalse(ta.rect.intersects(tb.rect), "targets overlap \(key)")
                    }
                }
                for v in q.vehicles {
                    let drawn = TapCountVehicleLayout.drawnFrame(v, in: q)
                    let hit = TapCountVehicleLayout.hitRect(bay: v.bay, in: q)
                    let centre = LineMatchPoint(x: drawn.midX, y: drawn.midY)
                    expectEqual(TapCountVehicleLayout.bay(atStage: centre, in: q), v.bay,
                                "drawn centre of bay \(v.bay) hits its own target \(key)")
                    // The middle of the vehicle body (the lower two thirds of the art box, where the
                    // child aims) is inside its target: tapping the top or bottom of a vehicle works.
                    for fy in [0.4, 0.6, 0.8] {
                        for fx in [0.2, 0.5, 0.8] {
                            let p = LineMatchPoint(x: drawn.x + drawn.width * fx, y: drawn.y + drawn.height * fy)
                            expectEqual(TapCountVehicleLayout.bay(atStage: p, in: q), v.bay,
                                        "body point (\(fx), \(fy)) of bay \(v.bay) \(key)")
                        }
                    }
                    // The pre-fix bug: a point one workspace offset (118u) below the vehicle is not it.
                    let shifted = LineMatchPoint(x: centre.x, y: centre.y + 118)
                    expectTrue(TapCountVehicleLayout.bay(atStage: shifted, in: q) != v.bay, "118u below is not the vehicle \(key)")
                    let ix = max(0, min(drawn.maxX, hit.maxX) - max(drawn.x, hit.x))
                    let iy = max(0, min(drawn.maxY, hit.maxY) - max(drawn.y, hit.y))
                    let coverage = ix * iy / max(1, drawn.width * drawn.height)
                    if coverage < minCoverage { minCoverage = coverage; worst = "\(key) bay \(v.bay) \(v.model)" }
                }
            }
        }
        // Every star × scene × count the generator can deal: ★/★★ 5 scenes × 1…10; ★★★ 5 × 3…10.
        for scene in TapCountScene.allCases {
            for n in 1...10 {
                expectTrue(seen.contains("tapCountAll/\(scene.rawValue)/\(n)"), "★ \(scene) \(n) covered")
                expectTrue(seen.contains("tapCountTrace/\(scene.rawValue)/\(n)"), "★★ \(scene) \(n) covered")
            }
            for n in 3...10 {
                expectTrue(seen.contains("tapCountPick/\(scene.rawValue)/\(n)"), "★★★ \(scene) \(n) covered")
            }
        }
        expectTrue(minCoverage >= 0.75, "drawn art inside its target ≥ 75% (worst \(worst): \(minCoverage))")
    }

    // MARK: Spoken 喎 (v0.28.2)

    /// UAT v0.28.1: Sinji read 「要八架喎！」 with 喎 as 窩 (wo1). The voice gets 禍 (wo6) instead;
    /// the screen, the keys and the recorded clips keep 喎.
    func testSpokenParticleReadsLowAndScreenKeepsWo() throws {
        let lines = [TapCountCopy.noneYet, TapCountCopy.need(8), TapCountCopy.over, TapCountCopy.under]
        for line in lines {
            expectTrue(line.traditionalChinese.contains("喎"), "screen keeps 喎: \(line.traditionalChinese)")
            let spoken = CantoneseSpeech.spoken(line.traditionalChinese)
            expectFalse(spoken.contains("喎"), "voice never gets 喎: \(spoken)")
            expectEqual(spoken, line.traditionalChinese.replacingOccurrences(of: "喎", with: "禍"))
        }
        expectEqual(CantoneseSpeech.spoken("要八架喎！"), "要八架禍！")
        expectEqual(CantoneseSpeech.spoken("點一點每架叮叮！"), "點一點每架叮叮！")
        for n in 1...10 { expectFalse(CantoneseSpeech.spoken(TapCountCopy.need(n).traditionalChinese).contains("喎"), "need \(n)") }
        // Every Cantonese system-voice utterance goes through the spoken mapping.
        let speech = try source("Sources/VisaGames/SystemSpeechPrompt.swift")
        for field in ["prompt", "cue", "follow"] {
            expectFalse(speech.contains("AVSpeechUtterance(string: \(field).traditionalChinese)"), "raw \(field) text")
        }
        expectTrue(speech.contains("AVSpeechUtterance(string: CantoneseSpeech.spoken(prompt.traditionalChinese))"))
    }

    // MARK: Reducer

    private func pickQuestion(target: Int, cars: Int) -> TapCountQuestion {
        for i in 0..<20_000 {
            let q = TapCountGenerator.make(seed: "p\(i)", kind: .tapCountPick)
            if q.target == target, q.count == cars { return q }
        }
        preconditionFailure("no deal with T=\(target) N=\(cars)")
    }

    func testStarOneAndTwoCountEachVehicleOnceAndIgnoreDoubleTaps() {
        let q = (0..<200).lazy.map { TapCountGenerator.make(seed: "c\($0)", kind: .tapCountTrace) }.first { $0.count >= 3 }!
        var board = TapCountBoard(question: q)
        var clock = 0.0
        let bays = q.occupiedBays
        expectEqual(board.tap(bay: bays[0], now: clock), .counted(k: 1))
        clock += 0.2
        expectEqual(board.tap(bay: bays[0], now: clock), .doubleTapIgnored)
        clock += 1
        expectEqual(board.tap(bay: bays[0], now: clock), .recount(bay: bays[0]))
        expectEqual(board.selectedCount, 1)
        expectEqual(board.recountAttempts, 1)
        expectEqual(board.nextUntapped, bays[1])
        for (i, bay) in bays.dropFirst().enumerated() {
            clock += 0.6
            let result = board.tap(bay: bay, now: clock)
            expectEqual(result, i == bays.count - 2 ? .completed(k: bays.count) : .counted(k: i + 2))
        }
        expectEqual(board.stage, .counted)
        expectEqual(board.selectedCount, q.count)
        expectEqual(board.tap(bay: bays[0], now: clock + 2), .locked)
        // ★★ then traces; the trace is never wrong and finishes the round.
        board.startTracing(tolerance: .standard)
        expectEqual(board.stage, .tracing)
        var trace = board.trace!
        drive(&trace, clock: &clock)
        board.updateTrace(trace, now: clock)
        expectEqual(board.stage, .done)
        // ★ ends after the reveal without a trace.
        let one = TapCountGenerator.make(seed: "c2", kind: .tapCountAll)
        var b1 = TapCountBoard(question: one)
        for (i, bay) in one.occupiedBays.enumerated() { _ = b1.tap(bay: bay, now: Double(i)) }
        b1.startTracing(tolerance: .standard)
        expectNil(b1.trace)
        b1.finishWithoutTrace(now: 20)
        expectTrue(b1.isComplete)
    }

    func testPickRenumbersOnUntapAcceptsOverPicksAndJudgesOnlyAtOK() {
        let q = pickQuestion(target: 3, cars: 6)
        var board = TapCountBoard(question: q)
        let bays = q.occupiedBays
        expectEqual(board.submit(now: 0), .needsSelection)
        expectEqual(board.misses, 0)
        expectFalse(board.okEnabled)
        expectEqual(board.tap(bay: bays[0], now: 1), .selected(k: 1))
        expectEqual(board.tap(bay: bays[1], now: 2), .selected(k: 2))
        expectEqual(board.tap(bay: bays[2], now: 3), .selected(k: 3))
        expectEqual(board.tap(bay: bays[3], now: 4), .selected(k: 4), "over-picks are accepted silently")
        expectEqual(board.tap(bay: bays[1], now: 5), .unselected(k: 3))
        expectEqual(board.badge(forBay: bays[0]), 1)
        expectEqual(board.badge(forBay: bays[2]), 2)
        expectEqual(board.badge(forBay: bays[3]), 3, "renumbered 1…k in pick order")
        expectNil(board.badge(forBay: bays[1]))
        // Any 3 is right, whichever vehicles they are.
        expectEqual(board.submit(now: 6), .judged(correct: true, selected: 3))
        expectEqual(board.stage, .counted)
        expectEqual(board.misses, 0)
    }

    func testOneMissPerOKTagsAndTheDemoAfterTwoMisses() {
        let q = pickQuestion(target: 3, cars: 6)
        var board = TapCountBoard(question: q)
        let bays = q.occupiedBays
        for (i, bay) in bays.prefix(5).enumerated() { _ = board.tap(bay: bay, now: Double(i)) }
        expectEqual(board.submit(now: 10), .judged(correct: false, selected: 5))
        expectEqual(board.misses, 1)
        expectTrue(board.submitTags(now: 10).contains("off_by_2plus"))
        expectEqual(board.missFeedback, .over)
        expectEqual(board.extraBays, Array(bays[3...4]))
        // Locked during the Think Pause: taps, OK and the eraser do nothing.
        board.setLocked(true)
        expectEqual(board.tap(bay: bays[0], now: 11), .locked)
        expectEqual(board.submit(now: 11), .locked)
        expectEqual(board.erase(now: 11), .unavailable)
        board.setLocked(false)
        // The picks stay; un-pick one → over by 1.
        expectEqual(board.selectedCount, 5)
        _ = board.tap(bay: bays[4], now: 30)
        expectEqual(board.submit(now: 40), .judged(correct: false, selected: 4))
        expectEqual(board.misses, 2)
        expectTrue(board.submitTags(now: 40).contains("over_by_1"))
        board.startDemo()
        expectEqual(board.selectedCount, 0)
        expectEqual(board.demoBays, Array(q.readingOrder.prefix(3)))
        for (i, bay) in board.demoBays.enumerated() { _ = board.tap(bay: bay, now: 50 + Double(i)) }
        expectEqual(board.submit(now: 60), .judged(correct: true, selected: 3))
        expectTrue(board.assisted)
        // Under by one, tapped-all and numeral confusion tags.
        var under = TapCountBoard(question: q)
        _ = under.tap(bay: bays[0], now: 0); _ = under.tap(bay: bays[1], now: 1)
        _ = under.submit(now: 5)
        expectTrue(under.submitTags(now: 5).contains("under_by_1"))
        expectEqual(under.missFeedback, .under)
        var all = TapCountBoard(question: q)
        for (i, bay) in bays.enumerated() { _ = all.tap(bay: bay, now: Double(i)) }
        _ = all.submit(now: 20)
        expectTrue(all.submitTags(now: 20).contains("tapped_all"))
        let six = pickQuestion(target: 6, cars: 10)
        var confused = TapCountBoard(question: six)
        for (i, bay) in six.occupiedBays.prefix(9).enumerated() { _ = confused.tap(bay: bay, now: Double(i)) }
        _ = confused.submit(now: 0.5 + 8)
        expectTrue(confused.submitTags(now: 8.5).contains("numeral_confusion:6-9"))
        // T = 10: picking all ten is the right answer.
        let ten = pickQuestion(target: 10, cars: 10)
        var tenBoard = TapCountBoard(question: ten)
        for (i, bay) in ten.occupiedBays.enumerated() { _ = tenBoard.tap(bay: bay, now: Double(i)) }
        expectEqual(tenBoard.submit(now: 20), .judged(correct: true, selected: 10))
    }

    func testEraserCooldownNudgeAndHide() {
        let q = pickQuestion(target: 3, cars: 6)
        var board = TapCountBoard(question: q)
        let bay = q.occupiedBays[0]
        expectEqual(board.erase(now: 0), .unavailable, "greyed with nothing picked")
        var clock = 0.0
        var results: [TapCountErase] = []
        for _ in 0..<6 {
            clock += 1
            if !board.isTapped(bay) { _ = board.tap(bay: bay, now: clock) }
            results.append(board.erase(now: clock))
            clock += 0.5
            if results.count == 1 {
                _ = board.tap(bay: bay, now: clock)
                expectEqual(board.erase(now: clock), .coolingDown)
            }
            clock += 3
        }
        expectEqual(results, [.cleared, .cleared, .cleared, .clearedNudge, .cleared, .clearedAndHidden])
        expectFalse(board.eraserVisible)
        _ = board.tap(bay: bay, now: clock + 1)
        _ = board.submit(now: clock + 2)
        expectTrue(board.eraserVisible, "back after the next OK")
        // ★ / ★★ have no eraser and no OK.
        var all = TapCountBoard(question: TapCountGenerator.make(seed: "e", kind: .tapCountAll))
        expectEqual(all.erase(now: 0), .unavailable)
        expectEqual(all.submit(now: 0), .locked)
    }

    func testTracingNeverChangesPendingAndBoardsOnlyMoveForward() {
        let q = pickQuestion(target: 4, cars: 7)
        var board = TapCountBoard(question: q)
        let older = board
        for (i, bay) in q.occupiedBays.prefix(4).enumerated() { _ = board.tap(bay: bay, now: Double(i)) }
        expectTrue(board.isMonotonicSuccessor(of: older))
        expectFalse(older.isMonotonicSuccessor(of: board))
        _ = board.submit(now: 10)
        board.startTracing(tolerance: .wide)
        var trace = board.trace!
        var clock = 20.0
        drive(&trace, clock: &clock, offset: 30)
        board.updateTrace(trace, now: clock)
        expectTrue(board.isComplete)
        expectEqual(board.misses, 0)
        let fields = board.resultFields
        expectEqual(fields["first_try"], .int(1))
        expectEqual(fields["numeral"], .int(4))
    }

    // MARK: Default off, playtest gate, settings, perf

    func testThreeKindsDefaultOffAndNeedAPlaytestFirst() {
        for kind in kinds {
            expectTrue(ActivityCatalog.playableKinds.contains(kind))
            expectTrue(ActivityCatalog.defaultOffKinds.contains(kind))
            expectFalse(ActivityCatalog.defaultOnKinds.contains(kind))
            expectTrue(kind.isTapCountFamily)
            expectTrue(kind.requiresPlaytestBeforeStars)
            expectTrue(QuestionGeneration.isGenerated(kind))
            expectFalse(ParentPlaytestLog().allowsStars(for: kind))
            expectTrue(ParentPlaytestLog().recording(kind, on: Date()).allowsStars(for: kind))
            for star in ChildDifficulty.allCases {
                expectFalse(MissionGameAssignment.defaults.isEnabled(kind, star: star))
            }
        }
        expectEqual(ActivityKind.tapCountAll.parentCardTitle, "一架一架數 · 點一點")
        expectEqual(ActivityKind.tapCountTrace.parentCardTitle, "一架一架數 · 數完畫")
        expectEqual(ActivityKind.tapCountPick.parentCardTitle, "一架一架數 · 揀啱數")
    }

    func testSettingsDefaultsPersistAndToleranceFollowsShapeTrace() {
        let suite = "tapCount.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TapCountSettingsStore(defaults: defaults)
        expectEqual(store.load(), TapCountSettings.defaults)
        let d = TapCountSettings.defaults
        expectEqual(d.range, .upTo10)
        expectTrue(d.countVoice && d.english)
        expectEqual(d.badgeStyle, .numbers)
        expectEqual(d.traceScaffold, .dots)
        expectNil(d.tolerance)
        let changed = TapCountSettings(range: .upTo5, countVoice: false, english: false, badgeStyle: .ticks,
                                       traceScaffold: .outline, tolerance: .wide)
        store.save(changed)
        expectEqual(store.load(), changed)
        defaults.set(Data("junk".utf8), forKey: TapCountSettingsStore.key)
        expectEqual(store.load(), .defaults)
        let shape = ShapeTraceSettings(tolerance: .narrow)
        expectEqual(d.effectiveTolerance(shapeTrace: shape, lineMatch: .wide), .narrow)
        expectEqual(d.effectiveTolerance(shapeTrace: ShapeTraceSettings(), lineMatch: .wide), .wide)
        expectEqual(changed.effectiveTolerance(shapeTrace: shape, lineMatch: .standard), .wide)
    }

    func testOnlyPickIsMasteryEvidence() {
        let pick = TapCountGenerator.make(seed: "m", kind: .tapCountPick)
        let facts = PerfChoiceCatalog.facts(tapCount: pick, settings: .defaults, tolerance: .standard, recentTargets: [3])
        expectEqual(facts.chance, 1 / Double(pick.count), accuracy: 1e-9)
        expectEqual(facts.correctChoice, "submit")
        expectEqual(facts.extraDealtFields["match_mode"], .string("free"))
        for kind in [ActivityKind.tapCountAll, .tapCountTrace] {
            let q = TapCountGenerator.make(seed: "m", kind: kind)
            let f = PerfChoiceCatalog.facts(tapCount: q, settings: .defaults, tolerance: .standard, recentTargets: [])
            expectEqual(f.chance, 1, accuracy: 1e-9)
            expectNil(f.correctChoice)
            expectEqual(f.extraDealtFields["match_mode"], .string("guided"))
        }
    }

    // MARK: Copy

    func testCopyIsHongKongTraditionalAndASCIIEnglish() {
        // Simplified forms (design §11.4) plus 这/這 (written-Mandarin "this"; Cantonese uses 呢).
        let simplified = ["数", "车", "点", "个", "写", "对", "错", "齐", "随", "机", "闪", "颜", "号", "两", "开", "关", "设",
                          "笔", "划", "顺", "边", "张", "双", "样", "读", "声", "试", "为", "们", "时", "从", "发", "后", "会",
                          "动", "还", "进", "过", "头", "画", "线", "圆", "这", "這", "么", "吗", "里"]
        let lines = TapCountCopy.allTraditionalLines
        expectTrue(lines.count > 200)
        for line in lines {
            for ch in simplified { expectFalse(line.contains(ch), "simplified \(ch) in \(line)") }
        }
        for line in TapCountCopy.allEnglishLines {
            // ASCII, plus the catalog's middle-dot separator (「Tap & Count · Tap each one」).
            expectTrue(line.unicodeScalars.allSatisfy { $0.isASCII || $0 == "·" }, "ASCII English: \(line)")
            expectFalse(line.isEmpty)
        }
        expectEqual(TapCountCopy.allPrompt(.tramDepot).traditionalChinese, "點一點每架叮叮！")
        expectEqual(TapCountCopy.pickPrompt(3).traditionalChinese, "點 3 架車，再撳 OK！")
        expectEqual(TapCountCopy.recount(4).traditionalChinese, "一、二、三、四。四架。")
        expectEqual(TapCountCopy.cue(3, english: true), "三、three")
        expectEqual(TapCountCopy.donePrompt(4, scene: .tramDepot).english, "Well done! Four trams!")
    }

    // MARK: App wiring

    func testAppWiringSourceGuards() throws {
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let host = try source("Sources/VisaGames/CanvasActivityHost.swift")
        expectTrue(host.contains("case .tapCountAll, .tapCountTrace, .tapCountPick:"))
        let view = try source("Sources/VisaGames/TapCountBoardView.swift")
        expectFalse(view.contains("assumeIsolated"))
        expectFalse(view.contains("unowned"))
        expectFalse(view.contains("presentationOptions"))
        expectFalse(view.contains("styleMask"))
        expectTrue(view.contains("ThinkPauseOverlay"))
        // v0.28.1: taps go through one target per vehicle on the shared stage rect, never through a
        // hand-converted point from a workspace overlay (the v0.28.0 one-row shift).
        expectTrue(view.contains("TapCountVehicleLayout.hitTargets(question)"))
        expectTrue(view.contains(".canvasPlaced(x: CGFloat(r.x), y: CGFloat(r.y))"))
        expectTrue(view.contains("view.onTap(bay)"))
        expectFalse(view.contains("bay(at:"), "no coordinate hit test in the view")
        expectTrue(view.contains("TapCountVehicleLayout.scale(model, layout: layout)"), "drawing shares the tap-target scale")
        expectTrue(view.contains("y: point.y / scale + Self.workspaceTop"), "pen points include the workspace top")
        expectFalse(model.contains("question.bay(at:"), "the model takes the tapped bay, not a point")
        let speech = try source("Sources/VisaGames/SystemSpeechPrompt.swift")
        expectTrue(speech.contains("func speakQueued"))
        expectTrue(model.contains("tapCountSettingsStore.save"))
        expectTrue(model.contains("TapCountGenerator.make("))
        let checklist = try source("docs/phase-0-kiosk-checklist.md")
        expectTrue(checklist.contains("一架一架數"))
    }
}
