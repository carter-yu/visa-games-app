import SwiftUI
import VisaCore

/// 連一連 · 引導 / guided roads (v0.24.0, ADR 0013; mockups 07a–07c).
///
/// Word / number cards on the left, pictures / counted objects on the right, one coloured road
/// per pair. The child drags the truck along each road, top → bottom. The truck only goes
/// forwards and waits whenever the pen leaves the road (never a miss). After 2 s away, a tiny
/// hint rings the truck. Every road done → the model runs the usual success flow. No 完成,
/// no 擦晒, no Think Pause, nothing in the bottom-right parent corner.
///
/// All rules live in `VisaCore.LineMatchGuidedBoard`. This view runs it on a local copy per pen
/// event and hands the result to the model on pen-up and when a road is done, so the model is
/// never published per move. No text input, no context menu, no navigation.
struct LineMatchGuidedBoardView: View {
    let board: LineMatchGuidedBoard
    /// Ticket ★ (1–3) for the header ticket colour.
    let ticketStars: Int
    let pendingMinutes: Int
    /// Finished (or the round is closing): no input.
    let locked: Bool
    let notice: SpokenPrompt?
    /// Model clock (seconds since reference date, 0.5 s tick) for the hint and idle re-prompt.
    let now: Double
    let onSpeak: () -> Void
    let onCommit: (LineMatchGuidedBoard) -> Void
    let onWrongStart: () -> Void
    let onHint: (Int) -> Void

    var body: some View {
        CanvasStage {
            LineMatchBackdrop()
        } content: {
            GuidedStageContent(view: self)
        }
        .onAppear(perform: onSpeak)
    }
}

private struct GuidedStageContent: View {
    let view: LineMatchGuidedBoardView
    @Environment(\.canvasMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Local board while the child drives (synced to the model on pen-up / road done).
    @State private var local: LineMatchGuidedBoard?
    /// Pen tip in stage units during a stroke (hint trail).
    @State private var penTip: CGPoint?
    @State private var dragSeen = false
    /// Model-clock time of the last pen activity (idle re-prompt). Nil until the board appears.
    @State private var lastInputAt: Double?
    @GestureState private var gestureActive = false

    /// The local copy when it is a newer version of the model's board; else the model's board.
    private var board: LineMatchGuidedBoard {
        if let local, local.isMonotonicSuccessor(of: view.board) { return local }
        return view.board
    }

    private var layout: LineMatchGuidedLayout { board.layout }
    private var hintOn: Bool { !view.locked && board.showsHint(now: view.now) }
    private var hintRow: Int? { hintOn ? board.currentRow : nil }
    private var idleDue: Bool {
        guard let last = lastInputAt, !view.locked, !board.isComplete, !dragSeen else { return false }
        return view.now - last >= LineMatchGuidedBoard.idleRepromptSeconds
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
            .onEnded { value in dragEnded(value) }
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
            let start = stagePoint(value.startLocation)
            if case .wrongStart = next.penDown(at: lm(start), now: clock) {
                local = next
                view.onWrongStart()
                return
            }
        }
        let move = next.penMove(to: lm(tip), now: clock)
        local = next
        if case .completed = move { view.onCommit(next) }
    }

