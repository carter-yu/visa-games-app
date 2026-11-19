import Foundation
import VisaCore

/// 畫直線・四方 R1 (four-direction design §5–§6, §11.3): connected coverage for every variant (T7–T12, T15, T18),
/// guidance bounded by G = L − 15.5 (T4a, T14), the held finish (T16, pure part), 識咗 per oriented variant (T19), the
/// dealt snapshot (T20, pure part) and no copied mastery (T21).
final class OrientedLineEngineTests {
    private static let variants = OrientedLineVariant.allCases

    /// A round of `variants` on the standard middle footprints (or the longest horizontal one).
    static func question(_ variants: [OrientedLineVariant], tolerance: LineMatchTolerance = .standard,
                         help: TapCountGuidanceLevel = .standard, long: Bool = false) -> OrientedLineQuestion {
        let lines = variants.map { v in
            OrientedLine(variant: v, footprint: v.isHorizontal
                ? (long ? .horizontal(left: 0, right: 2, row: 1) : .horizontal(left: 1, right: 1, row: 1)) : .diagonal(1))
        }
        let shape: OrientedLineShapeSetting = variants.allSatisfy(\.isHorizontal) ? .across
            : variants.allSatisfy { !$0.isHorizontal } ? .diagonal : .both
        let direction: OrientedLineDirectionSetting = variants.allSatisfy(\.isRightward) ? .rightward
            : variants.allSatisfy { !$0.isRightward } ? .leftward : .both
        let settings = OrientedLineSettings(lineShape: shape, lineDirection: direction, lineHelp: help, tolerance: tolerance)
        return OrientedLineQuestion(itemID: OrientedLineGenerator.itemID(shape: shape, direction: direction, lines: lines),
                                    dealt: settings, lines: lines)
    }

    /// P0 + s·u + d·n.
    static func at(_ line: OrientedLine, _ s: Double, _ d: Double = 0) -> LineMatchPoint {
        let u = line.unit, n = line.normal
        return LineMatchPoint(x: line.start.x + u.x * s + n.x * d, y: line.start.y + u.y * s + n.y * d)
    }

    /// The pen moves from s0 to s1 (either way) in steps of `step`; stops at a finished line.
    @discardableResult
    static func sweep(_ board: inout OrientedLineBoard, _ line: OrientedLine, from s0: Double, to s1: Double,
                      step: Double = 8, d: Double = 0, clock: inout Double) -> [OrientedLineMove] {
        var moves: [OrientedLineMove] = []
        var s = s0
        let forward = s1 >= s0
        while forward ? s < s1 : s > s1 {
            s = forward ? min(s + step, s1) : max(s - step, s1)
            clock += 0.016
            let move = board.penMove(to: at(line, s, d), now: clock)
            moves.append(move)
            if case .lineDone = move { break }
            if move == .allDone { break }
        }
        return moves
    }

    /// A help's numbers, compared within 1e-6 (positions come from projections).
    static func expectHelp(_ help: OrientedLineHelp, _ expected: OrientedLineHelp, file: StaticString = #file,
                           line: UInt = #line) {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }
        switch (help, expected) {
        case let (.pause(a, b, c), .pause(x, y, z)), let (.ghostToEnd(a, b, c), .ghostToEnd(x, y, z)):
            precondition(near(a, x) && near(b, y) && near(c, z), "\(help) ≠ \(expected)", file: file, line: line)
        case let (.ring(k, a, b, c), .ring(m, x, y, z)):
            precondition(k == m && near(a, x) && near(b, y) && near(c, z), "\(help) ≠ \(expected)", file: file, line: line)
        case let (.redemo(a), .redemo(x)):
            precondition(near(a, x), "\(help) ≠ \(expected)", file: file, line: line)
        case (.none, .none):
            break
        default:
            preconditionFailure("\(help) ≠ \(expected)", file: file, line: line)
        }
    }

    /// From the green sign (joined) to F = `to`.
    static func drawTo(_ board: inout OrientedLineBoard, _ to: Double, clock: inout Double) {
        guard let line = board.currentLine else { return }
        expectEqual(board.penDown(at: line.greenSign, now: clock), .joined)
        sweep(&board, line, from: -130, to: to, clock: &clock)
    }

    // MARK: T7, T8, T10

