import Foundation

// 一架一架數 numerals 0–10 (v0.28.0, design number-quantity §6, mockup 10, ADR 0017).
// Learning Without Tears stroke order (Q4 default): 4 and 5 in two strokes, 9 in one (up to the
// corner, then straight down), 0 anticlockwise from 12 o'clock like the shape-trace circle.
// Path data is copied verbatim from the Opus stroke-order sheet; nothing here is redrawn.

/// One stroke of a numeral in its glyph box (x right, y down).
public struct NumeralStroke: Sendable, Equatable {
    public let svg: String
    /// Stop-and-turn points (the vehicle waits there; 「停！轉彎！」).
    public let corners: [LineMatchPoint]
    /// Turn-back points (3's middle, 9's top corner): the search window never looks behind them.
    public let cusps: [LineMatchPoint]
    public let closed: Bool

    public init(_ svg: String, corners: [LineMatchPoint] = [], cusps: [LineMatchPoint] = [], closed: Bool = false) {
        self.svg = svg
        self.corners = corners
        self.cusps = cusps
        self.closed = closed
    }
}

public enum NumeralGlyphs {
    /// Glyph box of 0–9 (mockup 10). 10 uses a 320 × 300 box.
    public static let boxSize = (width: 200.0, height: 300.0)
    public static let tenBoxSize = (width: 320.0, height: 300.0)
    /// Drawn lane width in glyph units (mockup 03: ink 76, pale 64).
    public static let laneWidth: Double = 64
    public static let laneInkWidth: Double = 76

    public static let supported = 0...10

    private static func p(_ x: Double, _ y: Double) -> LineMatchPoint { LineMatchPoint(x: x, y: y) }

    public static func strokes(_ n: Int) -> [NumeralStroke] {
        switch n {
        case 0:
            return [NumeralStroke("M100 30 A66 120 0 1 0 100 270 A66 120 0 1 0 100 30", closed: true)]
        case 1:
            return [NumeralStroke("M100 30 V270")]
        case 2:
            return [NumeralStroke("M40 92 C46 52 72 30 104 30 C140 30 166 56 166 92 C166 128 142 152 116 180 L34 270 L172 270",
                                  corners: [p(34, 270)])]
        case 3:
            return [NumeralStroke("M44 64 C56 40 78 30 104 30 C138 30 162 52 162 84 C162 118 134 140 94 144 C138 146 170 172 170 210 C170 248 140 272 102 272 C72 272 50 260 36 238",
                                  cusps: [p(94, 144)])]
        case 4:
            return [NumeralStroke("M62 30 L24 192 L180 192", corners: [p(24, 192)]),
                    NumeralStroke("M120 30 V272")]
        case 5:
            return [NumeralStroke("M58 32 L50 132 C70 116 96 110 116 112 C152 116 176 144 176 184 C176 234 140 272 98 272 C70 272 50 262 34 244",
                                  corners: [p(50, 132)]),
                    NumeralStroke("M58 32 H168")]
        case 6:
            return [NumeralStroke("M150 42 C120 28 84 32 64 62 C44 92 36 136 36 186 C36 238 64 272 104 272 C144 272 170 242 170 204 C170 164 142 138 106 138 C72 138 48 160 38 188")]
        case 7:
            return [NumeralStroke("M32 36 H170 L80 272", corners: [p(170, 36)])]
        case 8:
            return [NumeralStroke("M104 30 C70 30 44 52 44 86 C44 118 72 134 100 146 C136 162 166 182 166 214 C166 250 138 272 100 272 C62 272 34 250 34 214 C34 182 64 162 100 146 C128 134 156 118 156 86 C156 52 132 30 104 30",
                                  closed: true)]
        case 9:
            return [NumeralStroke("M164 40 C150 32 128 30 104 30 C68 30 42 58 42 92 C42 128 68 152 102 152 C130 152 152 136 162 108 L164 40 L164 272",
                                  cusps: [p(164, 40)])]
        case 10:
            return [NumeralStroke("M52 30 V270"),
                    NumeralStroke("M214 30 A72 120 0 1 0 214 270 A72 120 0 1 0 214 30", closed: true)]
        default:
            return []
        }
    }

    /// Glyph box size for `n`.
    public static func box(_ n: Int) -> (width: Double, height: Double) {
        n == 10 ? tenBoxSize : boxSize
    }

    /// Trace board on the stage (mockups 03 / 07: 380 × 314 at 450,224; 08: 440 × 314 at 420,224 for 10).
    public static func traceBoard(_ n: Int) -> LineMatchRect {
        n == 10 ? LineMatchRect(x: 420, y: 224, width: 440, height: 314)
                : LineMatchRect(x: 450, y: 224, width: 380, height: 314)
    }

    /// Glyph placement on the trace board: scale 0.92 (03 / 07) or 0.9 for 10 (08), centred on x 640.
    public static func tracePlacement(_ n: Int) -> (offset: LineMatchPoint, scale: Double) {
        let scale = n == 10 ? 0.9 : 0.92
        let width = box(n).width * scale
        return (LineMatchPoint(x: 640 - width / 2, y: n == 10 ? 245 : 241), scale)
    }

    /// Stage-unit trace paths of `n` at `offset` / `scale`.
    public static func paths(_ n: Int, offset: LineMatchPoint, scale: Double) -> [TracePath] {
        strokes(n).map {
            TracePath(svg: $0.svg, scale: scale, offset: offset, corners: $0.corners, cusps: $0.cusps, closed: $0.closed)
        }
    }

    /// The numeral as a one-shape trace question for the shared `ShapeTraceBoard` (design §11.2.4).
    public static func traceQuestion(_ n: Int, itemID: String, kind: ActivityKind, colorIndex: Int) -> ShapeTraceQuestion {
        let placement = tracePlacement(n)
        let size = box(n)
        let frame = LineMatchRect(x: placement.offset.x, y: placement.offset.y,
                                  width: size.width * placement.scale, height: size.height * placement.scale)
        let shape = ShapeTraceShape(slot: "numeral\(n)", kind: .numeral,
                                    strokes: paths(n, offset: placement.offset, scale: placement.scale),
                                    colorIndex: colorIndex, frame: frame)
        return ShapeTraceQuestion(
            itemID: itemID, kind: kind, level: .l1, scene: .numeralBoard, shift: 0, big: false, slant: false,
            shapes: [shape], laneWidth: laneWidth * placement.scale, promptKey: "tapCount.trace.prompt.\(n)",
            promptTraditionalChinese: TapCountCopy.tracePrompt(n).traditionalChinese,
            promptEnglish: TapCountCopy.tracePrompt(n).english
        )
    }
}
