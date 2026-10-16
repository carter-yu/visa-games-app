import SwiftUI
import VisaCore

/// 畫線畫形 / Lines & Shapes (v0.25.0, ADR 0014; Opus mockups 01, 02, 03, 04).
///
/// 畫直線 · 熱身: a fire engine, a crane hook and a taxi follow the pen along wide lanes.
/// 畫形狀 · 跟虛線: a little paint car follows the pen along dotted circles, square windows (「口」
/// order) and ★ spires (∧). The vehicle only goes forwards, waits at every corner (「停！轉彎！」)
/// and waits whenever the pen leaves the lane — never a miss. Each shape auto-completes; no 完成,
/// no 擦晒. Nothing is drawn in the bottom-right parent corner.
///
/// All rules live in `VisaCore.ShapeTraceBoard`. This view runs it on a local copy per pen event
/// and hands it to the model on pen-up and at every milestone (corner, stroke, shape).
struct ShapeTraceBoardView: View {
    let board: ShapeTraceBoard
    let settings: ShapeTraceSettings
    let ticketStars: Int
    let pendingMinutes: Int
    let locked: Bool
    let notice: SpokenPrompt?
    /// Model clock (seconds since reference date) for the hint and the idle re-prompt.
    let now: Double
    let onSpeak: () -> Void
    let onCommit: (ShapeTraceBoard) -> Void
    let onWrongStart: () -> Void
    let onReverse: () -> Void
    let onHint: (String) -> Void

    var body: some View {
        CanvasStage {
            LineMatchBackdrop()
        } content: {
            ShapeTraceStageContent(view: self)
        }
        .onAppear(perform: onSpeak)
    }
}

private struct ShapeTraceStageContent: View {
    let view: ShapeTraceBoardView
    @Environment(\.canvasMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var local: ShapeTraceBoard?
    @State private var penTip: CGPoint?
    @State private var dragSeen = false
    @State private var lastInputAt: Double?
    @GestureState private var gestureActive = false

    private var board: ShapeTraceBoard {
        if let local, local.isMonotonicSuccessor(of: view.board) { return local }
        return view.board
    }

    private var hintOn: Bool { !view.locked && board.showsHint(now: view.now) }
    private var hintKey: String? { hintOn ? "\(board.shapeIndex).\(board.strokeIndex)" : nil }
    private var idleDue: Bool {
        guard let last = lastInputAt, !view.locked, !board.isComplete, !dragSeen else { return false }
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
        var next = board
        let tip = stagePoint(value.location)
        penTip = tip
        lastInputAt = view.now
        if !dragSeen {
            dragSeen = true
            switch next.penDown(at: lm(stagePoint(value.startLocation)), now: clock) {
            case .wrongStart:
                local = next
                view.onCommit(next)
                view.onWrongStart()
                return
            case .reverse:
                local = next
                view.onCommit(next)
                view.onReverse()
                return
            case .grabbed, .notNearVehicle, .ignored:
                break
            }
        }
        let move = next.penMove(to: lm(tip), now: clock)
        local = next
        switch move {
        case .cornerReached, .cornerOvershoot, .strokeDone, .shapeDone, .allDone:
            view.onCommit(next)
        case .drove, .waiting, .away, .ignored:
            break
        }
    }

    private func dragEnded() {
        guard dragSeen else { return }
        var next = board
        next.penUp()
        local = next
        resetDrag()
        view.onCommit(next)
    }

    private func cancelStroke() {
        guard dragSeen else { return }
        var next = board
        next.cancelStroke()
        local = next
        resetDrag()
        view.onCommit(next)
    }

    private func resetDrag() {
        dragSeen = false
        penTip = nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            sceneryLayer
            lanesLayer
            markersLayer
            followersLayer
            hintLayer
            ghostLayer
            Color.clear
                .frame(width: metrics.u(1280), height: metrics.u(720))
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .allowsHitTesting(!view.locked && !board.isComplete)
                .accessibilityHidden(true)
            bubble
            linkCard
            status
            header
        }
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
        .onChange(of: hintKey) { key in
            if let key { view.onHint(key) }
        }
        .onChange(of: idleDue) { due in
            guard due else { return }
            lastInputAt = view.now
            view.onSpeak()
        }
    }

    // MARK: Layers (one Canvas each; stage units)

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

    private var sceneryLayer: some View {
        let board = self.board
        return stageCanvas { g in ShapeTraceDrawing.scenery(board, in: &g) }
    }

    private var lanesLayer: some View {
        let board = self.board
        let settings = view.settings
        return stageCanvas { g in ShapeTraceDrawing.lanes(board, settings: settings, in: &g) }
    }

    private var markersLayer: some View {
        let board = self.board
        let settings = view.settings
        return stageCanvas { g in ShapeTraceDrawing.markers(board, settings: settings, in: &g) }
    }

    private var followersLayer: some View {
        let board = self.board
        return stageCanvas { g in ShapeTraceDrawing.followers(board, in: &g) }
    }