    func testEndpointsOnlyAndCounterexamplesForEveryVariant() {
        var cases = 0
        for v in Self.variants {
            for tolerance in LineMatchTolerance.allCases {
                let q = Self.question([v, v, v], tolerance: tolerance)
                let line = q.lines[0]
                let h = q.halfWidth
                let L = line.length
                var clock = 0.0
                // T7: green sign, lift, red sign → refused; green sign, then one jump to the bar → a gap break.
                var b = OrientedLineBoard(question: q)
                expectEqual(b.penDown(at: line.greenSign, now: clock), .joined)
                b.penUp()
                expectEqual(b.penDown(at: line.redSign, now: clock), .refusedReverse)
                expectEqual(b.penMove(to: Self.at(line, L - 5), now: clock), .ignored)
                b.penUp()
                expectEqual(b.penDown(at: line.greenSign, now: clock), .joined)
                expectEqual(b.penMove(to: Self.at(line, L), now: clock + 0.1), .segmentEnded(.gap))
                expectEqual(b.segment, .unjoined)
                expectEqual(b.frontier, 0)
                expectFalse(b.isDone(line: 0))
                // #1 off-road skip: to 60, out sideways, back in at 200 and on to the bar → F = 60.
                b = OrientedLineBoard(question: q)
                Self.drawTo(&b, 60, clock: &clock)
                expectEqual(b.frontier, 60, accuracy: 1e-9)
                expectEqual(b.penMove(to: Self.at(line, 70, h + 10), now: clock), .segmentEnded(.offRoad))
                expectEqual(b.penMove(to: Self.at(line, 120, h + 10), now: clock), .neutral)
                expectEqual(b.offPathCount, 1, "one exit, counted once")
                expectEqual(b.penMove(to: Self.at(line, 200), now: clock), .neutral)
                Self.sweep(&b, line, from: 200, to: L + 5, clock: &clock)
                expectEqual(b.frontier, 60, accuracy: 1e-9)
                expectFalse(b.isDone(line: 0))
                // #9 neutral recovery: the car's body, then forward → done; F never went down.
                b.penUp()
                expectEqual(b.penDown(at: Self.at(line, 60 - 30), now: clock), .joined)
                let beforeRecovery = b
                Self.sweep(&b, line, from: 30, to: L, clock: &clock)
                expectTrue(b.isDone(line: 0))
                expectTrue(b.isMonotonicSuccessor(of: beforeRecovery))
                expectFalse(beforeRecovery.isMonotonicSuccessor(of: b), "a stale copy cannot undo a finished line")
                // #2 lift and touch ahead: to 60, lift, touch at 150 and sweep on → unjoined, F = 60.
                b = OrientedLineBoard(question: q)
                Self.drawTo(&b, 60, clock: &clock)
                b.penUp()
                expectEqual(b.lifts, 1)
                expectEqual(b.penDown(at: Self.at(line, 150), now: clock), .unjoined)
                Self.sweep(&b, line, from: 150, to: L + 5, clock: &clock)
                expectEqual(b.frontier, 60, accuracy: 1e-9)
                // #3 repeated grabs from ahead: F stays 0.
                b = OrientedLineBoard(question: q)
                for _ in 0..<3 {
                    expectEqual(b.penDown(at: Self.at(line, 90), now: clock), .unjoined)
                    Self.sweep(&b, line, from: 90, to: 200, clock: &clock)
                    b.penUp()
                }
                expectEqual(b.frontier, 0)
                expectEqual(b.unjoinedSegments, 3)
                expectEqual(b.lifts, 0)
                // #4 tap-hopping on the car and 1 u ahead: F never moves.
                b = OrientedLineBoard(question: q)
                Self.drawTo(&b, 100, clock: &clock)
                b.penUp()
                for _ in 0..<4 {
                    expectEqual(b.penDown(at: Self.at(line, 80), now: clock), .joined)
                    expectEqual(b.penMove(to: Self.at(line, 80), now: clock), .neutral)
                    b.penUp()
                    expectEqual(b.penDown(at: Self.at(line, 101), now: clock), .unjoined)
                    expectEqual(b.penMove(to: Self.at(line, 101), now: clock), .neutral)
                    b.penUp()
                }
                expectEqual(b.frontier, 100, accuracy: 1e-9)
                // #5 cancel, then ahead: unjoined, F = 100; a cancel is not a lift.
                b = OrientedLineBoard(question: q)
                Self.drawTo(&b, 100, clock: &clock)
                b.cancelStroke()
                expectEqual(b.lifts, 0)
                expectEqual(b.penDown(at: Self.at(line, 150), now: clock), .unjoined)
                Self.sweep(&b, line, from: 150, to: 260, clock: &clock)
                expectEqual(b.frontier, 100, accuracy: 1e-9)
                // #6 a single jump of 300 u ends the segment; the far part never joins.
                b = OrientedLineBoard(question: q)
                Self.drawTo(&b, 20, clock: &clock)
                expectEqual(b.penMove(to: Self.at(line, 320), now: clock), .segmentEnded(.gap))
                Self.sweep(&b, line, from: 320, to: L + 5, clock: &clock)
                expectEqual(b.frontier, 20, accuracy: 1e-9)
                expectEqual(b.segmentGaps, 1)
                // #10 repeated small gaps from the start: F = 0.
                b = OrientedLineBoard(question: q)
                var s = 6.0
                while s < 120 {
                    expectEqual(b.penDown(at: Self.at(line, s), now: clock), .unjoined)
                    expectEqual(b.penMove(to: Self.at(line, s + 6), now: clock), .neutral)
                    b.penUp()
                    s += 12
                }
                expectEqual(b.frontier, 0)
                // … and after a joined sweep to F = 12: lift + touch at 13, off-road + re-entry at 18, cancel + touch at 18.
                b = OrientedLineBoard(question: q)
                expectEqual(b.penDown(at: Self.at(line, -20), now: clock), .joined)
                Self.sweep(&b, line, from: -20, to: 12, step: 4, clock: &clock)
                b.penUp()
                expectEqual(b.penDown(at: Self.at(line, 13), now: clock), .unjoined)
                Self.sweep(&b, line, from: 13, to: 40, step: 4, clock: &clock)
                b.penUp()
                expectEqual(b.penDown(at: Self.at(line, 0), now: clock), .joined)
                expectEqual(b.penMove(to: Self.at(line, 5, h + 20), now: clock), .segmentEnded(.offRoad))
                expectEqual(b.penMove(to: Self.at(line, 18), now: clock), .neutral)
                Self.sweep(&b, line, from: 18, to: 40, step: 4, clock: &clock)
                b.penUp()
                expectEqual(b.penDown(at: Self.at(line, 0), now: clock), .joined)
                b.cancelStroke()
                expectEqual(b.penDown(at: Self.at(line, 18), now: clock), .unjoined)
                Self.sweep(&b, line, from: 18, to: 40, step: 4, clock: &clock)
                expectEqual(b.frontier, 12, accuracy: 1e-9)
                // #11 retroactive completion (90 → finish → 0) in four forms: F = 0 and the sweep's ink stays faded.
                for form in 0..<4 {
                    b = OrientedLineBoard(question: q)
                    expectEqual(b.penDown(at: Self.at(line, 90), now: clock), .unjoined)
                    Self.sweep(&b, line, from: 90, to: L + 5, clock: &clock)
                    expectEqual(b.frontier, 0)
                    switch form {
                    case 0: Self.sweep(&b, line, from: L + 5, to: -10, clock: &clock)
                    case 1: Self.sweep(&b, line, from: L + 5, to: -130, clock: &clock)
                    case 2:
                        expectEqual(b.penMove(to: Self.at(line, L, h + 10), now: clock), .segmentEnded(.offRoad))
                        expectEqual(b.penMove(to: Self.at(line, -40, h + 10), now: clock), .neutral)
                        expectEqual(b.penMove(to: Self.at(line, -40), now: clock), .joined)
                    default:
                        b.penUp()
                        expectEqual(b.penDown(at: line.greenSign, now: clock), .joined)
                    }
                    expectEqual(b.segment, .joined)
                    expectEqual(b.frontier, 0)
                    expectFalse(b.isDone(line: 0))
                    let before = b.ink[0].flatMap { $0 }
                    let faded = before.filter { !$0.counted }.count
                    expectTrue(faded >= 30, "the unjoined sweep left faded ink")
                    // Render assertion (R3 m2): joining never recolours; the later joined sweep is normal navy.
                    Self.sweep(&b, line, from: form == 1 || form == 3 ? -130 : (form == 2 ? -40 : -10), to: 60,
                               clock: &clock)
                    let after = b.ink[0].flatMap { $0 }
                    expectEqual(Array(after.prefix(before.count)), before)
                    expectTrue(after.dropFirst(before.count).allSatisfy(\.counted))
                    expectEqual(after.filter { !$0.counted }.count, faded)
                    expectEqual(b.frontier, 60, accuracy: 1e-9)
                }
                // #12 positive control: the car's body, then forward → done on the first sample at L − 10.
                b = OrientedLineBoard(question: q)
                expectEqual(b.penDown(at: Self.at(line, -30), now: clock), .joined)
                let moves = Self.sweep(&b, line, from: -30, to: L, step: 3, clock: &clock)
                expectEqual(moves.last, .lineDone(0))
                expectTrue(moves.dropLast().allSatisfy { $0 == .earned || $0 == .neutral })
                expectTrue(b.isDone(line: 0))
                expectEqual(b.lineIndex, 1)
                expectEqual(b.frontier, 0)
                expectEqual(b.segment, .finished)
                expectEqual(b.penMove(to: Self.at(b.lines[1], 30), now: clock), .ignored, "the next line needs its own touch")
                cases += 1
            }
        }
        print("  畫直線・四方 T7 / T8: endpoints only and counterexamples #1–#6, #9–#12 for → ← ↗ ↙ at 3 tolerances (\(cases) runs); pre-join ink stays faded")
    }

