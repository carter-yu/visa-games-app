import SwiftUI
import VisaCore

/// 連一連 / Line Match board (v0.23.0, ADR 0012; approved mockups 05a–05i).
///
/// Header (Stampy + prompt = replay voice, game pill, visa ticket with live fuel minutes),
/// picture / count cards on the left with green dots, word / numeral cards on the right with
/// red dots, 擦晒 bottom-left and 完成 bottom bar (★) or top-right (★★ / ★★★). The bottom-right
/// parent corner stays empty. All rules live in `VisaCore.LineMatchBoard`; this view only
/// turns one pen / finger drag into begin / end calls and draws the live line + truck locally.
/// No text input, no context menu, no navigation.
struct LineMatchBoardView: View {
    let board: LineMatchBoard
    /// Ticket ★ (1–3) for the header ticket colour.
    let ticketStars: Int
    let pendingMinutes: Int
    let startingMinutes: Int
    let thinkPauseRemaining: Int
    let fuelFeedback: String?
    /// Think Pause or finished: no input.
    let locked: Bool
    let hintOn: Bool
    let notice: SpokenPrompt?
    /// Model clock (seconds since reference date) for the eraser cooldown and the orange rings.
    let now: Double
    let onSpeak: () -> Void
    /// Pen down at a stage point. Returns the row whose line the truck now draws.
    let onBeginDrag: (Double, Double) -> Int?
    let onEndDrag: (Double, Double) -> Void
    let onCancelDrag: () -> Void
    let onErase: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        ZStack {
            CanvasStage {
                LineMatchBackdrop()
            } content: {
                StageContent(view: self)
            }
            if thinkPauseRemaining > 0 {
                ThinkPauseOverlay(remainingSeconds: thinkPauseRemaining)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: thinkPauseRemaining > 0)
        .onAppear(perform: onSpeak)
    }
}

// MARK: - Palette (mockup colours)

private enum LM {
    static let ink = Color(hex: 0x2B2630)
    static let soft = Color(hex: 0x6B6170)
    static let card = Color(hex: 0xFFF9EC)
    static let header = Color(hex: 0xFFD147)
    static let headerSub = Color(hex: 0x6A5420)
    static let pill = Color(hex: 0xFFE68F)
    static let go = Color(hex: 0x5DBB63)
    static let end = Color(hex: 0xEE5A4C)
    static let route = Color(hex: 0xFFC93C)
    static let lockedRoute = Color(hex: 0x6CC46F)
    static let orange = Color(hex: 0xF5963C)
    static let offFill = Color(hex: 0xE4DFE7)
    static let offInk = Color(hex: 0x9A92A0)
    static let offMark = Color(hex: 0xB4ACBA)
    static let doneText = Color(hex: 0x24502A)
    static let glow = Color(hex: 0xFFF3A6)
    static let tomato = Color(hex: DesignTokens.Palette.tomato)

    static func ticketStub(_ stars: Int) -> Color {
        switch stars {
        case 2: return Color(hex: 0xE8473C)
        case 3: return Color(hex: 0x3B7DD8)
        default: return Color(hex: 0xFFB534)
        }
    }
}

// MARK: - Backdrop (sky + sand band aligned to stage y 540)

private struct LineMatchBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            let layout = DesignTokens.stageLayout(screenWidth: Double(proxy.size.width),
                                                  screenHeight: Double(proxy.size.height))
            let sandTop = CGFloat(layout.originY + 540 * layout.scale)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: 0x9ED5F2), Color(hex: 0xDDF2FC)],
                               startPoint: .top, endPoint: .bottom)
                Color(hex: 0xF4E1B4)
                    .frame(height: max(0, proxy.size.height - sandTop))
                    .offset(y: sandTop)
                Color(hex: 0xE5C98C)
                    .frame(height: CGFloat(8 * layout.scale))
                    .offset(y: sandTop)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Stage content

