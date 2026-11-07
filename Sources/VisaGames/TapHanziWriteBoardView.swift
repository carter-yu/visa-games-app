import SwiftUI
import VisaCore

/// 中文字 · 搵完寫's write round (Hanzi H3): design hanzi-tap v2 § Writing and mockups 01–05. The letter write board's
/// roles and places (`TapLetterWriteBoardView`: header, the two earned picture cards, the write card, the bubble and the
/// tray) with Hanzi providers: the 田字格 square (`HanziWriteBoard`), every stroke and numbered start from the pack's
/// centre lines, and the shared demo / headlights / sign / ghost drawing (`TapCountDrawing`) with the compact style
/// the guide carries. The trace engine judges the pen and never reports a miss. Every line is shown as text; the
/// speaker mark only says whether the voice is on.
struct TapHanziWriteBoardView: View {
    let round: TapHanziWriteRound
    let pack: HanziPack
    let copy: HanziWriteCopy
    let audioOn: Bool
    let now: Double
    let bubble: HanziWriteLine?
    let onDown: (LineMatchPoint) -> Bool
    let onMove: (LineMatchPoint) -> Void
    let onUp: () -> Void
    let onReprompt: () -> Void

    var body: some View {
        CanvasStage { LineMatchBackdrop() } content: {
            TapHanziWriteStage(round: round, pack: pack, copy: copy, audioOn: audioOn, now: now, bubble: bubble,
                               onDown: onDown, onMove: onMove, onUp: onUp, onReprompt: onReprompt)
        }
    }
}

