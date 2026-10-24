import SwiftUI
import VisaCore

// v0.30.0 guidance drawing for the 1–10 trace board (★★ / ★★★, Cantonese and English cards alike).
// Mockups: visa-games-design/number-quantity/guidance/01 (demo car), 02 (headlights + crossing sign),
// 03 (hop to the next stroke). Copy, timing, cue points and art come from the Opus spec
// (docs/tap-count-guidance-spec.json → TapCountGuideData). Nothing here can mark the child wrong:
// tracing is never wrong, and the demo never takes input away (the first touch ends it).

/// What the still board draws for guidance (headlights, the cue sign, the watch badge, faded strokes).
struct TapCountGuideDraw {
    let plan: TapCountGuidePlan
    let numeral: NumeralGuide
    /// The demo is on screen: no headlights or signs; the 「睇住」 badge shows.
    let demo: Bool
    /// Arc distances of the lit lane dots ahead of the car.
    let headlights: [Double]
    let cue: NumeralGuide.Cue?
    let popAt: Double?
    let stopWord: String
    let reduceMotion: Bool
    let now: Double
}

/// What the animated layer draws: the ghost car and its route, hops, help ghosts, the paint car.
struct TapCountGuideMotionState {
    let numeral: NumeralGuide
    let timeline: TapCountDemoTimeline?
    let run: TapCountGuideRun
    let trace: ShapeTraceBoard
    let help: TapCountGuideHelp
    let wiggleAt: Double?
    let reduceMotion: Bool
    let board: LineMatchRect
    let stopWord: String
    /// v0.31.0 筆順動畫: the pen's silent glance (識咗 at 標準); nil = the car demo or nothing.
    var glance: StrokeOrderTimeline? = nil
    var glanceColour: UInt32 = 0xFFC93C
}

/// Guides and demo timelines per numeral (the spec is a constant, so they never change).
@MainActor
enum TapCountGuideCache {
    private static var guides: [Int: NumeralGuide] = [:]
    private static var timelines: [Int: TapCountDemoTimeline] = [:]

    static func guide(_ n: Int) -> NumeralGuide? {
        if let cached = guides[n] { return cached }
        guard let made = NumeralGuide(n) else { return nil }
        guides[n] = made
        return made
    }

    static func timeline(_ n: Int) -> TapCountDemoTimeline? {
        if let cached = timelines[n] { return cached }
        guard let guide = guide(n) else { return nil }
        let made = TapCountDemoTimeline(guide: guide)
        timelines[n] = made
        return made
    }
}

extension TapCountDrawing {
    private static var styles: TapCountGuideStyles { TapCountGuideData.styles }

    private static func ease(_ u: Double) -> Double { u * u * (3 - 2 * u) }

    // MARK: Still board

    /// 車頭燈: a soft beam from the car's nose to the last lit dot, a chevron on each lit dot.
    static func guideHeadlights(_ guide: TapCountGuideDraw, path: TracePath, progress: Double, scale k: Double,
                                in g: inout GraphicsContext) {
        guard let last = guide.headlights.last else { return }
        let from = min(path.length, progress + TapCountGuideCoach.noseUnits * 0.5)
        let to = min(path.length, last + 10)
        if to > from {
            let beam = ShapeTraceDrawing.segment(path, from: from, to: to)
            g.stroke(beam, with: .color(Color(hex: styles.beamOuter)),
                     style: StrokeStyle(lineWidth: styles.beamOuterWidth * k, lineCap: .round, lineJoin: .round))
            g.stroke(beam, with: .color(Color(hex: styles.beamInner, opacity: styles.beamInnerOpacity)),
                     style: StrokeStyle(lineWidth: styles.beamInnerWidth * k, lineCap: .round, lineJoin: .round))
        }
        for d in guide.headlights {
            place(TapCountArt.guideChev, at: path.point(at: d), scale: k, angle: path.angle(at: d), in: &g)
        }
    }

    /// The crossing (直行) or turn (停) sign beside the cue point, with a pop when it appears.
    static func guideCueSign(_ cue: NumeralGuide.Cue, guide: TapCountGuideDraw, opacity: Double = 1,
                             in g: inout GraphicsContext) {
        if let at = guide.popAt, !guide.reduceMotion {
            let u = (guide.now - at) / 0.45
            if u >= 0, u < 1 {
                place(TapCountArt.guidePop, at: cue.signPoint, scale: 0.6 + 0.6 * u, opacity: 1 - u, in: &g)
            }
        }
        cueSign(cue, stopWord: guide.stopWord, opacity: opacity, in: &g)
    }