    func testBacktrackIsNeutralAndOnlyLateralExitsCount() {
        for v in Self.variants {
            let q = Self.question([v, v, v])
            let line = q.lines[0]
            var b = OrientedLineBoard(question: q)
            var clock = 0.0
            Self.drawTo(&b, 220, clock: &clock)
            // Δs < 0 is neutral whatever the screen direction (on ← and ↙ that is moving right / up-right).
            let back = Self.sweep(&b, line, from: 220, to: 40, clock: &clock)
            expectTrue(back.allSatisfy { $0 == .neutral })
            expectEqual(b.frontier, 220, accuracy: 1e-9)
            expectEqual(b.offPathCount, 0)
            expectEqual(b.segment, .joined)
            // Forward again from behind the car earns only past F.
            let ahead = Self.sweep(&b, line, from: 40, to: 260, clock: &clock)
            // 224, 232, 240, 248, 256 and 260 pass F = 220; 48 … 216 are behind it.
            expectEqual(ahead.filter { $0 == .earned }.count, 6)
            expectEqual(ahead.filter { $0 == .neutral }.count, 22)
            expectEqual(b.frontier, 260, accuracy: 1e-9)
            // A lateral exit is counted once however long the pen stays out; past the sign centre is not lateral.
            expectEqual(b.penMove(to: Self.at(line, 262, q.halfWidth + 1), now: clock), .segmentEnded(.offRoad))
            for k in 0..<5 { expectEqual(b.penMove(to: Self.at(line, 262 + Double(k), q.halfWidth + 30), now: clock), .neutral) }
            expectEqual(b.offPathCount, 1)
            expectEqual(b.penMove(to: Self.at(line, 250), now: clock), .joined)
            Self.sweep(&b, line, from: 250, to: -125, clock: &clock)
            // Behind the green sign's disc (60 u past its centre, on the axis): not a lateral exit.
            expectEqual(b.penMove(to: Self.at(line, -190, 0), now: clock), .segmentEnded(.beyondEnd))
            expectEqual(b.offPathCount, 1)
            // Screen direction never matters: the same pen path read on the reverse twin is the mirror in s.
            let screenLeft = line.unit.x < 0
            expectEqual(screenLeft, !v.isRightward)
        }
        print("  畫直線・四方 T10: backtracking (Δs < 0) is neutral on → ← ↗ ↙; one lateral exit counts once; past the sign centre is not off-path")
    }

    // MARK: T9, T11, T18

