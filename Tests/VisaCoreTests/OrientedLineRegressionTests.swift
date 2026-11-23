import Foundation
import VisaCore

/// 「畫直線・四方」 T17 (four-direction design §11.3): the original card 畫直線 · 熱身 (`traceLines`) stays byte-identical —
/// every item it can deal and its geometry, deals by seed, its deal facts, scripted drives' result fields, its settings
/// payload, and the app's original deal, commit, finish and settings path. The pins were taken on the unchanged base
/// `3237b46` (0.41.0 / 91) before the new card's first line of code.
final class OrientedLineRegressionTests {
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// FNV-1a 64 of the UTF-8 bytes: the same in every process (`hashValue` is not).
    static func fnv(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    static func render(_ value: PerfValue) -> String {
        switch value {
        case .string(let text): return "s:\(text)"
        case .int(let number): return "i:\(number)"
        case .double(let number): return "d:\(number)"
        case .bool(let flag): return "b:\(flag)"
        case .array(let values): return "[" + values.map(render).joined(separator: ",") + "]"
        case .object(let fields):
            return "{" + fields.keys.sorted().map { "\($0)=\(render(fields[$0] ?? .null))" }.joined(separator: ",") + "}"
        case .null: return "null"
        }
    }

    static func describe(_ q: ShapeTraceQuestion) -> String {
        var out = [q.itemID, q.kind.rawValue, q.level.code, q.scene.rawValue, "\(q.shift)", "\(q.big)", "\(q.slant)",
                   "\(q.laneWidth)", q.promptKey, q.promptTraditionalChinese, q.promptEnglish,
                   String(describing: q.featured), String(describing: q.car), "\(q.size)", "\(q.minimumArrivalFraction)",
                   "\(q.penRule)"].joined(separator: "|")
        for shape in q.shapes {
            out += "\n  \(shape.slot)|\(shape.kind.rawValue)|\(shape.colorIndex)|\(shape.frame)"
            for stroke in shape.strokes {
                out += "\n    \(stroke.closed)|\(stroke.corners)|\(stroke.cusps)|\(stroke.length)|"
                    + stroke.points.map { "\($0.x),\($0.y)" }.joined(separator: ";")
            }
        }
        return out
    }

    /// A fixed pen script: a red-end touch first (a reversal with the hint on, a reversed take with it off), then every
    /// line driven along the path it is driven on, with a wobble, one excursion off the lane and one lift.
    static func scriptedDrive(_ question: ShapeTraceQuestion, tolerance: LineMatchTolerance, hint: Bool) -> ShapeTraceBoard {
        var board = ShapeTraceBoard(question: question, tolerance: tolerance, directionHint: hint)
        var clock = 0.0
        if question.shapes.count > 1 {
            _ = board.penDown(at: question.shapes[1].strokes[0].start, now: clock)
            board.penUp()
        }
        clock += 0.5
        _ = board.penDown(at: question.shapes[0].strokes[0].end, now: clock)
        var guardSteps = 0
        while !board.isComplete, guardSteps < 16 {
            guardSteps += 1
            guard let path = board.currentPath else { break }
            if guardSteps > 1 {
                clock += 0.3
                _ = board.penDown(at: path.point(at: board.progress), now: clock)
            }
            var d = board.progress
            var wobble = 0
            var excursion = false
            var lifted = false
            var finished = false
            while d <= path.length + 16, !finished {
                d += 9
                wobble += 1
                let at = min(d, path.length)
                let p = path.point(at: at)
                let angle = path.angle(at: at)
                let side = Double(wobble % 5) * 3 - 6
                var q = LineMatchPoint(x: p.x - sin(angle) * side, y: p.y + cos(angle) * side)
                if !excursion, d > path.length * 0.3 {
                    excursion = true
                    q = LineMatchPoint(x: q.x, y: q.y + 220)
                }
                clock += 0.03
                switch board.penMove(to: q, now: clock) {
                case .strokeDone, .shapeDone, .allDone: finished = true
                default: break
                }
                if !finished, !lifted, d > path.length * 0.6 {
                    lifted = true
                    board.penUp()
                    clock += 0.4
                    _ = board.penDown(at: path.point(at: board.progress), now: clock)
                }
            }
            board.penUp()
        }
        return board
    }

    /// The text of the declaration that starts with `signature`, up to its matching brace.
    private func body(of signature: String, in text: String) -> String {
        guard let start = text.range(of: signature) else { return "" }
        var depth = 0
        var seenBrace = false
        var index = start.lowerBound
        while index < text.endIndex {
            let character = text[index]
            if character == "{" { depth += 1; seenBrace = true }
            if character == "}" {
                depth -= 1
                if seenBrace, depth == 0 { return String(text[start.lowerBound...index]) }
            }
            index = text.index(after: index)
        }
        return ""
    }

    func testOriginalCardIsByteIdentical() throws {
        // (a) Every item, both third-line forms, with its full geometry.
        let plain = ShapeTraceGenerator.allItems(kind: .traceLines, slant: false)
        let slant = ShapeTraceGenerator.allItems(kind: .traceLines, slant: true)
        let items = (plain + slant).map(Self.describe).joined(separator: "\n")
        // (b) Deals by seed, with and without the slant switch, and the no-repeat re-roll.
        var slantOn = ShapeTraceSettings.defaults
        slantOn.slantLines = true
        var deals = ""
        var last: String?
        for i in 0..<60 {
            let settings = i % 2 == 0 ? ShapeTraceSettings.defaults : slantOn
            let q = ShapeTraceGenerator.make(seed: "t17-\(i)", kind: .traceLines, settings: settings, avoidingItem: last)
            deals += q.itemID + "\n"
            last = q.itemID
        }
        // (c) Deal facts.
        var custom = ShapeTraceSettings(weights: [.circle: 60, .square: 25, .triangle: 15], tolerance: .wide,
                                        directionHint: false, cornerStop: false, slantLines: true, dotStyle: .dashes)
        custom.tolerance = .narrow
        var facts = ""
        for (index, q) in [plain[0], plain[17], slant[5], slant[53]].enumerated() {
            for (settings, tolerance) in [(ShapeTraceSettings.defaults, LineMatchTolerance.standard), (custom, .narrow)] {
                let f = PerfChoiceCatalog.facts(shapeTrace: q, settings: settings, tolerance: tolerance)
                facts += "\(index)|\(f.item)|\(f.gen)|\(String(describing: f.level))|\(f.chance)|\(f.slots)|"
                    + "\(String(describing: f.correctChoice))|\(Self.render(.object(f.dealtFields)))\n"
            }
        }
        // (d) Scripted drives' result fields (practice stats, per-shape rows, exposures).
        var drives = ""
        let tolerances = LineMatchTolerance.allCases
        for (index, q) in (Array(plain.prefix(6)) + Array(slant.suffix(6))).enumerated() {
            let board = Self.scriptedDrive(q, tolerance: tolerances[index % tolerances.count], hint: index % 2 == 0)
            // The script really drives: every round finishes, with an excursion, a lift and the red-end touch counted.
            expectTrue(board.isComplete, "scripted drive finishes \(q.itemID)")
            expectTrue(board.offPathCount >= 1 && board.lifts >= 1 && board.reverseDirections == 1)
            expectEqual(board.reversedStrokes.isEmpty, index % 2 == 0)
            drives += "\(q.itemID)|\(board.isComplete)|\(Self.render(.object(board.resultFields)))\n"
        }
        // (e) The settings payload as stored (keys sorted after decoding the stored JSON).
        let suite = "VisaGames.t17.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShapeTraceSettingsStore(defaults: defaults)
        var payload = ""
        for settings in [ShapeTraceSettings.defaults, custom] {
            store.save(settings)
            let data = defaults.data(forKey: ShapeTraceSettingsStore.key) ?? Data()
            let object = try JSONSerialization.jsonObject(with: data)
            let sorted = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            payload += String(decoding: sorted, as: UTF8.self) + "\n"
            expectEqual(store.load(), settings)
        }
        // (f) The app's original path: deal, commit, finish and the 畫形狀設定 setters; the board and settings views.
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        var app = ""
        for signature in ["private func makeShapeTraceBoard(", "private var shapeTraceUsesPlaytest:",
                          "private var shapeTraceInputOpen:", "func shapeTraceCommit(", "private func finishShapeTraceRound(",
                          "func shapeTraceWrongStart(", "func shapeTraceReverse(", "func shapeTraceHintShown(",
                          "func setShapeTraceTolerance(", "func setShapeTraceDirectionHint(", "func setShapeTraceSlantLines(",
                          "private func saveShapeTraceSettings("] {
            let text = body(of: signature, in: model)
            expectFalse(text.isEmpty)
            app += signature + " " + Self.fnv(text) + "\n"
        }
        for path in ["Sources/VisaGames/ShapeTraceBoardView.swift", "Sources/VisaGames/ParentShapeTraceSettingsView.swift"] {
            app += path + " " + Self.fnv(try source(path)) + "\n"
        }
        expectEqual(plain.count, 54)
        expectEqual(slant.count, 54)
        expectEqual(Self.fnv(items), "f8d6c45e44c65db")
        expectEqual(Self.fnv(deals), "ae41c913b7aa7d6a")
        expectEqual(Self.fnv(facts), "26bc7cb97862dfdd")
        expectEqual(Self.fnv(drives), "7474ab619b6d38dc")
        expectEqual(payload, """
            {"cornerStop":true,"directionHint":true,"dotStyle":"dots","slantLines":false,"weights":{"circle":45,"square":35,"triangle":20}}
            {"cornerStop":false,"directionHint":false,"dotStyle":"dashes","slantLines":true,"tolerance":"narrow","weights":{"circle":60,"square":25,"triangle":15}}

            """)
        expectEqual(ShapeTraceSettingsStore.key, "VisaGames.shapeTraceSettings.v1")
        expectEqual(app, """
            private func makeShapeTraceBoard( 941db596bced024a
            private var shapeTraceUsesPlaytest: 95774a40b70614c4
            private var shapeTraceInputOpen: 28325fe1e6edd22a
            func shapeTraceCommit( 90947136ad389e51
            private func finishShapeTraceRound( 1a47780bf71ff52b
            func shapeTraceWrongStart( 5c9232ea3f6c9a93
            func shapeTraceReverse( 2097839bea99e33c
            func shapeTraceHintShown( 79b234f1b6a489ee
            func setShapeTraceTolerance( 6c046b23cbc2daa2
            func setShapeTraceDirectionHint( 184367e55aec52da
            func setShapeTraceSlantLines( d74e564ef0909788
            private func saveShapeTraceSettings( db59c5d84d8e58d1
            Sources/VisaGames/ShapeTraceBoardView.swift af3fd98f212cbd7c
            Sources/VisaGames/ParentShapeTraceSettingsView.swift f640f5a23403a6f6

            """)
        // The original card keeps its family, labels, routes, weekly family and A8 / A9 evidence kinds.
        expectEqual(ActivityKind.allCases.filter(\.isShapeTraceFamily),
                    [.traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree])
        expectEqual(ActivityKind.traceLines.parentCardTitle, "畫直線 · 熱身")
        expectEqual(ActivityKind.traceLines.parentCardEnglish, "Lines · Warm-up")
        expectEqual(WeeklyPracticeFamily.of(kind: "traceLines"), .lines)
        expectEqual(WeeklyArea.of(kind: "traceLines"), .pen)
        let report = try source("Sources/VisaCore/WeeklyReportText.swift")
        expectTrue(report.contains("let shapeKinds = [ActivityKind.traceLines.rawValue, ActivityKind.traceShapesDotted.rawValue,\n                          ActivityKind.traceShapesArrows.rawValue]"))
        expectTrue(report.contains("game.kind == ActivityKind.traceLines.rawValue\n            && claims.isFree(game)"))
        print("  畫直線・四方 T17: 畫直線 · 熱身 byte-identical — 108 items, 60 deals, 8 fact sets, 12 scripted drives, the payload, 12 app paths and 2 views")
    }
}