    static func cueSign(_ cue: NumeralGuide.Cue, stopWord: String, opacity: Double = 1, in g: inout GraphicsContext) {
        switch cue.sign {
        case .ahead:
            place(TapCountArt.guideAhead, at: cue.signPoint, opacity: opacity, in: &g)
        case .stop:
            var layer = g
            layer.opacity = g.opacity * opacity
            stopSign(at: cue.signPoint, scale: 0.8, word: stopWord, in: &layer)
        }
    }

    /// The red stop sign; its word (停 / STOP) comes from the spec's copy.
    static func stopSign(at p: LineMatchPoint, scale s: Double, word: String, in g: inout GraphicsContext) {
        place(TapCountArt.guideStop, at: p, scale: s, in: &g)
        let latin = word.unicodeScalars.allSatisfy { $0.value < 0x2E80 }
        let size = (latin ? 19.0 : 32.0) * s
        g.draw(Text(word).font(CanvasFont.font(size: size, weight: 900)).foregroundColor(.white),
               at: CGPoint(x: p.x, y: p.y), anchor: .center)
    }

    /// 「睇住」 badge on the board's top-left corner while the demo plays (mockup guidance/01).
    static func guideWatchBadge(board: CGRect, in g: inout GraphicsContext) {
        let r = CGRect(x: board.minX + 12, y: board.minY + 12, width: 74, height: 40)
        g.fill(Path(roundedRect: r, cornerRadius: 20), with: .color(.white))
        g.stroke(Path(roundedRect: r, cornerRadius: 20), with: .color(ink), lineWidth: 4)
        place(TapCountArt.guideEye, at: LineMatchPoint(x: r.minX + 25, y: r.midY), scale: 0.8, in: &g)
        var play = Path()
        play.move(to: CGPoint(x: r.minX + 49, y: r.midY - 9))
        play.addLine(to: CGPoint(x: r.minX + 63, y: r.midY))
        play.addLine(to: CGPoint(x: r.minX + 49, y: r.midY + 9))
        play.closeSubpath()
        g.fill(play, with: .color(yellow))
        g.stroke(play, with: .color(ink), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
    }

    // MARK: Animated layer

    static func guideMotion(_ m: TapCountGuideMotionState, now: Double, in g: inout GraphicsContext) {
        let k = m.numeral.scale
        let trace = m.trace
        let timing = TapCountGuideData.timing
        // 筆順 glance: the smiley pen writes the numeral once over the road; the ink fades in 1.5 s.
        if let glance = m.glance, m.run.isGlance {
            let place = StrokeOrderDrawing.Placement(offset: m.numeral.offset, scale: k)
            if let t = m.run.glanceTime(now: now) {
                if t >= 0 {
                    StrokeOrderDrawing.ink(glance, at: t, reduceMotion: m.reduceMotion, place: place,
                                           colour: Color(hex: m.glanceColour), outline: 34, core: 22, opacity: 0.9, in: &g)
                    StrokeOrderDrawing.pen(glance, at: t, reduceMotion: m.reduceMotion, place: place,
                                           nibColour: m.glanceColour, penScale: 0.85, in: &g)
                }
                paintCar(m, now: now, in: &g)
                return
            }
            if let dt = m.run.glanceEndedFor(now: now), dt < StrokeOrderPacing.inkFadeSeconds {
                StrokeOrderDrawing.ink(glance, at: nil, reduceMotion: m.reduceMotion, place: place,
                                       colour: Color(hex: m.glanceColour), outline: 34, core: 22,
                                       opacity: 0.9 * (1 - dt / StrokeOrderPacing.inkFadeSeconds), in: &g)
            }
        }
        // The demo: route (fading behind the car), a blinking sign at each cue stop, the ghost car.
        if !m.run.isGlance, let timeline = m.timeline, let t = m.run.demoTime(now: now), t >= 0 {
            demoRoute(timeline, at: t, reduceMotion: m.reduceMotion, scale: k, in: &g)
            if let index = timeline.pausedCue(at: t), let cue = m.numeral.cues.first(where: { $0.index == index }) {
                let blink = m.reduceMotion ? 1 : 0.55 + 0.45 * sin(now * 14)
                cueSign(cue, stopWord: m.stopWord, opacity: blink, in: &g)
            }
            if let pose = timeline.pose(at: t, reduceMotion: m.reduceMotion) {
                if let hop = pose.hop { hopArc(m.numeral, from: hop.from, to: hop.to, in: &g) }
                ghostCar(pose, in: &g)
            }
            paintCar(m, now: now, in: &g)
            return
        }
        // The child's turn.
        if m.run.plan.hops, trace.strokeIndex > 0, trace.progress < 0.5, let at = trace.lastProgressAt {
            let from = trace.strokeIndex - 1
            let to = trace.strokeIndex
            let dt = now - at
            // The new stroke lights up with a soft glow; its ② badge pulses.
            let lit = dt - timing.hopSeconds
            if lit >= 0, lit < styles.litGlowSeconds, !m.reduceMotion, m.numeral.paths.indices.contains(to) {
                let u = lit / styles.litGlowSeconds
                g.stroke(ShapeTraceDrawing.whole(m.numeral.paths[to]),
                         with: .color(Color(hex: styles.litGlow, opacity: styles.litGlowOpacity * 0.5 * (1 - u))),
                         style: StrokeStyle(lineWidth: styles.litGlowWidth * k, lineCap: .round, lineJoin: .round))
            }
            if dt >= 0, dt < timing.hopSeconds + styles.litGlowSeconds, !m.reduceMotion, m.numeral.paths.indices.contains(to) {
                let start = m.numeral.paths[to].start
                let c = LineMatchPoint(x: max(m.board.x + 20, start.x - 34), y: max(m.board.y + 20, start.y - 30))
                let u = dt / (timing.hopSeconds + styles.litGlowSeconds)
                let r = 15 + 16 * u
                g.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(yellow.opacity(1 - u)), lineWidth: 5)
            }
            if !m.reduceMotion, let u = TapCountGuideCoach.hopping(trace: trace, now: now) {
                hopArc(m.numeral, from: from, to: to, in: &g)
                let p = m.numeral.hopPoint(from: from, to: to, at: ease(u))
                let lift = sin(Double.pi * u)
                g.fill(Path(ellipseIn: CGRect(x: p.point.x - 26, y: p.point.y + 20 + 14 * lift, width: 52, height: 12)),
                       with: .color(ink.opacity(0.16 * lift)))
                ShapeTraceDrawing.place(ShapeTraceArt.paintCar, at: p.point, scale: 0.72 + 0.08 * lift, angle: p.angle, in: &g)
                return
            }
        }
        if case .stall = m.help, let vehicle = trace.vehiclePoint {
            let pulse = m.reduceMotion ? 1 : 1 + 0.06 * sin(now * 2 * Double.pi)
            let r = styles.stallRingRadius * pulse
            let ring = Path(ellipseIn: CGRect(x: vehicle.x - r, y: vehicle.y - r, width: 2 * r, height: 2 * r))
            g.fill(ring, with: .color(Color(hex: styles.stallRingFill, opacity: 0.55)))
            g.stroke(ring, with: .color(Color(hex: styles.stallRingStroke)), style: StrokeStyle(lineWidth: 5, dash: [10, 9]))
        }
        if let pose = TapCountGuideCoach.ghostPose(m.help, guide: m.numeral, now: now, reduceMotion: m.reduceMotion) {
            ghostCar(pose, in: &g)
        }
        paintCar(m, now: now, in: &g)
    }