    /// Off the lane for 2 s: dashed glow ring on the vehicle and a dotted trail from the pen.
    @ViewBuilder
    private var hintLayer: some View {
        if hintOn, let vehicle = board.vehiclePoint {
            let tip = penTip
            stageCanvas { g in
                let ring = Path(ellipseIn: CGRect(x: vehicle.x - 58, y: vehicle.y - 58, width: 116, height: 116))
                g.fill(ring, with: .color(LM.glow.opacity(0.55)))
                g.stroke(ring, with: .color(Color(hex: 0xF5B82E)), style: StrokeStyle(lineWidth: 5, dash: [10, 9]))
                if let tip {
                    var trail = Path()
                    trail.move(to: tip)
                    trail.addLine(to: CGPoint(x: vehicle.x, y: vehicle.y))
                    g.stroke(trail, with: .color(Color(hex: 0xF5B82E)),
                             style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [2, 10]))
                }
            }
        }
    }

    /// No progress for 8 s: a faint ghost of the vehicle shows the way along the stroke.
    @ViewBuilder
    private var ghostLayer: some View {
        if !reduceMotion, !view.locked, !dragSeen, board.ghostDue(now: view.now), let path = board.currentPath {
            let start = board.progress
            let reach = min(170, max(0, path.length - start))
            let scale = metrics.scale
            let lines = board.question.kind == .traceLines
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                Canvas { context, _ in
                    var g = context
                    g.scaleBy(x: scale, y: scale)
                    g.opacity = 0.45
                    let d = start + reach * phase
                    let p = path.point(at: d)
                    ShapeTraceDrawing.place(lines ? ShapeTraceArt.taxi : ShapeTraceArt.paintCar, at: p,
                                            scale: lines ? 0.42 : 0.78, angle: lines ? 0 : path.angle(at: d), in: &g)
                }
            }
            .frame(width: metrics.u(1280), height: metrics.u(720))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: Bubble 「三角形、triangle」 (last finished shape)

    @ViewBuilder
    private var bubble: some View {
        if board.shapeIndex > 0, board.shapes.indices.contains(board.shapeIndex - 1) {
            let index = board.shapeIndex - 1
            let shape = board.shapes[index]
            let rect = ShapeTraceDrawing.bubbleRect(board.question, shape: shape)
            ZStack {
                RoundedRectangle(cornerRadius: metrics.u(28), style: .continuous)
                    .fill(LM.ink.opacity(0.16))
                    .offset(y: metrics.u(6))
                RoundedRectangle(cornerRadius: metrics.u(28), style: .continuous)
                    .fill(Color.white)
                RoundedRectangle(cornerRadius: metrics.u(28), style: .continuous)
                    .strokeBorder(LM.ink, lineWidth: metrics.u(5))
                HStack(spacing: metrics.u(10)) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: metrics.u(26), weight: .bold))
                        .foregroundStyle(LM.route)
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        CanvasText("\(shape.kind.cueTraditionalChinese)、", size: 32, weight: 900, color: LM.ink)
                        CanvasText(shape.kind.cueEnglish, size: 28, weight: 700, color: Color(hex: 0x4C8FE0))
                    }
                }
            }
            .frame(width: metrics.u(CGFloat(rect.width)), height: metrics.u(CGFloat(rect.height)))
            .canvasPlaced(x: CGFloat(rect.x), y: CGFloat(rect.y))
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ShapeTraceCopy.bubble(shape.kind))
        }
    }

    // MARK: Link card (shape ↔ character; dotted shapes only)

    @ViewBuilder
    private var linkCard: some View {
        if board.question.kind == .traceShapesDotted, board.shapeIndex > 0,
           let kind = board.shapes.first?.kind, let card = ShapeTraceCopy.linkCard(kind) {
            let rect = ShapeTraceLayout.linkCard
            HStack(spacing: metrics.u(14)) {
                CanvasText(card.glyph, size: 72, weight: 900, color: LM.ink)
                VStack(alignment: .leading, spacing: metrics.u(2)) {
                    CanvasText(card.top, size: 20, weight: 900, color: LM.ink)
                    CanvasText(card.bottom, size: 20, weight: 900, color: LM.ink)
                    CanvasText(card.english, size: 11, weight: 700, color: LM.soft)
                }
            }
            .frame(width: metrics.u(CGFloat(rect.width)), height: metrics.u(CGFloat(rect.height)))
            .background(RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous).fill(LM.card))
            .overlay(RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous)
                .strokeBorder(LM.ink, lineWidth: metrics.u(4)))
            .canvasPlaced(x: CGFloat(rect.x), y: CGFloat(rect.y))
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ShapeTraceCopy.link(kind).map { "\($0.traditionalChinese) / \($0.english)" } ?? "")
        }
    }

    // MARK: Status (one dot per shape + one line)

    private var statusLines: (zh: String, en: String) {
        if board.isComplete { return (ShapeTraceCopy.doneTraditionalChinese, ShapeTraceCopy.doneEnglish) }
        if hintOn { return (ShapeTraceCopy.offPathTraditionalChinese, ShapeTraceCopy.offPathEnglish) }
        if let notice = view.notice { return (notice.traditionalChinese, notice.english) }
        if board.isAtCorner, view.settings.cornerStop {
            return (ShapeTraceCopy.cornerTraditionalChinese, ShapeTraceCopy.cornerEnglish)
        }
        if board.shapeIndex > 0, board.question.kind == .traceLines,
           let arrival = ShapeTraceCopy.arrival(slot: board.shapes[board.shapeIndex - 1].slot), board.strokesDone > 0,
           board.progress < 1, !dragSeen {
            return (arrival.traditionalChinese, arrival.english)
        }
        let kind = board.question.kind == .traceLines ? nil : board.shapes.first?.kind
        return (ShapeTraceCopy.remainingTraditionalChinese(board.remainingShapes, kind: kind),
                ShapeTraceCopy.remainingEnglish(board.remainingShapes, kind: kind))
    }

    private var status: some View {
        let lines = statusLines
        let rect = ShapeTraceLayout.status
        return VStack(spacing: metrics.u(4)) {
            HStack(spacing: metrics.u(12)) {
                ForEach(Array(board.shapes.indices), id: \.self) { index in
                    let color = LineMatchRoadPalette.color(board.shapes[index].colorIndex)
                    let done = board.isDone(shape: index)
                    ZStack {
                        Circle().fill(done ? Color(hex: color.full) : Color.white)
                        Circle().strokeBorder(LM.ink, lineWidth: metrics.u(5))
                        if done {
                            CheckShape()
                                .stroke(Color.white, style: StrokeStyle(lineWidth: metrics.u(5), lineCap: .round,
                                                                        lineJoin: .round))
                                .padding(metrics.u(8))
                        }
                    }
                    .frame(width: metrics.u(32), height: metrics.u(32))
                }
            }
            CanvasText(lines.zh, size: 26, weight: 900, color: LM.ink)
            CanvasText(lines.en, size: 18, weight: 700, color: LM.soft)
        }
        .frame(width: metrics.u(CGFloat(rect.width)), height: metrics.u(CGFloat(rect.height)), alignment: .top)
        .canvasPlaced(x: CGFloat(rect.x), y: CGFloat(rect.y))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    // MARK: Header (Stampy + prompt = replay voice, card badge, visa ticket)

    private var header: some View {
        let frame = LineMatchLayout.header
        let stars = min(max(view.ticketStars, 1), 3)
        let zh = board.question.promptTraditionalChinese
        let en = board.question.promptEnglish
        let lines = board.question.kind == .traceLines
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

            Button(action: view.onSpeak) {
                HStack(alignment: .center, spacing: metrics.u(14)) {
                    VectorArtView(artwork: CanvasArt.stampy)
                        .frame(width: metrics.u(82), height: metrics.u(82))
                    VStack(alignment: .leading, spacing: metrics.u(2)) {
                        CanvasText(zh, size: 34, weight: 900, color: LM.ink)
                        CanvasText(en, size: 19, weight: 700, color: LM.headerSub)
                    }
                }
                .frame(width: metrics.u(820), height: metrics.u(92), alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .canvasPlaced(x: 40, y: 18)
            .accessibilityLabel("再聽一次：\(zh) / Hear it again: \(en)")

            VStack(spacing: 0) {
                CanvasText(lines ? ShapeTraceCopy.linesBadgeTraditionalChinese : ShapeTraceCopy.shapesBadgeTraditionalChinese,
                           size: 24, weight: 900, color: LM.ink)
                CanvasText(lines ? ShapeTraceCopy.linesBadgeSubTraditionalChinese
                                 : ShapeTraceCopy.shapesBadgeSubTraditionalChinese,
                           size: 16, weight: 700, color: LM.headerSub)
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

// MARK: - Drawing (pure functions of the board; stage units)

enum ShapeTraceDrawing {
    static let ink = Color(hex: 0x2B2630)
    static let guideGrey = Color(hex: 0x8C8494)

    /// Draws `artwork` with its anchor on `point`, scaled and turned about the anchor.
    static func place(_ artwork: CanvasArtwork, at point: LineMatchPoint, scale: Double = 1, angle: Double = 0,
                      in g: inout GraphicsContext) {
        let anchor = ShapeTraceArt.anchor(artwork)
        var layer = g
        layer.translateBy(x: point.x, y: point.y)
        if angle != 0 { layer.rotate(by: .radians(angle)) }
        layer.scaleBy(x: scale, y: scale)
        layer.translateBy(x: -anchor.x, y: -anchor.y)
        VectorArtRenderer.draw(artwork, in: &layer, size: CGSize(width: artwork.width, height: artwork.height),
                               contentMode: .fit)
    }

    /// Stage-sized scenery shifted horizontally.
    static func stage(_ artwork: CanvasArtwork, dx: Double = 0, in g: inout GraphicsContext) {
        var layer = g
        layer.translateBy(x: dx, y: 0)
        VectorArtRenderer.draw(artwork, in: &layer, size: CGSize(width: 1280, height: 720), contentMode: .fit)
    }

    static func cg(_ p: LineMatchPoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    /// Centre line of `path` from `a` to `b` (arc length).
    static func segment(_ path: TracePath, from a: Double, to b: Double) -> Path {
        var p = Path()
        let lo = max(0, a), hi = min(path.length, b)
        guard hi > lo else { return p }
        p.move(to: cg(path.point(at: lo)))
        for index in path.points.indices where path.cumulative[index] > lo && path.cumulative[index] < hi {
            p.addLine(to: cg(path.points[index]))
        }
        p.addLine(to: cg(path.point(at: hi)))
        if path.closed, lo <= 0.01, hi >= path.length - 0.01 { p.closeSubpath() }
        return p
    }

    static func whole(_ path: TracePath) -> Path { segment(path, from: 0, to: path.length) }

    private static func shape(_ board: ShapeTraceBoard, slot: String) -> ShapeTraceShape? {
        board.shapes.first { $0.slot == slot }
    }

    private static func shapeDone(_ board: ShapeTraceBoard, slot: String) -> Bool {
        guard let index = board.shapes.firstIndex(where: { $0.slot == slot }) else { return false }
        return board.isDone(shape: index)
    }

    // MARK: Scenery (under the lanes)

    static func scenery(_ board: ShapeTraceBoard, in g: inout GraphicsContext) {
        let q = board.question
        switch q.scene {
        case .fireStation:
            stage(ShapeTraceArt.fireStation, in: &g)
            g.draw(Text(ShapeTraceCopy.fireStationLabel).font(CanvasFont.font(size: 22, weight: 900))
                    .foregroundColor(.white), at: CGPoint(x: 1110, y: 151))
            if q.slant { stage(ShapeTraceArt.hill, in: &g) }
            stage(ShapeTraceArt.craneBoom, dx: craneDX(board), in: &g)
        case .castleTowers:
            stage(ShapeTraceArt.castleTowers, dx: q.shift, in: &g)
            for slot in 0...1 where shape(board, slot: slot == 0 ? "spireA" : "spireB") == nil {
                let roof = ShapeTraceGenerator.spire(slot: slot, big: true, shift: q.shift)
                spireRoof(roof, painted: false, in: &g)
            }
        case .castleWindows:
            stage(ShapeTraceArt.castleFacade, in: &g)
            for slot in 0...1 where shape(board, slot: slot == 0 ? "windowA" : "windowB") == nil {
                let window = ShapeTraceGenerator.window(slot: slot, big: true, shift: q.shift)
                litWindow(window.frame, in: &g)
                g.stroke(Path(window.frame.cgRect), with: .color(ink), style: StrokeStyle(lineWidth: 10, lineJoin: .round))
            }
        case .snowTown:
            stage(ShapeTraceArt.snowGround, in: &g)
            place(ShapeTraceArt.pine, at: LineMatchPoint(x: 1176, y: 522), in: &g)
            place(ShapeTraceArt.pine, at: LineMatchPoint(x: 1250, y: 532), scale: 0.75, in: &g)
            stage(ShapeTraceArt.church, in: &g)
            clockFace(LineMatchPoint(x: 205, y: 300), in: &g)
            if shape(board, slot: "sun") == nil {
                let sun = ShapeTraceGenerator.snowCircle(slot: 1, big: false, shift: q.shift)
                sunDone(sun, painted: false, in: &g)
            }
            let body = shape(board, slot: "body") ?? ShapeTraceGenerator.snowCircle(slot: 0, big: false, shift: q.shift)
            if shape(board, slot: "body") == nil {
                let disc = Path(ellipseIn: body.frame.cgRect)
                g.fill(disc, with: .color(.white))
                g.stroke(disc, with: .color(ink), lineWidth: 6)
            }
            place(ShapeTraceArt.snowArms, at: LineMatchPoint(x: body.frame.midX, y: body.frame.midY + 30), in: &g)
        }
    }

    static func craneDX(_ board: ShapeTraceBoard) -> Double {
        guard let down = shape(board, slot: "down") else { return 0 }
        return down.strokes[0].start.x - 170
    }

    // MARK: Lanes, guides and painted progress

    static func lanes(_ board: ShapeTraceBoard, settings: ShapeTraceSettings, in g: inout GraphicsContext) {
        let lines = board.question.kind == .traceLines
        let lane = board.question.laneWidth
        for (index, shape) in board.shapes.enumerated() {
            let color = LineMatchRoadPalette.color(shape.colorIndex)
            if !lines, board.isDone(shape: index) {
                doneShape(shape, in: &g)
                continue
            }
            let cap: CGLineCap = lines ? .butt : .round
            // Pale lane with its ink edge.
            for stroke in shape.strokes {
                let p = whole(stroke)
                g.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: lane + 12, lineCap: cap, lineJoin: .round))
            }
            for stroke in shape.strokes {
                let p = whole(stroke)
                g.stroke(p, with: .color(Color(hex: color.pale)), style: StrokeStyle(lineWidth: lane, lineCap: cap,
                                                                                      lineJoin: .round))
            }
            if !lines { pendingInterior(shape, in: &g) }
            // Guide: white dashes on 畫直線, grey dots / dashes on 跟虛線.
            for stroke in shape.strokes {
                let p = whole(stroke)
                if lines {
                    g.stroke(p, with: .color(Color.white.opacity(0.95)),
                             style: StrokeStyle(lineWidth: 6, lineCap: .butt, dash: [22, 18]))
                } else if settings.dotStyle == .dots {
                    g.stroke(p, with: .color(guideGrey), style: StrokeStyle(lineWidth: 15, lineCap: .round, dash: [0.1, 28]))
                } else {
                    g.stroke(p, with: .color(guideGrey), style: StrokeStyle(lineWidth: 9, lineCap: .butt, dash: [16, 14]))
                }
            }
            // Painted: done strokes whole, the current stroke up to the vehicle.
            let done = board.doneStrokes(shape: index)
            for (k, _) in shape.strokes.enumerated() {
                guard let path = board.path(shape: index, stroke: k) else { continue }
                let upTo: Double
                if k < done { upTo = path.length } else if index == board.shapeIndex && k == board.strokeIndex {
                    upTo = board.progress
                } else { continue }
                guard upTo > 0.5 else { continue }
                let p = segment(path, from: 0, to: upTo)
                if lines {
                    g.stroke(p, with: .color(Color(hex: color.full)), style: StrokeStyle(lineWidth: lane, lineCap: .butt))
                    g.stroke(p, with: .color(Color.white.opacity(0.55)),
                             style: StrokeStyle(lineWidth: 6, lineCap: .butt, dash: [22, 18]))
                } else {
                    g.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 32, lineCap: .round, lineJoin: .round))
                    g.stroke(p, with: .color(Color(hex: color.full)),
                             style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    /// Not drawn yet: the window is dim, the circle a faint snow disc (mockups 03, 04).
    private static func pendingInterior(_ shape: ShapeTraceShape, in g: inout GraphicsContext) {
        switch shape.kind {
        case .square:
            g.fill(Path(shape.frame.cgRect), with: .color(Color(hex: 0x5A5160).opacity(0.18)))
        case .circle:
            let inset = shape.frame.cgRect.insetBy(dx: 40, dy: 40)
            g.fill(Path(ellipseIn: inset), with: .color(Color.white.opacity(0.6)))
        case .across, .down, .slant, .spire:
            break
        }
    }

    /// A finished dotted shape: its done look plus the painted outline.
    private static func doneShape(_ shape: ShapeTraceShape, in g: inout GraphicsContext) {
        switch shape.kind {
        case .spire:
            spireRoof(shape, painted: true, in: &g)
        case .square:
            litWindow(shape.frame, in: &g)
            paintedOutline(shape, in: &g)
        case .circle:
            if shape.slot == "sun" {
                sunDone(shape, painted: true, in: &g)
            } else {
                g.fill(Path(ellipseIn: shape.frame.cgRect), with: .color(.white))
                paintedOutline(shape, in: &g)
            }
        case .across, .down, .slant:
            paintedOutline(shape, in: &g)
        }
    }

    private static func paintedOutline(_ shape: ShapeTraceShape, in g: inout GraphicsContext) {
        let color = Color(hex: LineMatchRoadPalette.color(shape.colorIndex).full)
        for stroke in shape.strokes {
            let p = whole(stroke)
            g.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 32, lineCap: .round, lineJoin: .round))
        }
        for stroke in shape.strokes {
            let p = whole(stroke)
            g.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
        }
    }

    /// Mockup 02 tower A: red roof, highlight, flag (scaled to the spire's height).
    static func spireRoof(_ shape: ShapeTraceShape, painted: Bool, in g: inout GraphicsContext) {
        let f = shape.frame
        let apex = CGPoint(x: f.midX, y: f.y)
        let k = f.height / 200
        var roof = Path()
        roof.move(to: apex)
        roof.addLine(to: CGPoint(x: f.x, y: f.maxY))
        roof.addLine(to: CGPoint(x: f.maxX, y: f.maxY))
        roof.closeSubpath()
        g.fill(roof, with: .color(Color(hex: 0xE8473C)))
        g.stroke(roof, with: .color(ink), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
        var shine = Path()
        shine.move(to: CGPoint(x: apex.x, y: apex.y + 32 * k))
        shine.addLine(to: CGPoint(x: apex.x - 36 * k, y: apex.y + 100 * k))
        shine.move(to: CGPoint(x: apex.x, y: apex.y + 32 * k))
        shine.addLine(to: CGPoint(x: apex.x + 36 * k, y: apex.y + 100 * k))
        g.stroke(shine, with: .color(Color(hex: 0xF27A6E).opacity(0.8)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        if painted { paintedOutline(shape, in: &g) }
        var pole = Path()
        pole.move(to: CGPoint(x: apex.x, y: apex.y - 2))
        pole.addLine(to: CGPoint(x: apex.x, y: apex.y - 34))
        g.stroke(pole, with: .color(ink), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        var flag = Path()
        flag.move(to: CGPoint(x: apex.x + 2, y: apex.y - 34))
        flag.addLine(to: CGPoint(x: apex.x + 44, y: apex.y - 23))
        flag.addLine(to: CGPoint(x: apex.x + 2, y: apex.y - 10))
        flag.closeSubpath()
        g.fill(flag, with: .color(Color(hex: 0xFFC93C)))
        g.stroke(flag, with: .color(ink), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
    }

    /// Mockup 04 window A: lamp glow, cross bars, curtains (scaled to the window's side).
    static func litWindow(_ frame: LineMatchRect, in g: inout GraphicsContext) {
        let r = frame.cgRect
        let k = frame.width / 200
        g.fill(Path(r), with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF6C8), Color(hex: 0xFFD447)]),
                                              center: CGPoint(x: r.midX, y: r.minY + r.height * 0.55),
                                              startRadius: 0, endRadius: r.width * 0.6))
        var bars = Path()
        bars.move(to: CGPoint(x: r.midX, y: r.minY))
        bars.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        bars.move(to: CGPoint(x: r.minX, y: r.midY))
        bars.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        g.stroke(bars, with: .color(Color(hex: 0xC98B52)), lineWidth: 10)
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
        var curtains = Path()
        curtains.move(to: pt(12, 12))
        curtains.addQuadCurve(to: pt(18, 140), control: pt(50, 56))
        curtains.addLine(to: pt(12, 140))
        curtains.closeSubpath()
        curtains.move(to: pt(188, 12))
        curtains.addQuadCurve(to: pt(182, 140), control: pt(150, 56))
        curtains.addLine(to: pt(188, 140))
        curtains.closeSubpath()
        g.fill(curtains, with: .color(Color(hex: 0xF49AB0)))
        g.stroke(curtains, with: .color(ink), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
    }

    /// Mockup 03 sun: rays, yellow face, eyes, smile, cheeks (scaled to the radius).
    static func sunDone(_ shape: ShapeTraceShape, painted: Bool, in g: inout GraphicsContext) {
        let c = CGPoint(x: shape.frame.midX, y: shape.frame.midY)
        let r = shape.frame.width / 2
        let k = r / 78
        var rays = Path()
        for step in 0..<8 {
            let a = Double(step) * Double.pi / 4
            rays.move(to: CGPoint(x: c.x + cos(a) * (r + 24), y: c.y + sin(a) * (r + 24)))
            rays.addLine(to: CGPoint(x: c.x + cos(a) * (r + 44), y: c.y + sin(a) * (r + 44)))
        }
        g.stroke(rays, with: .color(Color(hex: 0xF5963C)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
        let disc = Path(ellipseIn: shape.frame.cgRect)
        g.fill(disc, with: .color(Color(hex: 0xFFD447)))
        if painted {
            paintedOutline(shape, in: &g)
        } else {
            g.stroke(disc, with: .color(ink), lineWidth: 6)
        }
        for side in [-1.0, 1.0] {
            g.fill(Path(ellipseIn: CGRect(x: c.x + side * 24 * k - 7 * k, y: c.y - 10 * k - 7 * k, width: 14 * k, height: 14 * k)),
                   with: .color(ink))
            g.fill(Path(ellipseIn: CGRect(x: c.x + side * 42 * k - 10 * k, y: c.y + 12 * k - 6 * k, width: 20 * k, height: 12 * k)),
                   with: .color(Color(hex: 0xF9A9B4)))
        }
        var smile = Path()
        smile.move(to: CGPoint(x: c.x - 26 * k, y: c.y + 18 * k))
        smile.addQuadCurve(to: CGPoint(x: c.x + 26 * k, y: c.y + 18 * k), control: CGPoint(x: c.x, y: c.y + 42 * k))
        g.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 6, lineCap: .round))
    }

    /// Church clock (scenery in phase 1): white face, ink rim, hands at three o'clock.
    static func clockFace(_ c: LineMatchPoint, in g: inout GraphicsContext) {
        let disc = Path(ellipseIn: CGRect(x: c.x - 56, y: c.y - 56, width: 112, height: 112))
        g.fill(disc, with: .color(.white))
        g.stroke(disc, with: .color(ink), lineWidth: 6)
        var hands = Path()
        hands.move(to: CGPoint(x: c.x, y: c.y - 38))
        hands.addLine(to: CGPoint(x: c.x, y: c.y))
        hands.addLine(to: CGPoint(x: c.x + 28, y: c.y))
        g.stroke(hands, with: .color(ink), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
    }

    // MARK: Markers (go / end / ticks / numbers / chevrons / stop sign)

    static func markers(_ board: ShapeTraceBoard, settings: ShapeTraceSettings, in g: inout GraphicsContext) {
        let lines = board.question.kind == .traceLines
        for (index, shape) in board.shapes.enumerated() {
            if lines {
                let path = board.path(shape: index, stroke: 0) ?? shape.strokes[0]
                if board.isDone(shape: index) {
                    place(ShapeTraceArt.tick, at: path.end, in: &g)
                } else {
                    place(ShapeTraceArt.go, at: path.start, angle: path.angle(at: 0), in: &g)
                    place(ShapeTraceArt.end, at: path.end, angle: path.angle(at: path.length), in: &g)
                    number(index + 1, at: lineBadge(shape, path: path), radius: 22, in: &g)
                }
                continue
            }
            guard index == board.shapeIndex else { continue }
            let done = board.doneStrokes(shape: index)
            for k in shape.strokes.indices {
                guard let path = board.path(shape: index, stroke: k) else { continue }
                if k < done {
                    place(ShapeTraceArt.tickSmall, at: path.end, in: &g)
                } else if k == board.strokeIndex {
                    place(ShapeTraceArt.go, at: path.start, angle: path.angle(at: 0), in: &g)
                    if path.closed {
                        let d = board.arrivalDistance(path)
                        place(ShapeTraceArt.endRing, at: path.point(at: d), angle: path.angle(at: d), in: &g)
                    } else {
                        place(ShapeTraceArt.end, at: path.end, angle: path.angle(at: path.length), in: &g)
                    }
                }
                if shape.strokes.count > 1, let badge = strokeBadge(shape, stroke: k) {
                    number(k + 1, at: badge, radius: 20, in: &g)
                }
            }
        }
        // Direction chevrons ahead of the vehicle.
        if settings.directionHint, let path = board.currentPath {
            for ahead in [70.0, 140.0] {
                let d = board.progress + ahead
                guard d < path.length - 40 else { continue }
                let p = path.point(at: d)
                var layer = g
                layer.translateBy(x: p.x, y: p.y)
                layer.rotate(by: .radians(path.angle(at: d)))
                var chevron = Path()
                chevron.move(to: CGPoint(x: -9, y: -14))
                chevron.addLine(to: CGPoint(x: 7, y: 0))
                chevron.addLine(to: CGPoint(x: -9, y: 14))
                layer.stroke(chevron, with: .color(.white), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }
        }
        // Corner stop sign while the vehicle waits at a corner.
        if settings.cornerStop, board.isAtCorner, let path = board.currentPath {
            let corner = path.point(at: board.progress)
            let at = LineMatchPoint(x: min(corner.x + 60, 1180), y: max(corner.y - 64, 150))
            place(ShapeTraceArt.stopSign, at: at, in: &g)
            g.draw(Text(ShapeTraceCopy.stopSign).font(CanvasFont.font(size: 28, weight: 900)).foregroundColor(.white),
                   at: cg(at))
        }
    }

    private static func lineBadge(_ shape: ShapeTraceShape, path: TracePath) -> LineMatchPoint {
        switch shape.kind {
        case .down: return LineMatchPoint(x: path.start.x - 72, y: path.start.y)
        case .slant: return LineMatchPoint(x: path.start.x + 65, y: path.start.y - 61)
        default: return LineMatchPoint(x: path.start.x - 64, y: path.start.y)
        }
    }

    /// Stroke-order badges (mockups 02 and 04).
    private static func strokeBadge(_ shape: ShapeTraceShape, stroke k: Int) -> LineMatchPoint? {
        let f = shape.frame
        switch (shape.kind, k) {
        case (.square, 0): return LineMatchPoint(x: f.x - 60, y: f.y + 40)
        case (.square, 1): return LineMatchPoint(x: f.x + 40, y: f.y - 58)
        case (.square, 2): return LineMatchPoint(x: f.x + 40, y: f.maxY + 58)
        case (.spire, 0): return LineMatchPoint(x: f.midX - 92, y: f.y + 26)
        case (.spire, 1): return LineMatchPoint(x: f.midX + 92, y: f.y + 26)
        default: return nil
        }
    }

    private static func number(_ n: Int, at p: LineMatchPoint, radius: Double, in g: inout GraphicsContext) {
        let disc = Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
        g.fill(disc, with: .color(.white))
        g.stroke(disc, with: .color(ink), lineWidth: 5)
        g.draw(Text("\(n)").font(CanvasFont.font(size: radius * 1.3, weight: 800)).foregroundColor(ink), at: cg(p))
    }

    // MARK: Followers (the vehicle that follows the pen)

    static func followers(_ board: ShapeTraceBoard, in g: inout GraphicsContext) {
        let q = board.question
        if q.scene == .snowTown { snowmanHead(board, in: &g) }
        guard q.kind == .traceLines else {
            if let p = board.vehiclePoint {
                place(ShapeTraceArt.paintCar, at: p, scale: 0.78, angle: board.vehicleAngle, in: &g)
            }
            return
        }
        for (index, shape) in board.shapes.enumerated() {
            let path = board.path(shape: index, stroke: 0) ?? shape.strokes[0]
            let point: LineMatchPoint
            if board.isDone(shape: index) {
                point = path.end
            } else if index == board.shapeIndex {
                point = path.point(at: board.progress)
            } else {
                point = path.start
            }
            switch shape.kind {
            case .across where shape.slot == "across":
                if board.isDone(shape: index) {
                    place(ShapeTraceArt.fireEngine, at: LineMatchPoint(x: 1078, y: 300), scale: 0.72, in: &g)
                } else {
                    place(ShapeTraceArt.fireEngine, at: LineMatchPoint(x: point.x, y: point.y + 26), scale: 0.46, in: &g)
                }
            case .down:
                crane(at: point, dx: path.start.x - 170, in: &g)
            default:
                let angle = path.angle(at: 0)
                let ground = LineMatchPoint(x: point.x - sin(angle) * 22, y: point.y + cos(angle) * 22)
                place(ShapeTraceArt.taxi, at: ground, scale: 0.5, angle: shape.kind == .slant ? angle : 0, in: &g)
            }
        }
    }

    /// Crane truck, cable and hook; the hook rides just above the pen (mockup 01).
    private static func crane(at point: LineMatchPoint, dx: Double, in g: inout GraphicsContext) {
        stage(ShapeTraceArt.craneBox, dx: dx, in: &g)
        stage(ShapeTraceArt.craneTruck, dx: dx, in: &g)
        let cableEnd = LineMatchPoint(x: 170 + dx, y: max(point.y - 60, 170))
        var cable = Path()
        cable.move(to: CGPoint(x: 170 + dx, y: 160))
        cable.addLine(to: cg(cableEnd))
        g.stroke(cable, with: .color(ink), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        place(ShapeTraceArt.craneHook, at: cableEnd, in: &g)
    }

    /// The snowman's head sits above the body slot; a scarf joins them once the body is drawn.
    private static func snowmanHead(_ board: ShapeTraceBoard, in g: inout GraphicsContext) {
        let body = shape(board, slot: "body") ?? ShapeTraceGenerator.snowCircle(slot: 0, big: false, shift: board.question.shift)
        let r = body.frame.width / 2
        let c = CGPoint(x: body.frame.midX, y: body.frame.midY - r - 98)
        let head = Path(ellipseIn: CGRect(x: c.x - 52, y: c.y - 52, width: 104, height: 104))
        g.fill(head, with: .color(.white))
        g.stroke(head, with: .color(ink), lineWidth: 6)
        for side in [-1.0, 1.0] {
            g.fill(Path(ellipseIn: CGRect(x: c.x + side * 17 - 5.5, y: c.y - 10 - 5.5, width: 11, height: 11)), with: .color(ink))
        }
        var smile = Path()
        smile.move(to: CGPoint(x: c.x - 16, y: c.y + 14))
        smile.addQuadCurve(to: CGPoint(x: c.x + 16, y: c.y + 14), control: CGPoint(x: c.x, y: c.y + 28))
        g.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        let bodyDrawn = shape(board, slot: "body") == nil || shapeDone(board, slot: "body")
        if bodyDrawn {
            let top = c.y + 46
            let bottom = body.frame.y + 6
            let scarf = Path(roundedRect: CGRect(x: c.x - 64, y: top, width: 128, height: max(18, bottom - top)),
                             cornerRadius: 12)
            g.fill(scarf, with: .color(Color(hex: 0xE8473C)))
            g.stroke(scarf, with: .color(ink), lineWidth: 5)
        }
    }

    // MARK: Bubble placement

    static func bubbleRect(_ q: ShapeTraceQuestion, shape: ShapeTraceShape) -> LineMatchRect {
        let width = 270.0, height = 66.0
        if q.kind == .traceLines {
            switch shape.slot {
            case "across": return LineMatchRect(x: 862, y: 324, width: width, height: height)
            case "down": return LineMatchRect(x: 300, y: 262, width: width, height: height)
            default: return LineMatchRect(x: 850, y: 380, width: width, height: height)
            }
        }
        let f = shape.frame
        if f.x - 40 - width - 10 >= 20 {
            return LineMatchRect(x: f.x - 40 - width - 10, y: f.midY - height / 2, width: width, height: height)
        }
        return LineMatchRect(x: max(20, f.midX - width / 2), y: max(ShapeTraceLayout.workspaceTop, f.y - 40 - height - 10),
                             width: width, height: height)
    }
}

private extension LineMatchRect {
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
