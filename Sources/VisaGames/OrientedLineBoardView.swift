import SwiftUI
import VisaCore

/// 畫直線・四方 / Straight lines · Four ways (0.42.0; four-direction design §4–§7). One big line at a time: a wide warm
/// road between a green 起點 sign at the actual start and a red 終點 sign with a chequered bar at the actual finish. The
/// child draws the whole road from green to red in navy ink; the taxi's nose sits on the road drawn so far and faces the
/// way it drives (mirrored for ← and ↙; the words are never mirrored or turned). Drawing that has not joined the road
/// drawn so far stays faded and never counts. Guidance (chevrons, headlights, the pause glow, the ghost, the demo) is
/// clipped to s ≤ G = L − 15.5 and drawn below the bars. A progress row shows the round's → ← ↗ ↙.
///
/// All rules live in `VisaCore.OrientedLineBoard` and `OrientedLineCoach`. This view runs the board on a local copy per pen
/// event and hands it to the model on pen-up and when a line finishes. 畫直線 · 熱身 keeps `ShapeTraceBoardView`.
struct OrientedLineBoardView: View {
    let board: OrientedLineBoard
    let guide: OrientedLineGuideTally?
    let ticketStars: Int
    let pendingMinutes: Int
    let locked: Bool
    /// Every line just said, shown as it is said; hidden here as soon as F moves on the board being drawn.
    let caption: OrientedLineCaption?
    /// Model clock (seconds since reference date) for help timing and the idle re-prompt.
    let now: Double
    let onSpeak: () -> Void
    let onDemoAgain: () -> Void
    let onCommit: (OrientedLineBoard) -> Void
    let onDemoTouch: () -> Void
    /// A help episode appeared, with the board it appeared on (this view's current copy, not the last commit).
    let onHelp: (OrientedLineHelp, OrientedLineBoard) -> Void

    var body: some View {
        CanvasStage {
            LineMatchBackdrop()
        } content: {
            OrientedLineStageContent(view: self)
        }
        .onAppear(perform: onSpeak)
    }
}

private struct OrientedLineStageContent: View {
    let view: OrientedLineBoardView
    @Environment(\.canvasMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var local: OrientedLineBoard?
    @State private var dragSeen = false
    /// The touch that ended the demo: swallowed until lift (it never paints or moves the car).
    @State private var swallowing = false
    @State private var lastInputAt: Double?
    @GestureState private var gestureActive = false

    private var board: OrientedLineBoard {
        if let local, local.isMonotonicSuccessor(of: view.board) { return local }
        return view.board
    }

    /// The line on screen: the current one, or the last one once the round is drawn.
    private var lineIndex: Int { min(board.lineIndex, max(board.lines.count - 1, 0)) }
    private var line: OrientedLine? { board.lines.indices.contains(lineIndex) ? board.lines[lineIndex] : nil }
    private var frontier: Double { board.isComplete ? (line?.length ?? 0) : board.frontier }
    private var run: TapCountGuideRun? { view.guide?.run }

    private var help: OrientedLineHelp {
        guard !view.locked, let run else { return .none }
        return OrientedLineCoach.help(plan: run.plan, run: run, board: board, now: view.now)
    }

    private var demoPlaying: Bool { run?.demoPending(now: view.now) == true }

    /// The 20 s voice re-prompt where the level has no re-demo (少啲); 多啲 / 標準 re-demo through the coach.
    private var idleDue: Bool {
        guard let last = lastInputAt, !view.locked, !board.isComplete, !dragSeen, run?.plan.redemoSeconds == nil else {
            return false
        }
        return view.now - last >= ShapeTraceBoard.idleRepromptSeconds
    }

    private func stagePoint(_ point: CGPoint) -> CGPoint {
        let scale = max(metrics.scale, 0.0001)
        return CGPoint(x: point.x / scale, y: point.y / scale)
    }

    private func lm(_ point: CGPoint) -> LineMatchPoint {
        LineMatchPoint(x: Double(point.x), y: Double(point.y))
    }

    // MARK: Pen

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($gestureActive) { _, state, _ in state = true }
            .onChanged { value in dragChanged(value) }
            .onEnded { _ in dragEnded() }
    }