    func testRedEndRefusalsAndPaintedSignTargets() {
        var probes = 0
        for v in Self.variants {
            for tolerance in LineMatchTolerance.allCases {
                let q = Self.question([v, v, v], tolerance: tolerance)
                let line = q.lines[0]
                var clock = 0.0
                // T9: the red sign or finish zone at F < 10 → a reversal; mid-line → an early finish; both inert.
                var b = OrientedLineBoard(question: q)
                expectEqual(b.penDown(at: line.redSign, now: clock), .refusedReverse)
                Self.sweep(&b, line, from: line.length + 130, to: 0, clock: &clock)
                expectEqual(b.frontier, 0, "never driven backwards from red")
                b.penUp()
                expectEqual(b.penDown(at: Self.at(line, line.length - 5), now: clock), .refusedReverse)
                b.penUp()
                expectEqual([b.reverseDirections, b.wrongStarts, b.earlyFinishTaps], [2, 2, 0])
                Self.drawTo(&b, line.length / 2, clock: &clock)
                b.penUp()
                expectEqual(b.penDown(at: Self.at(line, line.length - 9), now: clock), .refusedEarlyFinish)
                expectEqual(b.penMove(to: Self.at(line, line.length), now: clock), .ignored)
                b.penUp()
                expectEqual(b.penDown(at: line.redSign, now: clock), .refusedEarlyFinish)
                b.penUp()
                expectEqual([b.reverseDirections, b.wrongStarts, b.earlyFinishTaps], [4, 4, 2])
                expectEqual(b.frontier, line.length / 2, accuracy: 1e-9)
                expectFalse(b.isDone(line: 0))
                // A joined segment that slides into the bar finishes normally.
                expectEqual(b.penDown(at: Self.at(line, line.length / 2 - 10), now: clock), .joined)
                Self.sweep(&b, line, from: line.length / 2 - 10, to: line.length, clock: &clock)
                expectTrue(b.isDone(line: 0))
                // T18: painted targets — r 46.5 u is on the sign in all 8 directions; at 48 u only the corridor rules
                // apply (in the band toward the line, outside beyond the sign centre).
                for k in 0..<8 {
                    let theta = (22.5 + 45 * Double(k)) * Double.pi / 180
                    for (sign, inward) in [(line.greenSign, 1.0), (line.redSign, -1.0)] {
                        for radius in [46.5, 48] {
                            let u = line.unit, n = line.normal
                            let p = LineMatchPoint(x: sign.x + radius * (cos(theta) * u.x + sin(theta) * n.x),
                                                   y: sign.y + radius * (cos(theta) * u.y + sin(theta) * n.y))
                            var probe = OrientedLineBoard(question: q)
                            let result = probe.penDown(at: p, now: 0)
                            let onDisc = radius < 47
                            let inBand = cos(theta) * inward > 0
                            let green = inward > 0
                            let expected: OrientedLinePenDown = onDisc || inBand
                                ? (green ? .joined : .refusedReverse) : .outside
                            expectEqual(result, expected, "\(v) \(green ? "green" : "red") r \(radius) at \(k)")
                            probes += 1
                        }
                    }
                }
                // M25: green is drawn and hit at the actual start (left, right, lower-left, upper-right).
                switch v {
                case .right: expectTrue(line.greenSign.x < line.redSign.x)
                case .left: expectTrue(line.greenSign.x > line.redSign.x)
                case .upRight: expectTrue(line.greenSign.x < line.redSign.x && line.greenSign.y > line.redSign.y)
                case .downLeft: expectTrue(line.greenSign.x > line.redSign.x && line.greenSign.y < line.redSign.y)
                }
            }
        }
        // T11: lines not yet shown never refuse: only the current line's own ends count.
        let q = Self.question([.right, .downLeft, .left])
        var b = OrientedLineBoard(question: q)
        expectEqual(b.penDown(at: q.lines[1].redSign, now: 0), .outside)
        b.penUp()
        expectEqual(b.penDown(at: q.lines[1].greenSign, now: 0), .outside)
        b.penUp()
        // Line 3's red sign (←) is line 1's green start (→): it joins line 1.
        expectEqual(b.penDown(at: q.lines[2].redSign, now: 0), .joined)
        expectEqual(b.wrongStarts, 0)
        print("  畫直線・四方 T9 / T11 / T18: red end refused (reverse at F < 10, early finish mid-line), inert, never backwards; \(probes) painted-target probes; later lines never refuse")
    }

    // MARK: T12, T15

    func testTerminalArrivalAndSampledInput() {
        for v in Self.variants {
            for long in [false, true] {
                let q = Self.question([v, v, v], long: long)
                let line = q.lines[0]
                let L = line.length
                var clock = 0.0
                // Traced to L − 11 and lifted: not done (a 97 % or slack rule would finish the 630 u line here).
                var b = OrientedLineBoard(question: q)
                Self.drawTo(&b, L - 11, clock: &clock)
                b.penUp()
                expectFalse(b.isDone(line: 0))
                expectEqual(b.frontier, L - 11, accuracy: 1e-9)
                // Done iff a joined forward sample makes F ≥ L − 10, on that sample only (±0.001 u around C).
                expectEqual(b.penDown(at: Self.at(line, L - 40), now: clock), .joined)
                expectEqual(b.penMove(to: Self.at(line, L - 10.001), now: clock), .earned)
                expectFalse(b.isDone(line: 0))
                expectEqual(b.penMove(to: Self.at(line, L - 9.999), now: clock), .lineDone(0))
                // An unjoined sweep into the chequers never finishes.
                b = OrientedLineBoard(question: q)
                Self.drawTo(&b, 100, clock: &clock)
                b.penUp()
                expectEqual(b.penDown(at: Self.at(line, 101), now: clock), .unjoined)
                Self.sweep(&b, line, from: 101, to: L + 20, step: 5, clock: &clock)
                expectFalse(b.isDone(line: 0))
                // T15: joined samples 140 u apart complete.
                b = OrientedLineBoard(question: q)
                expectEqual(b.penDown(at: line.greenSign, now: clock), .joined)
                var s = -130.0
                var finished = false
                while !finished {
                    s += 140
                    let move = b.penMove(to: Self.at(line, min(s, L)), now: clock)
                    if move == .lineDone(0) { finished = true }
                    expectTrue(move == .earned || move == .lineDone(0), "\(move)")
                }
                expectEqual(b.maxSampleGap, 140, accuracy: 1e-6)
                // A joined 150 u step credits only the part beyond F; a 151 u step breaks; unjoined sweeps earn nothing.
                b = OrientedLineBoard(question: q)
                Self.drawTo(&b, 100, clock: &clock)
                Self.sweep(&b, line, from: 100, to: 40, clock: &clock)
                // 149.999 u from s 40 (150 within rounding): valid, and F gains only 89.999 (from 100).
                expectEqual(b.penMove(to: Self.at(line, 189.999), now: clock), .earned)
                expectEqual(b.frontier, 189.999, accuracy: 1e-9)
                expectEqual(b.penMove(to: Self.at(line, 341), now: clock), .segmentEnded(.gap))
                expectEqual(b.frontier, 189.999, accuracy: 1e-9)
                expectEqual(b.segment, .unjoined)
                b.penUp()
                expectEqual(b.penDown(at: Self.at(line, 240), now: clock), .unjoined)
                var t = 240.0
                while t + 140 < L {
                    t += 140
                    expectEqual(b.penMove(to: Self.at(line, t), now: clock), .neutral)
                }
                expectEqual(b.frontier, 189.999, accuracy: 1e-9)
            }
        }
        print("  畫直線・四方 T12 / T15: done only on the joined sample reaching L − 10 (not at L − 11, not unjoined, also at L 630); 140 u samples complete, 150 u credits only past F, 151 u breaks")
    }