    private static func paintCar(_ m: TapCountGuideMotionState, now: Double, in g: inout GraphicsContext) {
        guard let vehicle = m.trace.vehiclePoint else { return }
        var angle = m.trace.vehicleAngle
        // 真車搖一搖: the touch that ended the demo.
        if let at = m.wiggleAt, !m.reduceMotion {
            let dt = now - at
            if dt >= 0, dt < 0.5 { angle += sin(dt * 38) * 0.16 * (1 - dt / 0.5) }
        }
        ShapeTraceDrawing.place(ShapeTraceArt.paintCar, at: vehicle, scale: 0.72, angle: angle, in: &g)
    }

    private static func ghostCar(_ pose: TapCountGhostPose, in g: inout GraphicsContext) {
        guard pose.opacity > 0.01 else { return }
        if pose.lift > 0.01 {
            g.fill(Path(ellipseIn: CGRect(x: pose.point.x - 26, y: pose.point.y + 20 + 14 * pose.lift, width: 52, height: 12)),
                   with: .color(ink.opacity(0.16 * pose.lift * pose.opacity)))
        }
        place(TapCountArt.guideGhostCar, at: pose.point, scale: 0.72 + 0.08 * pose.lift, angle: pose.angle,
              opacity: pose.opacity, in: &g)
    }

    /// The dotted hop arc with its arrowhead (mockup guidance/03).
    static func hopArc(_ guide: NumeralGuide, from: Int, to: Int, in g: inout GraphicsContext) {
        guard guide.paths.indices.contains(from), guide.paths.indices.contains(to) else { return }
        let (a, c, b) = guide.hopControl(from: from, to: to)
        var arc = Path()
        arc.move(to: CGPoint(x: a.x, y: a.y))
        arc.addQuadCurve(to: CGPoint(x: b.x, y: b.y), control: CGPoint(x: c.x, y: c.y))
        g.stroke(arc, with: .color(Color(hex: styles.hopArc)),
                 style: StrokeStyle(lineWidth: styles.hopArcWidth, lineCap: .round, dash: styles.hopArcDash.map { CGFloat($0) }))
        let end = guide.hopPoint(from: from, to: to, at: 1)
        var head = g
        head.translateBy(x: b.x, y: b.y)
        head.rotate(by: .radians(end.angle))
        var p = Path()
        // build/guide-art.svg #hop-head: M-13 -8 L0 0 L-13 8, stroke 5, tip at the anchor.
        p.move(to: CGPoint(x: -13, y: -8))
        p.addLine(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: -13, y: 8))
        head.stroke(p, with: .color(Color(hex: styles.hopArc)),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
    }

