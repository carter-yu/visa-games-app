import SwiftUI
import VisaCore

/// Four-line letter board. The trace engine owns all pen judging and never reports a miss.
struct TapLetterWriteBoardView: View {
    let round: TapLetterWriteRound
    let guide: String
    let demoStartedAt: Double
    let guideRun: TapCountGuideRun?
    let now: Double
    let bubble: String?
    let onDown: (LineMatchPoint) -> Bool
    let onMove: (LineMatchPoint) -> Void
    let onUp: () -> Void
    let onReprompt: () -> Void

    var body: some View {
        CanvasStage { LineMatchBackdrop() } content: {
            TapLetterWriteStage(round: round, guide: guide, demoStartedAt: demoStartedAt, guideRun: guideRun, now: now, bubble: bubble,
                onDown: onDown, onMove: onMove, onUp: onUp, onReprompt: onReprompt)
        }
    }
}

private struct TapLetterWriteStage: View {
    let round: TapLetterWriteRound
    let guide: String
    let demoStartedAt: Double
    let guideRun: TapCountGuideRun?
    let now: Double
    let bubble: String?
    let onDown: (LineMatchPoint) -> Bool
    let onMove: (LineMatchPoint) -> Void
    let onUp: () -> Void
    let onReprompt: () -> Void
    @Environment(\.canvasMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = false
    @State private var swallowed = false
    @State private var cueShownAt: [Int: Double] = [:]

    private var letter: String { round.board.deal.target }
    private var trace: ShapeTraceBoard { round.trace }
    private var paths: [TracePath] { trace.shapes.first?.strokes ?? [] }
    private var teal: Color { Color(hex: 0x168F96) }
    private var glyphGuide: NumeralGuide? { letter.first.flatMap { NumeralGuide(letter: $0) } }
    private var timeline: TapCountDemoTimeline? { glyphGuide.map { TapCountDemoTimeline(guide: $0) } }
    private var demoPending: Bool { guideRun?.demoPending(now: now) == true && round.demoActive }
    private var activeCueIndex: Int? {
        guard !demoPending, let glyphGuide else { return nil }
        return TapCountGuideCoach.activeCue(guide: glyphGuide, trace: trace)?.index
    }
    private var help: TapCountGuideHelp {
        guard let run = guideRun, let glyphGuide, !demoPending, !trace.isComplete else { return .none }
        return TapCountGuideCoach.help(plan: run.plan, guide: glyphGuide, trace: trace, readyAt: run.readyAt, now: now)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            header
            ForEach(0..<2, id: \.self) { wordCard($0) }
            writingBoard
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
            if let guideRun, let timeline, let t = guideRun.demoTime(now: now), t >= 0,
               let beat = timeline.beat(at: t), let glyphGuide, glyphGuide.spec.beats.indices.contains(beat) {
                engineBubble(glyphGuide.spec.beats[beat].line.en)
            } else if let guideRun, let timeline, let t = guideRun.demoTime(now: now),
                      t >= timeline.mergeStart, let glyphGuide {
                engineBubble(glyphGuide.spec.merge.en)
            } else if let bubble {
                engineBubble(bubble)
            }
        }
        .onAppear { if guideRun == nil { onReprompt() } }
        .onChange(of: activeCueIndex) { index in
            if let index, cueShownAt[index] == nil { cueShownAt[index] = Date().timeIntervalSinceReferenceDate }
        }
    }

    private var header: some View {
        HStack(spacing: metrics.u(8)) {
            Button(action: onReprompt) {
                VectorArtView(artwork: CanvasArt.stampy)
                    .frame(width: metrics.u(80), height: metrics.u(80))
            }.buttonStyle(.plain)
            CanvasText(round.canStamp ? "You wrote" : (demoPending && guide == "car" ? "Watch the car write" : "Now write"),
                       size: demoPending && guide == "car" ? 31 : 43, weight: 900)
            LatinLetterGlyph(letter: letter, ink: .ink, lineWidth: 26)
                .frame(width: metrics.u(48), height: metrics.u(75))
            CanvasText("!", size: 43, weight: 900)
            Spacer()
            VStack {
                CanvasText("ABC", size: 23, weight: 900)
                CanvasText("Find & write", size: 14, weight: 800)
            }
            .padding(metrics.u(9))
            .background(RoundedRectangle(cornerRadius: metrics.u(14))
                .fill(Color(hex: DesignTokens.Palette.sunny)))
        }
        .frame(width: metrics.u(1100), height: metrics.u(92))
        .canvasPlaced(x: 82, y: 17)
    }