    // MARK: T4a, T14 guidance

    func testGuidanceStaysBeforeTheFinishBar() {
        var checks = 0
        for v in Self.variants {
            for long in [false, true] {
                let q = Self.question([v, v, v], long: long)
                let line = q.lines[0]
                let L = line.length
                let G = L - 15.5
                for (F, ghostShown) in [(L - 200, true), (L - 60, true), (L - 35.5, true), (L - 30, false), (L - 12, false)] {
                    var b = OrientedLineBoard(question: q)
                    var tally = OrientedLineGuideTally(question: q)
                    tally.startLine(learned: true, now: 0, demoLead: 0)
                    var clock = 1.0
                    Self.drawTo(&b, F, clock: &clock)
                    expectEqual(b.frontier, F, accuracy: 1e-9)
                    expectFalse(b.isDone(line: 0))
                    let plan = OrientedLineCoach.plan(level: .standard, learned: true)
                    expectTrue(plan.headlights && !plan.demo)
                    let still = clock + 2.05
                    let help = OrientedLineCoach.help(plan: plan, run: tally.run!, board: b, now: still)
                    let statics = OrientedLineCoach.staticChevrons(line: line, frontier: F)
                    let lights = OrientedLineCoach.headlights(plan: plan, line: line, frontier: F)
                    let bigs = OrientedLineCoach.pauseChevrons(line: line, frontier: F)
                    let glow = OrientedLineCoach.glow(line: line, frontier: F)
                    if F >= G {
                        // Past the near rail: no guidance at all, and not done until F ≥ L − 10.
                        expectEqual(help, .none)
                        expectTrue(statics.isEmpty && lights.isEmpty && bigs.isEmpty && glow == nil)
                        continue
                    }
                    let T = min(F + 180, G)
                    Self.expectHelp(help, .pause(from: F, to: T, since: clock + 2))
                    expectEqual(glow?.lowerBound ?? -1, F, accuracy: 1e-6)
                    expectEqual(glow?.upperBound ?? -1, T, accuracy: 1e-6)
                    expectTrue((glow?.upperBound ?? .infinity) <= G + 1e-9, "the glow's butt end stops at G")
                    for c in statics {
                        expectTrue(c - 13 >= F && c + 13 <= G, "static chevron paint within [F, G]")
                    }
                    for c in lights { expectTrue(c - 15 >= F && c + 15 <= G, "headlight paint within [F, G]") }
                    expectTrue(lights.count <= 3)
                    for c in bigs { expectTrue(c - 20.8 >= F - 1e-9 && c + 20.8 <= T + 1e-9, "pause chevron within [F, T]") }
                    // The ghost's frontmost paint runs forward from F to T ≤ G; omitted when T − F < 20.
                    var fronts: [Double] = []
                    for step in 0...14 {
                        if let g = OrientedLineCoach.ghost(help, line: line, now: clock + 2 + Double(step) * 0.1) {
                            expectTrue(g.front >= F - 1e-9 && g.front <= T + 1e-9 && g.front <= G + 1e-9)
                            expectEqual(g.nose, g.front - 1.35, accuracy: 1e-9)
                            fronts.append(g.front)
                        }
                    }
                    expectEqual(!fronts.isEmpty, ghostShown, "ghost at F = L − \(L - F)")
                    expectEqual(fronts, fronts.sorted(), "forward only")
                    if ghostShown { expectEqual(fronts.last ?? 0, T, accuracy: 1e-6) }
                    // Ghost to the finish (8 s at 標準): its frontmost paint ends at G, never inside the bar.
                    let late = OrientedLineCoach.help(plan: plan, run: tally.run!, board: b, now: clock + 8.5)
                    if G - F >= 20 - 1e-9 {
                        Self.expectHelp(late, .ghostToEnd(from: F, to: G, since: clock + 8))
                        var last = -Double.infinity
                        for step in 0...30 {
                            if let g = OrientedLineCoach.ghost(late, line: line, now: clock + 8 + Double(step) * 0.05) {
                                expectTrue(g.front <= G + 1e-9 && g.front >= last)
                                last = g.front
                            }
                        }
                        expectEqual(last, G, accuracy: 1e-6)
                        expectNil(OrientedLineCoach.ghost(late, line: line, now: clock + 8 + 60))
                    } else {
                        // Less than 20 u left: no ghost to the finish; the pause stays glow-only, with no ghost.
                        Self.expectHelp(late, .pause(from: F, to: T, since: clock + 2))
                        expectNil(OrientedLineCoach.ghost(late, line: line, now: clock + 8.6))
                    }
                    checks += 1
                }
                // Lifted mid-line: nothing at first, the ghost to the finish after the ghost time.
                var b = OrientedLineBoard(question: q)
                var tally = OrientedLineGuideTally(question: q)
                tally.startLine(learned: true, now: 0, demoLead: 0)
                var clock = 1.0
                Self.drawTo(&b, 100, clock: &clock)
                b.penUp()
                let plan = OrientedLineCoach.plan(level: .standard, learned: true)
                expectEqual(OrientedLineCoach.help(plan: plan, run: tally.run!, board: b, now: clock + 3), .none)
                Self.expectHelp(OrientedLineCoach.help(plan: plan, run: tally.run!, board: b, now: clock + 8.1),
                                .ghostToEnd(from: 100, to: G, since: clock + 8))
                Self.expectHelp(OrientedLineCoach.help(plan: plan, run: tally.run!, board: b, now: clock + 20.1),
                                .redemo(since: clock + 20))
                // 少啲: no pause help and no headlights; 多啲: pause after 1 s.
                var down = OrientedLineBoard(question: q)
                var c2 = 1.0
                Self.drawTo(&down, 100, clock: &c2)
                let less = OrientedLineCoach.plan(level: .less, learned: false)
                expectEqual(OrientedLineCoach.help(plan: less, run: tally.run!, board: down, now: c2 + 3), .none)
                expectTrue(OrientedLineCoach.headlights(plan: less, line: line, frontier: 100).isEmpty)
                let more = OrientedLineCoach.plan(level: .more, learned: true)
                Self.expectHelp(OrientedLineCoach.help(plan: more, run: tally.run!, board: down, now: c2 + 1.05),
                                .pause(from: 100, to: 280, since: c2 + 1))
                // Not joined for 2 s: the ring (no trail) with the forward arrow; off the road: the ring with trace.offroad.
                var away = OrientedLineBoard(question: q)
                _ = away.penDown(at: Self.at(line, 150), now: 50)
                expectEqual(OrientedLineCoach.help(plan: plan, run: tally.run!, board: away, now: 51.9), .none)
                Self.expectHelp(OrientedLineCoach.help(plan: plan, run: tally.run!, board: away, now: 52.1),
                                .ring(.notJoined, from: 0, to: 180, since: 52))
                var road = OrientedLineBoard(question: q)
                var c3 = 60.0
                Self.drawTo(&road, 100, clock: &c3)
                _ = road.penMove(to: Self.at(line, 110, q.halfWidth + 40), now: 70)
                expectEqual(road.away(now: 72.1), .offRoad)
            }
        }
        print("  畫直線・四方 T4a: \(checks) near-finish cases × → ← ↗ ↙ — glow, chevrons, headlights and the ghost's frontmost paint within [F, G = L − 15.5]; ghost omitted below 20 u; nothing past the near rail")
    }