    private func dragEnded(_ value: DragGesture.Value) {
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
            roadsLayer
            ForEach(Array(board.rows), id: \.self) { row in
                leftCard(row)
            }
            ForEach(Array(board.rows), id: \.self) { slot in
                rightCard(slot)
            }
            dotsLayer
            hintLayer
            truck
            Color.clear
                .frame(width: metrics.u(1280), height: metrics.u(720))
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .allowsHitTesting(!view.locked && !board.isComplete)
                .accessibilityHidden(true)
            bubbles
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
            // Gesture cancelled by the system (no onEnded). Defer one main-queue turn so a real
            // onEnded always runs first (same rule as the free board).
            guard !active else { return }
            DispatchQueue.main.async {
                if dragSeen { cancelStroke() }
            }
        }
        .onChange(of: hintRow) { row in
            if let row { view.onHint(row) }
        }
        .onChange(of: idleDue) { due in
            guard due else { return }
            lastInputAt = view.now
            view.onSpeak()
        }
    }

    // MARK: Roads (pale tint, driven part in full colour, one bridge at ★★)

    private var roadsLayer: some View {
        let scale = metrics.scale
        let roads = board.roads
        let progress = board.progress
        let done = Set(board.doneRows)
        let current = board.currentRow
        let chevrons = layout.chevrons
        let over = board.question.guided?.bridgeOverRow
        let crossings = LineMatchGuidedGeometry.allCrossings(roads)
        // Bridge road last; the crossing road under it just before.
        let order = roads.indices.sorted { lhs, rhs in
            (lhs == over ? 1 : 0, lhs) < (rhs == over ? 1 : 0, rhs)
        }
        return Canvas { context, _ in
            var g = context
            g.scaleBy(x: scale, y: scale)
            func path(_ road: LineMatchRoad, from a: Double, to b: Double, offset: Double = 0) -> Path {
                var p = Path()
                let steps = max(2, Int((b - a) / 8))
                for index in 0...steps {
                    let d = a + (b - a) * Double(index) / Double(steps)
                    let q = road.point(at: d)
                    let angle = road.angle(at: d)
                    let point = CGPoint(x: q.x - sin(angle) * offset, y: q.y + cos(angle) * offset)
                    if index == 0 { p.move(to: point) } else { p.addLine(to: point) }
                }
                return p
            }
            func bridge(_ road: LineMatchRoad, at d: Double) {
                let half = 78.0
                let a = max(0, d - half), b = min(road.length, d + half)
                let deck = path(road, from: a, to: b)
                var shadow = g
                shadow.translateBy(x: 0, y: 10)
                shadow.stroke(deck, with: .color(LM.ink.opacity(0.22)), style: StrokeStyle(lineWidth: road.width + 44))
                g.stroke(deck, with: .color(LM.ink), style: StrokeStyle(lineWidth: road.width + 36))
                g.stroke(deck, with: .color(Color(hex: 0xE9E4EC)), style: StrokeStyle(lineWidth: road.width + 24))
                for side in [1.0, -1.0] {
                    g.stroke(path(road, from: a, to: b, offset: side * (road.width / 2 + 12)), with: .color(LM.ink),
                             style: StrokeStyle(lineWidth: 4, dash: [3, 13]))
                }
                for end in [a, b] {
                    let q = road.point(at: end)
                    let angle = road.angle(at: end)
                    let reach = road.width / 2 + 18
                    var cap = Path()
                    cap.move(to: CGPoint(x: q.x + sin(angle) * reach, y: q.y - cos(angle) * reach))
                    cap.addLine(to: CGPoint(x: q.x - sin(angle) * reach, y: q.y + cos(angle) * reach))
                    g.stroke(cap, with: .color(LM.ink), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    g.stroke(cap, with: .color(Color(hex: 0xCFC8D4)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                }
            }
            for index in order {
                let road = roads[index]
                let color = LineMatchRoadPalette.color(road.colorIndex)
                if index == over, let crossing = crossings.first {
                    bridge(road, at: crossing.upper == road.row ? crossing.crossing.distanceOnFirst
                                                                : crossing.crossing.distanceOnSecond)
                }
                let whole = path(road, from: 0, to: road.length)
                g.stroke(whole, with: .color(LM.ink), style: StrokeStyle(lineWidth: road.width + 12))
                g.stroke(whole, with: .color(Color(hex: color.pale)), style: StrokeStyle(lineWidth: road.width))
                let isDone = done.contains(road.row)
                let driven = isDone ? road.length : (progress.indices.contains(road.row) ? progress[road.row] : 0)
                if driven > 1 {
                    g.stroke(path(road, from: 0, to: driven), with: .color(Color(hex: color.full)),
                             style: StrokeStyle(lineWidth: road.width))
                }
                g.stroke(whole, with: .color(Color.white.opacity(isDone ? 0.55 : 0.95)),
                         style: StrokeStyle(lineWidth: 6, dash: [22, 18]))
                if chevrons, road.row == current {
                    var d = driven + 90
                    while d < road.endDistance - 60 {
                        let q = road.point(at: d)
                        let angle = road.angle(at: d)
                        var chevron = Path()
                        chevron.move(to: CGPoint(x: -9, y: -14))
                        chevron.addLine(to: CGPoint(x: 7, y: 0))
                        chevron.addLine(to: CGPoint(x: -9, y: 14))
                        let placed = chevron.applying(CGAffineTransform(rotationAngle: angle)
                            .concatenating(CGAffineTransform(translationX: q.x, y: q.y)))
                        g.stroke(placed, with: .color(.white),
                                 style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        d += 80
                    }
                }
            }
        }
        .frame(width: metrics.u(1280), height: metrics.u(720))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Dots (green start, red end → green tick when done; only the next green dot pulses)

    private var dotsLayer: some View {
        let scale = metrics.scale
        let goDots = layout.goDots
        let endDots = layout.endDots
        let current = board.currentRow
        let doneSlots = Set(board.rows.filter { board.isDone(slot: $0) })
        let pulse = !reduceMotion && Int(view.now * 2) % 2 == 0
        let truckAtStart = current.map { board.progress[$0] <= board.roads[$0].goDistance + 1 } ?? false
        return Canvas { context, _ in
            var g = context
            g.scaleBy(x: scale, y: scale)
            func circle(_ p: LineMatchPoint, _ r: Double) -> Path {
                Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            }
            func dot(_ p: LineMatchPoint, _ fill: Color) {
                let r = LineMatchGuidedLayout.dotRadius
                g.fill(circle(p, r), with: .color(fill))
                g.stroke(circle(p, r), with: .color(LM.ink), lineWidth: 6)
                g.fill(Path(ellipseIn: CGRect(x: p.x - 13, y: p.y - 13, width: 12, height: 12)),
                       with: .color(Color.white.opacity(0.8)))
            }
            for (row, p) in goDots.enumerated() {
                if row == current, truckAtStart {
                    g.stroke(circle(p, pulse ? 38 : 32), with: .color(LM.route), lineWidth: 7)
                }
                dot(p, LM.go)
            }
            for (slot, p) in endDots.enumerated() {
                if doneSlots.contains(slot) {
                    let r = LineMatchGuidedLayout.tickRadius
                    g.fill(circle(p, r), with: .color(LM.go))
                    g.stroke(circle(p, r), with: .color(LM.ink), lineWidth: 6)
                    var tick = Path()
                    tick.move(to: CGPoint(x: p.x - 14, y: p.y + 1))
                    tick.addLine(to: CGPoint(x: p.x - 4, y: p.y + 12))
                    tick.addLine(to: CGPoint(x: p.x + 16, y: p.y - 12))
                    g.stroke(tick, with: .color(.white),
                             style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                } else {
                    dot(p, LM.end)
                }
            }
        }
        .frame(width: metrics.u(1280), height: metrics.u(720))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Cards

    private func cardShell<Content: View>(_ rect: LineMatchRect, glow: Bool,
                                          @ViewBuilder content: () -> Content) -> some View {
        let radius = metrics.u(28)
        return ZStack {
            if glow {
                RoundedRectangle(cornerRadius: metrics.u(37), style: .continuous)
                    .fill(LM.go.opacity(0.35))
                    .padding(metrics.u(-9))
            }
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LM.ink.opacity(0.16))
                .offset(y: metrics.u(7))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LM.card)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(glow ? Color(hex: 0x3E9A45) : LM.ink, lineWidth: metrics.u(6))
            content()
        }
        .frame(width: metrics.u(CGFloat(rect.width)), height: metrics.u(CGFloat(rect.height)))
        .canvasPlaced(x: CGFloat(rect.x), y: CGFloat(rect.y))
        .allowsHitTesting(false)
    }

    /// Left: the word (HK Traditional, English under it) or the number card 「4 四」.
    @ViewBuilder
    private func leftCard(_ row: Int) -> some View {
        if layout.leftCards.indices.contains(row), board.question.pairs.indices.contains(row) {
            let rect = layout.leftCards[row]
            let pair = board.question.pairs[row]
            cardShell(rect, glow: board.isDone(row: row)) {
                if let numeral = pair.numeral {
                    HStack(alignment: .center, spacing: metrics.u(10)) {
                        CanvasText("\(numeral)", size: 72, weight: 900, color: LM.ink, lineHeight: 1.1)
                        CanvasText(pair.labelTraditionalChinese, size: 46, weight: 900, color: LM.ink)
                    }
                } else {
                    let characters = CGFloat(max(1, pair.labelTraditionalChinese.count))
                    let size = min(CGFloat(layout.wordChineseSize), (CGFloat(rect.width) - 24) / characters)
                    VStack(spacing: 0) {
                        CanvasText(pair.labelTraditionalChinese, size: size, weight: 900, color: LM.ink, lineHeight: 1.1)
                        CanvasText(pair.labelEnglish, size: CGFloat(layout.wordEnglishSize), weight: 700, color: LM.soft)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(pair.labelTraditionalChinese) \(pair.labelEnglish)")
        }
    }

    /// Right: the picture, or the counted objects (§6 排法, same size on every card).
    @ViewBuilder
    private func rightCard(_ slot: Int) -> some View {
        if layout.rightCards.indices.contains(slot), let pair = board.question.rightPair(atSlot: slot) {
            let rect = layout.rightCards[slot]
            cardShell(rect, glow: board.isDone(slot: slot)) {
                if let object = board.question.countObject, let art = LineMatchArt.icon(object.iconKey) {
                    let scale = LineMatchCountLayout.objectScale(object: object, counts: board.question.pairs.map(\.count),
                                                                 cardWidth: rect.width, cardHeight: rect.height)
                    let spots = LineMatchCountLayout.placements(count: pair.count, object: object, scale: scale,
                                                                cardWidth: rect.width, cardHeight: rect.height)
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
                            VectorArtView(artwork: art)
                                .frame(width: metrics.u(CGFloat(spot.width)), height: metrics.u(CGFloat(spot.height)))
                                .position(x: metrics.u(CGFloat(spot.x)), y: metrics.u(CGFloat(spot.y)))
                        }
                    }
                    .frame(width: metrics.u(CGFloat(rect.width)), height: metrics.u(CGFloat(rect.height)),
                           alignment: .topLeading)
                } else if let art = LineMatchArt.icon(pair.iconKey) {
                    VectorArtView(artwork: art)
                        .frame(width: metrics.u(CGFloat(layout.pictureSide)), height: metrics.u(CGFloat(layout.pictureSide)))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pair.numeral != nil ? "\(pair.count)" : pair.labelEnglish)
        }
    }

    // MARK: Truck + hint

    /// The truck sits with its nose at the driven point, turned along the road.
    @ViewBuilder
    private var truck: some View {
        if let row = board.truckRow, board.roads.indices.contains(row) {
            let road = board.roads[row]
            let width = layout.truckWidth
            let height = width * 126 / 210
            let centre = road.point(at: max(0, board.progress[row] - width * 0.3))
            let angle = road.angle(at: board.progress[row])
            ZStack(alignment: .topLeading) {
                VectorArtView(artwork: LineMatchArt.miniTruck)
                    .frame(width: metrics.u(CGFloat(width)), height: metrics.u(CGFloat(height)))
                    .rotationEffect(.radians(angle))
                    .position(x: metrics.u(CGFloat(centre.x)), y: metrics.u(CGFloat(centre.y - 4)))
            }
            .frame(width: metrics.u(1280), height: metrics.u(720), alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Off-road for 2 s: dashed yellow glow ring on the truck and a dotted trail from the pen.
    @ViewBuilder
    private var hintLayer: some View {
        if hintOn, let truck = board.truckPoint {
            let scale = metrics.scale
            let tip = penTip
            Canvas { context, _ in
                var g = context
                g.scaleBy(x: scale, y: scale)
                let ring = Path(ellipseIn: CGRect(x: truck.x - 54, y: truck.y - 54, width: 108, height: 108))
                g.fill(ring, with: .color(LM.glow.opacity(0.55)))
                g.stroke(ring, with: .color(Color(hex: 0xF5B82E)), style: StrokeStyle(lineWidth: 5, dash: [10, 9]))
                if let tip {
                    var trail = Path()
                    trail.move(to: tip)
                    trail.addLine(to: CGPoint(x: truck.x, y: truck.y))
                    g.stroke(trail, with: .color(Color(hex: 0xF5B82E)),
                             style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [2, 10]))
                }
            }
            .frame(width: metrics.u(1280), height: metrics.u(720))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: Bubbles 「眼睛、eye」 (stay until the round ends)

    private var bubbles: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(board.rows), id: \.self) { slot in
                if board.isDone(slot: slot), layout.bubbles.indices.contains(slot),
                   let pair = board.question.rightPair(atSlot: slot) {
                    GuidedBubble(rect: layout.bubbles[slot], tail: layout.bubbleTails[slot],
                                 stacked: layout.bubbleStacked[slot], pair: pair)
                }
            }
        }
        .frame(width: metrics.u(1280), height: metrics.u(720), alignment: .topLeading)
        .allowsHitTesting(false)
    }

    // MARK: Status (one dot per road + one line)

    private var statusLines: (zh: String, en: String) {
        if board.isComplete { return (LineMatchGuidedCopy.doneTraditionalChinese, LineMatchGuidedCopy.doneEnglish) }
        if hintOn { return (LineMatchGuidedCopy.offRoadTraditionalChinese, LineMatchGuidedCopy.offRoadEnglish) }
        if let notice = view.notice { return (notice.traditionalChinese, notice.english) }
        return (LineMatchGuidedCopy.remainingTraditionalChinese(board.remainingRoads),
                LineMatchGuidedCopy.remainingEnglish(board.remainingRoads))
    }

    private var status: some View {
        let lines = statusLines
        let rect = layout.status
        return VStack(spacing: metrics.u(4)) {
            HStack(spacing: metrics.u(12)) {
                ForEach(Array(board.rows), id: \.self) { row in
                    let color = LineMatchRoadPalette.color(board.roads[row].colorIndex)
                    let done = board.isDone(row: row)
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

    // MARK: Header (Stampy + prompt = replay voice, 連一連 · 引導 badge, visa ticket)

    private var header: some View {
        let frame = LineMatchLayout.header
        let stars = min(max(view.ticketStars, 1), 3)
        let zh = board.question.promptTraditionalChinese
        let en = board.question.promptEnglish
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
                        CanvasText(zh, size: 36, weight: 900, color: LM.ink)
                        CanvasText(en, size: 20, weight: 700, color: LM.headerSub)
                    }
                }
                .frame(width: metrics.u(820), height: metrics.u(92), alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .canvasPlaced(x: 40, y: 18)
            .accessibilityLabel("再聽一次：\(zh) / Hear it again: \(en)")

            VStack(spacing: 0) {
                CanvasText(LineMatchCopy.gameTraditionalChinese, size: 24, weight: 900, color: LM.ink)
                CanvasText("\(LineMatchGuidedCopy.badgeTraditionalChinese) · \(LineMatchGuidedCopy.badgeEnglish)",
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

/// 「眼睛、eye」 speech bubble with a speaker glyph (mockup `bubble`). One line above / between
/// the cards, or stacked (word over English) beside a lower ★★ picture.
private struct GuidedBubble: View {
    let rect: LineMatchRect
    let tail: LineMatchPoint
    let stacked: Bool
    let pair: LineMatchPair
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            tailShape
            ZStack {
                RoundedRectangle(cornerRadius: metrics.u(30), style: .continuous)
                    .fill(LM.ink.opacity(0.16))
                    .offset(y: metrics.u(6))
                RoundedRectangle(cornerRadius: metrics.u(30), style: .continuous)
                    .fill(Color.white)
                RoundedRectangle(cornerRadius: metrics.u(30), style: .continuous)
                    .strokeBorder(LM.ink, lineWidth: metrics.u(5))
                HStack(spacing: metrics.u(10)) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: metrics.u(stacked ? 24 : 28), weight: .bold))
                        .foregroundStyle(LM.route)
                    if stacked {
                        VStack(alignment: .leading, spacing: 0) {
                            CanvasText(pair.labelTraditionalChinese, size: 32, weight: 900, color: LM.ink, lineHeight: 1.15)
                            CanvasText(pair.labelEnglish, size: 24, weight: 700, color: Color(hex: 0x4C8FE0))
                        }
                    } else {
                        HStack(alignment: .lastTextBaseline, spacing: 0) {
                            CanvasText("\(pair.labelTraditionalChinese)、", size: 34, weight: 900, color: LM.ink)
                            CanvasText(pair.labelEnglish, size: 30, weight: 700, color: Color(hex: 0x4C8FE0))
                        }
                    }
                }
            }
            .frame(width: metrics.u(CGFloat(rect.width)), height: metrics.u(CGFloat(rect.height)))
            .canvasPlaced(x: CGFloat(rect.x), y: CGFloat(rect.y))
        }
        .frame(width: metrics.u(1280), height: metrics.u(720), alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LineMatchGuidedCopy.bubble(pair))
    }

    /// Triangle from the nearest bubble edge to the tick / card.
    private var tailShape: some View {
        let scale = metrics.scale
        let r = rect
        let t = tail
        return Canvas { context, _ in
            var g = context
            g.scaleBy(x: scale, y: scale)
            var p = Path()
            if t.y < r.y {
                let bx = min(max(t.x, r.x + 40), r.maxX - 40)
                p.move(to: CGPoint(x: bx - 16, y: r.y + 3))
                p.addLine(to: CGPoint(x: t.x, y: t.y))
                p.addLine(to: CGPoint(x: bx + 16, y: r.y + 3))
            } else if t.y > r.maxY {
                let bx = min(max(t.x, r.x + 40), r.maxX - 40)
                p.move(to: CGPoint(x: bx - 16, y: r.maxY - 3))
                p.addLine(to: CGPoint(x: t.x, y: t.y))
                p.addLine(to: CGPoint(x: bx + 16, y: r.maxY - 3))
            } else {
                let by = min(max(t.y, r.y + 24), r.maxY - 24)
                p.move(to: CGPoint(x: r.x + 3, y: by - 14))
                p.addLine(to: CGPoint(x: t.x, y: t.y))
                p.addLine(to: CGPoint(x: r.x + 3, y: by + 14))
            }
            p.closeSubpath()
            g.fill(p, with: .color(.white))
            g.stroke(p, with: .color(LM.ink), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
        }
        .frame(width: metrics.u(1280), height: metrics.u(720))
        .allowsHitTesting(false)
    }
}
