import Foundation
import VisaCore

/// v0.25.0 / v0.26.0 畫線畫形 / Lines & Shapes (ADR 0014, 0015; design shape-trace §7.6): 畫直線 · 熱身,
/// 畫形狀 · 跟虛線, 跟箭嘴 (★★) and 自己畫 (★★★). Geometry, stroke order, the forwards-only vehicle with corner stops, practice-
/// only stats, the D11 playtest gate, settings, copy and the app wiring.
final class ShapeTraceTests {
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func allQuestions() -> [ShapeTraceQuestion] {
        ShapeTraceGenerator.allItems(kind: .traceLines, slant: false)
            + ShapeTraceGenerator.allItems(kind: .traceLines, slant: true)
            + ShapeTraceGenerator.allItems(kind: .traceShapesDotted)
            + outlinedQuestions()
    }

    private func outlinedQuestions() -> [ShapeTraceQuestion] {
        ShapeTraceGenerator.allItems(kind: .traceShapesArrows) + ShapeTraceGenerator.allItems(kind: .traceShapesFree)
    }

    /// Drives every stroke with a synthetic pen along its centre line. Returns the last move.
    @discardableResult
    private func drive(_ board: inout ShapeTraceBoard, clock: inout Double, offset: Double = 0) -> ShapeTraceMove {
        var last = ShapeTraceMove.ignored
        var guardSteps = 0
        while !board.isComplete, guardSteps < 40 {
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
                d += 8
            }
            board.penUp()
        }
        return last
    }

    // MARK: Generator

    func testGeneratorIsDeterministicAndLabelled() {
        for kind in [ActivityKind.traceLines, .traceShapesDotted] {
            for i in 0..<200 {
                let a = ShapeTraceGenerator.make(seed: "s\(i)", kind: kind)
                expectEqual(a, ShapeTraceGenerator.make(seed: "s\(i)", kind: kind))
                expectEqual(a.kind, kind)
                expectEqual(a.level, .l1)
                expectTrue(a.itemID.hasPrefix(kind == .traceLines ? "traceLines.fireStation." : "traceShapes.L1."))
                expectEqual(a.laneWidth, kind == .traceLines ? 100 : 80)
                let again = ShapeTraceGenerator.make(seed: "s\(i)", kind: kind, avoidingItem: a.itemID)
                expectTrue(again.itemID != a.itemID, "no back-to-back repeat")
            }
        }
        let lines = ShapeTraceGenerator.make(seed: "x", kind: .traceLines)
        expectEqual(lines.shapes.map(\.kind), [.across, .down, .across])
        expectEqual(lines.scene, .fireStation)
        var slant = ShapeTraceSettings.defaults
        slant.slantLines = true
        expectEqual(ShapeTraceGenerator.make(seed: "x", kind: .traceLines, settings: slant).shapes.map(\.kind),
                    [.across, .down, .slant])
    }

    func testEveryItemIsWellFormedUniqueAndClearOfTheParentCorner() {
        let lines = ShapeTraceGenerator.allItems(kind: .traceLines)
        let slant = ShapeTraceGenerator.allItems(kind: .traceLines, slant: true)
        let shapes = ShapeTraceGenerator.allItems(kind: .traceShapesDotted)
        expectEqual(lines.count, 54)
        expectEqual(slant.count, 54)
        expectEqual(shapes.count, 54)
        expectEqual(Set((lines + slant + shapes).map(\.itemID)).count, 162)
        for question in allQuestions() where !question.isOutlined {
            expectTrue(question.isWellFormed, "ill-formed \(question.itemID)")
            for shape in question.shapes {
                for stroke in shape.strokes {
                    expectFalse(ShapeTraceLayout.entersParentCorner(stroke, halfWidth: question.laneWidth / 2))
                    // Lanes stay off the header and the tray's status / link card.
                    expectTrue(stroke.bounds.y - question.laneWidth / 2 >= 112)
                    expectTrue(stroke.bounds.maxY + question.laneWidth / 2 <= 560)
                }
            }
            // Drawn lanes of different shapes never touch (lane + ink edges).
            for i in question.shapes.indices {
                for j in question.shapes.indices where j > i {
                    for a in question.shapes[i].strokes {
                        for b in question.shapes[j].strokes {
                            expectTrue(a.minimumSeparation(to: b) >= question.laneWidth + 12,
                                       "lanes touch in \(question.itemID)")
                        }
                    }
                }
            }
            // Shapes go left → right.
            let xs = question.shapes.map(\.frame.x)
            if question.kind == .traceShapesDotted { expectEqual(xs, xs.sorted()) }
        }
    }

    // MARK: ★★ 跟箭嘴 / ★★★ 自己畫 (v0.26.0)

    func testOutlinedItemsAreWellFormedUniqueAndApart() {
        let arrows = ShapeTraceGenerator.allItems(kind: .traceShapesArrows)
        let free = ShapeTraceGenerator.allItems(kind: .traceShapesFree)
        expectEqual(arrows.count, free.count)
        expectTrue(arrows.count >= 90, "\(arrows.count) ★★ items")
        expectEqual(Set((arrows + free).map(\.itemID)).count, arrows.count * 2)
        for question in arrows { expectEqual(question.level, .l2); expectEqual(question.kind, .traceShapesArrows) }
        for question in free { expectEqual(question.level, .l3); expectEqual(question.kind, .traceShapesFree) }
        var scenes = Set<ShapeTraceScene>()
        var kinds = Set<ShapeTraceShapeKind>()
        var slots = Set<String>()
        for question in arrows + free {
            expectTrue(question.isWellFormed, "ill-formed \(question.itemID)")
            expectTrue(question.isOutlined)
            expectEqual(question.laneWidth, ShapeTraceGenerator.outlinedLaneWidth)
            expectTrue(question.itemID.hasPrefix("traceShapes.\(question.level.code)."))
            scenes.insert(question.scene)
            for shape in question.shapes {
                kinds.insert(shape.kind)
                slots.insert(shape.slot)
                expectFalse(shape.kind.isLine)
                expectTrue(shape.kind != .spire, "★★ / ★★★ roofs are closed ▲")
                for stroke in shape.strokes {
                    // Outlines (8u) and ink (16u) stay off the header, tray and parent corner.
                    expectFalse(ShapeTraceLayout.entersParentCorner(stroke, halfWidth: 16))
                    expectTrue(stroke.bounds.y - 16 >= 112)
                    expectTrue(stroke.bounds.maxY + 8 <= 560)
                }
            }
            // Only the active stroke is judged, so separate shapes may sit closer than two lanes
            // (pole ↔ body 40u, body ↔ wheels 50u) but never touch.
            for i in question.shapes.indices {
                for j in question.shapes.indices where j > i {
                    for a in question.shapes[i].strokes {
                        for b in question.shapes[j].strokes {
                            expectTrue(a.minimumSeparation(to: b) >= 36, "shapes touch in \(question.itemID)")
                        }
                    }
                }
            }
        }
        expectEqual(scenes, [.snowTown, .castleKeep, .castleHall, .garage])
        expectEqual(kinds, [.circle, .square, .triangle, .pennant, .cone])
        for slot in ["clock", "head", "sun", "body", "carBody", "backWheel", "frontWheel", "flag", "sail", "cone",
                     "spireA", "spireB", "spireC", "windowA", "windowB", "windowC"] {
            expectTrue(slots.contains(slot), "missing \(slot)")
        }
        // ◁ / ▽ / ▲ only from ★★.
        for question in ShapeTraceGenerator.allItems(kind: .traceShapesDotted) {
            for shape in question.shapes {
                expectFalse([ShapeTraceShapeKind.triangle, .pennant, .cone].contains(shape.kind))
            }
        }
    }

    func testOutlinedStrokeOrder() {
        for question in outlinedQuestions() {
            for shape in question.shapes {
                switch shape.kind {
                case .circle:
                    expectEqual(shape.strokes.count, 1)
                    expectTrue(shape.strokes[0].closed && shape.strokes[0].signedArea < 0)
                    expectEqual(shape.strokes[0].start.y, shape.frame.y, accuracy: 0.001)
                case .square:
                    expectEqual(shape.strokes.count, 3)
                    expectEqual(shape.strokes[1].corners.count, 1)
                case .triangle:
                    // ▲: 撇, 捺, then the base left → right.
                    expectEqual(shape.strokes.count, 3)
                    expectEqual(shape.strokes[0].start, shape.strokes[1].start)
                    expectTrue(shape.strokes[0].end.x < shape.strokes[0].start.x)
                    expectTrue(shape.strokes[1].end.x > shape.strokes[1].start.x)
                    expectEqual(shape.strokes[2].start, shape.strokes[0].end)
                    expectEqual(shape.strokes[2].end, shape.strokes[1].end)
                case .pennant:
                    // ◁ in one go: top of the pole → tip → bottom of the pole.
                    expectEqual(shape.strokes.count, 1)
                    expectEqual(shape.strokes[0].corners.count, 1)
                    expectEqual(shape.strokes[0].start.x, shape.strokes[0].end.x, accuracy: 0.001)
                case .cone:
                    // ▽: top edge, then each side down to the tip.
                    expectEqual(shape.strokes.count, 3)
                    expectEqual(shape.strokes[0].start.y, shape.strokes[0].end.y, accuracy: 0.001)
                    expectEqual(shape.strokes[1].end, shape.strokes[2].end)
                default:
                    preconditionFailure("unexpected \(shape.kind) on ★★ / ★★★")
                }
            }
            if question.scene == .garage {
                expectEqual(question.shapes.map(\.slot).prefix(3), ["carBody", "backWheel", "frontWheel"])
                expectTrue(question.car != nil)
                expectEqual(question.shapes.count, 4)
            }
        }
    }

    func testOutlinedFeaturedGroupFollowsTheParentWeights() {
        for kind in [ActivityKind.traceShapesArrows, .traceShapesFree] {
            var counts: [ShapeTraceMixShape: Int] = [:]
            var garages = 0
            let n = 6_000
            for i in 0..<n {
                let q = ShapeTraceGenerator.make(seed: "mix2-\(i)", kind: kind)
                expectEqual(q, ShapeTraceGenerator.make(seed: "mix2-\(i)", kind: kind))
                counts[q.featured!, default: 0] += 1
                if q.scene == .garage { garages += 1 } else {
                    expectTrue(q.shapes.allSatisfy { $0.kind.mixGroup == q.featured }, "scene shows its group")
                }
            }
            for shape in ShapeTraceMixShape.allCases {
                expectEqual(Double(counts[shape] ?? 0) / Double(n), Double(shape.defaultWeight) / 100, accuracy: 0.025)
            }
            expectEqual(Double(garages) / Double(n), 1.0 / 3.0, accuracy: 0.03)
            let a = ShapeTraceGenerator.make(seed: "rep", kind: kind)
            expectTrue(ShapeTraceGenerator.make(seed: "rep", kind: kind, avoidingItem: a.itemID).itemID != a.itemID)
        }
        expectEqual(ShapeTraceGenerator.level(for: .traceShapesArrows), .l2)
        expectEqual(ShapeTraceGenerator.level(for: .traceShapesFree), .l3)
    }

    func testFreeInkAndEraserClearOnlyTheCurrentShape() {
        let question = ShapeTraceGenerator.allItems(kind: .traceShapesFree).first { $0.scene == .castleHall }!
        var board = ShapeTraceBoard(question: question)
        expectTrue(board.recordsInk)
        expectTrue(board.eraserVisible)
        // Draw the first window fully.
        var clock = 0.0
        while board.shapeIndex == 0, let path = board.currentPath {
            clock += 0.1
            _ = board.penDown(at: path.start, now: clock)
            var d = 0.0
            var done = false
            while d <= path.length + 16, !done {
                clock += 0.02
                switch board.penMove(to: path.point(at: min(d, path.length)), now: clock) {
                case .strokeDone, .shapeDone, .allDone: done = true
                default: break
                }
                d += 8
            }
            board.penUp()
        }
        expectEqual(board.shapeIndex, 1)
        let firstInk = board.inkPolylines(shape: 0)
        expectFalse(firstInk.isEmpty)
        expectTrue((board.shapeStats[0].inkOutsideRatio ?? 1) < 0.05)
        // Start the second window, then 擦晒.
        let path = board.currentPath!
        clock += 1
        _ = board.penDown(at: path.start, now: clock)
        for step in 1...10 { clock += 0.02; _ = board.penMove(to: path.point(at: Double(step) * 8), now: clock) }
        board.penUp()
        expectTrue(board.progress > 0)
        expectFalse(board.inkPolylines(shape: 1).isEmpty)
        let before = board
        clock += 1
        expectEqual(board.erase(now: clock), .cleared)
        expectTrue(board.isMonotonicSuccessor(of: before))
        expectFalse(before.isMonotonicSuccessor(of: board), "erases never go back")
        expectEqual(board.progress, 0)
        expectEqual(board.strokeIndex, 0)
        expectEqual(board.shapeIndex, 1)
        expectTrue(board.inkPolylines(shape: 1).isEmpty)
        expectEqual(board.inkPolylines(shape: 0), firstInk, "finished shapes never change")
        expectEqual(board.erase(now: clock + 1), .coolingDown)
        expectEqual(board.erase(now: clock + 4), .cleared)
        expectEqual(board.erase(now: clock + 8), .cleared)
        expectEqual(board.erase(now: clock + 12), .clearedNudge)
        expectEqual(board.erase(now: clock + 16), .cleared)
        expectEqual(board.erase(now: clock + 20), .clearedAndHidden)
        expectFalse(board.eraserVisible)
        expectEqual(board.erase(now: clock + 24), .unavailable)
        let fields = board.resultFields
        expectEqual(fields["shape_trace_level"], .string("L3"))
        expectEqual(fields["erasers"], .int(6))
        expectEqual(fields["eraser_locked"], .int(1))
        expectTrue(fields["ink_outside_ratio"] != nil)
        // ★★: no ink, no 擦晒.
        let arrows = ShapeTraceBoard(question: ShapeTraceGenerator.make(seed: "a", kind: .traceShapesArrows))
        expectFalse(arrows.recordsInk)
        expectFalse(arrows.eraserVisible)
        var copy = arrows
        expectEqual(copy.erase(now: 10), .unavailable)
        expectEqual(arrows.resultFields["shape_trace_level"], .string("L2"))
        expectTrue(arrows.resultFields["erasers"] == nil)
    }

    func testStrokeOrderCirclesSquaresAndSpires() {
        for question in ShapeTraceGenerator.allItems(kind: .traceShapesDotted) {
            for shape in question.shapes {
                switch shape.kind {
                case .circle:
                    expectEqual(shape.strokes.count, 1)
                    let circle = shape.strokes[0]
                    expectTrue(circle.closed)
                    expectTrue(circle.signedArea < 0, "anticlockwise like writing o")
                    expectEqual(circle.start.x, shape.frame.midX, accuracy: 0.001)
                    expectEqual(circle.start.y, shape.frame.y, accuracy: 0.001)
                    expectTrue(circle.points[1].x < circle.start.x, "from 12 o'clock heading left")
                    expectEqual(circle.start.distance(to: circle.end), 0, accuracy: 0.01)
                case .square:
                    // 口: ① 丨 left side down, ② 𠃍 top then right side down, ③ 一 bottom.
                    expectEqual(shape.strokes.count, 3)
                    let f = shape.frame
                    let s = shape.strokes
                    expectEqual(s[0].start, LineMatchPoint(x: f.x, y: f.y))
                    expectEqual(s[0].end, LineMatchPoint(x: f.x, y: f.maxY))
                    expectEqual(s[1].start, LineMatchPoint(x: f.x, y: f.y))
                    expectEqual(s[1].corners.count, 1)
                    expectEqual(s[1].point(at: s[1].corners[0]).x, f.maxX, accuracy: 0.001)
                    expectEqual(s[1].end, LineMatchPoint(x: f.maxX, y: f.maxY))
                    expectEqual(s[2].start, LineMatchPoint(x: f.x, y: f.maxY))
                    expectEqual(s[2].end, LineMatchPoint(x: f.maxX, y: f.maxY))
                    expectEqual(f.width, f.height, accuracy: 0.001)
                case .spire:
                    // ★ ∧ only: 撇 apex → bottom-left, then 捺 apex → bottom-right (like 人).
                    expectEqual(shape.strokes.count, 2)
                    expectEqual(shape.strokes[0].start, shape.strokes[1].start)
                    expectTrue(shape.strokes[0].end.x < shape.strokes[0].start.x)
                    expectTrue(shape.strokes[1].end.x > shape.strokes[1].start.x)
                    expectEqual(shape.strokes[0].end.y, shape.strokes[1].end.y, accuracy: 0.001)
                default:
                    preconditionFailure("lines never appear on the shape card")
                }
            }
        }
    }

    func testShapeMixFollowsTheParentWeights() {
        var counts: [ShapeTraceMixShape: Int] = [:]
        let n = 6_000
        for i in 0..<n {
            let q = ShapeTraceGenerator.make(seed: "mix-\(i)", kind: .traceShapesDotted)
            counts[q.mixShape!, default: 0] += 1
            expectEqual(Set(q.shapes.map(\.kind)).count, 1, "one shape type per round")
        }
        for shape in ShapeTraceMixShape.allCases {
            let share = Double(counts[shape] ?? 0) / Double(n)
            expectEqual(share, Double(shape.defaultWeight) / 100, accuracy: 0.025)
        }
        let noTriangles = ShapeTraceSettings(weights: [.triangle: 0])
        for i in 0..<1_000 {
            expectTrue(ShapeTraceGenerator.make(seed: "t\(i)", kind: .traceShapesDotted, settings: noTriangles)
                .mixShape != .triangle)
        }
    }

    // MARK: Board

    func testEveryDealCompletesWithAPenAlongTheLanesAndTerminates() {
        for question in allQuestions() {
            for tolerance in LineMatchTolerance.allCases {
                var board = ShapeTraceBoard(question: question, tolerance: tolerance)
                var clock = 0.0
                let last = drive(&board, clock: &clock, offset: tolerance == .narrow ? 0 : 20)
                expectTrue(board.isComplete, "\(question.itemID) did not complete at \(tolerance)")
                expectEqual(last, .allDone)
                expectEqual(board.exposures, question.shapes.map(\.kind.rawValue))
                expectEqual(board.offPathCount, 0)
            }
        }
    }

    func testVehicleOnlyGoesForwardsAndOffPathIsNeverAMiss() {
        let question = ShapeTraceGenerator.make(seed: "fwd", kind: .traceLines)
        var board = ShapeTraceBoard(question: question)
        let path = question.shapes[0].strokes[0]
        expectEqual(board.penDown(at: path.start, now: 0), .grabbed(shape: 0, stroke: 0))
        var previous = board
        for d in stride(from: 8.0, through: 200, by: 8) {
            _ = board.penMove(to: path.point(at: d), now: d / 100)
            expectTrue(board.progress >= previous.progress)
            expectTrue(board.isMonotonicSuccessor(of: previous))
            previous = board
        }
        let reached = board.progress
        // Backwards: the vehicle stays.
        expectEqual(board.penMove(to: path.point(at: reached - 30), now: 3), .waiting)
        expectEqual(board.progress, reached)
        // Far off the lane: it waits, the slip is counted once, nothing is wrong.
        let off = LineMatchPoint(x: path.point(at: reached).x, y: path.start.y + 200)
        expectEqual(board.penMove(to: off, now: 4), .away)
        expectEqual(board.penMove(to: off, now: 4.5), .away)
        expectEqual(board.offPathCount, 1)
        expectEqual(board.progress, reached)
        expectFalse(board.showsHint(now: 5.9))
        expectTrue(board.showsHint(now: 6.1))
        // Too far ahead along the lane (more than the lead limit): it waits.
        expectEqual(board.penMove(to: path.point(at: reached + 300), now: 7), .away)
        expectEqual(board.progress, reached)
        // Back on the lane near the vehicle: it drives on.
        expectEqual(board.penMove(to: path.point(at: reached + 30), now: 8), .drove)
        board.penUp()
        expectEqual(board.lifts, 1)
        expectFalse(previous.isMonotonicSuccessor(of: board), "a stale copy cannot undo progress")
        expectFalse(ShapeTraceBoard(question: ShapeTraceGenerator.make(seed: "other", kind: .traceLines))
            .isMonotonicSuccessor(of: board))
        // The result fields say practice and never carry a correct / wrong verdict.
        let fields = board.resultFields
        expectEqual(fields["practice"], .string("shape_trace"))
        expectEqual(fields["off_path_count"], .int(1))
        expectTrue(fields["correct"] == nil && fields["misses"] == nil)
    }

    func testCornerStopsTheVehicleAndOvershootIsTaggedOnce() {
        let window = ShapeTraceGenerator.window(slot: 1, big: true, shift: 0)
        let question = ShapeTraceQuestion(itemID: "test.window", kind: .traceShapesDotted, level: .l1,
                                          scene: .castleWindows, shift: 0, big: true, slant: false, shapes: [window],
                                          laneWidth: 80, promptKey: "k", promptTraditionalChinese: "畫窗",
                                          promptEnglish: "Window")
        var board = ShapeTraceBoard(question: question)
        var clock = 0.0
        // Stroke ① (left side) first.
        let first = window.strokes[0]
        _ = board.penDown(at: first.start, now: clock)
        for d in stride(from: 8.0, through: first.length + 8, by: 8) {
            clock += 0.02
            if case .strokeDone = board.penMove(to: first.point(at: min(d, first.length)), now: clock) { break }
        }
        expectEqual(board.strokeIndex, 1)
        board.penUp()
        // Stroke ② 𠃍: drive along the top; the car stops at the corner.
        let second = window.strokes[1]
        let corner = second.corners[0]
        _ = board.penDown(at: second.start, now: clock)
        var sawCorner = false
        for d in stride(from: 8.0, through: corner + 4, by: 8) {
            clock += 0.02
            if board.penMove(to: second.point(at: d), now: clock) == .cornerReached { sawCorner = true }
        }
        expectTrue(sawCorner)
        expectTrue(board.isAtCorner)
        expectEqual(board.progress, corner, accuracy: 0.001)
        // The pen runs on to the right (old direction): stop-sign tag, once; the car waits.
        let cornerPoint = second.point(at: corner)
        expectEqual(board.penMove(to: LineMatchPoint(x: cornerPoint.x + 30, y: cornerPoint.y), now: clock + 0.1),
                    .cornerOvershoot)
        expectEqual(board.penMove(to: LineMatchPoint(x: cornerPoint.x + 34, y: cornerPoint.y), now: clock + 0.2),
                    .away)
        expectEqual(board.cornerOvershoots, 1)
        expectEqual(board.progress, corner, accuracy: 0.001)
        // Turning down: it drives on.
        expectEqual(board.penMove(to: LineMatchPoint(x: cornerPoint.x, y: cornerPoint.y + 30), now: clock + 0.3), .drove)
        expectTrue(board.progress > corner)
        expectFalse(board.isAtCorner)
    }

    func testACircleCannotFinishByJumpingFromItsStartToItsEnd() {
        let sun = ShapeTraceGenerator.snowCircle(slot: 1, big: true, shift: 0)
        let question = ShapeTraceQuestion(itemID: "test.sun", kind: .traceShapesDotted, level: .l1, scene: .snowTown,
                                          shift: 0, big: true, slant: false, shapes: [sun], laneWidth: 80,
                                          promptKey: "k", promptTraditionalChinese: "圓", promptEnglish: "Circle")
        var board = ShapeTraceBoard(question: question, tolerance: .wide)
        let path = sun.strokes[0]
        _ = board.penDown(at: path.start, now: 0)
        // A step clockwise (to the right of 12 o'clock) is the circle's end, not its next point.
        let wrongWay = path.point(at: path.length - 30)
        let move = board.penMove(to: wrongWay, now: 0.1)
        expectTrue(move == .waiting || move == .drove)
        expectTrue(board.progress < 40)
        expectFalse(board.isComplete)
        var clock = 1.0
        drive(&board, clock: &clock)
        expectTrue(board.isComplete)
    }

    func testWrongStartAndReverseAreGentleAndHintOffTakesEitherEnd() {
        let question = ShapeTraceGenerator.make(seed: "ws", kind: .traceLines)
        var board = ShapeTraceBoard(question: question, directionHint: true)
        let first = question.shapes[0].strokes[0]
        let second = question.shapes[1].strokes[0]
        expectEqual(board.penDown(at: second.start, now: 0), .wrongStart)
        expectEqual(board.penDown(at: first.end, now: 1), .reverse)
        expectEqual(board.wrongStarts, 2)
        expectEqual(board.progress, 0)
        var free = ShapeTraceBoard(question: question, directionHint: false)
        expectEqual(free.penDown(at: first.end, now: 0), .grabbed(shape: 0, stroke: 0))
        expectTrue(free.isReversed(shape: 0, stroke: 0))
        expectEqual(free.vehiclePoint, first.end)
        for d in stride(from: 8.0, through: first.length + 8, by: 8) {
            if case .shapeDone = free.penMove(to: first.reversed.point(at: min(d, first.length)), now: d / 100) { break }
        }
        expectTrue(free.isDone(shape: 0))
        expectEqual(free.reverseDirections, 1)
    }

    func testToleranceWidensOnlyTheJudgedCorridor() {
        let question = ShapeTraceGenerator.make(seed: "tol", kind: .traceShapesDotted)
        let halves = LineMatchTolerance.allCases.map { ShapeTraceBoard(question: question, tolerance: $0).corridorHalfWidth }
        for (half, expected) in zip(halves, [40.0, 60, 88]) { expectEqual(half, expected, accuracy: 0.0001) }
        let lines = ShapeTraceGenerator.make(seed: "tol", kind: .traceLines)
        expectEqual(ShapeTraceBoard(question: lines, tolerance: .standard).corridorHalfWidth, 75)
        // The drawn lane does not change with tolerance.
        expectEqual(question.laneWidth, 80)
        let path = lines.shapes[0].strokes[0]
        expectEqual(ShapeTraceBoard(question: lines, tolerance: .wide).arrivalDistance(path), path.length - 80, accuracy: 0.001)
    }

    // MARK: Settings, playtest gate, stats

    func testSettingsPersistClampAndKeepOneShape() {
        let suite = "VisaGames.shapeTrace.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShapeTraceSettingsStore(defaults: defaults)
        expectEqual(store.load(), .defaults)
        expectEqual(ShapeTraceSettings.defaults.mixDescription, "circle:45,square:35,triangle:20")
        expectTrue(ShapeTraceSettings.defaults.directionHint)
        expectTrue(ShapeTraceSettings.defaults.cornerStop)
        expectFalse(ShapeTraceSettings.defaults.slantLines)
        expectNil(ShapeTraceSettings.defaults.tolerance)
        var settings = ShapeTraceSettings.defaults.adjusting(.triangle, steps: -4)!
        expectEqual(settings.weight(.triangle), 0)
        settings.tolerance = .wide
        settings.slantLines = true
        settings.dotStyle = .dashes
        store.save(settings)
        expectEqual(store.load(), settings)
        defaults.set(Data("nope".utf8), forKey: ShapeTraceSettingsStore.key)
        expectEqual(store.load(), .defaults)
        let onlyCircles = ShapeTraceSettings(weights: [.circle: 5, .square: 0, .triangle: 0])
        expectNil(onlyCircles.adjusting(.circle, steps: -1))
        expectEqual(ShapeTraceSettings(weights: [.circle: 0, .square: 0, .triangle: 0]), .defaults)
        expectEqual(ShapeTraceSettings.defaults.effectiveTolerance(lineMatch: .narrow), .narrow)
        expectEqual(settings.effectiveTolerance(lineMatch: .narrow), .wide)
        expectEqual(ShapeTraceSettingsStore.key, "VisaGames.shapeTraceSettings.v1")
    }

    func testStarsNeedOnePlaytestFirstAndNewKindsStartOff() {
        for kind in [ActivityKind.traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree] {
            expectTrue(ActivityCatalog.defaultOffKinds.contains(kind))
            expectTrue(ActivityCatalog.playableKinds.contains(kind))
            expectTrue(kind.isShapeTraceFamily)
            expectTrue(kind.requiresPlaytestBeforeStars)
            for star in ChildDifficulty.allCases {
                expectFalse(MissionGameAssignment.defaults.isEnabled(kind, star: star))
            }
        }
        expectFalse(ActivityKind.lineMatch.requiresPlaytestBeforeStars)
        let log = ParentPlaytestLog()
        expectFalse(log.allowsStars(for: .traceLines))
        expectTrue(log.allowsStars(for: .countVehicles))
        let day = Date(timeIntervalSince1970: 1_792_000_000)
        let played = log.recording(.traceLines, on: day)
        expectTrue(played.allowsStars(for: .traceLines))
        expectFalse(played.allowsStars(for: .traceShapesDotted))
        let suite = "VisaGames.playtestLog.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ParentPlaytestLogStore(defaults: defaults)
        expectEqual(store.load(), ParentPlaytestLog())
        store.save(played)
        expectEqual(store.load().playtestedOn(.traceLines), day)
        expectTrue(ParentPlaytestLog.needsPlaytestBanner.hasPrefix("試玩一次先開"))
        // 描線 is now built; it left the muted 未做好 row. 畫線車 cards have their own names.
        expectFalse(ActivityCatalog.unbuiltParentActivities.contains { $0.traditionalChinese == "描線" })
        expectEqual(ActivityKind.traceLines.parentCardTitle, "畫直線 · 熱身")
        expectEqual(ActivityKind.traceShapesDotted.parentCardTitle, "畫形狀 · 跟虛線")
        expectEqual(ActivityKind.traceLines.parentCardEnglish, "Lines · Warm-up")
        expectEqual(ActivityKind.traceShapesDotted.parentCardEnglish, "Shapes · Follow the dots")
        expectEqual(ActivityKind.traceShapesArrows.parentCardTitle, "畫形狀 · 跟箭嘴")
        expectEqual(ActivityKind.traceShapesFree.parentCardTitle, "畫形狀 · 自己畫")
        expectEqual(ActivityKind.traceShapesArrows.parentCardEnglish, "Shapes · Follow the arrows")
        expectEqual(ActivityKind.traceShapesFree.parentCardEnglish, "Shapes · Draw it yourself")
        expectFalse(played.allowsStars(for: .traceShapesFree))
    }

    func testRoundsArePracticeOnlyInReviewAndRollups() {
        let question = ShapeTraceGenerator.make(seed: "p", kind: .traceShapesDotted)
        let facts = PerfChoiceCatalog.facts(shapeTrace: question, settings: .defaults, tolerance: .standard)
        expectEqual(facts.chance, 1)
        expectTrue(facts.correctChoice == nil)
        expectEqual(facts.dealtFields["match_mode"], .string("guided"))
        expectEqual(facts.dealtFields["practice"], .string("shape_trace"))
        expectEqual(facts.dealtFields["shape_mix"], .string("circle:45,square:35,triangle:20"))
        expectEqual(facts.item, question.itemID)
        let base = Date(timeIntervalSince1970: 1_792_000_000)
        var seq = 0
        func event(_ type: PerfEventType, _ fields: [String: PerfValue], at offset: Double) -> PerfEvent {
            seq += 1
            return PerfEvent(type: type, timestamp: base.addingTimeInterval(offset), tz: "+08:00", mono: offset,
                             launch: "L", seq: seq, app: "0.25.0", actor: .child, mode: "lock", session: "s",
                             fields: fields)
        }
        var events: [PerfEvent] = []
        for i in 0..<3 {
            var dealt = facts.dealtFields
            dealt["round"] = .string("t\(i)"); dealt["kind"] = .string("traceShapesDotted"); dealt["stars"] = .int(1)
            events.append(event(.gameDealt, dealt, at: Double(i * 100)))
            events.append(event(.roundResult, ["round": .string("t\(i)"), "outcome": .string("solved"),
                                               "answers": .int(0), "misses": .int(0),
                                               "practice": .string("shape_trace")], at: Double(i * 100 + 30)))
        }
        // Even a dealt line with no match_mode is practice for a shape-trace kind.
        events.append(event(.gameDealt, ["round": .string("bare"), "kind": .string("traceLines"), "stars": .int(1)], at: 900))
        expectTrue(PerfQuestionGeneration.isPracticeOnly(events.last!))
        let report = PerfReportBuilder.build(events: events, rollup: PerfRollup(), videos: [],
                                             now: base.addingTimeInterval(3_000), window: .all)
        let row = report.games.first { $0.kind == .traceShapesDotted }!
        expectEqual(row.guidedPractice, 3)
        expectEqual(row.deals, 0)
        expectEqual(row.evidence.rounds, 0)
        let day = PerfClock.dayStamp(base, timeZone: PerfClock.hongKong)
        let summaries = PerfSummaries.daySummaries(events: events, days: [day], excluded: [], timeZone: PerfClock.hongKong)
        expectEqual(summaries[day]?.games["traceShapesDotted|1|variants_v1|guided"]?.deals, 3)
    }

    // MARK: Copy and art

    func testCopyIsHongKongTraditionalAndASCIIEnglish() {
        // Simplified forms that must never appear (their Traditional forms are used instead).
        let simplified = ["画", "线", "圆", "钟", "个", "车", "门", "顶", "桥", "灯", "轮", "边", "点", "开", "这",
                          "为", "们", "时", "从", "发", "对", "后", "会", "动", "还", "进", "过", "头", "转", "弯",
                          "虚", "试", "玩", "设", "定", "窗"]
        let banned = Set(simplified.filter { !["玩", "定", "窗"].contains($0) })
        var traditional = ShapeTraceCopy.allTraditionalLines
        for kind in [ActivityKind.traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree] {
            traditional += [kind.parentCardTitle, kind.parentShortLabel, kind.parentHelpTraditionalChinese]
        }
        for question in ShapeTraceGenerator.allItems(kind: .traceShapesDotted) + ShapeTraceGenerator.allItems(kind: .traceLines)
            + outlinedQuestions() {
            traditional.append(question.promptTraditionalChinese)
        }
        for line in traditional {
            expectFalse(line.isEmpty)
            for character in line.map(String.init) where banned.contains(character) {
                preconditionFailure("Simplified \(character) in \(line)")
            }
        }
        var english = ShapeTraceCopy.allEnglishLines
        for kind in [ActivityKind.traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree] {
            english += [kind.parentCardEnglish, kind.parentHelpEnglish]
        }
        for question in outlinedQuestions() { english.append(question.promptEnglish) }
        for line in english {
            expectFalse(line.isEmpty)
            expectTrue(line.unicodeScalars.allSatisfy { $0.isASCII || $0 == "½" || $0 == "·" || $0 == "→" || $0 == "—" }, "non-ASCII English: \(line)")
        }
        // Cue = Cantonese word, then English word.
        expectEqual(ShapeTraceCopy.bubble(.spire), "三角形、triangle")
        expectEqual(ShapeTraceCopy.cue(.square).traditionalChinese, "正方形")
        expectEqual(ShapeTraceCopy.cue(.square).english, "square")
        expectEqual(ShapeTraceCopy.cue(.across).traditionalChinese, "打橫")
        expectEqual(ShapeTraceCopy.cornerTraditionalChinese, "停！轉彎！")
        expectEqual(ShapeTraceCopy.linesPromptTraditionalChinese, "由綠色箭嘴畫去紅色箭嘴！")
        expectEqual(ShapeTraceCopy.remainingTraditionalChinese(2, kind: .spire), "仲有 2 個尖頂")
        expectEqual(ShapeTraceCopy.remainingTraditionalChinese(1, kind: nil), "仲有 1 條線")
        expectEqual(ShapeTraceCopy.bubble(.pennant), "三角形、triangle")
        expectEqual(ShapeTraceCopy.bubble(.cone), "三角形、triangle")
        expectEqual(ShapeTraceCopy.eraserTraditionalChinese, "擦晒")
        expectEqual(ShapeTraceCopy.buildDoneTraditionalChinese, "砌好喇！嘟嘟，出發！")
        expectTrue(ShapeTraceCopy.linkCard(.pennant) == nil && ShapeTraceCopy.linkCard(.cone) == nil)
    }

    func testArtIsCompleteAndEveryPathParses() {
        let names = ShapeTraceArt.all.map(\.name)
        expectEqual(Set(names).count, names.count)
        expectEqual(names.count, 26)
        for artwork in ShapeTraceArt.all {
            expectFalse(artwork.elements.isEmpty)
            expectTrue(artwork.width > 0 && artwork.height > 0)
            for element in artwork.elements {
                if case let .path(commands) = element.geometry { expectFalse(commands.isEmpty, "empty path in \(artwork.name)") }
            }
        }
        let anchor = ShapeTraceArt.anchor(ShapeTraceArt.fireEngine)
        expectEqual(anchor, LineMatchPoint(x: 116, y: 132))
        expectEqual(ShapeTraceArt.anchor(ShapeTraceArt.fireStation), LineMatchPoint(x: 0, y: 0))
    }

    func testAppWiringSourceGuards() throws {
        let host = try source("Sources/VisaGames/CanvasActivityHost.swift")
        expectTrue(host.contains("ShapeTraceBoardView("))
        expectTrue(host.contains("case .traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree:"))
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        expectTrue(model.contains("func shapeTraceCommit("))
        expectTrue(model.contains("ParentPlaytestLog.needsPlaytestBanner"))
        expectTrue(model.contains("parentPlaytestLog.recording(kind, on: Date())"))
        expectTrue(model.contains("applyEntrySuccess(assisted: false)"))
        expectTrue(model.contains("PerfChoiceCatalog.facts(shapeTrace:"))
        let view = try source("Sources/VisaGames/ShapeTraceBoardView.swift")
        expectFalse(view.contains("TextField"))
        expectFalse(view.contains("完成"))
        // 擦晒 only ever comes from ShapeTraceCopy, and only on ★★★ (`eraserVisible`).
        expectFalse(view.contains("擦晒"))
        expectTrue(view.contains("if board.eraserVisible {"))
        expectTrue(view.contains("ShapeTraceCopy.eraserTraditionalChinese"))
        expectTrue(view.contains("isMonotonicSuccessor(of: view.board)"))
        let settings = try source("Sources/VisaGames/ParentSettingsView.swift")
        expectTrue(settings.contains("ParentShapeTraceSettingsView("))
        expectTrue(settings.contains("playtestedOn: model.parentPlaytestLog.playtestedOn(kind)"))
        let speech = try source("Sources/VisaGames/SystemSpeechPrompt.swift")
        expectTrue(speech.contains("func speakWordCue(_ cue: SpokenPrompt, then follow: SpokenPrompt? = nil)"))
        expectFalse(speech.contains("zh-CN"))
        let art = try source("Sources/VisaCore/ShapeTraceArt.swift")
        expectTrue(art.hasPrefix("// GENERATED by scripts/svg_to_shapetraceart.py"))
    }
}