    func testDemoRouteAndTouchSkip() {
        for v in Self.variants {
            let q = Self.question([v, v, v])
            let line = q.lines[0]
            let G = line.length - 15.5
            // The demo's own route: parked at the green start (nose at 0), forward until its frontmost paint is at G.
            expectEqual(OrientedLineCoach.demoGhost(line: line, t: 0).nose, 0, accuracy: 1e-9)
            expectEqual(OrientedLineCoach.demoGhost(line: line, t: 1.4).front, G, accuracy: 1e-9)
            expectEqual(OrientedLineCoach.demoGhost(line: line, t: 0, reduceMotion: true).front, G, accuracy: 1e-9)
            var previous = -Double.infinity
            for step in 0...40 {
                let g = OrientedLineCoach.demoGhost(line: line, t: Double(step) * 0.05)
                expectTrue(g.front <= G + 1e-9 && g.front >= previous)
                previous = g.front
            }
            expectEqual(OrientedLineCoach.demoRoute(line: line).lowerBound, 0)
            expectEqual(OrientedLineCoach.demoRoute(line: line).upperBound, G, accuracy: 1e-9)
            // Demo policy per level: 多啲 always, 標準 until 識咗, 少啲 never; a touch during the demo is swallowed.
            expectTrue(OrientedLineCoach.plan(level: .more, learned: true).demo)
            expectTrue(OrientedLineCoach.plan(level: .standard, learned: false).demo)
            expectFalse(OrientedLineCoach.plan(level: .standard, learned: true).demo)
            expectFalse(OrientedLineCoach.plan(level: .less, learned: false).demo)
            var tally = OrientedLineGuideTally(question: q)
            tally.startLine(learned: false, now: 10, demoLead: 0.5)
            let board = OrientedLineBoard(question: q)
            expectTrue(tally.touch(now: 10.8), "the first touch ends the demo and is swallowed")
            expectFalse(tally.touch(now: 10.9))
            expectEqual(board, OrientedLineBoard(question: q), "the demo never touches the board")
            expectEqual(tally.resultFields["demo"], .string("skipped"))
            expectEqual(tally.resultFields["guide_level"], .string("standard"))
            expectTrue(tally.currentClean, "a demo is not help")
            // An on-demand demo counts as help; the coach's idle re-demo plays the demo again.
            tally.demoOnDemand(now: 20, lead: 0.3)
            expectFalse(tally.currentClean)
            tally.redemo(now: 40, lead: 0.5)
            expectEqual(tally.resultFields["redemos"], .int(2))
            expectEqual(tally.resultFields["demos"], .int(3))
            expectTrue(tally.run?.demoPending(now: 40.6) == true)
        }
        print("  畫直線・四方 T14: the demo runs on its own route from the parked start to G for → ← ↗ ↙; a touch ends it unpainted; on-demand demos count as help")
    }

    // MARK: T16 (pure), T19, T20 (pure), T21

    func testHeldFinishStampsOnceForForwardAndReverse() {
        for v in [OrientedLineVariant.right, .downLeft] {
            let q = Self.question([v, v, v])
            var b = OrientedLineBoard(question: q)
            var clock = 0.0
            for index in 0..<3 {
                let line = q.lines[index]
                expectEqual(b.penDown(at: line.greenSign, now: clock), .joined)
                let moves = Self.sweep(&b, line, from: -130, to: line.length, clock: &clock)
                expectEqual(moves.last, index < 2 ? .lineDone(index) : .allDone)
                b.penUp()
            }
            expectTrue(b.isComplete)
            let stale = OrientedLineBoard(question: q)
            expectFalse(stale.isMonotonicSuccessor(of: b), "a stale copy never undoes a finished round")
            // (a) held outside the lock, (b) still held after a long interruption, (c) one release on Return,
            // (d) a duplicate Return releases nothing, (e) Return into a running visa keeps it until a reset.
            var hold = ChildFinishHold()
            expectFalse(hold.finishesNow("deal-1", mode: .parent))
            expectEqual(hold.round, "deal-1")
            expectEqual(hold.release(openRound: "deal-1", mode: .lock), "deal-1")
            expectNil(hold.release(openRound: "deal-1", mode: .lock))
            expectFalse(hold.finishesNow("deal-2", mode: .parent))
            // A stale hold for an old deal stamps nothing.
            expectNil(hold.release(openRound: "deal-3", mode: .lock))
            expectFalse(hold.finishesNow("deal-4", mode: .parent))
            expectNil(hold.release(openRound: "deal-4", mode: .play))
            expectEqual(hold.round, "deal-4")
            hold.drop()
            expectNil(hold.release(openRound: "deal-4", mode: .lock))
            expectTrue(hold.finishesNow("deal-5", mode: .lock))
            expectNil(hold.round)
        }
        print("  畫直線・四方 T16 (pure): → and ↙ rounds finish once; the hold stamps once on Return, never twice, never for a stale deal")
    }