    private func dragChanged(_ value: DragGesture.Value) {
        guard !view.locked else { return }
        let clock = Date().timeIntervalSinceReferenceDate
        lastInputAt = view.now
        if !dragSeen {
            dragSeen = true
            // A touch while the demo plays ends it and is swallowed (design §6.1): no paint, no car.
            if run?.demoPending(now: clock) == true {
                swallowing = true
                view.onDemoTouch()
                return
            }
            var next = board
            let down = next.penDown(at: lm(stagePoint(value.startLocation)), now: clock)
            local = next
            switch down {
            case .refusedReverse, .refusedEarlyFinish:
                view.onCommit(next)
                return
            case .joined, .unjoined, .outside, .ignored:
                break
            }
        }
        guard !swallowing else { return }
        var next = board
        let move = next.penMove(to: lm(stagePoint(value.location)), now: clock)
        local = next
        switch move {
        case .lineDone, .allDone:
            view.onCommit(next)
        case .earned, .neutral, .joined, .segmentEnded, .ignored:
            break
        }
    }

    private func dragEnded() {
        guard dragSeen else { return }
        defer { resetDrag() }
        guard !swallowing else { return }
        var next = board
        next.penUp()
        local = next
        view.onCommit(next)
    }

    private func cancelStroke() {
        guard dragSeen else { return }
        defer { resetDrag() }
        guard !swallowing else { return }
        var next = board
        next.cancelStroke()
        local = next
        view.onCommit(next)
    }

