import Foundation

/// One absolute drawing step from SVG path data.
public enum SVGPathCommand: Equatable, Sendable {
    case move(x: Double, y: Double)
    case line(x: Double, y: Double)
    case quad(cx: Double, cy: Double, x: Double, y: Double)
    case cubic(c1x: Double, c1y: Double, c2x: Double, c2y: Double, x: Double, y: Double)
    case close
}

public enum SVGPathParseError: Error, Equatable, Sendable {
    case missingCommand
    case unsupportedCommand(String)
    case expectedNumber(offset: Int)
}

/// Minimal SVG path-data parser so the canvas artwork can be carried over verbatim (ADR 0007).
/// Supports M L H V Q T C S A Z in absolute and relative forms; arcs become cubic segments.
public enum SVGPathData {
    public static func parse(_ data: String) throws -> [SVGPathCommand] {
        var reader = Reader(scalars: Array(data.unicodeScalars))
        var commands: [SVGPathCommand] = []
        var current = (x: 0.0, y: 0.0)
        var subpathStart = current
        var lastQuadControl: (x: Double, y: Double)?
        var lastCubicControl: (x: Double, y: Double)?
        var command: Character?

        while true {
            reader.skipSeparators()
            if reader.isAtEnd { break }
            if let letter = reader.readCommandLetter() {
                command = letter
            } else if command == nil || command == "Z" || command == "z" {
                throw SVGPathParseError.missingCommand
            }
            guard let active = command else { throw SVGPathParseError.missingCommand }
            let relative = active.isLowercase
            let base = relative ? current : (x: 0.0, y: 0.0)
            var quadControl: (x: Double, y: Double)?
            var cubicControl: (x: Double, y: Double)?

            switch active {
            case "M", "m":
                let x = try reader.number() + base.x, y = try reader.number() + base.y
                commands.append(.move(x: x, y: y))
                current = (x, y)
                subpathStart = current
                command = relative ? "l" : "L" // further pairs are implicit lines
            case "L", "l":
                let x = try reader.number() + base.x, y = try reader.number() + base.y
                commands.append(.line(x: x, y: y))
                current = (x, y)
            case "H", "h":
                let x = try reader.number() + (relative ? current.x : 0)
                commands.append(.line(x: x, y: current.y))
                current.x = x
            case "V", "v":
                let y = try reader.number() + (relative ? current.y : 0)
                commands.append(.line(x: current.x, y: y))
                current.y = y
            case "Q", "q":
                let cx = try reader.number() + base.x, cy = try reader.number() + base.y
                let x = try reader.number() + base.x, y = try reader.number() + base.y
                commands.append(.quad(cx: cx, cy: cy, x: x, y: y))
                quadControl = (cx, cy)
                current = (x, y)
            case "T", "t":
                let control = lastQuadControl.map { (2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current
                let x = try reader.number() + base.x, y = try reader.number() + base.y
                commands.append(.quad(cx: control.0, cy: control.1, x: x, y: y))
                quadControl = (control.0, control.1)
                current = (x, y)
            case "C", "c":
                let c1x = try reader.number() + base.x, c1y = try reader.number() + base.y
                let c2x = try reader.number() + base.x, c2y = try reader.number() + base.y
                let x = try reader.number() + base.x, y = try reader.number() + base.y
                commands.append(.cubic(c1x: c1x, c1y: c1y, c2x: c2x, c2y: c2y, x: x, y: y))
                cubicControl = (c2x, c2y)
                current = (x, y)
            case "S", "s":
                let c1 = lastCubicControl.map { (2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current
                let c2x = try reader.number() + base.x, c2y = try reader.number() + base.y
                let x = try reader.number() + base.x, y = try reader.number() + base.y
                commands.append(.cubic(c1x: c1.0, c1y: c1.1, c2x: c2x, c2y: c2y, x: x, y: y))
                cubicControl = (c2x, c2y)
                current = (x, y)
            case "A", "a":
                let rx = try reader.number(), ry = try reader.number(), rotation = try reader.number()
                let largeArc = try reader.flag(), sweep = try reader.flag()
                let x = try reader.number() + base.x, y = try reader.number() + base.y
                commands.append(contentsOf: arcToCubics(from: current, to: (x, y), rx: rx, ry: ry,
                                                        rotationDegrees: rotation, largeArc: largeArc, sweep: sweep))
                current = (x, y)
            case "Z", "z":
                commands.append(.close)
                current = subpathStart
            default:
                throw SVGPathParseError.unsupportedCommand(String(active))
            }
            lastQuadControl = quadControl
            lastCubicControl = cubicControl
        }
        return commands
    }

    /// SVG 1.1 implementation notes F.6.5/F.6.6: endpoint arc → centre form → cubic segments ≤ 90°.
    private static func arcToCubics(from start: (x: Double, y: Double), to end: (x: Double, y: Double),
                                    rx rawRX: Double, ry rawRY: Double, rotationDegrees: Double,
                                    largeArc: Bool, sweep: Bool) -> [SVGPathCommand] {
        if start.x == end.x && start.y == end.y { return [] }
        var rx = abs(rawRX), ry = abs(rawRY)
        if rx == 0 || ry == 0 { return [.line(x: end.x, y: end.y)] }
        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx2 = (start.x - end.x) / 2, dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coefficient = (largeArc == sweep ? -1.0 : 1.0) * max(0, numerator / denominator).squareRoot()
        let cxp = coefficient * rx * y1p / ry
        let cyp = coefficient * -ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        func point(_ t: Double) -> (Double, Double) {
            (cx + rx * cosPhi * cos(t) - ry * sinPhi * sin(t), cy + rx * sinPhi * cos(t) + ry * cosPhi * sin(t))
        }
        func derivative(_ t: Double) -> (Double, Double) {
            (-rx * cosPhi * sin(t) - ry * sinPhi * cos(t), -rx * sinPhi * sin(t) + ry * cosPhi * cos(t))
        }
        let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / Double(segments)
        let alpha = 4.0 / 3.0 * tan(step / 4)
        var result: [SVGPathCommand] = []
        var t = theta1
        for index in 0..<segments {
            let t2 = t + step
            let p0 = point(t), d0 = derivative(t)
            let d1 = derivative(t2)
            let p3 = index == segments - 1 ? (end.x, end.y) : point(t2)
            result.append(.cubic(c1x: p0.0 + alpha * d0.0, c1y: p0.1 + alpha * d0.1,
                                 c2x: p3.0 - alpha * d1.0, c2y: p3.1 - alpha * d1.1,
                                 x: p3.0, y: p3.1))
            t = t2
        }
        return result
    }

    private struct Reader {
        let scalars: [Unicode.Scalar]
        var index = 0

        var isAtEnd: Bool { index >= scalars.count }

        mutating func skipSeparators() {
            while index < scalars.count, scalars[index] == "," || scalars[index].properties.isWhitespace {
                index += 1
            }
        }

        mutating func readCommandLetter() -> Character? {
            guard index < scalars.count else { return nil }
            let scalar = scalars[index]
            guard scalar.properties.isAlphabetic, scalar != "e", scalar != "E" else { return nil }
            index += 1
            return Character(scalar)
        }

        mutating func number() throws -> Double {
            skipSeparators()
            let start = index
            if index < scalars.count, scalars[index] == "-" || scalars[index] == "+" { index += 1 }
            var sawDigit = false, sawDot = false
            while index < scalars.count {
                let scalar = scalars[index]
                if ("0"..."9").contains(scalar) {
                    sawDigit = true
                } else if scalar == ".", !sawDot {
                    sawDot = true
                } else {
                    break
                }
                index += 1
            }
            if sawDigit, index < scalars.count, scalars[index] == "e" || scalars[index] == "E" {
                var lookahead = index + 1
                if lookahead < scalars.count, scalars[lookahead] == "-" || scalars[lookahead] == "+" { lookahead += 1 }
                if lookahead < scalars.count, ("0"..."9").contains(scalars[lookahead]) {
                    index = lookahead
                    while index < scalars.count, ("0"..."9").contains(scalars[index]) { index += 1 }
                }
            }
            guard sawDigit, let value = Double(String(String.UnicodeScalarView(scalars[start..<index]))) else {
                index = start
                throw SVGPathParseError.expectedNumber(offset: start)
            }
            return value
        }

        /// Arc flags are single 0/1 digits and may be packed without separators ("a4 4 0 01 0 6").
        mutating func flag() throws -> Bool {
            skipSeparators()
            guard index < scalars.count, scalars[index] == "0" || scalars[index] == "1" else {
                throw SVGPathParseError.expectedNumber(offset: index)
            }
            defer { index += 1 }
            return scalars[index] == "1"
        }
    }
}
