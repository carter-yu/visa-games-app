import SwiftUI
import VisaCore

/// 一架一架數 / Tap & Count (v0.28.0, ADR 0017; mockups 01–08).
///
/// ★ 點一點: tap every vehicle; each lights up, bounces and gets its count badge while Stampy says
///   「一、二、三」. When all are tapped the pale numeral lights up 「四架！」. Nothing to get wrong.
/// ★★ 數完畫: the same count, then the vehicles park in a strip and the numeral becomes a trace
///   board (the 畫形狀 engine: forward-only paint car; corners and the cusp of 3 wait for the pen).
/// ★★★ 揀啱數: a yard with more vehicles than needed. Tap = pick, tap again = unpick, 擦晒 clears,
///   OK judges once (the existing wrong-answer policy: half the fuel + a 10 s Think Pause, shown in
///   the tray). Right = the numeral trace, as in ★★.
///
/// All rules live in `VisaCore.TapCountBoard` (and `ShapeTraceBoard` for the trace). This view sends
/// taps / pen events and draws. Nothing is drawn in the parent corner (x ≥ 1060, y ≥ 560).
/// No text input, no menus, no window changes.
struct TapCountBoardView: View {
    let board: TapCountBoard
    let settings: TapCountSettings
    let ticketStars: Int
    let pendingMinutes: Int
    let thinkPauseRemaining: Int
    /// Fuel before the latest halving (Think Pause card 「15 → 7 分鐘」).
    let fuelBefore: Int
    /// Think Pause, finished, or a reveal playing: no input.
    let locked: Bool
    let notice: SpokenPrompt?
    /// Model clock (seconds since the reference date).
    let now: Double
    let onSpeak: () -> Void
    /// A tap on the vehicle in this bay (each vehicle has its own tap target; see TapCountVehicleLayout).
    let onTap: (Int) -> Void
    let onSubmit: () -> Void
    let onErase: () -> Void
    let onTraceCommit: (ShapeTraceBoard) -> Void
    let onTraceWrongStart: () -> Void
    let onTraceReverse: () -> Void
    let onTraceHint: (String) -> Void
    /// v0.30.0 guidance (mockups guidance/01–03): the model's bubble line (cue / hop / stall).
    var guideBubble: TapCountGuideBubble? = nil
    /// The first touch during the demo: it ends the demo (input is never locked; that touch does not paint).
    var onGuideSkip: () -> Void = {}
    /// A help episode began on the board (key, kind).
    var onGuideHelp: (String, String) -> Void = { _, _ in }
    /// The car is coming up to cue `index` (a crossing or a turn).
    var onGuideCue: (Int) -> Void = { _ in }

    var body: some View {
        CanvasStage {
            LineMatchBackdrop()
        } content: {
            TapCountStageContent(view: self)
        }
    }
}

// MARK: - Stage content

