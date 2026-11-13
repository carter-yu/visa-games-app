import SwiftUI
import VisaCore

/// A pack glyph drawn from its approved centre lines in the 300 × 300 box (design: cards, plaque and samples use the
/// trace paths). Never a font, so a card cannot lose its glyph or show another form.
struct HanziGlyphView: View {
    let glyph: String
    let pack: HanziPack
    let ink: Color
    /// Glyph units (the mockups use 22).
    var lineWidth: CGFloat = 22
    var reveal: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / 300
            let x = (proxy.size.width - 300 * scale) / 2
            let y = (proxy.size.height - 300 * scale) / 2
            let paths = HanziGlyphs.paths(glyph, in: pack)
            ZStack {
                ForEach(paths.indices, id: \.self) { index in
                    Path { shape in
                        let points = paths[index].points
                        guard let first = points.first else { return }
                        shape.move(to: CGPoint(x: x + CGFloat(first.x) * scale, y: y + CGFloat(first.y) * scale))
                        for point in points.dropFirst() {
                            shape.addLine(to: CGPoint(x: x + CGFloat(point.x) * scale, y: y + CGFloat(point.y) * scale))
                        }
                    }
                    .trim(from: 0, to: reveal)
                    .stroke(ink, style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityLabel(glyph)
    }
}

/// 中文字 · 翻字卡 / Find & flip (Hanzi H2): design hanzi-tap v2 § ★ 搵字翻卡 and mockup 06. The letter board's roles
/// and places (`TapLetterBoardView`: header, the 2 × 5 grid, plaque, two collection slots, Think Pause, bubble) with
/// Hanzi providers: glyphs from the pack's centre lines, flips from `HanziCueArt`, copy from `HanziFindCopy`. Every
/// line is shown as text; the speaker mark only says whether the voice is on and is not a control.
struct TapHanziBoardView: View {
    let board: TapHanziBoard
    let pack: HanziPack
    let copy: HanziFindCopy
    let isWrite: Bool
    let audioOn: Bool
    let pendingMinutes: Int
    let fuelBefore: Int
    let thinkPauseRemaining: Int
    let bubble: String?
    let celebrating: Bool
    let strokeReveal: StrokeOrderReveal?
    let plaqueNudge: Bool
    let onTap: (Int) -> Void
    let onReprompt: () -> Void
    /// 粵拼 under each flipped card (H4, `AppModel.tapHanziJyutping`); nil while the parent has it OFF (D4).
    var jyutping: String? = nil

    var body: some View {
        CanvasStage { LineMatchBackdrop() } content: {
            TapHanziStageContent(board: board, pack: pack, copy: copy, isWrite: isWrite, audioOn: audioOn,
                                 pendingMinutes: pendingMinutes, fuelBefore: fuelBefore,
                                 thinkPauseRemaining: thinkPauseRemaining, bubble: bubble, celebrating: celebrating,
                                 strokeReveal: strokeReveal, plaqueNudge: plaqueNudge, onTap: onTap,
                                 onReprompt: onReprompt, jyutping: jyutping)
        }
    }
}

private struct TapHanziStageContent: View {
    let board: TapHanziBoard
    let pack: HanziPack
    let copy: HanziFindCopy
    let isWrite: Bool
    let audioOn: Bool
    let pendingMinutes: Int
    let fuelBefore: Int
    let thinkPauseRemaining: Int
    let bubble: String?
    let celebrating: Bool
    let strokeReveal: StrokeOrderReveal?
    let plaqueNudge: Bool
    let onTap: (Int) -> Void
    let onReprompt: () -> Void
    var jyutping: String?
    @Environment(\.canvasMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var paintProgress: CGFloat = 0

    /// Hanzi token sheet (D8): teal target glyph, cream unopened card.
    private static let teal = Color(hex: 0x2D9FA5)
    private static let cream = Color(hex: 0xFFF9ED)
    /// The plaque (tray 370, 10 → stage 416, 555; 120 × 142) and the square its glyph fills.
    private static let plaque = CGRect(x: 416, y: 555, width: 120, height: 142)
    private static let plaqueGlyphSide: CGFloat = 104

    var body: some View {
        ZStack(alignment: .topLeading) {
            header
            ForEach(0..<10, id: \.self) { index in
                card(index)
                    .frame(width: metrics.u(206), height: metrics.u(190))
                    .canvasPlaced(x: CGFloat(85 + (index % 5) * 222), y: CGFloat(136 + (index / 5) * 206))
            }
            tray
            strokeRevealLayer
            if let bubble {
                HStack(spacing: metrics.u(10)) {
                    speakerMark
                    CanvasText(bubble, size: 25, weight: 800)
                }
                .padding(metrics.u(12))
                .background(RoundedRectangle(cornerRadius: metrics.u(20)).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: metrics.u(20)).strokeBorder(Color.ink, lineWidth: metrics.u(3)))
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(bubble)
                .canvasPlaced(x: 745, y: 75)
            }
            if thinkPauseRemaining > 0 {
                // The shared Cantonese tray card (「停一停，想一想！」, fuel line, countdown); it absorbs taps, so a mash
                // neither skips the pause nor costs another penalty. The cards stay in view for comparison.
                ThinkPauseOverlay(remainingSeconds: thinkPauseRemaining, placement: .tray,
                                  minutesBefore: fuelBefore, minutesAfter: pendingMinutes)
            }
        }
        .onAppear(perform: onReprompt)
        .onChange(of: celebrating) { value in
            if value {
                if strokeReveal == nil {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) { paintProgress = 1 }
                }
            } else { paintProgress = 0 }
        }
    }

    private var header: some View {
        HStack(spacing: metrics.u(12)) {
            Button(action: onReprompt) {
                VectorArtView(artwork: HanziCueArt.robot)
                    .frame(width: metrics.u(96), height: metrics.u(80))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copy.prompt(board.target))
            if board.isComplete {
                CanvasText(copy.allFound, size: 48, weight: 900)
            } else {
                CanvasText(copy.headerParts.before, size: 48, weight: 900)
                HanziGlyphView(glyph: board.target, pack: pack, ink: .ink, lineWidth: 26)
                    .padding(metrics.u(5))
                    .frame(width: metrics.u(66), height: metrics.u(66))
                    .background(RoundedRectangle(cornerRadius: metrics.u(14)).fill(Self.cream))
                    .overlay(RoundedRectangle(cornerRadius: metrics.u(14)).strokeBorder(Color.ink, lineWidth: metrics.u(4)))
                CanvasText(copy.headerParts.after, size: 48, weight: 900)
            }
            Spacer()
            VStack {
                CanvasText("中文", size: 23, weight: 900)
                CanvasText(isWrite ? "Find & write" : "Find & flip", size: 14, weight: 800)
            }
            .padding(metrics.u(9))
            .background(RoundedRectangle(cornerRadius: metrics.u(14)).fill(Color(hex: DesignTokens.Palette.sunny)))
        }
        .opacity(thinkPauseRemaining > 0 ? 0.5 : 1)
        .frame(width: metrics.u(1100), height: metrics.u(92))
        .overlay(alignment: .bottomLeading) {
            if !board.isComplete {
                CanvasText(copy.subline, size: 18, weight: 700)
                    .offset(x: metrics.u(108), y: metrics.u(12))
            }
        }
        .canvasPlaced(x: 82, y: 17)
    }

    private func card(_ index: Int) -> some View {
        let face = board.face(index, pack: pack) ?? .glyph("")
        let flipped: HanziFlipArt? = { if case .flipped(let art) = face { return art } else { return nil } }()
        let wrong = board.knownWrong.contains(index)
        let hinted = board.assisted && board.hintCard == index
        return Button { if thinkPauseRemaining == 0 && !celebrating { onTap(index) } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: metrics.u(18))
                    .fill(flipped == nil ? Self.cream : .white)
                if let art = flipped {
                    VStack(spacing: metrics.u(4)) {
                        if let picture = HanziCueArt.picture(art.picture) {
                            // With 粵拼 on, the picture gives up 22 u so the reading fits under the card's glyph row.
                            VectorArtView(artwork: picture)
                                .frame(width: metrics.u(150), height: metrics.u(jyutping == nil ? 118 : 96))
                        }
                        HStack(spacing: metrics.u(8)) {
                            HanziGlyphView(glyph: art.glyph, pack: pack, ink: Self.teal, lineWidth: 30)
                                .frame(width: metrics.u(44), height: metrics.u(44))
                            CanvasText(art.meaning, size: 24, weight: 800)
                        }
                        // 粵拼 (design: 「開咗先喺字卡下面顯示。」): drawn only when the parent turned it on, and never
                        // spoken (kept out of the accessibility label too).
                        if let jyutping {
                            CanvasText(jyutping, size: 18, weight: 700, color: Self.teal)
                                .accessibilityHidden(true)
                        }
                    }
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                } else {
                    // Every unopened card: one background, one ink, one scale (no picture, colour or count clue).
                    HanziGlyphView(glyph: face.glyph, pack: pack, ink: .ink)
                        .frame(width: metrics.u(150), height: metrics.u(150))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: metrics.u(18))
                .strokeBorder(Color.ink, lineWidth: metrics.u(4)))
            .overlay(RoundedRectangle(cornerRadius: metrics.u(21))
                .strokeBorder(wrong ? Color.orange : Color(hex: DesignTokens.Palette.sunny),
                              style: StrokeStyle(lineWidth: metrics.u(5), dash: [metrics.u(9), metrics.u(6)]))
                .opacity(wrong || hinted ? 1 : 0))
            .overlay(alignment: .topTrailing) {
                if flipped != nil { foundMark.padding(metrics.u(8)) }
            }
            .opacity(wrong ? 0.65 : celebrating && flipped == nil ? 0.4 : 1)
            .offset(x: wrong && !reduceMotion && thinkPauseRemaining > 0 ? metrics.u(3) : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.09).repeatCount(3, autoreverses: true), value: wrong)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: flipped != nil)
            .shadow(color: flipped != nil ? Color(hex: DesignTokens.Palette.sunny) : .clear,
                    radius: metrics.u(celebrating && !reduceMotion ? 16 : 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(flipped.map { "\($0.glyph) \($0.meaning)" } ?? face.glyph)
    }

    /// Mockup 06: the green tick on a flipped card.
    private var foundMark: some View {
        ZStack {
            Circle().fill(Color(hex: 0x58BC65))
            Circle().strokeBorder(Color.ink, lineWidth: metrics.u(2))
            Path { tick in
                tick.move(to: CGPoint(x: metrics.u(7), y: metrics.u(13)))
                tick.addLine(to: CGPoint(x: metrics.u(11), y: metrics.u(17)))
                tick.addLine(to: CGPoint(x: metrics.u(18), y: metrics.u(8)))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: metrics.u(2.5), lineCap: .round, lineJoin: .round))
        }
        .frame(width: metrics.u(25), height: metrics.u(25))
        .accessibilityHidden(true)
    }

    /// Voice state, shown beside every bubble line: crossed out unless the voice can speak (`AppModel.tapHanziAudioOn`:
    /// 廣東話語音 on and a zh-HK / yue-HK voice installed). Not a button.
    private var speakerMark: some View {
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

    private var tray: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: metrics.u(28))
                .fill(Color(hex: DesignTokens.Palette.paper))
                .overlay(RoundedRectangle(cornerRadius: metrics.u(28)).strokeBorder(Color.ink, lineWidth: metrics.u(4)))
            Button(action: onReprompt) {
                ZStack {
                    HanziGlyphView(glyph: board.target, pack: pack, ink: .ink, lineWidth: 24)
                    HanziGlyphView(glyph: board.target, pack: pack, ink: Self.teal, lineWidth: 24,
                                   reveal: strokeReveal == nil ? paintProgress : 0)
                }
                .padding(metrics.u((Self.plaque.width - Self.plaqueGlyphSide) / 2))
                .frame(width: metrics.u(Self.plaque.width), height: metrics.u(Self.plaque.height))
                .background(RoundedRectangle(cornerRadius: metrics.u(15)).fill(Color(hex: DesignTokens.Palette.sunny)))
                .scaleEffect(plaqueNudge && !reduceMotion ? 1.08 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2).repeatCount(2, autoreverses: true),
                           value: plaqueNudge)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copy.prompt(board.target))
            .canvasPlaced(x: 370, y: 10)
            HStack(spacing: metrics.u(12)) {
                ForEach(0..<2, id: \.self) { slot in
                    RoundedRectangle(cornerRadius: metrics.u(12))
                        .fill(.white)
                        .overlay {
                            if let art = board.slot(slot, pack: pack), let picture = HanziCueArt.picture(art.picture) {
                                VectorArtView(artwork: picture).padding(metrics.u(5))
                            }
                        }
                        .frame(width: metrics.u(95), height: metrics.u(95))
                }
                CanvasText(copy.remaining(board.remaining), size: 24, weight: 900)
            }
            .canvasPlaced(x: 535, y: 20)
        }
        .frame(width: metrics.u(1010), height: metrics.u(165))
        .canvasPlaced(x: 46, y: 545)
    }

    /// Both found: the plaque writes the target in MOE order (`StrokeGlyph.hanzi`, 筆順動畫 setting), then flashes.
    @ViewBuilder private var strokeRevealLayer: some View {
        if let reveal = strokeReveal, let glyph = StrokeGlyph.hanzi(board.target, in: pack) {
            let timeline = StrokeOrderTimeline(glyph: glyph, dosage: reveal.dosage)
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let now = context.date.timeIntervalSinceReferenceDate
                Canvas { canvas, _ in
                    var g = canvas
                    g.scaleBy(x: metrics.scale, y: metrics.scale)
                    let side = Double(Self.plaqueGlyphSide)
                    let place = StrokeOrderDrawing.Placement(
                        offset: LineMatchPoint(x: Double(Self.plaque.minX) + (Double(Self.plaque.width) - side) / 2,
                                               y: Double(Self.plaque.minY) + (Double(Self.plaque.height) - side) / 2),
                        scale: side / 300)
                    if reveal.writing(now: now) {
                        let t = max(0, now - reveal.startedAt)
                        StrokeOrderDrawing.ink(timeline, at: t, reduceMotion: reduceMotion, place: place,
                                               colour: Self.teal, outline: 32, core: 24, in: &g)
                        StrokeOrderDrawing.pen(timeline, at: t, reduceMotion: reduceMotion, place: place,
                                               nibColour: 0x2D9FA5, penScale: 0.55, in: &g)
                    } else if now >= reveal.endsAt(now: now) {
                        StrokeOrderDrawing.ink(timeline, at: nil, reduceMotion: reduceMotion, place: place,
                                               colour: Self.teal, outline: 32, core: 24, in: &g)
                        if !reduceMotion && now - reveal.endsAt(now: now) < 0.25 {
                            g.fill(Path(roundedRect: Self.plaque, cornerRadius: 15), with: .color(.white.opacity(0.35)))
                        }
                    }
                }
            }
            .frame(width: metrics.u(1280), height: metrics.u(720))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