    func testLearnedPerOrientedVariantInItsOwnStore() {
        var progress = OrientedLineGuideProgress()
        for v in Self.variants { expectFalse(progress.isLearned(v)) }
        expectEqual(Self.variants.map(\.learnKey), ["line.right", "line.left", "line.upRight", "line.downLeft"])
        // Two clean → lines mark only line.right.
        progress = OrientedLineLearning.lineDone(progress, variant: .right, clean: true, lane: .child)!
        expectFalse(progress.isLearned(.right))
        progress = OrientedLineLearning.lineDone(progress, variant: .right, clean: true, lane: .child)!
        expectTrue(progress.isLearned(.right))
        expectEqual(progress.learned, [.right])
        // ↙ learned, then one helped ↙ line resets only line.downLeft.
        for _ in 0..<2 { progress = OrientedLineLearning.lineDone(progress, variant: .downLeft, clean: true, lane: .child)! }
        expectEqual(progress.learned, [.right, .downLeft])
        progress = OrientedLineLearning.lineDone(progress, variant: .downLeft, clean: false, lane: .child)!
        expectEqual(progress.learned, [.right])
        expectEqual(progress.streak(.downLeft), 0)
        expectEqual(progress.streak(.right), 2)
        // A parent's 試玩 never writes.
        expectNil(OrientedLineLearning.lineDone(progress, variant: .left, clean: true, lane: .playtest))
        // A line's guidance record decides clean: a pause, a refusal or an on-demand demo is help.
        let q = Self.question([.downLeft, .downLeft, .downLeft])
        var tally = OrientedLineGuideTally(question: q)
        tally.startLine(learned: false, now: 0, demoLead: 0)
        expectTrue(tally.currentClean)
        tally.note(.pause(from: 10, to: 190, since: 3))
        expectFalse(tally.currentClean)
        tally.startLine(learned: false, now: 5, demoLead: 0)
        tally.noteRefusal(0)
        expectFalse(tally.currentClean)
        expectEqual(tally.resultFields["stall_helps"], .int(1))
        expectEqual(tally.resultFields["guide_clean"], .bool(false))
        // Store: its own key, round-trip, unknown keys dropped, corrupt → nothing learned.
        let suite = "VisaGames.orientedLearn.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OrientedLineGuideProgressStore(defaults: defaults)
        expectEqual(OrientedLineGuideProgressStore.key, "VisaGames.orientedLineGuideProgress.v1")
        expectEqual(store.load(), OrientedLineGuideProgress())
        store.save(progress)
        expectEqual(store.load(), progress)
        defaults.set(Data("{\"streaks\":{\"line.right\":5,\"7\":9}}".utf8), forKey: OrientedLineGuideProgressStore.key)
        expectEqual(store.load().streaks, ["line.right": 5])
        defaults.set(Data("nope".utf8), forKey: OrientedLineGuideProgressStore.key)
        expectEqual(store.load(), OrientedLineGuideProgress())
        print("  畫直線・四方 T19: 識咗 per oriented variant — two clean → mark only line.right; a helped ↙ resets only line.downLeft; 試玩 never writes")
    }