    private func wordCard(_ index: Int) -> some View {
        let word = round.board.deal.words[index]
        return VStack(spacing: metrics.u(4)) {
            LetterWordArt(imageID: word.imageID)
                .frame(width: metrics.u(115), height: metrics.u(105))
            HStack(spacing: 0) {
                LatinLetterGlyph(letter: letter, ink: teal, lineWidth: 28)
                    .frame(width: metrics.u(26), height: metrics.u(52))
                CanvasText(String(word.word.dropFirst()), size: 27, weight: 900)
            }
        }
        .frame(width: metrics.u(206), height: metrics.u(210))
        .background(RoundedRectangle(cornerRadius: metrics.u(18)).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: metrics.u(18)).strokeBorder(Color.ink, lineWidth: metrics.u(4)))
        .scaleEffect(round.canStamp && !reduceMotion ? 1.07 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6), value: round.canStamp)
        .canvasPlaced(x: index == 0 ? 112 : 962, y: 188)
    }

    private var writingBoard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: metrics.u(25))
                .fill(Color(hex: DesignTokens.Palette.paper))
                .overlay(RoundedRectangle(cornerRadius: metrics.u(25)).strokeBorder(Color.ink, lineWidth: metrics.u(4)))
                .frame(width: metrics.u(400), height: metrics.u(408))
                .canvasPlaced(x: 440, y: 126)
            ForEach([172.0, 272.0, 412.0, 492.0], id: \.self) { y in
                Path { p in
                    p.move(to: CGPoint(x: metrics.u(455), y: metrics.u(CGFloat(y))))
                    p.addLine(to: CGPoint(x: metrics.u(825), y: metrics.u(CGFloat(y))))
                }
                .stroke(Color.ink.opacity(0.28), style: StrokeStyle(lineWidth: metrics.u(2), dash: [metrics.u(8), metrics.u(7)]))
            }
            ForEach(paths.indices, id: \.self) { index in
                let path = paths[index]
                let visible = index <= trace.strokeIndex || trace.isComplete
                drawn(path)
                    .stroke(Color(hex: 0xE7E4E8).opacity(visible ? 1 : 0.35),
                            style: StrokeStyle(lineWidth: metrics.u(CGFloat(NumeralGlyphs.laneWidth * 0.92 * LetterGuideData.board.laneScale)), lineCap: .round, lineJoin: .round))
                drawn(path)
                    .stroke(Color(hex: 0xB4AEB5).opacity(visible ? 0.9 : 0.35),
                            style: StrokeStyle(lineWidth: metrics.u(4), lineCap: .round,
                                               dash: [metrics.u(1), metrics.u(CGFloat(LetterGuideData.board.laneDotSpacing - 1))]))
                drawn(path)
                    .trim(from: 0, to: fraction(index, path))
                    .stroke(teal, style: StrokeStyle(lineWidth: metrics.u(17), lineCap: .round, lineJoin: .round))
            }
            guidanceLayer
            if let path = trace.currentPath {
                if trace.progress < 1 || !["a", "d", "g", "e"].contains(letter) {
                    marker(path.start, green: true, angle: path.angle(at: 0))
                } else {
                    Circle().stroke(Color.green, lineWidth: metrics.u(5))
                        .frame(width: metrics.u(24), height: metrics.u(24))
                        .position(x: metrics.u(CGFloat(path.start.x)), y: metrics.u(CGFloat(path.start.y)))
                }
                marker(path.end, green: false, angle: path.angle(at: path.length))
            }
            demoLayer
        }
    }

    @ViewBuilder private var demoLayer: some View {
        if round.demoActive, guide == "glance", let character = letter.first, let glyph = StrokeGlyph.latin(character) {
            let dosage: StrokeOrderDosage = guide == "glance" ? .glance : .teach
            let timeline = StrokeOrderTimeline(glyph: glyph, dosage: dosage)
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let t = min(timeline.duration, max(0, context.date.timeIntervalSinceReferenceDate - demoStartedAt))
                Canvas { canvas, _ in
                    var g = canvas
                    g.scaleBy(x: metrics.scale, y: metrics.scale)
                    let place = StrokeOrderDrawing.Placement(offset: LineMatchPoint(x: 545, y: 142), scale: 1)
                    StrokeOrderDrawing.ink(timeline, at: t, reduceMotion: reduceMotion, place: place,
                                           colour: teal, outline: 46, core: 36, opacity: 0.75, in: &g)
                    if guide == "glance" {
                        StrokeOrderDrawing.pen(timeline, at: t, reduceMotion: reduceMotion, place: place,
                                               nibColour: 0x168F96, penScale: 0.85, in: &g)
                    }
                }
            }
            .frame(width: metrics.u(1280), height: metrics.u(720))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var guidanceLayer: some View {
        if let glyphGuide, let run = guideRun {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let clock = context.date.timeIntervalSinceReferenceDate
                let currentHelp = demoPending ? TapCountGuideHelp.none :
                    TapCountGuideCoach.help(plan: run.plan, guide: glyphGuide, trace: trace, readyAt: run.readyAt, now: clock)
                let cue = demoPending || !run.plan.cueSigns ? nil : TapCountGuideCoach.activeCue(guide: glyphGuide, trace: trace)
                let draw = TapCountGuideDraw(plan: run.plan, numeral: glyphGuide, demo: demoPending,
                    headlights: demoPending ? [] : TapCountGuideCoach.headlights(plan: run.plan, guide: glyphGuide, trace: trace),
                    cue: cue, popAt: cue.flatMap { cueShownAt[$0.index] }, stopWord: "STOP", reduceMotion: reduceMotion, now: clock)
                let state = TapCountGuideMotionState(numeral: glyphGuide, timeline: timeline, run: run, trace: trace,
                    help: currentHelp, wiggleAt: nil, reduceMotion: reduceMotion,
                    board: LineMatchRect(x: 440, y: 126, width: 400, height: 408), stopWord: "STOP")
                Canvas { canvas, _ in
                    var g = canvas
                    g.scaleBy(x: metrics.scale, y: metrics.scale)
                    if let path = trace.currentPath, !demoPending {
                        TapCountDrawing.guideHeadlights(draw, path: path, progress: trace.progress, scale: 1, in: &g)
                        if let cue { TapCountDrawing.guideCueSign(cue, guide: draw, in: &g) }
                    }
                    if demoPending {
                        TapCountDrawing.guideWatchBadge(board: CGRect(x: 440, y: 126, width: 400, height: 408), in: &g)
                    }
                    TapCountDrawing.guideMotion(state, now: clock, in: &g)
                }
            }
            .frame(width: metrics.u(1280), height: metrics.u(720))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func engineBubble(_ line: String) -> some View {
        HStack(spacing: metrics.u(6)) {
            VectorArtView(artwork: TapCountArt.speaker)
                .frame(width: metrics.u(27), height: metrics.u(27))
            CanvasText(line, size: 20, weight: 900)
                .lineLimit(2)
        }
        .frame(width: metrics.u(266), height: metrics.u(104))
        .background(RoundedRectangle(cornerRadius: metrics.u(25)).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: metrics.u(25)).strokeBorder(Color.ink, lineWidth: metrics.u(4)))
        .canvasPlaced(x: 164, y: 418)
        .allowsHitTesting(false)
    }

    private func drawn(_ path: TracePath) -> Path {
        Path { p in
            guard let first = path.points.first else { return }
            p.move(to: CGPoint(x: metrics.u(CGFloat(first.x)), y: metrics.u(CGFloat(first.y))))
            for point in path.points.dropFirst() {
                p.addLine(to: CGPoint(x: metrics.u(CGFloat(point.x)), y: metrics.u(CGFloat(point.y))))
            }
        }
    }

    private func fraction(_ index: Int, _ path: TracePath) -> CGFloat {
        if trace.isComplete || index < trace.strokeIndex { return 1 }
        if index > trace.strokeIndex { return 0 }
        return CGFloat(min(1, trace.progress / max(path.length, 1)))
    }

    private func marker(_ point: LineMatchPoint, green: Bool, angle: Double) -> some View {
        VectorArtView(artwork: green ? ShapeTraceArt.go : ShapeTraceArt.end)
            .frame(width: metrics.u(48), height: metrics.u(48))
            .rotationEffect(.radians(angle))
            .position(x: metrics.u(CGFloat(point.x)), y: metrics.u(CGFloat(point.y)))
    }

    private func legend(_ art: CanvasArtwork, _ title: String) -> some View {
        HStack(spacing: metrics.u(3)) {
            VectorArtView(artwork: art).frame(width: metrics.u(27), height: metrics.u(27))
            CanvasText(title, size: 15, weight: 800)
        }
    }

    private var tray: some View {
        HStack(spacing: metrics.u(30)) {
            CanvasText("Find", size: 22, weight: 900)
            LatinLetterGlyph(letter: letter, ink: .ink, lineWidth: 24)
                .frame(width: metrics.u(24), height: metrics.u(42))
            CanvasText("✓", size: 25, weight: 900)
            CanvasText("Write", size: 22, weight: 900)
            LatinLetterGlyph(letter: letter, ink: .ink, lineWidth: 24)
                .frame(width: metrics.u(24), height: metrics.u(42))
            VStack(alignment: .leading) {
                CanvasText(round.canStamp ? "Next: your stamp!" : (demoPending ? LetterGuideData.copy.trayDemo.en : (help == .none ? LetterGuideData.copy.trayTrace.en : LetterGuideData.copy.trayStall.en)), size: 22, weight: 900)
                CanvasText(demoPending ? LetterGuideData.copy.trayDemo.enSub : (help == .none ? LetterGuideData.copy.trayTrace.enSub : LetterGuideData.copy.trayStall.enSub), size: 16, weight: 700)
            }
            if guideRun?.plan.headlights == true { legend(TapCountArt.guideChev, "Headlights") }
            if glyphGuide?.cues.contains(where: { $0.sign == .ahead }) == true { legend(TapCountArt.guideAhead, "Keep going") }
            if glyphGuide?.cues.contains(where: { $0.sign == .stop }) == true { legend(TapCountArt.guideStop, "Stop") }
        }
        .frame(width: metrics.u(1010), height: metrics.u(125))
        .background(RoundedRectangle(cornerRadius: metrics.u(24)).fill(Color(hex: DesignTokens.Palette.paper)))
        .canvasPlaced(x: 46, y: 565)
    }
}