private struct TapCountStageContent: View {
    let view: TapCountBoardView
    @Environment(\.canvasMetrics) private var metrics
    /// Trace pen state (a local copy per pen event; handed to the model at milestones and pen-up).
    @State private var traceLocal: ShapeTraceBoard?
    @State private var penTip: CGPoint?
    @State private var dragSeen = false
    @GestureState private var gestureActive = false
    /// The vehicle that hops 6u right after its tap.
    @State private var bounceBay: Int?
    /// Guidance: the touch that ended the demo (the car wiggles, nothing is painted until the next touch).
    @State private var swallowTouch = false
    @State private var wiggleAt: Double?
    @State private var cueShownAt: [Int: Double] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.tapCountShowsHitTargets) private var showsHitTargets
    private var board: TapCountBoard { view.board }

    /// Off in the app; the offline render check turns it on to see the real hit frames.
    @ViewBuilder private var debugHitTint: some View {
        if showsHitTargets {
            Rectangle().fill(Color.red.opacity(0.22))
                .overlay(Rectangle().strokeBorder(Color.red, lineWidth: metrics.u(3)))
                .allowsHitTesting(false)
        }
    }
    private var question: TapCountQuestion { board.question }
    /// Words in the card's language (English cards share every rule and drawing with 一架一架數).
    private var lines: TapCountLines { TapCountLines(question.language) }
    private var english: Bool { question.language == .english }
    private var tracingShown: Bool {
        question.tracesNumeral && (board.stage == .tracing || board.stage == .done) && board.trace != nil
    }
    private var paused: Bool { view.thinkPauseRemaining > 0 }

    private var trace: ShapeTraceBoard? {
        guard let model = board.trace else { return nil }
        if let traceLocal, traceLocal.isMonotonicSuccessor(of: model) { return traceLocal }
        return model
    }

    /// The workspace overlays (pen) sit at stage y = 118, so their gesture locations start there.
    private static let workspaceTop: CGFloat = 118

    /// A location in a workspace overlay (origin at stage y = 118) → stage units.
    private func stagePoint(_ point: CGPoint) -> CGPoint {
        let scale = max(metrics.scale, 0.0001)
        return CGPoint(x: point.x / scale, y: point.y / scale + Self.workspaceTop)
    }

    private func lm(_ point: CGPoint) -> LineMatchPoint { LineMatchPoint(x: Double(point.x), y: Double(point.y)) }

    // MARK: Taps (count / pick)

    /// One tap target per vehicle, laid on the same stage rect the drawing uses (v0.28.1). The
    /// handler is attached to the target itself, so there is no coordinate maths to get wrong.
    private func bayHitTarget(_ bay: Int, rect r: LineMatchRect) -> some View {
        Color.clear
            .frame(width: metrics.u(CGFloat(r.width)), height: metrics.u(CGFloat(r.height)))
            .overlay { debugHitTint }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard !view.locked, board.stage == .tapping else { return }
                        // A tap, not a swipe (40u of travel at most).
                        let travel = hypot(value.translation.width, value.translation.height) / max(metrics.scale, 0.0001)
                        guard travel <= 40 else { return }
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) { bounceBay = bay }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                            withAnimation(.easeOut(duration: 0.15)) { if bounceBay == bay { bounceBay = nil } }
                        }
                        view.onTap(bay)
                    }
            )
            .canvasPlaced(x: CGFloat(r.x), y: CGFloat(r.y))
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(question.prompt.mainText) \(bay + 1)")
    }

    // MARK: Pen (numeral trace; the ShapeTraceStageContent pattern)

    private var penGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($gestureActive) { _, state, _ in state = true }
            .onChanged { value in penChanged(value) }
            .onEnded { _ in penEnded() }
    }

    private func penChanged(_ value: DragGesture.Value) {
        guard !view.locked, var next = trace, !next.isComplete else { return }
        let clock = Date().timeIntervalSinceReferenceDate
        let tip = stagePoint(value.location)
        penTip = tip
        if !dragSeen {
            dragSeen = true
            // Guidance demo on screen: this touch ends it (never a lock, never a miss) and paints nothing.
            if board.guideDemoPending(now: clock) {
                view.onGuideSkip()
                wiggleAt = clock
                if TapCountGuideData.touchEndsDemoWithoutPaint {
                    swallowTouch = true
                    return
                }
            }
            switch next.penDown(at: lm(stagePoint(value.startLocation)), now: clock) {
            case .wrongStart:
                traceLocal = next
                view.onTraceCommit(next)
                view.onTraceWrongStart()
                return
            case .reverse:
                traceLocal = next
                view.onTraceCommit(next)
                view.onTraceReverse()
                return
            case .grabbed, .notNearVehicle, .ignored:
                break
            }
        }
        if swallowTouch { return }
        let move = next.penMove(to: lm(tip), now: clock)
        traceLocal = next
        switch move {
        case .drove, .waiting, .away:
            break
        default:
            view.onTraceCommit(next)
        }
    }

    private func penEnded() {
        if swallowTouch { resetPen(); return }
        guard dragSeen, var next = trace else { resetPen(); return }
        next.penUp()
        traceLocal = next
        resetPen()
        view.onTraceCommit(next)
    }

    private func cancelPen() {
        if swallowTouch { resetPen(); return }
        guard dragSeen, var next = trace else { return }
        next.cancelStroke()
        traceLocal = next
        resetPen()
        view.onTraceCommit(next)
    }

    private func resetPen() {
        dragSeen = false
        swallowTouch = false
        penTip = nil
    }

    // MARK: Guidance (v0.30.0)

    private var guideRun: TapCountGuideRun? { board.stage == .tracing || board.stage == .done ? board.guide : nil }
    private var numeralGuide: NumeralGuide? { guideRun == nil ? nil : TapCountGuideCache.guide(board.target) }
    private var demoOn: Bool { board.stage == .tracing && board.guideDemoPending(now: view.now) }

    /// The help the board shows now (stall ring + ghost, ghost to the end, or the 20 s re-demo).
    private var guideHelp: TapCountGuideHelp {
        guard let run = guideRun, let numeralGuide, let trace, board.stage == .tracing, !view.locked,
              !board.guideDemoPending(now: view.now) else { return .none }
        return TapCountGuideCoach.help(plan: run.plan, guide: numeralGuide, trace: trace, readyAt: run.readyAt, now: view.now)
    }

    private var activeCue: NumeralGuide.Cue? {
        guard let run = guideRun, run.plan.cueSigns || run.plan.cueWords, let numeralGuide, let trace,
              board.stage == .tracing, !view.locked, !board.guideDemoPending(now: view.now) else { return nil }
        return TapCountGuideCoach.activeCue(guide: numeralGuide, trace: trace)
    }

    private var guideDraw: TapCountGuideDraw? {
        guard let run = guideRun, let numeralGuide, let trace, board.stage == .tracing else { return nil }
        let demo = board.guideDemoPending(now: view.now)
        let cue = demo || !run.plan.cueSigns ? nil : activeCue
        let clock = Date().timeIntervalSinceReferenceDate
        return TapCountGuideDraw(
            plan: run.plan, numeral: numeralGuide, demo: demo,
            headlights: demo ? [] : TapCountGuideCoach.headlights(plan: run.plan, guide: numeralGuide, trace: trace),
            cue: cue, popAt: cue.flatMap { cueShownAt[$0.index] }, stopWord: lines.guideStopWord,
            reduceMotion: reduceMotion, now: clock)
    }

    /// Whether the guidance layer needs frames (demo, a hop, a help ghost, a wiggle). Off = no timer.
    private var guideAnimating: Bool {
        guard !reduceMotion, let run = guideRun, let trace, board.stage == .tracing else { return false }
        let clock = Date().timeIntervalSinceReferenceDate
        if run.demoPending(now: clock) { return true }
        if let at = wiggleAt, clock - at < 0.6 { return true }
        if run.plan.hops, trace.strokeIndex > 0, trace.progress < 0.5, let at = trace.lastProgressAt,
           clock - at < TapCountGuideData.timing.hopSeconds + TapCountGuideData.styles.litGlowSeconds + 0.2 { return true }
        switch guideHelp {
        case .stall, .ghostToEnd: return true
        default: return false
        }
    }

    @ViewBuilder private var guideMotionLayer: some View {
        if let run = guideRun, let numeralGuide, let trace, board.stage == .tracing {
            let state = TapCountGuideMotionState(
                numeral: numeralGuide, timeline: TapCountGuideCache.timeline(board.target), run: run, trace: trace,
                help: guideHelp, wiggleAt: wiggleAt, reduceMotion: reduceMotion,
                board: NumeralGlyphs.traceBoard(board.target), stopWord: lines.guideStopWord)
            let scale = metrics.scale
            let animating = guideAnimating
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating)) { context in
                let now = animating ? context.date.timeIntervalSinceReferenceDate : Date().timeIntervalSinceReferenceDate
                Canvas { canvas, _ in
                    var g = canvas
                    g.scaleBy(x: scale, y: scale)
                    TapCountDrawing.guideMotion(state, now: now, in: &g)
                }
            }
            .frame(width: metrics.u(1280), height: metrics.u(720))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The voice bubble left of the board (mockups 01–03): the demo's rhyme line (the line before in
    /// grey), or the model's cue / hop / stall line.
    private var guideBubbleContent: (previous: String?, main: String, sub: String?, demo: Bool)? {
        guard board.stage == .tracing, let run = guideRun else { return nil }
        if let t = run.demoTime(now: view.now) {
            guard t >= 0, let timeline = TapCountGuideCache.timeline(board.target) else { return nil }
            let beats = lines.guideBeats(board.target)
            if let i = timeline.beat(at: t), beats.indices.contains(i) {
                return (i > 0 ? beats[i - 1].mainText : nil, beats[i].mainText, beats[i].subText, true)
            }
            if t >= timeline.mergeStart, let merge = lines.guideMerge(board.target) {
                return (beats.last?.mainText, merge.mainText, merge.subText, true)
            }
            return nil
        }
        if let bubble = view.guideBubble, view.now < bubble.until {
            let text = bubble.prompt.mainText
            for mark in ["\u{FF0C}", ", ", "\u{FF1A}", ": "] {  // full-width comma / colon, ", ", ": "
                if let r = text.range(of: mark), r.upperBound < text.endIndex {
                    let head = String(text[..<r.upperBound]).trimmingCharacters(in: .whitespaces)
                    let tail = String(text[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    return (head, tail, bubble.prompt.subText, false)
                }
            }
            return (nil, text, bubble.prompt.subText, false)
        }
        return nil
    }

    /// CanvasText is fixedSize: pick a size that fits `width` (CJK ≈ 1 em, Latin ≈ 0.62 em).
    private func fitSize(_ text: String, base: CGFloat, width: CGFloat, latinEm: Double = 0.62) -> CGFloat {
        let ems = text.unicodeScalars.reduce(0.0) { $0 + ($1.value >= 0x2E80 ? 1.0 : latinEm) }
        return max(11, min(base, width / CGFloat(max(ems, 1))))
    }

    /// English bubble lines are long ("Then straight back home!"): wrap them onto two lines at the space nearest
    /// the middle instead of shrinking one line to unreadable. CJK lines stay on one line.
    private func bubbleLines(_ text: String, base: CGFloat, width: CGFloat) -> (lines: [String], size: CGFloat) {
        let one = fitSize(text, base: base, width: width)
        let cjk = text.unicodeScalars.contains { $0.value >= 0x2E80 }
        guard !cjk, one < 22 else { return ([text], one) }
        let chars = Array(text)
        let spaces = chars.indices.filter { chars[$0] == " " }
        guard let cut = spaces.min(by: { abs($0 - chars.count / 2) < abs($1 - chars.count / 2) }) else { return ([text], one) }
        let first = String(chars[..<cut]), second = String(chars[(cut + 1)...])
        let size = min(fitSize(first, base: base - 2, width: width), fitSize(second, base: base - 2, width: width))
        return size > one ? ([first, second], size) : ([text], one)
    }

    @ViewBuilder private var guideVoiceBubble: some View {
        if let content = guideBubbleContent {
            let boardRect = NumeralGlyphs.traceBoard(board.target)
            let right = CGFloat(boardRect.x) - 10
            let left = max(16, right - 266)
            let top: CGFloat = content.demo ? 250 : 284
            let scale = metrics.scale
            ZStack(alignment: .topLeading) {
                Canvas { canvas, _ in
                    var g = canvas
                    g.scaleBy(x: scale, y: scale)
                    let rect = CGRect(x: 0, y: 0, width: 246, height: 104)
                    var tail = Path()
                    tail.move(to: CGPoint(x: 244, y: 40))
                    tail.addLine(to: CGPoint(x: 266, y: 54))
                    tail.addLine(to: CGPoint(x: 244, y: 66))
                    tail.closeSubpath()
                    g.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 5), cornerRadius: 26), with: .color(LM.ink.opacity(0.14)))
                    g.fill(Path(roundedRect: rect, cornerRadius: 26), with: .color(.white))
                    g.fill(tail, with: .color(.white))
                    g.stroke(Path(roundedRect: rect, cornerRadius: 26), with: .color(LM.ink), lineWidth: 4)
                    var tailEdge = Path()
                    tailEdge.move(to: CGPoint(x: 245, y: 40))
                    tailEdge.addLine(to: CGPoint(x: 266, y: 54))
                    tailEdge.addLine(to: CGPoint(x: 245, y: 66))
                    g.stroke(tailEdge, with: .color(LM.ink), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
                    TapCountDrawing.place(TapCountArt.speaker, at: LineMatchPoint(x: 30, y: 52), scale: 0.6, in: &g)
                }
                .frame(width: metrics.u(270), height: metrics.u(112))
                VStack(alignment: .leading, spacing: metrics.u(1)) {
                    if let previous = content.previous {
                        CanvasText(previous, size: fitSize(previous, base: content.demo ? 18 : 21, width: 180),
                                   weight: content.demo ? 800 : 900, color: content.demo ? Color(hex: 0xA39AA8) : LM.ink)
                    }
                    let main = bubbleLines(content.main, base: 28, width: 180)
                    ForEach(Array(main.lines.enumerated()), id: \.offset) { _, line in
                        CanvasText(line, size: main.size, weight: 900, color: LM.ink)
                    }
                    if let sub = content.sub, !sub.isEmpty {
                        CanvasText(sub, size: fitSize(sub, base: 14, width: 180), weight: 700, color: Color(hex: 0x6B6170))
                    }
                }
                .frame(width: metrics.u(186), height: metrics.u(104), alignment: .leading)
                .canvasPlaced(x: 56, y: 0)
            }
            .canvasPlaced(x: left, y: top)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .transition(.opacity)
        }
    }

    private var traceHintOn: Bool {
        guard let trace, !view.locked, board.stage == .tracing else { return false }
        return trace.showsHint(now: view.now)
    }

    private var traceHintKey: String? {
        guard traceHintOn, let trace else { return nil }
        return "\(trace.shapeIndex).\(trace.strokeIndex)"
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            sceneLayer
            guideMotionLayer
            if board.stage == .tapping {
                ForEach(TapCountVehicleLayout.hitTargets(question), id: \.bay) { target in
                    bayHitTarget(target.bay, rect: target.rect)
                        .allowsHitTesting(!view.locked)
                }
            }
            if board.stage == .tracing {
                Color.clear
                    .frame(width: metrics.u(1280), height: metrics.u(422))
                    .contentShape(Rectangle())
                    .gesture(penGesture)
                    .allowsHitTesting(!view.locked)
                    .canvasPlaced(x: 0, y: Self.workspaceTop)
                    .accessibilityLabel(lines.tracePrompt(board.target).mainText)
            }
            bubbles
            guideVoiceBubble
            countedChip
            tray
            pickButtons
            header
            if paused, question.isPick {
                pauseDim
                ThinkPauseOverlay(remainingSeconds: view.thinkPauseRemaining, placement: .tray,
                                  minutesBefore: view.fuelBefore, minutesAfter: view.pendingMinutes,
                                  trayLines: lines)
                    .transition(.opacity)
            }
            recountBubble
        }
        .animation(.easeInOut(duration: 0.35), value: board.stage)
        .animation(.easeInOut(duration: 0.2), value: paused)
        .onChange(of: board.question) { _ in
            traceLocal = nil
            resetPen()
        }
        .onChange(of: view.locked) { isLocked in
            if isLocked { cancelPen() }
        }
        .onChange(of: gestureActive) { active in
            guard !active else { return }
            DispatchQueue.main.async {
                if dragSeen { cancelPen() }
            }
        }
        .onChange(of: traceHintKey) { key in
            if let key { view.onTraceHint(key) }
        }
        .onChange(of: guideHelp.key) { key in
            if let key { view.onGuideHelp(key, guideHelp.kind) }
        }
        .onChange(of: activeCue?.index) { index in
            guard let index else { return }
            if cueShownAt[index] == nil { cueShownAt[index] = Date().timeIntervalSinceReferenceDate }
            view.onGuideCue(index)
        }
        .onChange(of: board.question) { _ in
            cueShownAt = [:]
            wiggleAt = nil
        }
    }

    // MARK: The drawn scene (one Canvas; pure function of the board)

    private var sceneLayer: some View {
        let snapshot = TapCountDrawing.Snapshot(
            board: board, trace: trace, tracing: tracingShown, settings: view.settings,
            lifted: bounceBay, paused: paused, now: view.now,
            nudge: !question.isPick && board.stage == .tapping && board.idleNudges > 0
                && view.now - (board.lastActivityAt ?? 0) < 3,
            tip: dragSeen && !swallowTouch ? penTip : nil, hint: traceHintOn, guide: guideDraw)
        let scale = metrics.scale
        return Canvas { context, _ in
            var g = context
            g.scaleBy(x: scale, y: scale)
            TapCountDrawing.draw(snapshot, in: &g)
        }
        .frame(width: metrics.u(1280), height: metrics.u(720))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(question.prompt.mainText)
    }

    // MARK: Bubbles (count word beside the latest badge; the reveal cue 「四、four」)

    @ViewBuilder
    private var bubbles: some View {
        ZStack(alignment: .topLeading) {
            if let (rect, word) = countBubble {
                speechBubble(text: word, english: nil, rect: rect, size: question.layout == .row ? 30 : 27)
            }
            if !question.isPick, board.stage == .counted || (board.stage == .done && !question.tracesNumeral) {
                let reveal = lines.revealBubble(board.target, addEnglish: view.settings.english)
                speechBubble(text: reveal.0, english: reveal.1,
                             rect: LineMatchRect(x: 806, y: 434,
                                                 width: english ? 196 : (reveal.1 != nil ? 214 : 150), height: 62),
                             size: 30)
            }
        }
        .allowsHitTesting(false)
    }

    /// The latest counted / picked vehicle: 「二」 beside its badge for about 1.5 s.
    private var countBubble: (LineMatchRect, String)? {
        guard board.stage == .tapping || board.stage == .counted, !paused, board.missFeedback == nil,
              let bay = board.lastTapBay, let k = board.badge(forBay: bay), let at = board.lastTapAt,
              view.now - at < 1.6 else { return nil }
        let badge = TapCountDrawing.badgeCentre(question, bay: bay)
        // English words are longer than 一二三: the bubble widens, same place and height.
        let rect = question.layout == .row
            ? LineMatchRect(x: badge.x + 46, y: badge.y - 28, width: english ? 150 : 104, height: 54)
            : LineMatchRect(x: badge.x + 32, y: badge.y - 25, width: english ? 136 : 96, height: 50)
        // Keep it on the stage: flip to the left of the badge near the right edge.
        if rect.maxX > 1268 {
            return (LineMatchRect(x: 2 * badge.x - rect.maxX, y: rect.y, width: rect.width, height: rect.height),
                    lines.countWord(k))
        }
        return (rect, lines.countWord(k))
    }

    private func speechBubble(text: String, english: String?, rect: LineMatchRect, size: CGFloat) -> some View {
        let radius = metrics.u(CGFloat(min(28, rect.height / 2)))
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            shape.fill(LM.ink.opacity(0.16)).offset(y: metrics.u(6))
            shape.fill(Color.white)
            shape.strokeBorder(LM.ink, lineWidth: metrics.u(5))
            HStack(spacing: metrics.u(6)) {
                VectorArtView(artwork: TapCountArt.speaker)
                    .frame(width: metrics.u(30), height: metrics.u(28))
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    CanvasText(text, size: size, weight: 900, color: LM.ink)
                    if let english {
                        CanvasText(english, size: size, weight: 700, color: Color(hex: 0x4C8FE0))
                    }
                }
            }
        }
        .frame(width: metrics.u(CGFloat(rect.width)), height: metrics.u(CGFloat(rect.height)))
        .canvasPlaced(x: CGFloat(rect.x), y: CGFloat(rect.y))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(english.map { "\(text)\($0)" } ?? text)
    }

    /// Mockup 06: 「一、二、三、四。四架。」 (picks past the target orange) and 「要三架喎！」.
    @ViewBuilder
    private var recountBubble: some View {
        if question.isPick, board.stage == .tapping, board.missFeedback != nil, let k = board.attempts.last, k > 0 {
            let orange = Color(hex: 0xD9701E)
            let need = lines.need(board.target)
            let subline = lines.recountSubline(k, target: board.target)
            let shape = RoundedRectangle(cornerRadius: metrics.u(28), style: .continuous)
            ZStack(alignment: .topLeading) {
                shape.fill(LM.ink.opacity(0.2)).offset(y: metrics.u(6))
                shape.fill(Color.white)
                shape.strokeBorder(LM.ink, lineWidth: metrics.u(5))
                VectorArtView(artwork: TapCountArt.speaker)
                    .frame(width: metrics.u(30), height: metrics.u(28))
                    .canvasPlaced(x: 20, y: 18)
                HStack(spacing: 0) {
                    ForEach(1...k, id: \.self) { index in
                        CanvasText(lines.recountWord(index, last: index == k), size: recountSize(k), weight: 900,
                                   color: index > board.target ? orange : LM.ink)
                    }
                    // English: 「That's four.」 opens line 2 instead (digits on line 1, words in the voice).
                    if !english { CanvasText(lines.recountTotal(k), size: 25, weight: 900, color: LM.ink) }
                }
                .frame(width: metrics.u(384), alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .canvasPlaced(x: 62, y: 14)
                HStack(alignment: .lastTextBaseline, spacing: metrics.u(12)) {
                    if english { CanvasText(lines.recountTotal(k), size: 22, weight: 900, color: LM.ink) }
                    CanvasText(need.mainText, size: 22, weight: 900, color: orange)
                    if !subline.isEmpty {
                        CanvasText(subline, size: 14, weight: 700, color: LM.soft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .frame(width: metrics.u(380), alignment: .leading)
                .canvasPlaced(x: 62, y: 52)
            }
            .frame(width: metrics.u(460), height: metrics.u(96), alignment: .topLeading)
            .canvasPlaced(x: 772, y: 400)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(lines.recount(k).mainText) \(need.mainText)")
        }
    }

    /// CanvasText is fixedSize, so the English digit row picks a size that fits its 384u instead of
    /// scaling (「1, 2, 3, 4, 5, 6, 7, 8, 9, 10」 is the longest).
    private func recountSize(_ k: Int) -> CGFloat {
        guard english else { return 25 }
        let chars = CGFloat((1...max(k, 1)).map { lines.recountWord($0, last: $0 == k).count }.reduce(0, +))
        return min(25, 384 / (0.6 * max(chars, 1)))
    }

    // MARK: 「三架！ 3 counted」 chip above the strip (mockup 03)

    @ViewBuilder
    private var countedChip: some View {
        if tracingShown, TapCountDrawing.stripLeftEdge(board) > 366 {
            let chip = lines.countedChip(board.target, pick: question.isPick)
            let green = Color(hex: 0x2F7A3A)
            HStack(spacing: metrics.u(8)) {
                CheckShape()
                    .stroke(green, style: StrokeStyle(lineWidth: metrics.u(5), lineCap: .round, lineJoin: .round))
                    .frame(width: metrics.u(22), height: metrics.u(18))
                CanvasText(chip.top, size: 19, weight: 900, color: green)
                if !chip.bottom.isEmpty { CanvasText(chip.bottom, size: 12, weight: 700, color: green) }
            }
            .frame(width: metrics.u(208), height: metrics.u(44))
            .background(Capsule().fill(Color(hex: 0xDFF3DF)))
            .overlay(Capsule().strokeBorder(Color(hex: 0x5DBB63), lineWidth: metrics.u(4)))
            .canvasPlaced(x: 146, y: 160)
            .allowsHitTesting(false)
        }
    }

    // MARK: Tray (y 540–720; the parent corner x ≥ 1060, y ≥ 560 stays empty)

    @ViewBuilder
    private var tray: some View {
        ZStack(alignment: .topLeading) {
            if tracingShown {
                let centre: CGFloat = question.isPick ? 648 : 640
                stepChips(first: question.isPick ? lines.stepPick(board.target) : lines.stepTap,
                          firstDone: true, traceDone: board.stage == .done, centreX: centre, watching: demoOn)
                trayStatus(traceStatus, centreX: centre, top: 634)
                if board.stage == .done {
                    stampLegend(x: 826, width: 214)
                } else if guideRun != nil {
                    guideLegend
                } else {
                    traceLegend
                }
            } else if question.isPick {
                if !paused {
                    stepChips(first: lines.stepPick(board.target), firstDone: false, traceDone: false,
                              centreX: 512)
                    if let notice = view.notice {
                        trayStatus((notice.mainText, notice.subText ?? ""), centreX: 512, top: 634)
                    }
                }
            } else {
                progressDots
                trayStatus(countStatus, centreX: 640, top: 628)
                if board.stage == .tapping { countLegend } else { stampLegend(x: 790, width: 250) }
            }
        }
        .allowsHitTesting(false)
    }

    private var countStatus: (String, String) {
        if board.stage != .tapping { return lines.allTappedTray }
        if let notice = view.notice { return (notice.mainText, notice.subText ?? "") }
        return lines.remaining(board.remaining)
    }

    private var traceStatus: (String, String) {
        if board.stage == .done {
            return lines.strokesDoneTray(board.target, scene: question.scene, pick: question.isPick)
        }
        if guideRun != nil {
            if demoOn { return lines.guideTrayDemo }
            if case .stall = guideHelp { return lines.guideTrayStall }
        }
        if traceHintOn { return lines.offPathStatus }
        if let notice = view.notice { return (notice.mainText, notice.subText ?? "") }
        if let trace, let strokes = trace.shapes.first?.strokes.count, strokes > 1, trace.strokeIndex == strokes - 1 {
            if guideRun != nil, let last = lines.guideLastStroke(board.target) { return last }
            if board.target == 5 { return lines.lastStrokeHat }
        }
        return guideRun != nil ? lines.guideTrayTrace : lines.traceStatus
    }

    private func trayStatus(_ lines: (String, String), centreX: CGFloat, top: CGFloat) -> some View {
        VStack(spacing: metrics.u(1)) {
            CanvasText(lines.0, size: 26, weight: 900, color: LM.ink)
            if !lines.1.isEmpty { CanvasText(lines.1, size: 18, weight: 700, color: LM.soft) }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: metrics.u(400))
        .canvasPlaced(x: centreX - 200, y: top)
        .accessibilityElement(children: .combine)
    }

    /// One dot per vehicle (mockup 01): yellow with a tick once counted.
    private var progressDots: some View {
        let n = question.count
        let spacing: CGFloat = n > 6 ? 36 : 44
        let width = CGFloat(max(n - 1, 0)) * spacing
        return ZStack(alignment: .topLeading) {
            ForEach(0..<n, id: \.self) { index in
                let on = index < board.selectedCount
                ZStack {
                    Circle().fill(on ? Color(hex: 0xFFC93C) : Color.white)
                    Circle().strokeBorder(LM.ink, lineWidth: metrics.u(5))
                    if on {
                        CheckShape()
                            .stroke(LM.ink, style: StrokeStyle(lineWidth: metrics.u(4), lineCap: .round, lineJoin: .round))
                            .padding(metrics.u(9))
                    }
                }
                .frame(width: metrics.u(32), height: metrics.u(32))
                .canvasPlaced(x: 640 - width / 2 + CGFloat(index) * spacing - 16, y: 584)
            }
        }
    }

    private func stepChips(first: String, firstDone: Bool, traceDone: Bool, centreX: CGFloat,
                           watching: Bool = false) -> some View {
        let width: CGFloat = question.isPick ? 146 : 132
        let gap: CGFloat = question.isPick ? 32 : 38
        let left = centreX - width - gap / 2
        let colour = LineMatchRoadPalette.color(TapCountDrawing.traceColorIndex(question.scene))
        return ZStack(alignment: .topLeading) {
            chip(first, done: firstDone, accent: Color(hex: colour.full), trace: false)
                .frame(width: metrics.u(width), height: metrics.u(44))
                .canvasPlaced(x: left, y: 578)
            ChevronRight()
                .stroke(LM.ink, style: StrokeStyle(lineWidth: metrics.u(5), lineCap: .round, lineJoin: .round))
                .frame(width: metrics.u(12), height: metrics.u(20))
                .canvasPlaced(x: left + width + gap / 2 - 6, y: 590)
            chip(lines.stepTrace(board.target), done: traceDone, accent: Color(hex: colour.full), trace: true,
                 watching: watching)
                .frame(width: metrics.u(width), height: metrics.u(44))
                .canvasPlaced(x: left + width + gap, y: 578)
        }
    }

    private func chip(_ text: String, done: Bool, accent: Color, trace: Bool, watching: Bool = false) -> some View {
        let green = Color(hex: 0x2F7A3A)
        return HStack(spacing: metrics.u(8)) {
            if watching {
                // Guidance demo: 「睇住」 eye on the trace chip (mockup guidance/01).
                VectorArtView(artwork: TapCountArt.guideEye).frame(width: metrics.u(26), height: metrics.u(22))
            } else if done {
                CheckShape()
                    .stroke(green, style: StrokeStyle(lineWidth: metrics.u(5), lineCap: .round, lineJoin: .round))
                    .frame(width: metrics.u(22), height: metrics.u(18))
            } else if trace && tracingShown {
                ZStack {
                    Circle().fill(Color.white)
                    Circle().trim(from: 0, to: CGFloat(traceFraction))
                        .stroke(accent, style: StrokeStyle(lineWidth: metrics.u(10)))
                        .rotationEffect(.degrees(-90))
                        .padding(metrics.u(5))
                    Circle().strokeBorder(LM.ink, lineWidth: metrics.u(3))
                }
                .frame(width: metrics.u(22), height: metrics.u(22))
            }
            CanvasText(text, size: 19, weight: 900, color: done ? green : LM.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(done ? Color(hex: 0xDFF3DF) : LM.card))
        .overlay(Capsule().strokeBorder(done ? Color(hex: 0x5DBB63) : (trace && tracingShown ? accent : LM.ink),
                                        lineWidth: metrics.u(4)))
    }

    private var traceFraction: Double {
        guard let trace, let shape = trace.shapes.first else { return 0 }
        if trace.isComplete { return 1 }
        let total = shape.strokes.reduce(0) { $0 + $1.length }
        guard total > 0 else { return 0 }
        var done = 0.0
        for (k, stroke) in shape.strokes.enumerated() {
            if k < trace.doneStrokes(shape: 0) {
                done += stroke.length
            } else if k == trace.strokeIndex {
                done += trace.progress
            }
        }
        return min(1, done / total)
    }

    private func legendBox<Content: View>(x: CGFloat, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.leading, metrics.u(16))
            .frame(width: metrics.u(width), height: metrics.u(124), alignment: .leading)
            .background(RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous).fill(LM.card))
            .overlay(RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous)
                .strokeBorder(LM.ink, lineWidth: metrics.u(4)))
            .canvasPlaced(x: x, y: 568)
    }

    private func legendRow<Icon: View>(_ pair: (String, String), @ViewBuilder icon: () -> Icon) -> some View {
        legendRow(pair.0, pair.1, icon: icon)
    }

    private func legendRow<Icon: View>(_ zh: String, _ en: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: metrics.u(10)) {
            icon().frame(width: metrics.u(48), height: metrics.u(44))
            VStack(alignment: .leading, spacing: 0) {
                // Sized to the 214u legend box (CanvasText is fixedSize).
                CanvasText(zh, size: fitSize(zh, base: 20, width: 136), weight: 900, color: LM.ink)
                if !en.isEmpty { CanvasText(en, size: fitSize(en, base: 12.5, width: 136), weight: 700, color: LM.soft) }
            }
        }
    }

    /// Mockup 01: 點咗 (lit + number) / 未點.
    private var countLegend: some View {
        legendBox(x: 790, width: 250) {
            VStack(alignment: .leading, spacing: metrics.u(8)) {
                legendRow(lines.legendTapped) {
                    ZStack {
                        RoundedRectangle(cornerRadius: metrics.u(10)).fill(Color(hex: 0xFFF1A8))
                        RoundedRectangle(cornerRadius: metrics.u(10)).strokeBorder(Color(hex: 0xFFC93C), lineWidth: metrics.u(5))
                        numberDisc(1, radius: 13)
                    }
                    .frame(width: metrics.u(44), height: metrics.u(40))
                }
                legendRow(lines.legendNotYet) {
                    ZStack {
                        RoundedRectangle(cornerRadius: metrics.u(10)).fill(Color(hex: 0xEDE7F0))
                        RoundedRectangle(cornerRadius: metrics.u(10)).strokeBorder(Color(hex: 0xB9B0BE), lineWidth: metrics.u(4))
                    }
                    .frame(width: metrics.u(44), height: metrics.u(40))
                }
            }
        }
    }

    /// Mockups 03 / 07: 開始 / 停 (one stroke) or 第幾筆 / 畫好一筆 (two strokes).
    private var traceLegend: some View {
        let multi = (trace?.shapes.first?.strokes.count ?? 1) > 1
        return legendBox(x: 826, width: 214) {
            VStack(alignment: .leading, spacing: metrics.u(8)) {
                if multi {
                    legendRow(lines.legendStrokeNumber) {
                        HStack(spacing: metrics.u(4)) { numberDisc(1, radius: 13); numberDisc(2, radius: 13) }
                    }
                    legendRow(lines.legendStrokeDone) {
                        VectorArtView(artwork: ShapeTraceArt.tickSmall).frame(width: metrics.u(36), height: metrics.u(36))
                    }
                } else {
                    legendRow(lines.legendStart) {
                        VectorArtView(artwork: ShapeTraceArt.go).frame(width: metrics.u(46), height: metrics.u(46))
                    }
                    legendRow(lines.legendStop) {
                        VectorArtView(artwork: ShapeTraceArt.end).frame(width: metrics.u(46), height: metrics.u(46))
                    }
                }
            }
        }
    }

    /// Guidance legends (mockups guidance/01–03): demo car + route; headlights + crossing sign; stroke
    /// order + hop. 少啲 (no headlights, no hop) keeps the v0.28 legend.
    @ViewBuilder private var guideLegend: some View {
        let plan = guideRun?.plan
        let multi = (trace?.shapes.first?.strokes.count ?? 1) > 1
        if demoOn {
            legendBox(x: 826, width: 214) {
                VStack(alignment: .leading, spacing: metrics.u(8)) {
                    legendRow(lines.guideLegendDemoCar) { legendIcon { g in
                        TapCountDrawing.place(TapCountArt.guideGhostCar, at: LineMatchPoint(x: 24, y: 22), scale: 0.36, in: &g)
                    } }
                    legendRow(lines.guideLegendRoute) { legendIcon { g in
                        TapCountDrawing.legendRoute(in: &g)
                    } }
                }
            }
        } else if multi, plan?.hops == true {
            legendBox(x: 826, width: 214) {
                VStack(alignment: .leading, spacing: metrics.u(8)) {
                    legendRow(lines.guideLegendStrokeOrder) {
                        HStack(spacing: metrics.u(4)) { numberDisc(1, radius: 13); numberDisc(2, radius: 13) }
                    }
                    legendRow(lines.guideLegendHop) { legendIcon { g in TapCountDrawing.legendHop(in: &g) } }
                }
            }
        } else if plan?.headlights == true {
            let first = numeralGuide?.cues.first
            legendBox(x: 826, width: 214) {
                VStack(alignment: .leading, spacing: metrics.u(8)) {
                    legendRow(lines.guideLegendHeadlights) { legendIcon { g in TapCountDrawing.legendHeadlights(in: &g) } }
                    if plan?.cueSigns == true, let first {
                        if first.sign == .ahead {
                            legendRow(lines.guideLegendAhead) { legendIcon { g in
                                TapCountDrawing.place(TapCountArt.guideAhead, at: LineMatchPoint(x: 24, y: 22), scale: 0.72, in: &g)
                            } }
                        } else {
                            let word = lines.guideStopWord
                            legendRow(lines.guideLegendStop) { legendIcon { g in
                                TapCountDrawing.stopSign(at: LineMatchPoint(x: 24, y: 22), scale: 0.58, word: word, in: &g)
                            } }
                        }
                    } else {
                        legendRow(lines.legendStop) {
                            VectorArtView(artwork: ShapeTraceArt.end).frame(width: metrics.u(46), height: metrics.u(46))
                        }
                    }
                }
            }
        } else {
            traceLegend
        }
    }

    /// A 48×44 legend icon drawn in stage units.
    private func legendIcon(_ draw: @escaping (inout GraphicsContext) -> Void) -> some View {
        let scale = metrics.scale
        return Canvas { canvas, _ in
            var g = canvas
            g.scaleBy(x: scale, y: scale)
            draw(&g)
        }
        .frame(width: metrics.u(48), height: metrics.u(44))
    }

    private func numberDisc(_ n: Int, radius: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color.white)
            Circle().strokeBorder(LM.ink, lineWidth: metrics.u(4))
            CanvasText("\(n)", size: radius * 1.3, weight: 800, color: LM.ink)
        }
        .frame(width: metrics.u(radius * 2), height: metrics.u(radius * 2))
    }

    /// Mockups 02 / 04 / 08: 跟住：蓋印！ + the visa line (★: 冇得錯，唔會扣油).
    private func stampLegend(x: CGFloat, width: CGFloat) -> some View {
        let green = Color(hex: 0x2F7A3A)
        let minutes = max(0, view.pendingMinutes)
        return legendBox(x: x, width: width) {
            HStack(spacing: metrics.u(8)) {
                VectorArtView(artwork: CanvasArt.stampy).frame(width: metrics.u(58), height: metrics.u(58))
                VStack(alignment: .leading, spacing: metrics.u(1)) {
                    let next = lines.stampNextTray
                    let visa = question.base == .tapCountAll ? lines.noMissTray
                                                             : lines.visaTray(minutes, firstTry: board.misses == 0)
                    // English lines run longer than 跟住：蓋印！; one size down keeps them inside the box.
                    CanvasText(next.0, size: english ? 16.5 : 20, weight: 900, color: LM.ink)
                    if !next.1.isEmpty { CanvasText(next.1, size: 12, weight: 700, color: LM.soft) }
                    CanvasText(visa.0, size: english ? 12.5 : 13, weight: 900, color: green)
                    if !visa.1.isEmpty { CanvasText(visa.1, size: 11, weight: 700, color: LM.soft) }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
    }

    // MARK: ★★★ 擦晒 and OK (mockup 05: eraser at 24,548; OK at 800,548; clear of the parent corner)

    private func buttonArt(_ artwork: CanvasArtwork) -> some View {
        let anchor = TapCountArt.anchor(artwork)
        return VectorArtView(artwork: artwork)
            .frame(width: metrics.u(CGFloat(artwork.width)), height: metrics.u(CGFloat(artwork.height)))
            .offset(x: metrics.u(-CGFloat(anchor.x)), y: metrics.u(-CGFloat(anchor.y)))
    }

    @ViewBuilder
    private var pickButtons: some View {
        if question.isPick, board.stage == .tapping {
            if board.eraserVisible {
                let on = board.eraserEnabled && !view.locked
                Button(action: view.onErase) {
                    ZStack(alignment: .topLeading) {
                        buttonArt(TapCountArt.eraserButton)
                        CanvasText(lines.eraser.0, size: 34, weight: 900, color: LM.ink)
                            .frame(width: metrics.u(200))
                            .canvasPlaced(x: 0, y: lines.eraser.1.isEmpty ? 104 : 92)
                        if !lines.eraser.1.isEmpty {
                            CanvasText(lines.eraser.1, size: 18, weight: 700, color: LM.soft)
                                .frame(width: metrics.u(200))
                                .canvasPlaced(x: 0, y: 132)
                        }
                    }
                    .frame(width: metrics.u(200), height: metrics.u(160), alignment: .topLeading)
                    .overlay { debugHitTint }
                    .contentShape(Rectangle())
                    .saturation(on ? 1 : 0)
                    .opacity(on ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!on)
                .canvasPlaced(x: 24, y: 548)
                .accessibilityLabel([lines.eraser.0, lines.eraser.1].filter { !$0.isEmpty }.joined(separator: " / "))
            }
            let okOn = board.okEnabled && !view.locked
            if okOn {
                RoundedRectangle(cornerRadius: metrics.u(40), style: .continuous)
                    .fill(LM.glow.opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: metrics.u(40), style: .continuous)
                        .strokeBorder(Color(hex: 0xFFC93C), lineWidth: metrics.u(7)))
                    .frame(width: metrics.u(258), height: metrics.u(170))
                    .canvasPlaced(x: 791, y: 539)
                    .allowsHitTesting(false)
            }
            Button(action: view.onSubmit) {
                ZStack(alignment: .topLeading) {
                    buttonArt(TapCountArt.okButton)
                    CanvasText(lines.ok.0, size: 62, weight: 800, color: LM.ink)
                        .frame(width: metrics.u(140))
                        .canvasPlaced(x: 102, y: 30)
                    CanvasText(lines.ok.1, size: 20, weight: 900, color: LM.doneText)
                        .frame(width: metrics.u(140))
                        .canvasPlaced(x: 102, y: 112)
                }
                .frame(width: metrics.u(240), height: metrics.u(160), alignment: .topLeading)
                .overlay { debugHitTint }
                .contentShape(Rectangle())
                .saturation(board.okEnabled ? 1 : 0)
                .opacity(board.okEnabled ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            // A grey OK still answers with 「未揀車喎！」 (no penalty); only a lock blocks it.
            .disabled(view.locked)
            .canvasPlaced(x: 800, y: 548)
            .accessibilityLabel("\(lines.ok.0) / \(lines.ok.1)")
        }
    }

    // MARK: Think Pause dim (mockup 06: everything except the yard and the sign)

    private var pauseDim: some View {
        let scale = metrics.scale
        return Canvas { context, _ in
            var g = context
            g.scaleBy(x: scale, y: scale)
            var p = Path()
            p.addRect(CGRect(x: 0, y: 0, width: 1280, height: 720))
            p.addRoundedRect(in: CGRect(x: 62, y: 120, width: 1156, height: 270), cornerSize: CGSize(width: 22, height: 22))
            p.addRoundedRect(in: CGRect(x: 534, y: 393, width: 212, height: 147), cornerSize: CGSize(width: 26, height: 26))
            g.fill(p, with: .color(LM.ink.opacity(0.38)), style: FillStyle(eoFill: true))
        }
        .frame(width: metrics.u(1280), height: metrics.u(720))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Header (Stampy + prompt = hear it again; card pill; visa ticket)

    private var headerPrompt: SpokenPrompt {
        switch board.stage {
        case .tapping:
            return question.isPick ? lines.pickPrompt(board.target) : question.prompt
        case .counted, .tracing:
            if question.tracesNumeral, board.stage == .tracing, let run = guideRun {
                // Guidance (mockups guidance/01–02): 「八架！睇住架車先！」 during the demo, 「到你喇！」 after one.
                if demoOn { return lines.guideWatchFirst(board.target) }
                if run.demosPlayed > 0 { return lines.guideYourTurn(board.target) }
            }
            return question.tracesNumeral ? lines.countedTracePrompt(board.target, pick: question.isPick)
                                          : lines.donePrompt(board.target, scene: question.scene)
        case .done:
            return question.tracesNumeral ? lines.traceDonePrompt(board.target)
                                          : lines.donePrompt(board.target, scene: question.scene)
        }
    }

    private var header: some View {
        let frame = LineMatchLayout.header
        let stars = min(max(view.ticketStars, 1), 3)
        let prompt = headerPrompt
        let shape = RoundedRectangle(cornerRadius: metrics.u(30), style: .continuous)
        return ZStack(alignment: .topLeading) {
            ZStack {
                shape.fill(LM.ink.opacity(0.18)).offset(y: metrics.u(6))
                shape.fill(LM.header)
                shape.strokeBorder(LM.ink, lineWidth: metrics.u(6))
            }
            .frame(width: metrics.u(CGFloat(frame.width)), height: metrics.u(CGFloat(frame.height)))
            .canvasPlaced(x: CGFloat(frame.x), y: CGFloat(frame.y))
            .allowsHitTesting(false)

            Button(action: view.onSpeak) {
                HStack(alignment: .center, spacing: metrics.u(14)) {
                    VectorArtView(artwork: CanvasArt.stampy)
                        .frame(width: metrics.u(82), height: metrics.u(82))
                    VStack(alignment: .leading, spacing: metrics.u(2)) {
                        // Fit before the card pill (CanvasText is fixedSize, so minimumScaleFactor cannot shrink it):
                        // "Your turn! Follow the arrows and draw 8!" ran under the pill at 36.
                        CanvasText(prompt.mainText, size: fitSize(prompt.mainText, base: 36, width: 930, latinEm: 0.7),
                                   weight: 900, color: LM.ink)
                        if let sub = prompt.subText {
                            CanvasText(sub, size: 20, weight: 700, color: LM.headerSub)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .frame(width: metrics.u(800), height: metrics.u(92), alignment: .leading)
                .overlay { debugHitTint }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .canvasPlaced(x: 40, y: 18)
            .accessibilityLabel(lines.hearAgain(prompt))

            VStack(spacing: 0) {
                CanvasText(lines.familyTitle, size: english ? 19 : 22, weight: 900, color: LM.ink)
                // CanvasText is fixedSize, so pick a size that fits the 150u pill instead of scaling.
                let subtitle = lines.chipSubtitle(question.kind)
                CanvasText(subtitle, size: subtitle.count > 17 ? 12.5 : 15, weight: 700, color: LM.headerSub)
            }
            .frame(width: metrics.u(150), height: metrics.u(68))
            .background(RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous).fill(LM.pill))
            .overlay(RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous)
                .strokeBorder(LM.ink, lineWidth: metrics.u(4)))
            .canvasPlaced(x: 850, y: 30)
            .allowsHitTesting(false)

            VisaTicketBadge(stars: stars, minutes: max(0, view.pendingMinutes),
                            minutesWord: lines.minutesWord, visaWord: lines.visaWord)
                .frame(width: metrics.u(220), height: metrics.u(74))
                .canvasPlaced(x: 1026, y: 27)
                .allowsHitTesting(false)
                .accessibilityLabel(lines.minutesLeft(view.pendingMinutes))
        }
    }
}

/// The small arrow between the step chips.
private struct ChevronRight: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

// MARK: - Drawing (pure functions of a snapshot; stage units)

enum TapCountDrawing {
    static let ink = Color(hex: 0x2B2630)
    static let yellow = Color(hex: 0xFFC93C)
    static let orange = Color(hex: 0xF5963C)
    static let guideGrey = Color(hex: 0x8C8494)

    struct Snapshot {
        let board: TapCountBoard
        let trace: ShapeTraceBoard?
        let tracing: Bool
        let settings: TapCountSettings
        let lifted: Int?
        let paused: Bool
        let now: Double
        let nudge: Bool
        let tip: CGPoint?
        let hint: Bool
        /// v0.30.0 guidance (nil = the v0.28 board).
        var guide: TapCountGuideDraw? = nil
    }

    static func draw(_ s: Snapshot, in g: inout GraphicsContext) {
        backdrop(s, in: &g)
        vehicles(s, in: &g)
        badges(s, in: &g)
        if s.tracing, let trace = s.trace {
            traceBoard(trace, target: s.board.target, scaffold: s.settings.traceScaffold, tip: s.tip, hint: s.hint,
                       guide: s.guide, in: &g)
        } else if s.board.question.isPick {
            worksSign(s, in: &g)
        } else {
            numeralTile(s, in: &g)
        }
    }

    /// Road colour of the numeral per scene (tram teal as in mockup 02, fire engine blue as in 03).
    static func traceColorIndex(_ scene: TapCountScene) -> Int {
        switch scene {
        case .tramDepot: return 0
        case .fireStation: return 4
        case .site: return 2
        case .airport: return 1
        case .busTerminus: return 3
        }
    }

    // MARK: Placement helpers

    /// Draws `artwork` with its def origin on `point` (its radial glows first), scaled and turned:
    /// the mockups' `translate(x y) scale(s)`.
    static func place(_ artwork: CanvasArtwork, at point: LineMatchPoint, scale: Double = 1, angle: Double = 0,
                      opacity: Double = 1, in g: inout GraphicsContext) {
        let anchor = TapCountArt.anchor(artwork)
        var layer = g
        layer.opacity = g.opacity * opacity
        layer.translateBy(x: point.x, y: point.y)
        if angle != 0 { layer.rotate(by: .radians(angle)) }
        layer.scaleBy(x: scale, y: scale)
        layer.translateBy(x: -anchor.x, y: -anchor.y)
        for glow in TapCountArt.glows(artwork) {
            radial(cx: glow.cx, cy: glow.cy, rx: glow.rx, ry: glow.ry, opacity: glow.opacity,
                   stops: glow.stops.map { ($0.offset, $0.color, $0.opacity) }, in: &layer)
        }
        VectorArtRenderer.draw(artwork, in: &layer, size: CGSize(width: artwork.width, height: artwork.height),
                               contentMode: .fit)
    }

    static func radial(cx: Double, cy: Double, rx: Double, ry: Double, opacity: Double,
                       stops: [(Double, UInt32, Double)], in g: inout GraphicsContext) {
        guard rx > 0, ry > 0, !stops.isEmpty else { return }
        var layer = g
        layer.opacity = g.opacity * opacity
        layer.translateBy(x: cx, y: cy)
        layer.scaleBy(x: 1, y: ry / rx)
        let gradient = Gradient(stops: stops.map { Gradient.Stop(color: Color(hex: $0.1, opacity: $0.2), location: $0.0) })
        layer.fill(Path(ellipseIn: CGRect(x: -rx, y: -rx, width: 2 * rx, height: 2 * rx)),
                   with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: rx))
    }

    /// Mockup `board-glow`.
    static func boardGlow(cx: Double, cy: Double, rx: Double, ry: Double, in g: inout GraphicsContext) {
        radial(cx: cx, cy: cy, rx: rx, ry: ry, opacity: 1,
               stops: [(0, 0xFFF3A6, 0.95), (0.6, 0xFFE066, 0.45), (1, 0xFFE066, 0)], in: &g)
    }

    static func rect(_ r: LineMatchRect) -> CGRect { CGRect(x: r.x, y: r.y, width: r.width, height: r.height) }

    // MARK: Art per model

    static func art(_ model: TapCountModel) -> CanvasArtwork { TapCountVehicleLayout.art(model) }

    /// The lit layer, and where its origin sits from the vehicle origin in vehicle units
    /// (nil = drawn on the vehicle origin at the vehicle scale). Beacons sit on each roof cap (mockup 05).
    static func lit(_ model: TapCountModel) -> (art: CanvasArtwork, offset: LineMatchPoint?) {
        switch model {
        case .tram: return (TapCountArt.lampOn, LineMatchPoint(x: 80, y: -52))
        case .fireEngine: return (TapCountArt.fireEngineLit, nil)
        case .plane: return (TapCountArt.planeLit, nil)
        case .bus: return (TapCountArt.busLit, nil)
        case .digger: return (TapCountArt.beaconOn, LineMatchPoint(x: -38, y: -127))
        case .mixer: return (TapCountArt.beaconOn, LineMatchPoint(x: 64, y: -99))
        case .dumper: return (TapCountArt.beaconOn, LineMatchPoint(x: 68, y: -101))
        case .dozer: return (TapCountArt.beaconOn, LineMatchPoint(x: -37, y: -123))
        case .roller: return (TapCountArt.beaconOn, LineMatchPoint(x: -30, y: -127))
        case .craneTruck: return (TapCountArt.beaconOn, LineMatchPoint(x: 76, y: -101))
        }
    }

    /// The mockup scales (row 0.92; cells 0.7); shared with the tap targets.
    static func scale(_ model: TapCountModel, layout: TapCountLayout) -> Double {
        TapCountVehicleLayout.scale(model, layout: layout)
    }

    /// The strip (mockups 03 / 08: 0.42–0.44), fitted to the spacing.
    static func stripScale(_ model: TapCountModel, count: Int) -> Double {
        let spacing = TapCountLayoutGeometry.stripSpacing(count: count)
        return min(model == .bus ? 0.44 : 0.42, (spacing - 6) / max(1, art(model).width))
    }

    static func parked(_ board: TapCountBoard) -> [TapCountVehicle] {
        board.order.compactMap { board.question.vehicle(atBay: $0) }
    }

    static func stripLeftEdge(_ board: TapCountBoard) -> Double {
        let cars = parked(board)
        guard let first = cars.first else { return 1280 }
        let anchor = TapCountArt.anchor(art(first.model))
        return TapCountLayoutGeometry.stripX(0, count: cars.count) - anchor.x * stripScale(first.model, count: cars.count)
    }

    static func badgeCentre(_ q: TapCountQuestion, bay: Int) -> LineMatchPoint {
        switch q.layout {
        case .row:
            return LineMatchPoint(x: TapCountLayoutGeometry.rowCentreX(bay, count: q.bayCount) + 32, y: 174)
        case .tenFrame, .yard:
            let cell = TapCountLayoutGeometry.cell(bay)
            return LineMatchPoint(x: cell.maxX - 23, y: cell.y + 20)
        }
    }

    // MARK: Backdrop (Opus scene kit when present; a plain fallback otherwise)

    static func backdrop(_ s: Snapshot, in g: inout GraphicsContext) {
        let q = s.board.question
        let key = s.tracing ? "strip" : (q.layout == .row ? "row" : "yard")
        if let art = TapCountArt.named("\(key)_\(q.scene.rawValue)") {
            VectorArtRenderer.draw(art, in: &g, size: CGSize(width: 1280, height: 720), contentMode: .fit)
        } else {
            fallbackBackdrop(key, in: &g)
        }
        if !s.tracing, q.layout == .row, q.count > 1 {
            let post = TapCountArt.named("baypost_\(q.scene.rawValue)")
            for index in 0..<(q.count - 1) {
                let x = (TapCountLayoutGeometry.rowCentreX(index, count: q.count)
                         + TapCountLayoutGeometry.rowCentreX(index + 1, count: q.count)) / 2
                if let post {
                    place(post, at: LineMatchPoint(x: x, y: TapCountLayoutGeometry.rowGround), in: &g)
                } else {
                    let r = CGRect(x: x - 7, y: 196, width: 14, height: 128)
                    g.fill(Path(roundedRect: r, cornerRadius: 6), with: .color(.white))
                    g.stroke(Path(roundedRect: r, cornerRadius: 6), with: .color(ink), lineWidth: 3.5)
                }
            }
        }
        if !s.tracing, q.layout != .row {
            let occupied = Set(q.occupiedBays)
            let marker = TapCountArt.named("empty_\(q.scene.rawValue)")
            for bay in 0..<10 where !occupied.contains(bay) {
                let cell = TapCountLayoutGeometry.cell(bay)
                let point = LineMatchPoint(x: cell.midX, y: TapCountLayoutGeometry.cellGrounds[min(bay / 5, 1)] - 6)
                if let marker { place(marker, at: point, in: &g) } else { cone(at: point, in: &g) }
            }
        }
    }

    /// Mockup 05 cone: an empty bay has nothing to tap.
    static func cone(at p: LineMatchPoint, in g: inout GraphicsContext) {
        var body = Path()
        body.move(to: CGPoint(x: p.x - 16, y: p.y))
        body.addLine(to: CGPoint(x: p.x - 4, y: p.y - 48))
        body.addLine(to: CGPoint(x: p.x + 4, y: p.y - 48))
        body.addLine(to: CGPoint(x: p.x + 16, y: p.y))
        body.closeSubpath()
        g.fill(body, with: .color(orange))
        g.stroke(body, with: .color(ink), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
        var band = Path()
        band.move(to: CGPoint(x: p.x - 10, y: p.y - 22))
        band.addLine(to: CGPoint(x: p.x + 10, y: p.y - 22))
        g.stroke(band, with: .color(.white), lineWidth: 6)
        var base = Path()
        base.addRoundedRect(in: CGRect(x: p.x - 22, y: p.y - 4, width: 44, height: 8), cornerSize: CGSize(width: 4, height: 4))
        g.fill(base, with: .color(orange))
        g.stroke(base, with: .color(ink), lineWidth: 3.5)
    }

    private static func fallbackBackdrop(_ key: String, in g: inout GraphicsContext) {
        switch key {
        case "row":
            g.fill(Path(CGRect(x: 0, y: 326, width: 1280, height: 214)), with: .color(Color(hex: 0xEEE3C9)))
            g.fill(Path(CGRect(x: 0, y: 323, width: 1280, height: 6)), with: .color(ink))
        case "yard":
            g.fill(Path(CGRect(x: 0, y: 392, width: 1280, height: 148)), with: .color(Color(hex: 0xE9D3A6)))
            let panel = rect(TapCountLayoutGeometry.yardPanel)
            g.fill(Path(roundedRect: panel, cornerRadius: 22), with: .color(Color(hex: 0xD9BE8C)))
            g.stroke(Path(roundedRect: panel, cornerRadius: 22), with: .color(ink), lineWidth: 5)
            for bay in 0..<10 {
                let cell = Path(roundedRect: rect(TapCountLayoutGeometry.cell(bay)), cornerRadius: 14)
                g.fill(cell, with: .color(Color(hex: 0xE7CF9F)))
                g.stroke(cell, with: .color(.white), style: StrokeStyle(lineWidth: 4, dash: [14, 10]))
            }
        default:
            g.fill(Path(CGRect(x: 0, y: 214, width: 1280, height: 10)), with: .color(Color(hex: 0xB9B0BE)))
            g.fill(Path(CGRect(x: 0, y: 212, width: 1280, height: 4)), with: .color(ink))
        }
    }

    // MARK: Vehicles (glow + lit layer once counted / picked)

    static func vehicles(_ s: Snapshot, in g: inout GraphicsContext) {
        let board = s.board
        let q = board.question
        if s.tracing {
            // The counted / picked set parks in the strip in tap order (mockups 03 / 07 / 08).
            let cars = parked(board)
            for (index, vehicle) in cars.enumerated() {
                let point = LineMatchPoint(x: TapCountLayoutGeometry.stripX(index, count: cars.count),
                                           y: TapCountLayoutGeometry.stripGround)
                drawVehicle(vehicle, at: point, scale: stripScale(vehicle.model, count: cars.count), lit: true, in: &g)
            }
            return
        }
        for vehicle in q.vehicles where board.isTapped(vehicle.bay) {
            if q.layout == .row {
                place(TapCountArt.glow, at: LineMatchPoint(x: q.ground(vehicle).x, y: TapCountLayoutGeometry.rowGround), in: &g)
            } else {
                let cell = TapCountLayoutGeometry.cell(vehicle.bay)
                place(TapCountArt.bayGlow, at: LineMatchPoint(x: cell.midX, y: cell.maxY - 2), in: &g)
            }
        }
        for vehicle in q.vehicles {
            var point = q.ground(vehicle)
            if s.lifted == vehicle.bay { point.y -= 6 }
            drawVehicle(vehicle, at: point, scale: scale(vehicle.model, layout: q.layout),
                        lit: board.isTapped(vehicle.bay), in: &g)
        }
        // ★ / ★★ reveal: the underbrace from the whole row to the numeral (mockup 02).
        if board.stage != .tapping, !q.isPick, q.layout == .row, q.count > 1 {
            let left = TapCountLayoutGeometry.rowCentreX(0, count: q.count) - 90
            let right = TapCountLayoutGeometry.rowCentreX(q.count - 1, count: q.count) + 90
            var brace = Path()
            brace.move(to: CGPoint(x: left, y: 362))
            brace.addQuadCurve(to: CGPoint(x: left + 16, y: 378), control: CGPoint(x: left, y: 378))
            brace.addLine(to: CGPoint(x: 616, y: 378))
            brace.addQuadCurve(to: CGPoint(x: 640, y: 394), control: CGPoint(x: 634, y: 378))
            brace.addQuadCurve(to: CGPoint(x: 664, y: 378), control: CGPoint(x: 646, y: 378))
            brace.addLine(to: CGPoint(x: right - 16, y: 378))
            brace.addQuadCurve(to: CGPoint(x: right, y: 362), control: CGPoint(x: right, y: 378))
            g.stroke(brace, with: .color(ink), style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
            g.stroke(brace, with: .color(yellow), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        }
    }

    static func drawVehicle(_ vehicle: TapCountVehicle, at point: LineMatchPoint, scale k: Double, lit: Bool,
                            in g: inout GraphicsContext) {
        place(TapCountArt.tinted(art(vehicle.model), body: vehicle.color), at: point, scale: k, in: &g)
        guard lit else { return }
        let layer = Self.lit(vehicle.model)
        if let offset = layer.offset {
            // Lamps and beacons are drawn at their own size beside a 0.92 / 0.7 vehicle (mockups 01 / 05).
            let base = layer.art.name == TapCountArt.beaconOn.name ? 0.7 : 0.92
            place(layer.art, at: LineMatchPoint(x: point.x + offset.x * k, y: point.y + offset.y * k),
                  scale: min(1, k / base), in: &g)
        } else {
            place(layer.art, at: point, scale: k, in: &g)
        }
    }

    // MARK: Badges, rings, reveal marks, nudge

    static func badges(_ s: Snapshot, in g: inout GraphicsContext) {
        let board = s.board
        let q = board.question
        let mark = q.scene == .tramDepot ? TapCountArt.ding : TapCountArt.honk
        if s.tracing {
            let cars = board.order
            let small = cars.count > 5
            for index in cars.indices {
                let x = TapCountLayoutGeometry.stripX(index, count: cars.count)
                badge(index + 1, at: LineMatchPoint(x: small ? x : x - 31, y: small ? 134 : 150), radius: small ? 15 : 19,
                      fill: .white, ticks: false, in: &g)
                // Done: the horns / bells sound along the strip (mockup 04).
                if board.stage == .done, !small {
                    let fade = 0.5 + 0.5 * Double(index + 1) / Double(max(1, cars.count))
                    revealMark(mark, tram: q.scene == .tramDepot, word: TapCountLines(q.language).tapMark(tram: q.scene == .tramDepot), at: LineMatchPoint(x: x + 35, y: 146),
                               scale: index == cars.count - 1 ? 1 : 0.75, opacity: fade, in: &g)
                }
            }
            return
        }
        // ★★★ over-pick: a soft orange dashed ring round each pick past the target (never a cross).
        let extras = Set(board.extraBays)
        let showExtras = board.missFeedback == .over || s.paused
        if showExtras {
            for bay in extras {
                let r = rect(q.bayRect(bay)).insetBy(dx: -6, dy: -6)
                g.stroke(Path(roundedRect: r, cornerRadius: 20), with: .color(orange),
                         style: StrokeStyle(lineWidth: 7, dash: [16, 10]))
            }
        }
        // Demo count after the 2nd miss: the first `target` vehicles ringed in reading order.
        if board.showsDemoRings {
            for bay in board.demoBays {
                let r = rect(q.bayRect(bay)).insetBy(dx: -4, dy: -4)
                g.stroke(Path(roundedRect: r, cornerRadius: 18), with: .color(yellow),
                         style: StrokeStyle(lineWidth: 7, dash: [14, 9]))
            }
        }
        let row = q.layout == .row
        let latestBay = board.stage == .tapping && !s.paused ? board.order.last : nil
        let ticks = q.isPick && s.settings.badgeStyle == .ticks
        for (index, bay) in board.order.enumerated() {
            let centre = badgeCentre(q, bay: bay)
            let extra = showExtras && extras.contains(bay)
            if extra {
                badge(index + 1, at: centre, radius: row ? 28 : 24, fill: orange, ticks: ticks, textColour: .white, in: &g)
            } else if bay == latestBay {
                let c = LineMatchPoint(x: centre.x, y: centre.y - (row ? 6 : 0))
                badge(index + 1, at: c, radius: row ? 30 : 25, fill: yellow, ticks: ticks, in: &g)
                let ring = row ? 40.0 : 34.0
                g.stroke(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: 2 * ring, height: 2 * ring)),
                         with: .color(yellow.opacity(0.6)), lineWidth: 5)
            } else {
                badge(index + 1, at: centre, radius: row ? 26 : 22, fill: .white, ticks: ticks, in: &g)
            }
        }
        // ★ / ★★ reveal: the bells / horns ring along the set (mockup 02).
        if board.stage != .tapping, !q.isPick {
            for (index, bay) in board.order.enumerated() {
                let c = badgeCentre(q, bay: bay)
                let last = index == board.order.count - 1
                let fade = 0.55 + 0.45 * Double(index + 1) / Double(max(1, board.order.count))
                let at = row ? LineMatchPoint(x: c.x - 64, y: c.y - 34 - (last ? 4 : 0))
                             : LineMatchPoint(x: c.x - 56, y: c.y + 2)
                revealMark(mark, tram: q.scene == .tramDepot, word: TapCountLines(q.language).tapMark(tram: q.scene == .tramDepot), at: at,
                           scale: row ? (last ? 1 : 0.8) : 0.7, opacity: fade, in: &g)
            }
        }
        // ★ / ★★ idle nudge: the next vehicle gets a dashed ring.
        if s.nudge, let next = board.nextUntapped {
            let r = rect(q.bayRect(next)).insetBy(dx: 6, dy: 6)
            g.stroke(Path(roundedRect: r, cornerRadius: 24), with: .color(yellow),
                     style: StrokeStyle(lineWidth: 7, dash: [12, 9]))
        }
    }

    /// 叮 star (mockup 02) or 嘟 horn (mockup 04). The word is part of the mark (sound itself stays silent).
    static func revealMark(_ mark: CanvasArtwork, tram: Bool, word: String, at p: LineMatchPoint, scale k: Double, opacity: Double,
                           in g: inout GraphicsContext) {
        place(mark, at: p, scale: k, opacity: opacity, in: &g)
        var layer = g
        layer.opacity = g.opacity * opacity
        // One CJK glyph fits the star / horn; a longer English word gets a smaller size.
        let long = word.count > 1
        let centre = tram ? CGPoint(x: p.x, y: p.y + 1 * k) : CGPoint(x: p.x + (long ? 44 : 38) * k, y: p.y)
        let size: Double = tram ? (long ? 12 : 17) : (long ? 14 : 19)
        layer.draw(Text(word).font(CanvasFont.font(size: size * k, weight: 900)).foregroundColor(ink),
                   at: centre, anchor: .center)
    }

    static func badge(_ n: Int, at c: LineMatchPoint, radius r: Double, fill: Color, ticks: Bool,
                      textColour: Color = ink, in g: inout GraphicsContext) {
        let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        g.fill(disc, with: .color(fill))
        g.stroke(disc, with: .color(ink), lineWidth: r >= 24 ? 6 : 4)
        if ticks {
            var tick = Path()
            tick.move(to: CGPoint(x: c.x - r * 0.45, y: c.y + r * 0.02))
            tick.addLine(to: CGPoint(x: c.x - r * 0.1, y: c.y + r * 0.38))
            tick.addLine(to: CGPoint(x: c.x + r * 0.48, y: c.y - r * 0.35))
            g.stroke(tick, with: .color(textColour), style: StrokeStyle(lineWidth: r * 0.22, lineCap: .round, lineJoin: .round))
        } else {
            g.draw(Text("\(n)").font(CanvasFont.font(size: r * (n >= 10 ? 1.1 : 1.36), weight: 800)).foregroundColor(textColour),
                   at: CGPoint(x: c.x, y: c.y + r * 0.04), anchor: .center)
        }
    }

    // MARK: ★ / ★★ numeral tile (pale while counting; lights up when all are counted, mockups 01 / 02)

    static func numeralTile(_ s: Snapshot, in g: inout GraphicsContext) {
        let board = s.board
        let n = board.target
        let revealed = board.stage != .tapping
        let tile = rect(TapCountLayoutGeometry.tile)
        if revealed { boardGlow(cx: 640, cy: 463, rx: 230, ry: 96, in: &g) }
        g.fill(Path(roundedRect: tile.offsetBy(dx: 0, dy: 6), cornerRadius: 26), with: .color(ink.opacity(0.16)))
        g.fill(Path(roundedRect: tile, cornerRadius: 26), with: .color(LM.card))
        if revealed {
            g.stroke(Path(roundedRect: tile, cornerRadius: 26), with: .color(yellow), lineWidth: 8)
            g.stroke(Path(roundedRect: tile, cornerRadius: 26), with: .color(ink), lineWidth: 4)
        } else {
            g.stroke(Path(roundedRect: tile, cornerRadius: 26), with: .color(ink), lineWidth: 5)
        }
        let k = 0.38
        let paths = NumeralGlyphs.paths(n, offset: LineMatchPoint(x: 640 - NumeralGlyphs.box(n).width * k / 2, y: 403), scale: k)
        let colour = Color(hex: LineMatchRoadPalette.color(traceColorIndex(board.question.scene)).full)
        for path in paths {
            g.stroke(ShapeTraceDrawing.whole(path), with: .color(revealed ? ink : Color(hex: 0xCFC6D6)),
                     style: StrokeStyle(lineWidth: 76 * k, lineCap: .round, lineJoin: .round))
        }
        for path in paths {
            g.stroke(ShapeTraceDrawing.whole(path), with: .color(revealed ? colour : Color(hex: 0xF4F0F6)),
                     style: StrokeStyle(lineWidth: (revealed ? 58 : 62) * k, lineCap: .round, lineJoin: .round))
        }
        if revealed {
            let sparkles: [(Double, Double, Double)] = [(548, 420, 1), (736, 418, 1.2), (746, 506, 0.8), (536, 500, 0.9),
                                                        (488, 430, 0.6), (790, 462, 0.6)]
            for (x, y, size) in sparkles { place(TapCountArt.sparkle, at: LineMatchPoint(x: x, y: y), scale: size, in: &g) }
        }
    }

    // MARK: ★★★ works sign (mockup 05; orange dashed ring after a miss, mockup 06)

    static func worksSign(_ s: Snapshot, in g: inout GraphicsContext) {
        let board = s.board
        guard board.stage == .tapping || board.stage == .counted else { return }
        if s.paused || board.missFeedback != nil {
            g.stroke(Path(roundedRect: CGRect(x: 536, y: 388, width: 208, height: 150), cornerRadius: 28),
                     with: .color(orange), style: StrokeStyle(lineWidth: 7, dash: [16, 10]))
        }
        let sign = rect(TapCountLayoutGeometry.sign)
        g.fill(Path(roundedRect: sign.offsetBy(dx: 0, dy: 6), cornerRadius: 20), with: .color(ink.opacity(0.16)))
        g.fill(Path(roundedRect: sign, cornerRadius: 20), with: .color(yellow))
        g.stroke(Path(roundedRect: sign, cornerRadius: 20), with: .color(ink), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
        let inner = CGRect(x: 566, y: 412, width: 148, height: 100)
        g.fill(Path(roundedRect: inner, cornerRadius: 12), with: .color(LM.card))
        g.stroke(Path(roundedRect: inner, cornerRadius: 12), with: .color(ink), lineWidth: 4)
        // Hazard corners.
        var hazard = Path()
        hazard.move(to: CGPoint(x: 551, y: 416)); hazard.addLine(to: CGPoint(x: 566, y: 401))
        hazard.addLine(to: CGPoint(x: 578, y: 401)); hazard.addLine(to: CGPoint(x: 551, y: 428)); hazard.closeSubpath()
        hazard.move(to: CGPoint(x: 729, y: 508)); hazard.addLine(to: CGPoint(x: 714, y: 523))
        hazard.addLine(to: CGPoint(x: 702, y: 523)); hazard.addLine(to: CGPoint(x: 729, y: 496)); hazard.closeSubpath()
        g.fill(hazard, with: .color(ink))
        let k = 0.33
        let n = board.target
        let paths = NumeralGlyphs.paths(n, offset: LineMatchPoint(x: 640 - NumeralGlyphs.box(n).width * k / 2, y: 409.2), scale: k)
        for path in paths {
            g.stroke(ShapeTraceDrawing.whole(path), with: .color(ink),
                     style: StrokeStyle(lineWidth: 40 * k, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Trace board (mockups 03 / 07 / 08)

    static func traceBoard(_ trace: ShapeTraceBoard, target n: Int, scaffold: TapCountTraceScaffold, tip: CGPoint?,
                           hint: Bool, guide: TapCountGuideDraw? = nil, in g: inout GraphicsContext) {
        let board = rect(NumeralGlyphs.traceBoard(n))
        let k = NumeralGlyphs.tracePlacement(n).scale
        if trace.isComplete {
            boardGlow(cx: Double(board.midX), cy: Double(board.midY), rx: Double(board.width) * 0.72,
                      ry: Double(board.height) * 0.6, in: &g)
        }
        g.fill(Path(roundedRect: board.offsetBy(dx: 0, dy: 6), cornerRadius: 30), with: .color(ink.opacity(0.16)))
        g.fill(Path(roundedRect: board, cornerRadius: 30), with: .color(LM.card))
        g.stroke(Path(roundedRect: board, cornerRadius: 30), with: .color(trace.isComplete ? yellow : ink),
                 lineWidth: trace.isComplete ? 8 : 5)
        guard let shape = trace.shapes.first else { return }
        let palette = LineMatchRoadPalette.color(shape.colorIndex)
        let strokes = shape.strokes
        // Guidance: strokes not reached yet are faded, with no dots and no markers (mockup guidance/03).
        let faded: (Int) -> Bool = { index in
            guard let guide, guide.plan.fadesLaterStrokes, !trace.isComplete else { return false }
            return index > trace.strokeIndex
        }
        // Lane: 虛線路 (pale road + thick grey dots) or 淡框 + 箭嘴 (faint outline + chevrons).
        for (index, stroke) in strokes.enumerated() {
            let p = ShapeTraceDrawing.whole(stroke)
            var lane = g
            if faded(index) { lane.opacity = TapCountGuideData.styles.fadedStrokeOpacity }
            switch scaffold {
            case .dots:
                lane.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 76 * k, lineCap: .round, lineJoin: .round))
                lane.stroke(p, with: .color(Color(hex: palette.pale)), style: StrokeStyle(lineWidth: 64 * k, lineCap: .round, lineJoin: .round))
            case .outline:
                lane.stroke(p, with: .color(ink.opacity(0.3)), style: StrokeStyle(lineWidth: 76 * k, lineCap: .round, lineJoin: .round))
                lane.stroke(p, with: .color(LM.card), style: StrokeStyle(lineWidth: 66 * k, lineCap: .round, lineJoin: .round))
            }
        }
        for (index, stroke) in strokes.enumerated() where !faded(index) {
            switch scaffold {
            case .dots:
                g.stroke(ShapeTraceDrawing.whole(stroke), with: .color(guideGrey),
                         style: StrokeStyle(lineWidth: 16 * k, lineCap: .round, dash: [0.1, 30 * k]))
            case .outline:
                chevrons(stroke, in: &g)
            }
        }
        // Paint: finished strokes whole; the current stroke up to the paint car.
        let done = trace.doneStrokes(shape: 0)
        for index in strokes.indices {
            guard let path = trace.path(shape: 0, stroke: index) else { continue }
            let upTo: Double
            if trace.isComplete || index < done {
                upTo = path.length
            } else if index == trace.strokeIndex {
                upTo = trace.progress
            } else {
                continue
            }
            guard upTo > 0.5 else { continue }
            let p = ShapeTraceDrawing.segment(path, from: 0, to: upTo)
            g.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 35 * k, lineCap: .round, lineJoin: .round))
            g.stroke(p, with: .color(Color(hex: palette.full)), style: StrokeStyle(lineWidth: 24 * k, lineCap: .round, lineJoin: .round))
        }
        if trace.isComplete {
            let sparkles: [(Double, Double, Double)] = [(-0.4, -0.32, 1), (0.4, -0.34, 1.2), (0.42, 0.36, 0.8), (-0.42, 0.32, 0.9)]
            for (dx, dy, size) in sparkles {
                place(TapCountArt.sparkle, at: LineMatchPoint(x: Double(board.midX) + dx * Double(board.width),
                                                             y: Double(board.midY) + dy * Double(board.height)),
                      scale: size, in: &g)
            }
            return
        }
        // Guidance: headlights on the next dots, then the crossing / turn sign (mockup guidance/02).
        if let guide, let path = trace.currentPath {
            guideHeadlights(guide, path: path, progress: trace.progress, scale: k, in: &g)
            if let cue = guide.cue {
                guideCueSign(cue, guide: guide, in: &g)
            }
        }
        // Markers: ticks on finished strokes; go / end on the current one; stroke-order discs (two strokes).
        let multi = strokes.count > 1
        // A later stroke's go / end are drawn smaller (mockup guidance/03).
        let markerScale = guide != nil && trace.strokeIndex > 0 ? 0.64 : 1
        for index in strokes.indices {
            guard let path = trace.path(shape: 0, stroke: index) else { continue }
            if index < done {
                ShapeTraceDrawing.place(ShapeTraceArt.tickSmall, at: path.end, in: &g)
            } else if index == trace.strokeIndex {
                if trace.progress < 1 {
                    ShapeTraceDrawing.place(ShapeTraceArt.go, at: path.start, scale: markerScale, angle: path.angle(at: 0), in: &g)
                }
                if path.closed {
                    let d = trace.arrivalDistance(path)
                    ShapeTraceDrawing.place(ShapeTraceArt.endRing, at: path.point(at: d), scale: markerScale,
                                            angle: path.angle(at: d), in: &g)
                } else {
                    ShapeTraceDrawing.place(ShapeTraceArt.end, at: path.end, scale: markerScale,
                                            angle: path.angle(at: path.length), in: &g)
                }
            }
            if multi, index >= done {
                let start = path.start
                let c = LineMatchPoint(x: max(Double(board.minX) + 20, start.x - 34), y: max(Double(board.minY) + 20, start.y - 30))
                badge(index + 1, at: c, radius: 15, fill: index == trace.strokeIndex ? yellow : .white, ticks: false, in: &g)
            }
        }
        if let vehicle = trace.vehiclePoint {
            if hint {
                let ring = Path(ellipseIn: CGRect(x: vehicle.x - 52, y: vehicle.y - 52, width: 104, height: 104))
                g.fill(ring, with: .color(LM.glow.opacity(0.55)))
                g.stroke(ring, with: .color(Color(hex: 0xF5B82E)), style: StrokeStyle(lineWidth: 5, dash: [10, 9]))
            }
            // With guidance the car lives on the animated layer (hop, wiggle); the board draws it otherwise.
            if guide == nil {
                ShapeTraceDrawing.place(ShapeTraceArt.paintCar, at: vehicle, scale: 0.72, angle: trace.vehicleAngle, in: &g)
            }
        }
        if let guide, guide.demo {
            guideWatchBadge(board: board, in: &g)
        }
        if let tip {
            place(TapCountArt.spark, at: LineMatchPoint(x: Double(tip.x), y: Double(tip.y)), scale: 0.8, in: &g)
        }
    }

    /// 淡框 + 箭嘴: grey chevrons every 56u along the stroke (the `chev` mark, grey on the board).
    static func chevrons(_ path: TracePath, in g: inout GraphicsContext) {
        var d = 28.0
        while d < path.length - 20 {
            let p = path.point(at: d)
            var layer = g
            layer.translateBy(x: p.x, y: p.y)
            layer.rotate(by: .radians(path.angle(at: d)))
            var chev = Path()
            chev.move(to: CGPoint(x: -7, y: -11))
            chev.addLine(to: CGPoint(x: 6, y: 0))
            chev.addLine(to: CGPoint(x: -7, y: 11))
            layer.stroke(chev, with: .color(guideGrey), style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
            d += 56
        }
    }
}

/// Debug only: tint the per-vehicle tap targets (the offline render check). Always false in the app.
private struct TapCountShowsHitTargetsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var tapCountShowsHitTargets: Bool {
        get { self[TapCountShowsHitTargetsKey.self] }
        set { self[TapCountShowsHitTargetsKey.self] = newValue }
    }
}