    /// The route the ghost car drove: glow + dashed core, fading with age (three steps, as in the mockup).
    /// With Reduce Motion the whole route shows at once, steady.
    private static func demoRoute(_ timeline: TapCountDemoTimeline, at t: Double, reduceMotion: Bool, scale k: Double,
                                  in g: inout GraphicsContext) {
        let fade = TapCountGuideData.timing.routeFadeSeconds
        let pieces = reduceMotion ? timeline.route(at: timeline.mergeStart, reduceMotion: true) : timeline.route(at: t)
        let mergeFade = t >= timeline.mergeStart
            ? max(0, 1 - (t - timeline.mergeStart) / max(TapCountGuideData.timing.mergeSeconds, 0.01)) : 1
        func band(_ piece: TapCountRoutePiece) -> Double {
            if reduceMotion { return 0.6 }
            let age = t - piece.passedAt
            if age < fade / 3 { return 1 }
            if age < fade * 2 / 3 { return 0.6 }
            return 0.3
        }
        var runs: [(stroke: Int, from: Double, to: Double, opacity: Double)] = []
        for piece in pieces {
            let o = band(piece)
            if let last = runs.last, last.stroke == piece.stroke, last.opacity == o, abs(last.to - piece.from) < 0.5 {
                runs[runs.count - 1].to = piece.to
            } else {
                runs.append((piece.stroke, piece.from, piece.to, o))
            }
        }
        for run in runs {
            guard timeline.guide.paths.indices.contains(run.stroke) else { continue }
            let p = ShapeTraceDrawing.segment(timeline.guide.paths[run.stroke], from: run.from, to: run.to)
            var layer = g
            layer.opacity = g.opacity * run.opacity * mergeFade
            layer.stroke(p, with: .color(Color(hex: styles.routeGlow)),
                         style: StrokeStyle(lineWidth: styles.routeGlowWidth * k, lineCap: .round, lineJoin: .round))
            layer.stroke(p, with: .color(Color(hex: styles.routeCore)),
                         style: StrokeStyle(lineWidth: styles.routeCoreWidth * k, lineCap: .round, lineJoin: .round,
                                            dash: styles.routeDash.map { CGFloat($0 * k) }))
        }
    }

    // MARK: Legend icons (48×44)

    static func legendRoute(in g: inout GraphicsContext) {
        var p = Path()
        p.move(to: CGPoint(x: 6, y: 30))
        p.addQuadCurve(to: CGPoint(x: 42, y: 14), control: CGPoint(x: 22, y: 6))
        g.stroke(p, with: .color(Color(hex: styles.routeGlow)), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        g.stroke(p, with: .color(Color(hex: styles.routeCore)),
                 style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [7, 5]))
    }

    static func legendHeadlights(in g: inout GraphicsContext) {
        var p = Path()
        p.move(to: CGPoint(x: 4, y: 22))
        p.addLine(to: CGPoint(x: 44, y: 22))
        g.stroke(p, with: .color(Color(hex: styles.beamOuter)), style: StrokeStyle(lineWidth: 22, lineCap: .round))
        g.stroke(p, with: .color(Color(hex: styles.beamInner, opacity: styles.beamInnerOpacity)),
                 style: StrokeStyle(lineWidth: 9, lineCap: .round))
        place(TapCountArt.guideChev, at: LineMatchPoint(x: 16, y: 22), scale: 0.6, in: &g)
        place(TapCountArt.guideChev, at: LineMatchPoint(x: 32, y: 22), scale: 0.6, in: &g)
    }

    static func legendHop(in g: inout GraphicsContext) {
        var arc = Path()
        arc.move(to: CGPoint(x: 6, y: 34))
        arc.addQuadCurve(to: CGPoint(x: 40, y: 32), control: CGPoint(x: 20, y: -4))
        g.stroke(arc, with: .color(Color(hex: styles.hopArc)), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 8]))
        var head = Path()
        head.move(to: CGPoint(x: 32, y: 26))
        head.addLine(to: CGPoint(x: 40, y: 33))
        head.addLine(to: CGPoint(x: 43, y: 23))
        g.stroke(head, with: .color(Color(hex: styles.hopArc)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }
}
