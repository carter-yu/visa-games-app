import SwiftUI
import VisaCore

// v0.31.0 筆順動畫 drawing (stroke-order design D2, D3, D5, D9; mockups stroke-order/01–02).
// The smiley pen writes the numeral on the ★ plate, or glances once over the ★★ trace board.
// Pure drawing: no input, no voice, no window or presentation calls (ADR 0011).

enum StrokeOrderDrawing {
    static let ink = Color(hex: 0x2B2630)
    /// The pen leans this far right; left when it would cover the line ahead (D5).
    static let penLean = 28.0 * Double.pi / 180

    /// Where a glyph sits on the stage: `stage = offset + glyph * scale`.
    struct Placement {
        let offset: LineMatchPoint
        let scale: Double
        func point(_ p: LineMatchPoint) -> LineMatchPoint {
            LineMatchPoint(x: offset.x + p.x * scale, y: offset.y + p.y * scale)
        }
    }

    /// Ink written by `t` (or all of it when `t` is nil), in `colour` with an ink outline.
    static func ink(_ timeline: StrokeOrderTimeline, at t: Double?, reduceMotion: Bool, place: Placement,
                    colour: Color, outline: Double, core: Double, opacity: Double = 1, in g: inout GraphicsContext) {
        let glyph = timeline.glyph
        let pose = t.map { timeline.pose(at: $0, reduceMotion: reduceMotion) }
        let reached = t.map { timeline.inked(at: $0, reduceMotion: reduceMotion) }
            ?? glyph.strokes.map { $0.path.length }
        var layer = g
        layer.opacity = g.opacity * opacity
        layer.translateBy(x: place.offset.x, y: place.offset.y)
        layer.scaleBy(x: place.scale, y: place.scale)
        for pass in 0..<2 {
            for (index, stroke) in glyph.strokes.enumerated() where reached[index] > 0.01 {
                // Reduce Motion: the newest chunk fades in (nothing glides, D9).
                var segments: [(Double, Double, Double)] = [(0, reached[index], 1)]
                if let pose, reduceMotion, pose.stroke == index, pose.newestOpacity < 1 {
                    segments = [(0, pose.newestFrom, 1), (pose.newestFrom, reached[index], pose.newestOpacity)]
                }
                for (a, b, alpha) in segments where b > a {
                    let path = ShapeTraceDrawing.segment(stroke.path, from: a, to: b)
                    layer.stroke(path, with: .color(pass == 0 ? ink.opacity(alpha) : colour.opacity(alpha)),
                                 style: StrokeStyle(lineWidth: pass == 0 ? outline : core, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    /// The start dot (white ring + ink centre) and the smiley pen at its nib (D5). Hidden after the write.
    static func pen(_ timeline: StrokeOrderTimeline, at t: Double, reduceMotion: Bool, place: Placement,
                    nibColour: UInt32, penScale: Double, in g: inout GraphicsContext) {
        guard t < timeline.duration else { return }
        let glyph = timeline.glyph
        let pose = timeline.pose(at: t, reduceMotion: reduceMotion)
        guard glyph.strokes.indices.contains(pose.stroke) else { return }
        // 落筆點: where the coming stroke starts (lead-in, a lift, or the first instants of a stroke).
        var dotStroke: Int?
        if let lift = pose.lift { dotStroke = lift.to }
        else if pose.penDown, pose.distance < 1 { dotStroke = pose.stroke }
        if let dotStroke, glyph.strokes.indices.contains(dotStroke) {
            let start = place.point(glyph.strokes[dotStroke].path.start)
            TapCountDrawing.place(TapCountArt.guideStartDot, at: start, scale: penScale * 0.9, in: &g)
        }
        // The nib: on the line, or gliding to the next start during a lift.
        let stroke = glyph.strokes[pose.stroke].path
        var nib = stroke.point(at: min(pose.distance, stroke.length))
        var ahead = stroke.angle(at: min(pose.distance, stroke.length))
        if let lift = pose.lift, glyph.strokes.indices.contains(lift.to) {
            let a = glyph.strokes[lift.from].path
            let b = glyph.strokes[lift.to].path
            let from = a.point(at: a.length), to = b.start
            let u = reduceMotion ? (lift.u < 0.5 ? 0 : 1) : ease(lift.u)
            nib = LineMatchPoint(x: from.x + (to.x - from.x) * u, y: from.y + (to.y - from.y) * u)
            ahead = atan2(to.y - from.y, to.x - from.x)
        }
        let lift = pose.penDown ? 0.0 : 8.0
        let tip = place.point(nib)
        // The body points up-right; if the line ahead runs that way, lean left instead.
        let body = (x: sin(penLean), y: -cos(penLean))
        let dot = cos(ahead) * body.x + sin(ahead) * body.y
        let angle = dot > 0.6 ? -penLean : penLean
        let art = TapCountArt.tinted(TapCountArt.guidePen, body: nibColour)
        TapCountDrawing.place(art, at: LineMatchPoint(x: tip.x, y: tip.y - lift * penScale), scale: penScale,
                              angle: angle, in: &g)
    }

    private static func ease(_ u: Double) -> Double { u * u * (3 - 2 * u) }
}

/// Timelines per numeral and dosage (constant spec, so cached).
@MainActor
enum StrokeOrderCache {
    private static var timelines: [String: StrokeOrderTimeline] = [:]
    static func timeline(_ n: Int, _ dosage: StrokeOrderDosage) -> StrokeOrderTimeline? {
        let key = "\(n).\(dosage.rawValue)"
        if let hit = timelines[key] { return hit }
        guard let made = StrokeOrderTimeline.digit(n, dosage: dosage) else { return nil }
        timelines[key] = made
        return made
    }
}
