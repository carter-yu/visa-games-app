import Foundation
import VisaCore

final class LatinGlyphTests {
    private let letters: [Character] = ["a", "b", "c", "d", "e", "g", "k", "o", "u"]

    func testCatalogPathsAndStarts() {
        let starts: [Character: [(Double, Double)]] = [
            "a": [(142, 152)], "b": [(44, 30)], "c": [(146, 154)],
            "d": [(142, 152)], "e": [(42, 202)], "g": [(142, 152)],
            "k": [(44, 30), (146, 130)], "o": [(96, 130)], "u": [(44, 130)]
        ]
        for letter in letters {
            let paths = LatinGlyphs.paths(letter, offset: LineMatchPoint(x: 0, y: 0), scale: 1)
            expectEqual(paths.count, starts[letter]!.count, "stroke count for \(letter)")
            for (path, start) in zip(paths, starts[letter]!) {
                expectEqual(path.start.x, start.0, accuracy: 0.01)
                expectEqual(path.start.y, start.1, accuracy: 0.01)
                expectTrue(path.length > 80, "parsed path for \(letter)")
                for index in 0..<(path.points.count - 1) {
                    expectTrue(path.points[index].distance(to: path.points[index + 1]) <= TracePath.sampleSpacing + 0.01)
                }
            }
            let glyph = StrokeGlyph.latin(letter)!
            expectEqual(glyph.id, "latin:\(letter)")
            expectEqual(glyph.script, .latin)
            expectEqual(glyph.strokes.map(\.path), paths)
            expectEqual(glyph.orderStandard, "LWT")
        }
        expectNil(StrokeGlyph.latin("f"))
        expectNil(StrokeGlyph.latin("A"))
    }

    func testGlyphEqualityIncludesLatinMetadata() {
        let latin = StrokeGlyph.latin("a")!
        let same = StrokeGlyph.latin("a")!
        expectEqual(latin, same)
        let differentOrder = StrokeGlyph(id: latin.id, script: latin.script, strokes: latin.strokes,
                                         box: latin.box, progressKey: latin.progressKey,
                                         orderStandard: "ballstick", alternates: latin.alternates)
        expectFalse(latin == differentOrder)
        let noAlternates = StrokeGlyph(id: latin.id, script: latin.script, strokes: latin.strokes,
                                       box: latin.box, progressKey: latin.progressKey)
        expectFalse(latin == noAlternates)
        let differentKey = StrokeGlyph(id: latin.id, script: latin.script, strokes: latin.strokes,
                                       box: latin.box, progressKey: "other", alternates: latin.alternates)
        expectFalse(latin == differentKey)
        let differentScript = StrokeGlyph(id: latin.id, script: .digit, strokes: latin.strokes,
                                          box: latin.box, progressKey: latin.progressKey, alternates: latin.alternates)
        expectFalse(latin == differentScript)
    }

    func testTurnsAlternatesAndHouseLines() {
        let cusps: [Character: (Double, Double)] = ["a": (148, 130), "b": (44, 270),
                                                   "d": (148, 30), "g": (148, 130), "u": (148, 130)]
        for letter in letters {
            let paths = LatinGlyphs.paths(letter, offset: LineMatchPoint(x: 0, y: 0), scale: 1)
            let allCusps = paths.flatMap(\.cusps)
            if let target = cusps[letter] {
                expectEqual(allCusps.count, 1, "cusp for \(letter)")
                let path = paths.first { !$0.cusps.isEmpty }!
                let point = path.point(at: path.cusps[0])
                expectEqual(point.x, target.0, accuracy: 0.5)
                expectEqual(point.y, target.1, accuracy: 0.5)
                expectTrue(path.cusps[0] > 0 && path.cusps[0] < path.length)
            } else { expectTrue(allCusps.isEmpty) }
            for path in paths {
                expectTrue(path.points.allSatisfy { $0.x >= 0 && $0.x <= LatinGlyphs.boxSize.width
                    && $0.y >= 30 && $0.y <= 350 }, "house box for \(letter)")
            }
        }
        let kTurn = LatinGlyphs.paths("k", offset: LineMatchPoint(x: 0, y: 0), scale: 1)[1]
        expectEqual(kTurn.corners.count, 1)
        expectEqual(kTurn.point(at: kTurn.corners[0]), LineMatchPoint(x: 52, y: 208))
        expectTrue(LatinGlyphs.paths("o", offset: LineMatchPoint(x: 0, y: 0), scale: 1)[0].closed)
        for letter in [Character("a"), "b", "d"] {
            let alternate = StrokeGlyph.latin(letter)!.alternates["latin:\(letter).ballstick"]
            expectEqual(alternate?.count, 2)
            expectTrue(alternate!.allSatisfy { $0.path.length > 100 })
        }
    }

    func testMagicCAndStickStartsAndFixture() {
        let a = "M142 152 C132 138 116 130 96 130 C62 130 40 162 40 200 C40 240 64 270 96 270 C122 270 140 252 146 226 L148 130 L148 270"
        expectEqual(LatinGlyphs.strokes("a")[0].svg, a)
        let cPrefix = "C132 138 116 130 96 130 C62 130 40 162 40 200 C40 240 64 270 96 270"
        for letter in [Character("a"), "d", "g"] {
            expectTrue(LatinGlyphs.strokes(letter)[0].svg.contains(cPrefix), "Magic-c start for \(letter)")
        }
        expectTrue(LatinGlyphs.strokes("b")[0].svg.hasPrefix("M44 30 L44 270"))
        expectEqual(LatinGlyphs.strokes("k")[0].svg, "M44 30 L44 270")
    }

    func testPathsCompleteAtExistingTolerances() {
        for letter in letters {
            let paths = LatinGlyphs.paths(letter, offset: LineMatchPoint(x: 0, y: 0), scale: 1)
            let shape = ShapeTraceShape(slot: "latin", kind: .numeral, strokes: paths, colorIndex: 0,
                                        frame: LineMatchRect(x: 0, y: 0, width: 190, height: 380))
            let question = ShapeTraceQuestion(itemID: "latin:\(letter)", kind: .tapCountTrace, level: .l1,
                scene: .numeralBoard, shift: 0, big: false, slant: false, shapes: [shape], laneWidth: LatinGlyphs.laneWidth,
                promptKey: "", promptTraditionalChinese: "", promptEnglish: "")
            for tolerance in [LineMatchTolerance.narrow, .standard, .wide] {
                var board = ShapeTraceBoard(question: question, tolerance: tolerance, directionHint: true)
                var clock = 0.0
                var attempts = 0
                while !board.isComplete && attempts < paths.count + 2 {
                    attempts += 1
                    guard let path = board.currentPath else { break }
                    clock += 0.1
                    _ = board.penDown(at: path.start, now: clock)
                    var distance = 0.0
                    while distance <= path.length + 16 {
                        clock += 0.02
                        let move = board.penMove(to: path.point(at: min(distance, path.length)), now: clock)
                        if case .strokeDone = move { break }
                        if case .shapeDone = move { break }
                        if case .allDone = move { break }
                        distance += 6
                    }
                    board.penUp()
                }
                expectTrue(board.isComplete, "\(letter) at \(tolerance)")
            }
        }
    }
}