    private func resetDrag() {
        dragSeen = false
        swallowing = false
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            lineLayers
                .id(lineIndex)
                .transition(.opacity)
            Color.clear
                .frame(width: metrics.u(1280), height: metrics.u(720))
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .allowsHitTesting(!view.locked && !board.isComplete)
                .accessibilityHidden(true)
            progressRow
            captionView
            header
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: lineIndex)
        .onAppear { lastInputAt = view.now }
        .onChange(of: view.board.question) { _ in
            local = nil
            resetDrag()
        }
        .onChange(of: view.locked) { isLocked in
            if isLocked { cancelStroke() }
        }
        .onChange(of: gestureActive) { active in
            guard !active else { return }
            DispatchQueue.main.async {
                if dragSeen { cancelStroke() }
            }
        }
        .onChange(of: help.key) { key in
            // With the board it was seen on: the model chooses the line from this, not from its last commit.
            if key != nil { view.onHelp(help, board) }
        }
        .onChange(of: idleDue) { due in
            guard due else { return }
            lastInputAt = view.now
            view.onSpeak()
        }
    }

    // MARK: One line (road → guidance → bars → signs → ink → car)

    @ViewBuilder
    private var lineLayers: some View {
        if let line {
            let board = self.board
            let frontier = self.frontier
            let help = self.help
            let plan = run?.plan
            let done = board.isComplete
            let index = lineIndex
            stageCanvas { g in
                OrientedLineDrawing.road(line, frontier: frontier, in: &g)
                if !done, let plan { OrientedLineDrawing.staticGuidance(line, frontier: frontier, plan: plan, in: &g) }
                OrientedLineDrawing.bars(line, in: &g)
                OrientedLineDrawing.signs(line, done: done, in: &g)
                OrientedLineDrawing.ink(board.ink.indices.contains(index) ? board.ink[index] : [], in: &g)
            }
            if !done { guidanceLayer(line, help: help) }
            stageCanvas { g in
                OrientedLineDrawing.car(line, nose: frontier, in: &g)
            }
        }
    }

    /// Timed guidance (pause glow and chevrons, the ring, ghosts, the demo): clipped to s ≤ G, below the bars and the
    /// child's car (the bars are drawn again on top, so even an edge never covers them).
    private func guidanceLayer(_ line: OrientedLine, help: OrientedLineHelp) -> some View {
        let scale = metrics.scale
        let frontier = self.frontier
        let reduce = reduceMotion
        let start = run?.demoStartedAt
        let pending = demoPlaying
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let clock = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, _ in
                var g = context
                g.scaleBy(x: scale, y: scale)
                OrientedLineDrawing.clipToGuidance(line, in: &g)
                if pending, let start {
                    let t = clock - start
                    OrientedLineDrawing.demo(line, ghost: OrientedLineCoach.demoGhost(line: line, t: max(t, 0), reduceMotion: reduce),
                                             showRoute: t >= 0, in: &g)
                }
                OrientedLineDrawing.help(help, line: line, frontier: frontier,
                                         ghost: OrientedLineCoach.ghost(help, line: line, now: clock, reduceMotion: reduce),
                                         in: &g)
            }
            .frame(width: metrics.u(1280), height: metrics.u(720))
        }
        .frame(width: metrics.u(1280), height: metrics.u(720))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .overlay(alignment: .topLeading) {
            stageCanvas { g in OrientedLineDrawing.bars(line, in: &g) }
        }
    }

    private func stageCanvas(_ draw: @escaping (inout GraphicsContext) -> Void) -> some View {
        let scale = metrics.scale
        return Canvas { context, _ in
            var g = context
            g.scaleBy(x: scale, y: scale)
            draw(&g)
        }
        .frame(width: metrics.u(1280), height: metrics.u(720))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: 上方進度列 (DECISIONS Q6: the round's → ← ↗ ↙ — done ✓ / current / next — just under the header)

    private var progressRow: some View {
        let rect = OrientedLineLayout.progressRow
        return HStack(spacing: metrics.u(12)) {
            ForEach(Array(board.lines.indices), id: \.self) { index in
                let done = board.isDone(line: index)
                let current = index == board.lineIndex
                ZStack {
                    RoundedRectangle(cornerRadius: metrics.u(10), style: .continuous)
                        .fill(done ? LM.go : current ? LM.pill : Color.white)
                    RoundedRectangle(cornerRadius: metrics.u(10), style: .continuous)
                        .strokeBorder(LM.ink, lineWidth: metrics.u(current ? 5 : 3))
                    if done {
                        CheckShape()
                            .stroke(Color.white, style: StrokeStyle(lineWidth: metrics.u(5), lineCap: .round,
                                                                    lineJoin: .round))
                            .padding(metrics.u(10))
                    } else {
                        Text(board.lines[index].variant.arrow)
                            .font(.system(size: metrics.u(26), weight: .black))
                            .foregroundStyle(LM.ink)
                    }
                }
                .frame(width: metrics.u(46), height: metrics.u(40))
                .accessibilityLabel("\(board.lines[index].variant.arrow) \(done ? "畫好 / done" : current ? "而家 / now" : "")")
            }
        }
        .frame(width: metrics.u(CGFloat(rect.width)), height: metrics.u(CGFloat(rect.height)))
        .canvasPlaced(x: CGFloat(rect.x), y: CGFloat(rect.y))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    // MARK: Caption (every line just said, shown as it is said, until F moves) — else the lines left

    private var captionRows: [(zh: String, en: String)] {
        if let caption = view.caption, caption.isShowing(on: board) {
            return caption.lines.map { ($0.traditionalChinese, $0.english) }
        }
        if board.isComplete { return [(ShapeTraceCopy.doneTraditionalChinese, ShapeTraceCopy.doneEnglish)] }
        let n = board.remainingLines
        return [(ShapeTraceCopy.remainingTraditionalChinese(n, kind: nil), ShapeTraceCopy.remainingEnglish(n, kind: nil))]
    }

    private var captionView: some View {
        let rows = captionRows
        let rect = OrientedLineLayout.caption
        return VStack(alignment: .center, spacing: metrics.u(2)) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .lastTextBaseline, spacing: metrics.u(10)) {
                    Text(row.zh)
                        .font(CanvasFont.font(size: metrics.u(22), weight: 900))
                        .foregroundStyle(LM.ink)
                    Text(row.en)
                        .font(CanvasFont.font(size: metrics.u(14), weight: 700))
                        .foregroundStyle(LM.soft)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
        }
        .frame(width: metrics.u(CGFloat(rect.width)), height: metrics.u(CGFloat(rect.height)), alignment: .top)
        .canvasPlaced(x: CGFloat(rect.x), y: CGFloat(rect.y))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    // MARK: Header (Stampy + prompt = the line and the demo again, the card badge, the visa ticket)

    private var header: some View {
        let frame = LineMatchLayout.header
        let stars = min(max(view.ticketStars, 1), 3)
        let prompt = board.question.prompt
        return ZStack(alignment: .topLeading) {
            ZStack {
                RoundedRectangle(cornerRadius: metrics.u(30), style: .continuous)
                    .fill(LM.ink.opacity(0.18))
                    .offset(y: metrics.u(6))
                RoundedRectangle(cornerRadius: metrics.u(30), style: .continuous)
                    .fill(LM.header)
                RoundedRectangle(cornerRadius: metrics.u(30), style: .continuous)
                    .strokeBorder(LM.ink, lineWidth: metrics.u(6))
            }
            .frame(width: metrics.u(CGFloat(frame.width)), height: metrics.u(CGFloat(frame.height)))
            .canvasPlaced(x: CGFloat(frame.x), y: CGFloat(frame.y))
            .allowsHitTesting(false)

            Button(action: view.onDemoAgain) {
                HStack(alignment: .center, spacing: metrics.u(14)) {
                    VectorArtView(artwork: CanvasArt.stampy)
                        .frame(width: metrics.u(82), height: metrics.u(82))
                    VStack(alignment: .leading, spacing: metrics.u(2)) {
                        CanvasText(prompt.traditionalChinese, size: 32, weight: 900, color: LM.ink)
                        CanvasText(prompt.english, size: 18, weight: 700, color: LM.headerSub)
                    }
                }
                .frame(width: metrics.u(820), height: metrics.u(92), alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(view.locked)
            .canvasPlaced(x: 40, y: 18)
            .accessibilityLabel("再聽一次，睇示範：\(prompt.traditionalChinese) / Hear it again and watch: \(prompt.english)")

            VStack(spacing: 0) {
                CanvasText(OrientedLineCopy.badgeTitle, size: 22, weight: 900, color: LM.ink)
                CanvasText(board.question.dealt.lineDirection.badgeTraditionalChinese, size: 13, weight: 700,
                           color: LM.headerSub)
            }
            .frame(width: metrics.u(138), height: metrics.u(68))
            .background(RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous).fill(LM.pill))
            .overlay(RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous)
                .strokeBorder(LM.ink, lineWidth: metrics.u(4)))
            .canvasPlaced(x: 872, y: 30)
            .allowsHitTesting(false)

            VisaTicketBadge(stars: stars, minutes: max(0, view.pendingMinutes))
                .frame(width: metrics.u(220), height: metrics.u(74))
                .canvasPlaced(x: 1026, y: 27)
                .allowsHitTesting(false)
                .accessibilityLabel("剩餘 \(view.pendingMinutes) 分鐘 / \(view.pendingMinutes) minutes left")
        }
    }
}

// MARK: - Drawing (pure functions of the line and the board; stage units)

enum OrientedLineDrawing {
    static let road = Color(hex: 0xFFF9EC)
    static let roadEdge = Color(hex: 0x2B2630)
    static let counted = Color(hex: 0xCBE9EA)
    static let centre = Color(hex: 0x8C8494)
    static let navy = Color(hex: 0x2B4E9E)
    static let navyHighlight = Color(hex: 0x7FA6F0)
    static let headlight = Color(hex: 0xFFE680)
    static let glow = Color(hex: 0xFFF6C8)
    static let ghostFill = Color(hex: 0xFBE3E0)
    /// Today's taxi at 0.45 (about 79 × 41 u).
    static let carScale: Double = 0.45

    static func cg(_ p: LineMatchPoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    /// P0 + s·u + d·n.
    static func at(_ line: OrientedLine, _ s: Double, _ d: Double = 0) -> CGPoint {
        let p = line.point(at: s), n = line.normal
        return CGPoint(x: p.x + n.x * d, y: p.y + n.y * d)
    }

    static func segment(_ line: OrientedLine, from a: Double, to b: Double) -> Path {
        var path = Path()
        path.move(to: at(line, a))
        path.addLine(to: at(line, b))
        return path
    }

    /// The drawn corridor (sign centre to sign centre, round caps), the counted tint from the start bar to F, and the
    /// centre dashes from F toward red.
    static func road(_ line: OrientedLine, frontier: Double, in g: inout GraphicsContext) {
        let whole = segment(line, from: -OrientedLine.signOffset, to: line.length + OrientedLine.signOffset)
        g.stroke(whole, with: .color(roadEdge), style: StrokeStyle(lineWidth: 112, lineCap: .round))
        g.stroke(whole, with: .color(road), style: StrokeStyle(lineWidth: 100, lineCap: .round))
        if frontier > 0 {
            g.stroke(segment(line, from: 0, to: frontier), with: .color(counted), style: StrokeStyle(lineWidth: 100, lineCap: .butt))
        }
        if frontier < line.length {
            g.stroke(segment(line, from: frontier, to: line.length), with: .color(centre),
                     style: StrokeStyle(lineWidth: 6, lineCap: .butt, dash: [22, 18]))
        }
    }

    /// Everything guidance paints stays on the green side of G: the half-plane s ≤ G.
    static func clipToGuidance(_ line: OrientedLine, in g: inout GraphicsContext) {
        let G = line.guidanceLimit
        var half = Path()
        half.move(to: at(line, G, -2000))
        half.addLine(to: at(line, G, 2000))
        half.addLine(to: at(line, G - 4000, 2000))
        half.addLine(to: at(line, G - 4000, -2000))
        half.closeSubpath()
        g.clip(to: half)
    }

    /// A ">" centred at s along u (never toward green); `big` is the pause size.
    static func chevron(_ line: OrientedLine, at s: Double, big: Bool = false) -> Path {
        let k = big ? OrientedLineCoach.bigChevronScale : 1
        let half = OrientedLineCoach.chevronHalf * k
        var path = Path()
        path.move(to: at(line, s - half, -16 * k))
        path.addLine(to: at(line, s + half, 0))
        path.addLine(to: at(line, s - half, 16 * k))
        return path
    }

    /// Static chevrons (ink 60 %) and headlights (yellow with an ink outline), both within [F, G].
    static func staticGuidance(_ line: OrientedLine, frontier: Double, plan: TapCountGuidePlan, in g: inout GraphicsContext) {
        var layer = g
        clipToGuidance(line, in: &layer)
        let lights = OrientedLineCoach.headlights(plan: plan, line: line, frontier: frontier)
        for s in OrientedLineCoach.staticChevrons(line: line, frontier: frontier) where !lights.contains(s) {
            layer.stroke(chevron(line, at: s), with: .color(roadEdge.opacity(0.6)),
                         style: StrokeStyle(lineWidth: OrientedLineCoach.chevronStroke, lineCap: .round, lineJoin: .round))
        }
        for s in lights {
            let shape = chevron(line, at: s)
            layer.stroke(shape, with: .color(roadEdge),
                         style: StrokeStyle(lineWidth: OrientedLineCoach.chevronStroke + 2 * OrientedLineCoach.headlightOutline,
                                            lineCap: .round, lineJoin: .round))
            layer.stroke(shape, with: .color(headlight),
                         style: StrokeStyle(lineWidth: OrientedLineCoach.chevronStroke, lineCap: .round, lineJoin: .round))
        }
    }

    /// The pause (glow, big chevrons, one ghost run) or the ring (on the car, with the forward glow; no trail).
    static func help(_ help: OrientedLineHelp, line: OrientedLine, frontier: Double, ghost: OrientedLineGhost?,
                     in g: inout GraphicsContext) {
        switch help {
        case .none, .redemo:
            return
        case .pause, .ring:
            if let glow = OrientedLineCoach.glow(line: line, frontier: frontier) {
                let road = segment(line, from: glow.lowerBound, to: glow.upperBound)
                g.stroke(road, with: .color(Self.glow), style: StrokeStyle(lineWidth: 54, lineCap: .butt))
                g.stroke(road, with: .color(headlight.opacity(0.55)), style: StrokeStyle(lineWidth: 22, lineCap: .butt))
            }
            if case .pause = help {
                for s in OrientedLineCoach.pauseChevrons(line: line, frontier: frontier) {
                    g.stroke(chevron(line, at: s, big: true), with: .color(roadEdge.opacity(0.8)),
                             style: StrokeStyle(lineWidth: OrientedLineCoach.chevronStroke * OrientedLineCoach.bigChevronScale,
                                                lineCap: .round, lineJoin: .round))
                }
            }
            if case .ring = help {
                let car = at(line, frontier - OrientedLineCoach.carLength / 2)
                let ring = Path(ellipseIn: CGRect(x: car.x - 58, y: car.y - 58, width: 116, height: 116))
                g.fill(ring, with: .color(LM.glow.opacity(0.55)))
                g.stroke(ring, with: .color(Color(hex: 0xF5B82E)), style: StrokeStyle(lineWidth: 5, dash: [10, 9]))
            }
        case .ghostToEnd:
            break
        }
        if let ghost { ghostCar(line, ghost: ghost, in: &g) }
    }

    /// The demo: its own route glow to G (butt cap) and the ghost car, never the child's tint or ink.
    static func demo(_ line: OrientedLine, ghost: OrientedLineGhost, showRoute: Bool, in g: inout GraphicsContext) {
        if showRoute {
            let route = OrientedLineCoach.demoRoute(line: line)
            g.stroke(segment(line, from: route.lowerBound, to: route.upperBound), with: .color(glow.opacity(0.8)),
                     style: StrokeStyle(lineWidth: 54, lineCap: .butt))
        }
        ghostCar(line, ghost: ghost, in: &g)
    }

    /// A pale, dashed ghost taxi with its nose at `ghost.nose` (its outline reaches `ghost.front`), under the child's car.
    static func ghostCar(_ line: OrientedLine, ghost: OrientedLineGhost, in g: inout GraphicsContext) {
        var layer = g
        layer.opacity = 0.5 * ghost.opacity
        taxi(line, nose: ghost.nose, in: &layer)
        var outline = Path()
        outline.move(to: at(line, ghost.nose - OrientedLineCoach.carLength, -20.5))
        outline.addLine(to: at(line, ghost.nose, -20.5))
        outline.addLine(to: at(line, ghost.nose, 20.5))
        outline.addLine(to: at(line, ghost.nose - OrientedLineCoach.carLength, 20.5))
        outline.closeSubpath()
        var edge = g
        edge.opacity = ghost.opacity
        edge.fill(outline, with: .color(ghostFill.opacity(0.35)))
        edge.stroke(outline, with: .color(centre), style: StrokeStyle(lineWidth: 2 * OrientedLineCoach.ghostOutline, dash: [6, 5]))
    }

    /// The solid green start bar at P0; the finish bar on P1: chequers over [L − 10, L + 10] between two red rails.
    static func bars(_ line: OrientedLine, in g: inout GraphicsContext) {
        let across: Double = 56
        g.stroke(Path { p in p.move(to: at(line, 0, -across)); p.addLine(to: at(line, 0, across)) },
                 with: .color(LM.go), style: StrokeStyle(lineWidth: OrientedLine.startBarWidth, lineCap: .butt))
        let L = line.length, band = OrientedLine.finishBand
        let rows = 10
        let cell = 2 * across / Double(rows)
        for row in 0..<rows {
            for column in 0..<2 {
                let s0 = L - band + Double(column) * band, s1 = s0 + band
                let d0 = -across + Double(row) * cell, d1 = d0 + cell
                var square = Path()
                square.move(to: at(line, s0, d0))
                square.addLine(to: at(line, s1, d0))
                square.addLine(to: at(line, s1, d1))
                square.addLine(to: at(line, s0, d1))
                square.closeSubpath()
                g.fill(square, with: .color((row + column) % 2 == 0 ? roadEdge : Color.white))
            }
        }
        for offset in [-OrientedLine.railOffset, OrientedLine.railOffset] {
            g.stroke(Path { p in p.move(to: at(line, L + offset, -across)); p.addLine(to: at(line, L + offset, across)) },
                     with: .color(LM.end), style: StrokeStyle(lineWidth: OrientedLine.railWidth, lineCap: .butt))
        }
    }

    /// The green 起點 sign at the actual start (an arrow along u above upright text) and the red 終點 sign at the actual
    /// finish (an upright chequered flag above upright text); a drawn line's finish sign becomes the green ✓.
    static func signs(_ line: OrientedLine, done: Bool, in g: inout GraphicsContext) {
        let r = OrientedLine.signRadius
        let edge = OrientedLine.signPaintedRadius - r
        func disc(_ c: LineMatchPoint, _ fill: Color) {
            let outer = Path(ellipseIn: CGRect(x: c.x - r - edge, y: c.y - r - edge, width: 2 * (r + edge), height: 2 * (r + edge)))
            g.fill(outer, with: .color(roadEdge))
            g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(fill))
        }
        let green = line.greenSign, red = line.redSign
        disc(green, LM.go)
        // The arrow along u in the top half (anchored 15 u above the centre); only the arrow turns.
        let tip = CGPoint(x: green.x + line.unit.x * 18, y: green.y - 15 + line.unit.y * 18)
        let tail = CGPoint(x: green.x - line.unit.x * 18, y: green.y - 15 - line.unit.y * 18)
        var arrow = Path()
        arrow.move(to: tail)
        arrow.addLine(to: tip)
        let a = line.angle
        arrow.move(to: CGPoint(x: tip.x - 11 * cos(a - 0.6), y: tip.y - 11 * sin(a - 0.6)))
        arrow.addLine(to: tip)
        arrow.addLine(to: CGPoint(x: tip.x - 11 * cos(a + 0.6), y: tip.y - 11 * sin(a + 0.6)))
        g.stroke(arrow, with: .color(Color.white), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        g.draw(Text(OrientedLineCopy.startSign).font(CanvasFont.font(size: 20, weight: 900)).foregroundColor(.white),
               at: CGPoint(x: green.x, y: green.y + 16), anchor: .center)
        if done {
            disc(red, LM.go)
            var tick = Path()
            tick.move(to: CGPoint(x: red.x - 18, y: red.y))
            tick.addLine(to: CGPoint(x: red.x - 5, y: red.y + 14))
            tick.addLine(to: CGPoint(x: red.x + 20, y: red.y - 14))
            g.stroke(tick, with: .color(Color.white), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            return
        }
        disc(red, LM.end)
        // The chequered flag, always upright.
        let pole = CGPoint(x: red.x - 14, y: red.y - 30)
        g.stroke(Path { p in p.move(to: pole); p.addLine(to: CGPoint(x: pole.x, y: pole.y + 26)) },
                 with: .color(Color.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        for row in 0..<2 {
            for column in 0..<3 {
                let cell = CGRect(x: pole.x + 2 + CGFloat(column) * 8, y: pole.y + CGFloat(row) * 7, width: 8, height: 7)
                g.fill(Path(cell), with: .color((row + column) % 2 == 0 ? roadEdge : Color.white))
            }
        }
        g.draw(Text(OrientedLineCopy.finishSign).font(CanvasFont.font(size: 20, weight: 900)).foregroundColor(.white),
               at: CGPoint(x: red.x, y: red.y + 16), anchor: .center)
    }

    /// Navy ink: drawn while joined at full strength with its highlight; drawn before joining faded (40 %), forever. Each
    /// edge takes `OrientedLineInk.edges`' style, so the edge arriving at a join stays faded.
    static func ink(_ strokes: [[OrientedInkSample]], in g: inout GraphicsContext) {
        for stroke in strokes where stroke.count == 1 {
            let p = stroke[0].point
            g.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)),
                   with: .color(navy.opacity(stroke[0].counted ? 1 : 0.4)))
        }
        for edge in OrientedLineInk.edges(strokes) {
            var piece = Path()
            piece.move(to: cg(edge.from))
            piece.addLine(to: cg(edge.to))
            g.stroke(piece, with: .color(navy.opacity(edge.counted ? 1 : 0.4)),
                     style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
            if edge.counted {
                g.stroke(piece, with: .color(navyHighlight), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
        }
    }

    /// The child's taxi with its nose at F.
    static func car(_ line: OrientedLine, nose: Double, in g: inout GraphicsContext) {
        taxi(line, nose: nose, in: &g)
    }

    /// Today's taxi art (it faces right), its nose at `nose`, wheels toward n: as drawn on → and turned −35° on ↗;
    /// mirrored on ← and ↙ (then turned −35° on ↙). Only the car is mirrored; no text is.
    static func taxi(_ line: OrientedLine, nose: Double, in g: inout GraphicsContext) {
        let art = ShapeTraceArt.taxi
        let anchor = ShapeTraceArt.anchor(art)
        let mirrored = !line.variant.isRightward
        let forward = (mirrored ? anchor.x : art.width - anchor.x) * carScale
        let below = (anchor.y - art.height / 2) * carScale
        let place = at(line, nose - forward, below)
        var layer = g
        layer.translateBy(x: place.x, y: place.y)
        let turn = mirrored ? line.angle - Double.pi : line.angle
        if abs(turn) > 1e-9 { layer.rotate(by: .radians(turn)) }
        layer.scaleBy(x: mirrored ? -carScale : carScale, y: carScale)
        layer.translateBy(x: -anchor.x, y: -anchor.y)
        VectorArtRenderer.draw(art, in: &layer, size: CGSize(width: art.width, height: art.height), contentMode: .fit)
    }
}