    func testOpenRoundKeepsItsDealtSnapshot() {
        let suite = "VisaGames.orientedSnapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OrientedLineSettingsStore(defaults: defaults)
        for v in Self.variants {
            let s1 = OrientedLineSettings(lineShape: v.isHorizontal ? .across : .diagonal,
                                          lineDirection: v.isRightward ? .rightward : .leftward, lineHelp: .standard,
                                          tolerance: .narrow)
            store.save(s1)
            let q = OrientedLineGenerator.make(seed: "snap-\(v.rawValue)", settings: store.load())
            expectEqual(q.dealt, s1)
            expectTrue(q.lines.allSatisfy { $0.variant == v })
            var b = OrientedLineBoard(question: q)
            var tally = OrientedLineGuideTally(question: q)
            var progress = OrientedLineGuideProgress()
            tally.startLine(learned: progress.isLearned(v), now: 0, demoLead: 0)
            var clock = 1.0
            let line = q.lines[0]
            Self.drawTo(&b, line.length / 2, clock: &clock)
            let before = b
            // 家長: every setting changes (also each alone), saved at once.
            let s2 = OrientedLineSettings(lineShape: v.isHorizontal ? .diagonal : .across,
                                          lineDirection: v.isRightward ? .leftward : .rightward, lineHelp: .less,
                                          tolerance: .wide)
            for changed in [s2, OrientedLineSettings(lineShape: s2.lineShape, lineDirection: s1.lineDirection,
                                                     lineHelp: s1.lineHelp, tolerance: s1.tolerance),
                            OrientedLineSettings(lineShape: s1.lineShape, lineDirection: s1.lineDirection,
                                                 lineHelp: .less, tolerance: s1.tolerance), s2] {
                store.save(changed)
            }
            b.cancelStroke()
            // (a) geometry: the same item, lines, variant, footprint, ends, signs and F.
            expectEqual(b.question, before.question)
            expectEqual(b.frontier, before.frontier)
            expectEqual(b.halfWidth, 50, accuracy: 1e-9)
            // (b) guidance follows S1: dealt 標準 still shows the pause after 2 s with 少啲 saved.
            expectEqual(tally.level, .standard)
            var resumed = b
            expectEqual(resumed.penDown(at: Self.at(line, line.length / 2 - 5), now: clock), .joined)
            let plan = OrientedLineCoach.plan(level: tally.level, learned: false)
            Self.expectHelp(OrientedLineCoach.help(plan: plan, run: tally.run!, board: resumed, now: clock + 2.1),
                            .pause(from: line.length / 2, to: min(line.length / 2 + 180, line.length - 15.5), since: clock + 2))
            // (c) recorded facts carry S1.
            let fields = PerfChoiceCatalog.facts(orientedLines: q).dealtFields
            expectEqual(fields["line_help"], .string("standard"))
            expectEqual(fields["tolerance"], .string("narrow"))
            expectEqual(fields["line_shape"], .string(s1.lineShape.rawValue))
            expectEqual(fields["line_direction"], .string(s1.lineDirection.rawValue))
            expectEqual(resumed.resultFields(playtest: false)["tolerance"], .string("narrow"))
            expectEqual(tally.resultFields["guide_level"], .string("standard"))
            // (d) learning: only the dealt line's variant, judged by its own record.
            tally.note(OrientedLineCoach.help(plan: plan, run: tally.run!, board: resumed, now: clock + 2.1))
            progress = OrientedLineLearning.lineDone(progress, variant: line.variant, clean: tally.currentClean,
                                                     lane: .child)!
            expectEqual(progress.streak(v), 0)
            expectEqual(progress.streaks.keys.sorted(), [v.learnKey])
            // (f) the next deal uses S2 in every respect.
            let next = OrientedLineGenerator.make(seed: "snap-next-\(v.rawValue)", settings: store.load())
            expectEqual(next.dealt, s2)
            expectTrue(next.lines.allSatisfy { $0.variant.isHorizontal == (s2.lineShape == .across) })
            expectTrue(next.lines.allSatisfy { $0.variant.isRightward == (s2.lineDirection == .rightward) })
            expectEqual(next.halfWidth, 110, accuracy: 1e-9)
            expectEqual(OrientedLineGuideTally(question: next).level, .less)
        }
        print("  畫直線・四方 T20 (pure): a round dealt with S1 keeps its geometry, corridor, guidance level, facts and 識咗 key after 家長 saves S2 for → ← ↗ ↙; the next deal takes S2")
    }

    func testNewCardStartsEmptyBesideAPopulatedOriginalCard() {
        let suite = "VisaGames.orientedNoCopy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // Seed: 畫直線 · 熱身 played in 試玩 and on every star, 畫形狀設定 changed (its tolerance included), numerals
        // learned in the tracing help.
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let playtests = ParentPlaytestLogStore(defaults: defaults)
        playtests.save(ParentPlaytestLog().recording(.traceLines, on: day).recording(.traceShapesDotted, on: day))
        let stars = MissionGameAssignmentStore(defaults: defaults)
        var assignment = MissionGameAssignment.defaults
        for star in ChildDifficulty.allCases {
            if case .updated(let next) = assignment.toggling(.traceLines, star: star) { assignment = next }
        }
        stars.save(assignment)
        let shapes = ShapeTraceSettingsStore(defaults: defaults)
        var shapeSettings = ShapeTraceSettings.defaults
        shapeSettings.tolerance = .wide
        shapeSettings.slantLines = true
        shapeSettings.directionHint = false
        shapes.save(shapeSettings)
        var numerals = TapCountGuideProgress()
        for n in [1, 7] { for _ in 0..<2 { numerals.recordClean(n, language: .cantonese) } }
        TapCountGuideProgressStore(defaults: defaults).save(numerals)
        expectTrue(stars.load().isEnabled(.traceLines, star: .easy))
        expectTrue(TapCountGuideProgressStore(defaults: defaults).load().isLearned(1, language: .cantonese))
        // The new card, loaded through the stores the app uses: no 試玩, no star, nothing learned, default settings.
        let kind = ActivityKind.traceOrientedLines
        expectNil(playtests.load().playtestedOn(kind))
        expectFalse(playtests.load().allowsStars(for: kind))
        for star in ChildDifficulty.allCases { expectFalse(stars.load().isEnabled(kind, star: star)) }
        let learned = OrientedLineGuideProgressStore(defaults: defaults).load()
        for v in OrientedLineVariant.allCases {
            expectFalse(learned.isLearned(v))
            expectEqual(learned.streak(v), 0)
        }
        expectTrue(learned.streaks.isEmpty)
        expectEqual(OrientedLineSettingsStore(defaults: defaults).load(), .defaults)
        // Playing the new card (its 試玩, a learned →) leaves the original card's records exactly as they were.
        playtests.save(playtests.load().recording(kind, on: day.addingTimeInterval(60)))
        var mine = learned
        for _ in 0..<2 { mine.record(.right, clean: true) }
        OrientedLineGuideProgressStore(defaults: defaults).save(mine)
        OrientedLineSettingsStore(defaults: defaults).save(OrientedLineSettings(tolerance: .narrow))
        expectEqual(playtests.load().playtestedOn(.traceLines), day)
        expectEqual(playtests.load().playtestedOn(kind), day.addingTimeInterval(60))
        expectEqual(stars.load(), assignment.normalized())
        expectEqual(shapes.load(), shapeSettings)
        expectEqual(TapCountGuideProgressStore(defaults: defaults).load(), numerals)
        expectTrue(OrientedLineGuideProgressStore(defaults: defaults).load().isLearned(.right))
        print("  畫直線・四方 T21: beside a populated 畫直線 · 熱身 (試玩, ★ ★★ ★★★, 畫形狀設定, numeral 識咗) the new card starts with no 試玩, no star, no 識咗 and default settings; its own play leaves the original untouched")
    }
}
