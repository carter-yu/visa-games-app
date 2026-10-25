import SwiftUI
import VisaCore

/// Four-line letter board. The trace engine owns all pen judging and never reports a miss.
struct TapLetterWriteBoardView: View {
    let round: TapLetterWriteRound
    let guide: String
    let demoStartedAt: Double
    let bubble: String?
    let onDown: (LineMatchPoint) -> Bool
    let onMove: (LineMatchPoint) -> Void
    let onUp: () -> Void
    let onReprompt: () -> Void

    var body: some View {
        CanvasStage { LineMatchBackdrop() } content: {
            TapLetterWriteStage(round: round, guide: guide, demoStartedAt: demoStartedAt, bubble: bubble,
                onDown: onDown, onMove: onMove, onUp: onUp, onReprompt: onReprompt)
        }
    }
}

private struct TapLetterWriteStage: View {
    let round: TapLetterWriteRound
    let guide: String
    let demoStartedAt: Double
    let bubble: String?
    let onDown: (LineMatchPoint) -> Bool
    let onMove: (LineMatchPoint) -> Void
    let onUp: () -> Void
    let onReprompt: () -> Void
    @Environment(\.canvasMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = false
    @State private var swallowed = false

    private var letter: String { round.board.deal.target }
    private var trace: ShapeTraceBoard { round.trace }
    private var paths: [TracePath] { trace.shapes.first?.strokes ?? [] }
    private var teal: Color { Color(hex: 0x168F96) }

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
            if let bubble {
                CanvasText(bubble, size: 24, weight: 900)
                    .padding(metrics.u(12))
                    .background(RoundedRectangle(cornerRadius: metrics.u(18)).fill(.white))
                    .canvasPlaced(x: 465, y: 65)
            }
        }
        .onAppear(perform: onReprompt)
    }

    private var header: some View {
        HStack(spacing: metrics.u(8)) {
            Button(action: onReprompt) {
                VectorArtView(artwork: CanvasArt.stampy)
                    .frame(width: metrics.u(80), height: metrics.u(80))
            }.buttonStyle(.plain)
            CanvasText(round.canStamp ? "You wrote" : "Now write", size: 43, weight: 900)
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
                    .stroke(teal.opacity(visible ? 0.23 : 0.08),
                            style: StrokeStyle(lineWidth: metrics.u(CGFloat(LatinGlyphs.laneInkWidth)),
                                               lineCap: .round, lineJoin: .round, dash: [metrics.u(2), metrics.u(12)]))
                drawn(path)
                    .trim(from: 0, to: fraction(index, path))
                    .stroke(teal, style: StrokeStyle(lineWidth: metrics.u(17), lineCap: .round, lineJoin: .round))
            }
            if let path = trace.currentPath {
                marker(path.start, green: true, angle: path.angle(at: 0))
                marker(path.end, green: false, angle: path.angle(at: path.length))
            }
            if trace.isAtCorner, trace.currentPath?.cusps.contains(where: { abs($0 - trace.progress) < 0.5 }) == true {
                CanvasText("STOP", size: 20, weight: 900)
                    .padding(metrics.u(6))
                    .background(RoundedRectangle(cornerRadius: metrics.u(8)).fill(.red))
                    .canvasPlaced(x: 745, y: 145)
            }
            demoLayer
        }
    }

    @ViewBuilder private var demoLayer: some View {
        if round.demoActive, let character = letter.first, let glyph = StrokeGlyph.latin(character) {
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
                    } else {
                        let pose = timeline.pose(at: t, reduceMotion: reduceMotion)
                        let path = glyph.strokes[pose.stroke].path
                        let point = place.point(path.point(at: pose.distance))
                        TapCountDrawing.place(TapCountArt.guideGhostCar, at: point, scale: 0.72,
                                              angle: path.angle(at: pose.distance), in: &g)
                    }
                }
            }
            .frame(width: metrics.u(1280), height: metrics.u(720))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
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
        Image(systemName: "arrow.right.circle.fill")
            .font(.system(size: metrics.u(30)))
            .foregroundStyle(green ? Color.green : Color.red)
            .rotationEffect(.radians(angle))
            .position(x: metrics.u(CGFloat(point.x)), y: metrics.u(CGFloat(point.y)))
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
            CanvasText(round.canStamp ? "Next: your stamp!" : "Keep going!", size: 24, weight: 900)
            CanvasText("Nothing to get wrong", size: 18, weight: 700)
        }
        .frame(width: metrics.u(1010), height: metrics.u(125))
        .background(RoundedRectangle(cornerRadius: metrics.u(24)).fill(Color(hex: DesignTokens.Palette.paper)))
        .canvasPlaced(x: 46, y: 565)
    }
}