private struct StageContent: View {
    let view: LineMatchBoardView
    @Environment(\.canvasMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Live line: drawn here only (stage units); the model hears begin and end.
    @State private var liveRow: Int?
    @State private var liveTip: CGPoint?
    /// A gesture is in flight and its begin was already sent.
    @State private var dragSeen = false
    @GestureState private var gestureActive = false

    private var live: (row: Int, tip: CGPoint)? {
        guard let row = liveRow, let tip = liveTip else { return nil }
        return (row, tip)
    }

    private func stagePoint(_ point: CGPoint) -> CGPoint {
        let scale = max(metrics.scale, 0.0001)
        return CGPoint(x: point.x / scale, y: point.y / scale)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($gestureActive) { _, state, _ in state = true }
            .onChanged { value in dragChanged(value) }
            .onEnded { value in dragEnded(value) }
    }

    private func dragChanged(_ value: DragGesture.Value) {
        guard !view.locked else { return }
        if !dragSeen {
            dragSeen = true
            let start = stagePoint(value.startLocation)
            liveRow = view.onBeginDrag(Double(start.x), Double(start.y))
        }
        if liveRow != nil { liveTip = stagePoint(value.location) }
    }

    private func dragEnded(_ value: DragGesture.Value) {
        let started = dragSeen && liveRow != nil
        let tip = stagePoint(value.location)
        resetDrag()
        guard started, !view.locked else { return }
        view.onEndDrag(Double(tip.x), Double(tip.y))
    }

    private func resetDrag() {
        liveRow = nil
        liveTip = nil
        dragSeen = false
    }

    private var board: LineMatchBoard { view.board }
    private var layout: LineMatchLayout { board.layout }

    private var liveTarget: Int? {
        guard let current = live else { return nil }
        return board.dropTarget(at: LineMatchPoint(x: Double(current.tip.x), y: Double(current.tip.y)))
    }

    private var showRings: Bool { board.showsRejectRings(now: view.now, paused: view.thinkPauseRemaining > 0) }

    private var hintPair: (row: Int, slot: Int)? {
        guard view.hintOn, let row = board.hintRow, let slot = board.question.correctSlot(forRow: row) else { return nil }
        return (row, slot)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(board.rows), id: \.self) { row in
                leftCard(row)
            }
            ForEach(Array(board.rows), id: \.self) { slot in
                rightCard(slot)
            }
            linesLayer
            truck
            Color.clear
                .frame(width: metrics.u(1280), height: metrics.u(720))
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .allowsHitTesting(!view.locked && !board.solved)
                .accessibilityHidden(true)
            status
            eraserButton
            doneButton
            header
        }
        .onChange(of: view.locked) { isLocked in
            // Think Pause starts mid-drag: the line springs back (the model cancels too).
            if isLocked { resetDrag() }
        }
        .onChange(of: gestureActive) { active in
            // Gesture cancelled by the system (no onEnded): drop the live line.
            if !active, dragSeen {
                view.onCancelDrag()
                resetDrag()
            }
        }
    }

    // MARK: Cards

    private func border(left row: Int) -> (Color, CGFloat) {
        if board.locked[row] != nil { return (LM.go, 9) }
        if showRings, board.rejectedRows.contains(row) { return (LM.orange, 9) }
        if hintPair?.row == row { return (LM.route, 9) }
        if live?.row == row { return (LM.route, 8) }
        return (LM.ink, 6)
    }

    private func border(right slot: Int) -> (Color, CGFloat) {
        if board.slotIsLocked(slot) { return (LM.go, 9) }
        if showRings, board.rejectedSlots.contains(slot) { return (LM.orange, 9) }
        if hintPair?.slot == slot { return (LM.route, 9) }
        if liveTarget == slot { return (LM.route, 8) }
        return (LM.ink, 6)
    }

    private func cardShell<Content: View>(_ rect: LineMatchRect, edge: (Color, CGFloat),
                                          @ViewBuilder content: () -> Content) -> some View {
        let radius = metrics.u(rect.height >= 140 ? 30 : 26)
        return ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LM.ink.opacity(0.16))
                .offset(y: metrics.u(7))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LM.card)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(edge.0, lineWidth: metrics.u(edge.1))
            content()
        }
        .frame(width: metrics.u(CGFloat(rect.width)), height: metrics.u(CGFloat(rect.height)))
        .canvasPlaced(x: CGFloat(rect.x), y: CGFloat(rect.y))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func leftCard(_ row: Int) -> some View {
        if layout.leftCards.indices.contains(row), board.question.pairs.indices.contains(row) {
            let rect = layout.leftCards[row]
            let pair = board.question.pairs[row]
            cardShell(rect, edge: border(left: row)) {
                if let object = board.question.countObject, let art = LineMatchArt.icon(object.iconKey) {
                    let spots = board.objectPlacements(row: row)
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
                    let side = min(rect.width, rect.height) - 16
                    VectorArtView(artwork: art)
                        .frame(width: metrics.u(CGFloat(side)), height: metrics.u(CGFloat(side)))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pair.numeral != nil ? "\(pair.count)" : pair.labelEnglish)
        }
    }

    @ViewBuilder
    private func rightCard(_ slot: Int) -> some View {
        if layout.rightCards.indices.contains(slot), let pair = board.question.rightPair(atSlot: slot) {
            let rect = layout.rightCards[slot]
            cardShell(rect, edge: border(right: slot)) {
                if let numeral = pair.numeral {
                    HStack(alignment: .center, spacing: metrics.u(10)) {
                        CanvasText("\(numeral)", size: 72, weight: 900, color: LM.ink, lineHeight: 1.1)
                        CanvasText(pair.labelTraditionalChinese, size: 46, weight: 900, color: LM.ink)
                    }
                } else {
                    let characters = CGFloat(max(1, pair.labelTraditionalChinese.count))
                    let size = min(54, (CGFloat(rect.width) - 24) / characters)
                    VStack(spacing: 0) {
                        CanvasText(pair.labelTraditionalChinese, size: size, weight: 900, color: LM.ink, lineHeight: 1.15)
                        CanvasText(pair.labelEnglish, size: 24, weight: 700, color: LM.soft)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(pair.labelTraditionalChinese) \(pair.labelEnglish)")
        }
    }

    // MARK: Lines, dots, truck

    private var linesLayer: some View {
        let scale = metrics.scale
        let leftDots = layout.leftDots
        let rightDots = layout.rightDots
        let lines = board.visibleLines
        let current = live
        let target = liveTarget
        let ringRows = showRings ? board.rejectedRows : []
        let ringSlots = showRings ? board.rejectedSlots : []
        let hint = hintPair
        return Canvas { context, _ in
            var g = context
            g.scaleBy(x: scale, y: scale)
            func point(_ p: LineMatchPoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }
            func route(_ a: CGPoint, _ b: CGPoint, _ fill: Color) {
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                g.stroke(path, with: .color(LM.ink), style: StrokeStyle(lineWidth: 34, lineCap: .round))
                g.stroke(path, with: .color(fill), style: StrokeStyle(lineWidth: 22, lineCap: .round))
            }
            func ring(_ p: LineMatchPoint, _ color: Color) {
                let r = 36.0
                g.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(color), lineWidth: 8)
            }
            func dot(_ p: LineMatchPoint, _ fill: Color, grow: Bool) {
                let r = grow ? 28.0 : 22.0
                let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
                g.fill(Path(ellipseIn: rect), with: .color(fill))
                g.stroke(Path(ellipseIn: rect), with: .color(LM.ink), lineWidth: 6)
                g.fill(Path(ellipseIn: CGRect(x: p.x - 13, y: p.y - 13, width: 12, height: 12)),
                       with: .color(Color.white.opacity(0.8)))
            }
            for entry in lines where leftDots.indices.contains(entry.line.row)
                && rightDots.indices.contains(entry.line.slot) {
                route(point(leftDots[entry.line.row]), point(rightDots[entry.line.slot]),
                      entry.locked ? LM.lockedRoute : LM.route)
            }
            if let current, leftDots.indices.contains(current.row) {
                route(point(leftDots[current.row]), current.tip, LM.route)
            }
            if let hint, leftDots.indices.contains(hint.row), rightDots.indices.contains(hint.slot) {
                ring(leftDots[hint.row], LM.route)
                ring(rightDots[hint.slot], LM.route)
            }
            for row in ringRows where leftDots.indices.contains(row) { ring(leftDots[row], LM.orange) }
            for slot in ringSlots where rightDots.indices.contains(slot) { ring(rightDots[slot], LM.orange) }
            for (index, p) in leftDots.enumerated() { dot(p, LM.go, grow: current?.row == index) }
            for (index, p) in rightDots.enumerated() { dot(p, LM.end, grow: target == index) }
        }
        .frame(width: metrics.u(1280), height: metrics.u(720))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The mini truck rides the line tip (it turns over the other way when the line points left).
    @ViewBuilder
    private var truck: some View {
        if let current = live, layout.leftDots.indices.contains(current.row) {
            let from = layout.leftDots[current.row]
            let dx = Double(current.tip.x) - from.x
            let dy = Double(current.tip.y) - from.y
            let length = max(1, (dx * dx + dy * dy).squareRoot())
            let angle = atan2(dy, dx)
            let back = min(46, length / 2)
            ZStack(alignment: .topLeading) {
                VectorArtView(artwork: LineMatchArt.miniTruck)
                    .frame(width: metrics.u(130), height: metrics.u(78))
                    .scaleEffect(x: 1, y: abs(angle) > Double.pi / 2 ? -1 : 1)
                    .rotationEffect(.radians(angle))
                    .position(x: metrics.u(CGFloat(Double(current.tip.x) - dx / length * back)),
                              y: metrics.u(CGFloat(Double(current.tip.y) - dy / length * back)))
            }
            .frame(width: metrics.u(1280), height: metrics.u(720), alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: Status (progress dots + one line)

    private var statusLines: (zh: String, en: String, color: Color) {
        if let notice = view.notice { return (notice.traditionalChinese, notice.english, LM.ink) }
        if let fuel = view.fuelFeedback, !fuel.isEmpty, view.thinkPauseRemaining == 0 {
            return (fuel, WrongAnswerCopy.fuelHalvedEnglish, LM.tomato)
        }
        if view.hintOn, !board.canSubmit {
            let parts = board.question.hintTraditionalChinese.components(separatedBy: " / ")
            return (parts.first ?? "", parts.count > 1 ? parts[1] : "", LM.ink)
        }
        if board.canSubmit { return (LineMatchCopy.allJoinedTraditionalChinese, LineMatchCopy.allJoinedEnglish, LM.ink) }
        if board.joinedCount == 0 { return (LineMatchCopy.pullTraditionalChinese, LineMatchCopy.pullEnglish, LM.ink) }
        return (LineMatchCopy.moreToJoinTraditionalChinese(board.missingCount),
                LineMatchCopy.moreToJoinEnglish(board.missingCount), LM.ink)
    }

    private var showsArrow: Bool { layout.style == .wide && board.canSubmit && view.notice == nil }

    private var status: some View {
        let lines = statusLines
        let centre = showsArrow ? LineMatchPoint(x: 416, y: layout.status.y) : layout.status
        let width: CGFloat = 400
        let height: CGFloat = 110
        return ZStack(alignment: .topLeading) {
            VStack(spacing: metrics.u(4)) {
                HStack(spacing: metrics.u(12)) {
                    ForEach(Array(board.rows), id: \.self) { index in
                        Circle()
                            .fill(index < board.joinedCount ? LM.route : Color.white)
                            .overlay(Circle().strokeBorder(LM.ink, lineWidth: metrics.u(5)))
                            .frame(width: metrics.u(30), height: metrics.u(30))
                    }
                }
                CanvasText(lines.zh, size: 26, weight: 900, color: lines.color)
                if !lines.en.isEmpty {
                    CanvasText(lines.en, size: 17, weight: 700, color: LM.soft)
                }
            }
            .frame(width: metrics.u(width), height: metrics.u(height), alignment: .top)
            .canvasPlaced(x: CGFloat(centre.x) - width / 2, y: CGFloat(centre.y) - height / 2)
            if showsArrow {
                ArrowToDone()
                    .frame(width: metrics.u(230), height: metrics.u(60))
                    .canvasPlaced(x: 582, y: CGFloat(layout.status.y) - 24)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    // MARK: Buttons

    @ViewBuilder
    private var eraserButton: some View {
        let state = board.eraserState(now: view.now)
        if state != .hidden {
            let rect = layout.eraser
            let on = state == .ready && !view.locked
            let cooldown: Double = {
                if case .coolingDown(let remaining) = state {
                    return max(0, min(1, remaining / LineMatchBoard.eraserCooldownSeconds))
                }
                return 0
            }()
            Button(action: view.onErase) {
                EraserFace(on: on, cooldown: cooldown, compact: rect.width < 180)
                    .frame(width: metrics.u(CGFloat(rect.width)), height: metrics.u(CGFloat(rect.height)))
            }
            .buttonStyle(.plain)
            .disabled(!on)
            .canvasPlaced(x: CGFloat(rect.x), y: CGFloat(rect.y))
            .accessibilityLabel("\(LineMatchCopy.eraserTraditionalChinese) / \(LineMatchCopy.eraserEnglish)")
        }
    }

    private var doneButton: some View {
        let rect = layout.done
        let on = board.canSubmit && !view.locked
        let glow = on || board.submitNudge
        return Button(action: view.onSubmit) {
            DoneFace(on: on, glow: glow, pulse: board.submitNudge && !reduceMotion, compact: rect.width < 200)
                .frame(width: metrics.u(CGFloat(rect.width)), height: metrics.u(CGFloat(rect.height)))
        }
        .buttonStyle(.plain)
        // Grey 完成 still answers a tap with 「仲有未連嘅」 (no penalty); only the pause blocks it.
        .disabled(view.locked || board.solved)
        .canvasPlaced(x: CGFloat(rect.x), y: CGFloat(rect.y))
        .accessibilityLabel("\(LineMatchCopy.doneTraditionalChinese) / \(LineMatchCopy.doneEnglish)")
    }

    // MARK: Header

    private var header: some View {
        let frame = LineMatchLayout.header
        let allJoined = board.canSubmit
        let zh = allJoined ? LineMatchCopy.checkTraditionalChinese : board.question.promptTraditionalChinese
        let en = allJoined ? LineMatchCopy.checkEnglish : board.question.promptEnglish
        let stars = min(max(view.ticketStars, 1), 3)
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
                CanvasText(LineMatchCopy.gameEnglish, size: 16, weight: 700, color: LM.headerSub)
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

// MARK: - Pieces

/// Header ticket: coloured stub with the live fuel minutes, stars and 「簽證 Visa」.
private struct VisaTicketBadge: View {
    let stars: Int
    let minutes: Int
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        let text = stars == 1 ? LM.ink : Color.white
        let shape = RoundedRectangle(cornerRadius: metrics.u(12), style: .continuous)
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                CanvasText("\(minutes)", size: 32, weight: 900, color: text, lineHeight: 1.05)
                CanvasText("分鐘", size: 15, weight: 700, color: text)
            }
            .frame(width: metrics.u(72), height: metrics.u(74))
            .background(LM.ticketStub(stars))
            Rectangle()
                .fill(LM.ink)
                .frame(width: metrics.u(3), height: metrics.u(62))
            VStack(spacing: metrics.u(4)) {
                HStack(spacing: metrics.u(6)) {
                    ForEach(1...3, id: \.self) { index in
                        VectorArtView(artwork: CanvasArt.star)
                            .frame(width: metrics.u(28), height: metrics.u(28))
                            .opacity(index <= stars ? 1 : 0.25)
                    }
                }
                CanvasText("簽證 Visa", size: 17, weight: 900, color: LM.ink)
            }
            .frame(maxWidth: .infinity)
        }
        .background(LM.card)
        .clipShape(shape)
        .overlay(shape.strokeBorder(LM.ink, lineWidth: metrics.u(5)))
    }
}

/// 擦晒 face (mockup btn-eraser / -off / -v). A ring counts down the 3 s cooldown.
private struct EraserFace: View {
    let on: Bool
    /// 1 → 0 while cooling down.
    let cooldown: Double
    let compact: Bool
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.u(32), style: .continuous)
        let line = on ? LM.ink : LM.offInk
        VStack(spacing: 0) {
            ZStack {
                eraserGlyph(line: line)
                    .scaleEffect(compact ? 0.74 : 0.86)
                    .rotationEffect(.degrees(-20))
                if cooldown > 0 {
                    Circle()
                        .trim(from: 0, to: CGFloat(cooldown))
                        .stroke(LM.ink, style: StrokeStyle(lineWidth: metrics.u(6), lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: metrics.u(84), height: metrics.u(84))
                        .animation(.linear(duration: 0.5), value: cooldown)
                }
            }
            .frame(height: metrics.u(compact ? 80 : 88))
            CanvasText(LineMatchCopy.eraserTraditionalChinese, size: 34, weight: 900, color: on ? LM.ink : LM.offInk)
            CanvasText(LineMatchCopy.eraserEnglish, size: 18, weight: 700, color: on ? LM.soft : LM.offInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                shape.fill(LM.ink.opacity(on ? 0.18 : 0.12)).offset(y: metrics.u(8))
                shape.fill(on ? LM.card : LM.offFill)
                shape.strokeBorder(on ? LM.ink : LM.offInk, lineWidth: metrics.u(6))
            }
        }
        .contentShape(shape)
    }

    private func eraserGlyph(line: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: metrics.u(12), style: .continuous)
        return HStack(spacing: 0) {
            Rectangle().fill(on ? Color(hex: 0xF49AB0) : Color(hex: 0xD2CBD7))
                .frame(width: metrics.u(68))
            Rectangle().fill(line).frame(width: metrics.u(6))
            Rectangle().fill(on ? Color(hex: 0x6FA8E8) : Color(hex: 0xBDB5C3))
                .frame(width: metrics.u(34))
        }
        .frame(width: metrics.u(108), height: metrics.u(52))
        .clipShape(shape)
        .overlay(shape.strokeBorder(line, lineWidth: metrics.u(7)))
    }
}

/// 完成 face (mockup btn-done-on / -off / -v). Glows once every dot is joined, and after the
/// 4th erase (「試吓撳完成啦！」).
private struct DoneFace: View {
    let on: Bool
    let glow: Bool
    let pulse: Bool
    let compact: Bool
    @Environment(\.canvasMetrics) private var metrics
    @State private var pulsing = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.u(32), style: .continuous)
        ZStack {
            if glow {
                RoundedRectangle(cornerRadius: metrics.u(40), style: .continuous)
                    .fill(LM.glow.opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: metrics.u(40), style: .continuous)
                        .strokeBorder(LM.route, lineWidth: metrics.u(7)))
                    .padding(metrics.u(-9))
                    .scaleEffect(pulsing ? 1.05 : 1)
            }
            shape.fill(LM.ink.opacity(on ? 0.2 : 0.12)).offset(y: metrics.u(8))
            shape.fill(on ? LM.lockedRoute : LM.offFill)
            shape.strokeBorder(on ? LM.ink : LM.offInk, lineWidth: metrics.u(6))
            if compact {
                VStack(spacing: 0) {
                    checkMark.frame(width: metrics.u(84), height: metrics.u(66))
                    CanvasText(LineMatchCopy.doneTraditionalChinese, size: 38, weight: 900, color: textColor)
                    CanvasText(LineMatchCopy.doneEnglish, size: 18, weight: 700, color: subColor)
                }
            } else {
                HStack(spacing: metrics.u(8)) {
                    checkMark.frame(width: metrics.u(96), height: metrics.u(80))
                    VStack(spacing: 0) {
                        CanvasText(LineMatchCopy.doneTraditionalChinese, size: 44, weight: 900, color: textColor)
                        CanvasText(LineMatchCopy.doneEnglish, size: 22, weight: 700, color: subColor)
                    }
                }
            }
        }
        .contentShape(shape)
        .onAppear { startPulse(pulse) }
        .onChange(of: pulse) { startPulse($0) }
    }

    private var textColor: Color { on ? LM.ink : LM.offInk }
    private var subColor: Color { on ? LM.doneText : LM.offInk }

    private var checkMark: some View {
        ZStack {
            CheckShape().stroke(on ? LM.ink : LM.offMark,
                                style: StrokeStyle(lineWidth: metrics.u(26), lineCap: .round, lineJoin: .round))
            CheckShape().stroke(on ? Color.white : Color(hex: 0xF6F3F8),
                                style: StrokeStyle(lineWidth: metrics.u(12), lineCap: .round, lineJoin: .round))
        }
    }

    private func startPulse(_ on: Bool) {
        if on {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { pulsing = true }
        } else {
            pulsing = false
        }
    }
}

/// Tick from the mockup (M32 82 L58 108 L104 54 inside a 96 × 80 box, inset for the stroke).
private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.40, y: rect.minY + rect.height * 0.84))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.16))
        return path
    }
}

/// Yellow arrow from the status line to 完成 (mockup 05f).
private struct ArrowToDone: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 230
            var g = context
            g.scaleBy(x: s, y: s)
            var shaft = Path()
            shaft.move(to: CGPoint(x: 8, y: 24))
            shaft.addLine(to: CGPoint(x: 190, y: 24))
            g.stroke(shaft, with: .color(LM.ink), style: StrokeStyle(lineWidth: 26, lineCap: .round))
            g.stroke(shaft, with: .color(LM.route), style: StrokeStyle(lineWidth: 14, lineCap: .round))
            var head = Path()
            head.move(to: CGPoint(x: 178, y: 0))
            head.addLine(to: CGPoint(x: 222, y: 24))
            head.addLine(to: CGPoint(x: 178, y: 48))
            head.closeSubpath()
            g.fill(head, with: .color(LM.route))
            g.stroke(head, with: .color(LM.ink), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
