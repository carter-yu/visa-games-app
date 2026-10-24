import Foundation

/// A centre-line stroke in the four-line house (top 30, midline 130, baseline 270, descender 350).
public struct LatinStroke: Sendable, Equatable {
    public let svg: String
    public let corners: [LineMatchPoint]
    public let cusps: [LineMatchPoint]
    public let closed: Bool

    public init(_ svg: String, corners: [LineMatchPoint] = [], cusps: [LineMatchPoint] = [], closed: Bool = false) {
        self.svg = svg
        self.corners = corners
        self.cusps = cusps
        self.closed = closed
    }
}

/// Authored Latin centre lines from letter-tap design section 8.2.
public enum LatinGlyphs {
    public static let boxSize = (width: 190.0, height: 380.0)
    public static let laneWidth: Double = 36
    public static let laneInkWidth: Double = 46
    public static let supported: [Character] = ["a", "b", "c", "d", "e", "g", "k", "o", "u"]

    private static func p(_ x: Double, _ y: Double) -> LineMatchPoint { LineMatchPoint(x: x, y: y) }

    /// Learning Without Tears default order. Unsupported characters have no strokes.
    public static func strokes(_ letter: Character) -> [LatinStroke] {
        switch letter {
        case "a": return [LatinStroke("M142 152 C132 138 116 130 96 130 C62 130 40 162 40 200 C40 240 64 270 96 270 C122 270 140 252 146 226 L148 130 L148 270", cusps: [p(148, 130)])]
        case "b": return [LatinStroke("M44 30 L44 270 L44 186 C52 150 74 130 104 130 C138 130 160 162 160 200 C160 240 136 270 104 270 C80 270 58 260 46 244", cusps: [p(44, 270)])]
        case "c": return [LatinStroke("M146 154 C134 138 116 130 96 130 C62 130 40 162 40 200 C40 240 64 270 96 270 C118 270 136 260 148 242")]
        case "d": return [LatinStroke("M142 152 C132 138 116 130 96 130 C62 130 40 162 40 200 C40 240 64 270 96 270 C122 270 140 252 146 226 L148 30 L148 270", cusps: [p(148, 30)])]
        case "e": return [LatinStroke("M42 202 L154 202 C154 160 130 130 96 130 C62 130 40 162 40 202 C40 242 66 270 98 270 C122 270 140 260 152 244")]
        case "g": return [LatinStroke("M142 152 C132 138 116 130 96 130 C62 130 40 162 40 200 C40 240 64 270 96 270 C122 270 140 252 146 226 L148 130 L148 296 C148 334 126 350 96 350 C72 350 56 342 46 330", cusps: [p(148, 130)])]
        case "k": return [LatinStroke("M44 30 L44 270"), LatinStroke("M146 130 L52 208 L150 270", corners: [p(52, 208)])]
        case "o": return [LatinStroke("M96 130 C62 130 40 162 40 200 C40 240 62 270 96 270 C130 270 152 240 152 200 C152 162 130 130 96 130", closed: true)]
        case "u": return [LatinStroke("M44 130 L44 216 C44 250 66 270 96 270 C126 270 148 250 148 216 L148 130 L148 270", cusps: [p(148, 130)])]
        default: return []
        }
    }

    /// School ball-stick forms explicitly authored in design section 8.2.
    public static func ballStickStrokes(_ letter: Character) -> [LatinStroke] {
        let bowl = "M146 154 C134 138 116 130 96 130 C62 130 40 162 40 200 C40 240 64 270 96 270 C118 270 136 260 148 242"
        switch letter {
        case "a": return [LatinStroke(bowl), LatinStroke("M150 130 L150 270")]
        case "b": return [LatinStroke("M44 30 L44 270"), LatinStroke("M46 168 C58 144 78 130 104 130 C138 130 160 162 160 200 C160 240 136 270 104 270 C80 270 58 260 46 244")]
        case "d": return [LatinStroke(bowl), LatinStroke("M150 30 L150 270")]
        default: return []
        }
    }

    public static func paths(_ letter: Character, offset: LineMatchPoint, scale: Double) -> [TracePath] {
        strokes(letter).map { TracePath(svg: $0.svg, scale: scale, offset: offset,
                                        corners: $0.corners, cusps: $0.cusps, closed: $0.closed) }
    }
}

extension StrokeGlyph {
    private static func adapt(_ paths: [TracePath]) -> [Stroke] {
        paths.map { path in
            let candidates = path.corners + path.cusps
            let turns = candidates.filter { $0 > 0.5 && $0 < path.length - 0.5 }.sorted()
            return Stroke(path: path, turns: turns, kind: nil)
        }
    }

    public static func latin(_ letter: Character) -> StrokeGlyph? {
        guard LatinGlyphs.supported.contains(letter) else { return nil }
        let origin = LineMatchPoint(x: 0, y: 0)
        let alternatePaths = LatinGlyphs.ballStickStrokes(letter).map {
            TracePath(svg: $0.svg, corners: $0.corners, cusps: $0.cusps, closed: $0.closed)
        }
        let strokes = adapt(LatinGlyphs.paths(letter, offset: origin, scale: 1))
        var alternates: [String: [Stroke]] = [:]
        if !alternatePaths.isEmpty {
            alternates["latin:\(letter).ballstick"] = adapt(alternatePaths)
        }
        return StrokeGlyph(id: "latin:\(letter)", script: .latin,
                           strokes: strokes,
                           box: LatinGlyphs.boxSize, progressKey: String(letter), orderStandard: "LWT",
                           alternates: alternates)
    }
}