private struct TapHanziWriteStage: View {
    let round: TapHanziWriteRound
    let pack: HanziPack
    let copy: HanziWriteCopy
    let audioOn: Bool
    let now: Double
    let bubble: HanziWriteLine?
    let onDown: (LineMatchPoint) -> Bool
    let onMove: (LineMatchPoint) -> Void
    let onUp: () -> Void
    let onReprompt: () -> Void
    @Environment(\.canvasMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = false
    @State private var swallowed = false
    @State private var cueShownAt: [Int: Double] = [:]

    /// Hanzi token sheet (D8): teal ink, cream card.
    private static let teal = Color(hex: 0x2D9FA5)
    private static let cream = Color(hex: 0xFFF9ED)
    private static let green = Color(hex: 0x58BC65)
    /// mockups 01–05: the arrow drawn at each numbered start and at the current end (M-9 -6 L-2 -6 L-2 -12 L11 0 L-2 12
    /// L-2 6 L-9 6 Z), pointing along +x.
    private static var arrow: Path {
        var p = Path()
        let points: [CGPoint] = [CGPoint(x: -9, y: -6), CGPoint(x: -2, y: -6), CGPoint(x: -2, y: -12), CGPoint(x: 11, y: 0),
                                 CGPoint(x: -2, y: 12), CGPoint(x: -2, y: 6), CGPoint(x: -9, y: 6)]
        p.move(to: points[0])
        for point in points.dropFirst() { p.addLine(to: point) }
        p.closeSubpath()
        return p
    }

    private var glyph: String { round.glyph }
    private var trace: ShapeTraceBoard { round.trace }
    private var guide: NumeralGuide { round.guide }
    private var demoPending: Bool { round.demoPending(now: now) }
    private var help: TapCountGuideHelp {
        guard let run = round.coach, !demoPending, !trace.isComplete else { return .none }
        return TapCountGuideCoach.help(plan: run.plan, guide: guide, trace: trace, readyAt: run.readyAt, now: now)
    }
    private var activeCueIndex: Int? {
        guard !demoPending, round.coach?.plan.cueSigns == true else { return nil }
        return TapCountGuideCoach.activeCue(guide: guide, trace: trace)?.index
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            header
            ForEach(0..<2, id: \.self) { pictureCard($0) }
            writingCard
            tray
            Color.clear
                .frame(width: metrics.u(490), height: metrics.u(430))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let scale = max(metrics.scale, 0.0001)
                        let point = LineMatchPoint(x: Double(value.location.x / scale) + 395,
                                                   y: Double(value.location.y / scale) + 113)
                        if !started {
                            started = true
                            swallowed = !onDown(point)
                        }
                        if !swallowed { onMove(point) }
                    }
                    .onEnded { _ in
                        if !swallowed { onUp() }
                        started = false
                        swallowed = false
                    })
                .canvasPlaced(x: 395, y: 113)
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                if let line = demoLine(at: context.date.timeIntervalSinceReferenceDate) ?? bubble { speech(line) }
            }
        }
        .onChange(of: activeCueIndex) { index in
            if let index, cueShownAt[index] == nil { cueShownAt[index] = Date().timeIntervalSinceReferenceDate }
        }
    }

    /// While the demo car drives: its beat line, then 「到你喇！」 (the merge).
    private func demoLine(at clock: Double) -> HanziWriteLine? {
        guard round.demoPending(now: clock), let t = round.coach?.demoTime(now: clock), t >= 0 else { return nil }
        if let beat = round.timeline.beat(at: t), guide.spec.beats.indices.contains(beat) {
            return HanziWriteLine(guide.spec.beats[beat].line.zh)
        }
        return t >= round.timeline.mergeStart ? HanziWriteLine(guide.spec.merge.zh) : nil
    }

    private var header: some View {
        let parts = round.canStamp ? copy.doneParts : copy.headerParts
        return HStack(spacing: metrics.u(12)) {
            Button(action: onReprompt) {
                VectorArtView(artwork: HanziCueArt.robot)
                    .frame(width: metrics.u(96), height: metrics.u(80))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copy.reprompt(glyph))
            CanvasText(parts.before, size: 48, weight: 900)
            HanziGlyphView(glyph: glyph, pack: pack, ink: .ink, lineWidth: 26)
                .padding(metrics.u(5))
                .frame(width: metrics.u(66), height: metrics.u(66))
                .background(RoundedRectangle(cornerRadius: metrics.u(14)).fill(Self.cream))
                .overlay(RoundedRectangle(cornerRadius: metrics.u(14)).strokeBorder(Color.ink, lineWidth: metrics.u(4)))
            CanvasText(parts.after, size: 48, weight: 900)
            Spacer()
            VStack {
                CanvasText("中文", size: 23, weight: 900)
                CanvasText("Find & write", size: 14, weight: 800)
            }
            .padding(metrics.u(9))
            .background(RoundedRectangle(cornerRadius: metrics.u(14)).fill(Color(hex: DesignTokens.Palette.sunny)))
        }
        .frame(width: metrics.u(1100), height: metrics.u(92))
        .overlay(alignment: .bottomLeading) {
            if !round.canStamp {
                CanvasText(copy.subline, size: 18, weight: 700)
                    .offset(x: metrics.u(108), y: metrics.u(12))
            }
        }
        .canvasPlaced(x: 82, y: 17)
    }

    /// The two pictures earned in the find: picture, teal target glyph and meaning (左／右: 「我隻左手」／「我隻右手」).
    private func pictureCard(_ slot: Int) -> some View {
        let art = round.board.slot(slot, pack: pack)
        return VStack(spacing: metrics.u(4)) {
            if let art, let picture = HanziCueArt.picture(art.picture) {
                VectorArtView(artwork: picture)
                    .frame(width: metrics.u(150), height: metrics.u(125))
            }
            HStack(spacing: metrics.u(8)) {
                HanziGlyphView(glyph: glyph, pack: pack, ink: Self.teal, lineWidth: 30)
                    .frame(width: metrics.u(44), height: metrics.u(44))
                CanvasText(art?.meaning ?? "", size: 22, weight: 900)
            }
        }
        .frame(width: metrics.u(206), height: metrics.u(210))
        .background(RoundedRectangle(cornerRadius: metrics.u(18)).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: metrics.u(18)).strokeBorder(Color.ink, lineWidth: metrics.u(4)))
        .padding(metrics.u(6))
        .background(RoundedRectangle(cornerRadius: metrics.u(23)).fill(Color(hex: DesignTokens.Palette.sunny)))
        .scaleEffect(round.canStamp && !reduceMotion ? 1.07 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6), value: round.canStamp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(glyph) \(art?.meaning ?? "")")
        .canvasPlaced(x: slot == 0 ? 106 : 956, y: 182)
    }

    private var writingCard: some View {
        let card = HanziWriteBoard.card
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: metrics.u(31))
                .fill(Self.cream)
                .overlay(RoundedRectangle(cornerRadius: metrics.u(31)).strokeBorder(Color.ink, lineWidth: metrics.u(6)))
                .frame(width: metrics.u(CGFloat(card.width)), height: metrics.u(CGFloat(card.height)))
                .canvasPlaced(x: CGFloat(card.x), y: CGFloat(card.y))
            if !demoPending, !trace.isComplete {
                CanvasText(copy.strokeCount(trace.strokeIndex + 1, of: guide.paths.count), size: 14, weight: 700,
                           color: Color(hex: 0x756B7E))
                    .canvasPlaced(x: 461, y: 134)
            }
            Canvas { canvas, _ in
                var g = canvas
                g.scaleBy(x: metrics.scale, y: metrics.scale)
                drawGrid(in: &g)
                drawStrokes(in: &g)
            }
            .frame(width: metrics.u(1280), height: metrics.u(720))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            guidanceLayer
            // Above the cars: at rest the paint car sits on the current start and would hide its green number.
            Canvas { canvas, _ in
                var g = canvas
                g.scaleBy(x: metrics.scale, y: metrics.scale)
                drawStarts(in: &g)
            }
            .frame(width: metrics.u(1280), height: metrics.u(720))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The 田字格: a faint square border and a dashed centre cross only (D3; no diagonals).
    private func drawGrid(in g: inout GraphicsContext) {
        let s = HanziWriteBoard.square
        let rect = CGRect(x: s.x, y: s.y, width: s.width, height: s.height)
        g.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color(hex: 0xADBFCE)), lineWidth: 1.5)
        var cross = Path()
        cross.move(to: CGPoint(x: rect.midX, y: rect.minY))
        cross.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        cross.move(to: CGPoint(x: rect.minX, y: rect.midY))
        cross.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        g.stroke(cross, with: .color(Color(hex: 0xB4C8D8)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 7]))
    }

    /// Each stroke's road (outline, lane, lane dots on the headlight spacing) and the teal ink drawn so far. Strokes not
    /// reached yet fade (the style's `fadedStrokeOpacity`).
    private func drawStrokes(in g: inout GraphicsContext) {
        let k = HanziWriteBoard.scale
        let fades = round.coach?.plan.fadesLaterStrokes ?? true
        for (index, path) in guide.paths.enumerated() {
            var layer = g
            if fades, !trace.isComplete, index > trace.strokeIndex {
                layer.opacity = guide.compactStyles?.fadedStrokeOpacity ?? 0.35
            }
            let road = ShapeTraceDrawing.whole(path)
            layer.stroke(road, with: .color(Color.ink), style: StrokeStyle(lineWidth: 34 * k, lineCap: .round, lineJoin: .round))
            layer.stroke(road, with: .color(Color(hex: 0xD6E3EE)),
                         style: StrokeStyle(lineWidth: 26 * k, lineCap: .round, lineJoin: .round))
            layer.stroke(road, with: .color(Color(hex: 0x8A8B98)),
                         style: StrokeStyle(lineWidth: 3.3 * k, lineCap: .round, dash: [1, max(1, guide.dotSpacing - 1)]))
            let drawn = trace.isComplete || index < trace.strokeIndex ? path.length
                : index == trace.strokeIndex ? min(trace.progress, path.length) : 0
            if drawn > 0 {
                layer.stroke(ShapeTraceDrawing.segment(path, from: 0, to: drawn), with: .color(Self.teal),
                             style: StrokeStyle(lineWidth: 20 * k, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// D10: every numbered start with its direction arrow (the current one green, written ones muted, later ones
    /// subdued); a leader joins a moved number to its true start (D12). The current stroke ends at the red dot.
    private func drawStarts(in g: inout GraphicsContext) {
        let k = HanziWriteBoard.scale
        let arrow = Self.arrow
        for mark in HanziWriteBoard.startMarks(glyph, in: pack, current: trace.isComplete ? nil : trace.strokeIndex) {
            var layer = g
            layer.opacity = mark.state == .future ? 0.55 : mark.state == .done ? 0.7 : 1
            let current = mark.state == .current
            if mark.leader {
                var leader = Path()
                leader.move(to: ShapeTraceDrawing.cg(mark.labelAt))
                leader.addLine(to: ShapeTraceDrawing.cg(mark.start))
                layer.stroke(leader, with: .color(Color.ink), style: StrokeStyle(lineWidth: 1.6 * k, lineCap: .round))
                let dot = Path(ellipseIn: CGRect(x: mark.start.x - 3 * k, y: mark.start.y - 3 * k, width: 6 * k, height: 6 * k))
                layer.fill(dot, with: .color(Self.green))
                layer.stroke(dot, with: .color(Color.ink), lineWidth: k)
            }
            var head = layer
            head.translateBy(x: mark.arrowAt.x, y: mark.arrowAt.y)
            head.rotate(by: .radians(mark.arrowAngle))
            head.scaleBy(x: 0.45 * k, y: 0.45 * k)
            head.fill(arrow, with: .color(current ? .white : Color(hex: 0x638B77)))
            head.stroke(arrow, with: .color(Color.ink), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            let disc = Path(ellipseIn: CGRect(x: mark.labelAt.x - 10 * k, y: mark.labelAt.y - 10 * k, width: 20 * k, height: 20 * k))
            layer.fill(disc, with: .color(current ? Self.green : Color(hex: 0xE3F1DE)))
            layer.stroke(disc, with: .color(Color.ink), lineWidth: 2)
            layer.draw(Text(mark.label).font(CanvasFont.font(size: 13 * k, weight: 900))
                .foregroundColor(current ? .white : Color(hex: 0x355C3A)),
                       at: ShapeTraceDrawing.cg(mark.labelAt), anchor: .center)
        }
        if let path = trace.currentPath {
            let end = Path(ellipseIn: CGRect(x: path.end.x - 10 * k, y: path.end.y - 10 * k, width: 20 * k, height: 20 * k))
            g.fill(end, with: .color(Color(hex: 0xED4B41)))
            g.stroke(end, with: .color(Color.ink), lineWidth: 2)
            var head = g
            head.translateBy(x: path.end.x, y: path.end.y)
            head.rotate(by: .radians(path.angle(at: path.length)))
            head.scaleBy(x: 0.46 * k, y: 0.46 * k)
            head.fill(arrow, with: .color(.white))
            head.stroke(arrow, with: .color(Color.ink), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
    }

    /// The shared coach drawing, as on the letter board: headlights and the active sign while the child writes, the
    /// 「睇住」 badge, the demo car with its route and the blinking sign it waits at (右's STOP turn only), the stall ring,
    /// help ghosts and the paint car. Reduce Motion: no gliding or hopping (`TapCountDemoTimeline.pose`).
    @ViewBuilder private var guidanceLayer: some View {
        if let run = round.coach {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let clock = context.date.timeIntervalSinceReferenceDate
                let pending = round.demoPending(now: clock)
                let currentHelp = pending || trace.isComplete ? TapCountGuideHelp.none :
                    TapCountGuideCoach.help(plan: run.plan, guide: guide, trace: trace, readyAt: run.readyAt, now: clock)
                let cue = pending || !run.plan.cueSigns ? nil : TapCountGuideCoach.activeCue(guide: guide, trace: trace)
                let draw = TapCountGuideDraw(plan: run.plan, numeral: guide, demo: pending,
                    headlights: pending ? [] : TapCountGuideCoach.headlights(plan: run.plan, guide: guide, trace: trace),
                    cue: cue, popAt: cue.flatMap { cueShownAt[$0.index] }, stopWord: copy.stopWord,
                    reduceMotion: reduceMotion, now: clock)
                let state = TapCountGuideMotionState(numeral: guide, timeline: round.timeline, run: run, trace: trace,
                    help: currentHelp, wiggleAt: nil, reduceMotion: reduceMotion, board: HanziWriteBoard.card,
                    stopWord: copy.stopWord)
                Canvas { canvas, _ in
                    var g = canvas
                    g.scaleBy(x: metrics.scale, y: metrics.scale)
                    if let path = trace.currentPath, !pending {
                        TapCountDrawing.guideHeadlights(draw, path: path, progress: trace.progress, scale: 1, in: &g)
                        if let cue { TapCountDrawing.guideCueSign(cue, guide: draw, in: &g) }
                    }
                    if pending {
                        let card = HanziWriteBoard.card
                        TapCountDrawing.guideWatchBadge(board: CGRect(x: card.x, y: card.y, width: card.width,
                                                                      height: card.height), in: &g)
                    }
                    TapCountDrawing.guideMotion(state, now: clock, in: &g)
                }
            }
            .frame(width: metrics.u(1280), height: metrics.u(720))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func speech(_ line: HanziWriteLine) -> some View {
        HStack(spacing: metrics.u(8)) {
            HanziSpeakerMark(audioOn: audioOn)
            VStack(alignment: .leading, spacing: metrics.u(2)) {
                CanvasText(line.text, size: 22, weight: 900)
                    .lineLimit(2)
                if let sub = line.sub { CanvasText(sub, size: 16, weight: 700) }
            }
        }
        .frame(width: metrics.u(266), height: metrics.u(104))
        .background(RoundedRectangle(cornerRadius: metrics.u(25)).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: metrics.u(25)).strokeBorder(Color.ink, lineWidth: metrics.u(4)))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.text + (line.sub ?? ""))
        .canvasPlaced(x: 164, y: 418)
    }

    private func legend(_ art: CanvasArtwork, _ line: HanziWriteLine) -> some View {
        HStack(spacing: metrics.u(4)) {
            VectorArtView(artwork: art).frame(width: metrics.u(27), height: metrics.u(27))
            VStack(alignment: .leading, spacing: 0) {
                CanvasText(line.text, size: 16, weight: 900)
                if let sub = line.sub { CanvasText(sub, size: 12, weight: 700) }
            }
        }
    }

    /// Find → Write chips, the tray line (demo, writing, or a help running) and the legend for what this glyph shows.
    private var tray: some View {
        let line = demoPending ? copy.trayDemo : help == .none ? copy.trayTrace : copy.trayStall
        let plan = round.coach?.plan
        return HStack(spacing: metrics.u(22)) {
            CanvasText(HanziWriteCopy.findChip, size: 22, weight: 900)
            HanziGlyphView(glyph: glyph, pack: pack, ink: .ink, lineWidth: 24)
                .frame(width: metrics.u(40), height: metrics.u(40))
            CanvasText("→", size: 25, weight: 900)
            CanvasText(HanziWriteCopy.writeChip, size: 22, weight: 900)
            HanziGlyphView(glyph: glyph, pack: pack, ink: Self.teal, lineWidth: 24)
                .frame(width: metrics.u(40), height: metrics.u(40))
            VStack(alignment: .leading) {
                CanvasText(round.canStamp ? copy.done(glyph) : line.text, size: 22, weight: 900)
                if !round.canStamp, let sub = line.sub { CanvasText(sub, size: 16, weight: 700) }
            }
            Spacer(minLength: 0)
            if plan?.headlights == true { legend(TapCountArt.guideChev, copy.legendHeadlights) }
            if plan?.cueSigns == true, guide.cues.contains(where: { $0.sign == .ahead }) {
                legend(TapCountArt.guideAhead, copy.legendAhead)
            }
            if plan?.cueSigns == true, guide.cues.contains(where: { $0.sign == .stop }) {
                legend(TapCountArt.guideStop, copy.legendStop)
            }
        }
        .padding(.horizontal, metrics.u(28))
        .frame(width: metrics.u(1010), height: metrics.u(125))
        .background(RoundedRectangle(cornerRadius: metrics.u(24)).fill(Color(hex: DesignTokens.Palette.paper)))
        .canvasPlaced(x: 46, y: 565)
    }
}

/// Voice state beside a bubble line: crossed out while 廣東話語音 is off (D4). Not a button.
private struct HanziSpeakerMark: View {
    let audioOn: Bool
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        ZStack {
            VectorArtView(artwork: CanvasArt.speaker)
            if !audioOn {
                Path { slash in
                    slash.move(to: CGPoint(x: metrics.u(3), y: metrics.u(29)))
                    slash.addLine(to: CGPoint(x: metrics.u(29), y: metrics.u(3)))
                }
                .stroke(Color.ink, style: StrokeStyle(lineWidth: metrics.u(3), lineCap: .round))
            }
        }
        .frame(width: metrics.u(32), height: metrics.u(32))
        .accessibilityHidden(true)
    }
}
