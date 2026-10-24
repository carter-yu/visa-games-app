import SwiftUI
import VisaCore

/// A centre-line house glyph shared by the cards, target plaque, header and word card.
struct LatinLetterGlyph: View {
    let letter: String
    let ink: Color
    let lineWidth: CGFloat
    var reveal: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 190, proxy.size.height / 380)
            let catalog = letter.first.map { LatinGlyphs.paths($0, offset: LineMatchPoint(x: 0, y: 0), scale: 1) } ?? []
            let paths = catalog.isEmpty && letter == "f"
                ? [TracePath(svg: "M120 44 C90 22 66 43 66 78 L66 270"),
                   TracePath(svg: "M40 130 L125 130")]
                : catalog
            ZStack {
                ForEach(paths.indices, id: \.self) { index in
                    Path { shape in
                        let points = paths[index].points
                        guard let first = points.first else { return }
                        let x = (proxy.size.width - 190 * scale) / 2
                        let y = (proxy.size.height - 380 * scale) / 2
                        shape.move(to: CGPoint(x: x + CGFloat(first.x) * scale,
                                               y: y + CGFloat(first.y) * scale))
                        for point in points.dropFirst() {
                            shape.addLine(to: CGPoint(x: x + CGFloat(point.x) * scale,
                                                      y: y + CGFloat(point.y) * scale))
                        }
                    }
                    .trim(from: 0, to: reveal)
                    .stroke(ink, style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityLabel(letter)
    }
}

struct TapLetterBoardView: View {
    let board: TapLetterBoard
    let isWrite: Bool
    let pendingMinutes: Int
    let fuelBefore: Int
    let thinkPauseRemaining: Int
    let bubble: String?
    let celebrating: Bool
    let plaqueNudge: Bool
    let onTap: (Int) -> Void
    let onReprompt: () -> Void

    var body: some View {
        CanvasStage { LineMatchBackdrop() } content: {
            TapLetterStageContent(board: board, isWrite: isWrite, pendingMinutes: pendingMinutes, fuelBefore: fuelBefore,
                                  thinkPauseRemaining: thinkPauseRemaining, bubble: bubble,
                                  celebrating: celebrating, plaqueNudge: plaqueNudge,
                                  onTap: onTap, onReprompt: onReprompt)
        }
    }
}

private struct TapLetterStageContent: View {
    let board: TapLetterBoard
    let isWrite: Bool
    let pendingMinutes: Int
    let fuelBefore: Int
    let thinkPauseRemaining: Int
    let bubble: String?
    let celebrating: Bool
    let plaqueNudge: Bool
    let onTap: (Int) -> Void
    let onReprompt: () -> Void
    @Environment(\.canvasMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var paintProgress: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
                header
                ForEach(0..<10, id: \.self) { index in
                    card(index)
                        .frame(width: metrics.u(206), height: metrics.u(190))
                        .canvasPlaced(x: CGFloat(85 + (index % 5) * 222),
                                      y: CGFloat(136 + (index / 5) * 206))
                }
                tray
                if let bubble {
                    bubbleLine(bubble)
                        .padding(metrics.u(12))
                        .background(RoundedRectangle(cornerRadius: metrics.u(20)).fill(.white))
                        .canvasPlaced(x: 745, y: 75)
                }
        }
        .onAppear(perform: onReprompt)
        .onChange(of: celebrating) { value in
            if value {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) { paintProgress = 1 }
            } else { paintProgress = 0 }
        }
    }

    @ViewBuilder private func bubbleLine(_ line: String) -> some View {
        if line.hasPrefix("That's "), let letter = line.dropFirst(7).first {
            HStack(spacing: 0) {
                CanvasText("That's ", size: 25, weight: 800)
                LatinLetterGlyph(letter: String(letter), ink: .ink, lineWidth: 29)
                    .frame(width: metrics.u(25), height: metrics.u(45))
                CanvasText(".", size: 25, weight: 800)
            }
        } else if line.hasPrefix("\(board.deal.target) is for ") {
            HStack(spacing: 0) {
                LatinLetterGlyph(letter: board.deal.target, ink: .ink, lineWidth: 29)
                    .frame(width: metrics.u(25), height: metrics.u(45))
                CanvasText(String(line.dropFirst(board.deal.target.count)), size: 25, weight: 800)
            }
        } else {
            CanvasText(line, size: 25, weight: 800)
        }
    }

    private var header: some View {
        HStack(spacing: metrics.u(12)) {
            Button(action: onReprompt) {
                VectorArtView(artwork: CanvasArt.stampy)
                    .frame(width: metrics.u(80), height: metrics.u(80))
            }.buttonStyle(.plain)
            CanvasText(board.isComplete ? "Well done!" : "Tap every", size: 48, weight: 900)
            if !board.isComplete {
                LatinLetterGlyph(letter: board.deal.target, ink: .ink, lineWidth: 25)
                    .frame(width: metrics.u(65), height: metrics.u(78))
                CanvasText("!", size: 48, weight: 900)
            }
            Spacer()
            VStack {
                CanvasText("ABC", size: 23, weight: 900)
                CanvasText(isWrite ? "Find & write" : "Find & flip", size: 14, weight: 800)
            }
            .padding(metrics.u(9))
            .background(RoundedRectangle(cornerRadius: metrics.u(14)).fill(Color(hex: DesignTokens.Palette.sunny)))
        }
        .opacity(thinkPauseRemaining > 0 ? 0.5 : 1)
        .frame(width: metrics.u(1100), height: metrics.u(92))
        .overlay(alignment: .bottomLeading) {
            if !board.isComplete {
                HStack(spacing: 0) {
                    CanvasText("Find the letter ", size: 16, weight: 700)
                    LatinLetterGlyph(letter: board.deal.target, ink: .ink, lineWidth: 26)
                        .frame(width: metrics.u(17), height: metrics.u(30))
                    CanvasText(".", size: 16, weight: 700)
                }
                .offset(x: metrics.u(108), y: metrics.u(10))
            }
        }
        .canvasPlaced(x: 82, y: 17)
    }

    private func card(_ index: Int) -> some View {
        let letter = board.deal.board.rows[index / 5][index % 5]
        let found = board.found.contains(index)
        let wrong = board.knownWrong.contains(index)
        let hinted = board.assisted && board.hintCard == index
        let wordIndex = board.deal.board.targetCards.firstIndex(of: index) ?? 0
        return Button { if thinkPauseRemaining == 0 && !celebrating { onTap(index) } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: metrics.u(18))
                    .fill(found ? .white : Color(hex: DesignTokens.Palette.paper))
                if found {
                    let word = board.deal.words[wordIndex]
                    VStack(spacing: metrics.u(5)) {
                        LetterWordArt(imageID: word.imageID)
                            .frame(width: metrics.u(110), height: metrics.u(105))
                        HStack(spacing: 0) {
                            LatinLetterGlyph(letter: board.deal.target, ink: Color(hex: 0x168F96), lineWidth: 31)
                                .frame(width: metrics.u(28), height: metrics.u(55))
                            CanvasText(String(word.word.dropFirst()), size: 29, weight: 900)
                        }
                    }
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                } else {
                    LatinLetterGlyph(letter: letter, ink: .ink, lineWidth: 31)
                        .frame(width: metrics.u(128), height: metrics.u(168))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: metrics.u(18))
                .strokeBorder(Color.ink, lineWidth: metrics.u(4)))
            .overlay(RoundedRectangle(cornerRadius: metrics.u(21))
                .strokeBorder(wrong ? Color.orange : Color(hex: DesignTokens.Palette.sunny),
                              style: StrokeStyle(lineWidth: metrics.u(5), dash: [metrics.u(9), metrics.u(6)]))
                .opacity(wrong || hinted ? 1 : 0))
            .opacity(wrong ? 0.65 : celebrating && !found ? 0.4 : 1)
            .offset(x: wrong && !reduceMotion && thinkPauseRemaining > 0 ? metrics.u(3) : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.09).repeatCount(3, autoreverses: true), value: wrong)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: found)
            .shadow(color: found ? Color(hex: DesignTokens.Palette.sunny) : .clear,
                    radius: metrics.u(celebrating && !reduceMotion ? 16 : 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(found ? board.deal.words[wordIndex].word : letter)
    }

    private var tray: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: metrics.u(28))
                .fill(Color(hex: DesignTokens.Palette.paper))
                .overlay(RoundedRectangle(cornerRadius: metrics.u(28)).strokeBorder(Color.ink, lineWidth: metrics.u(4)))
            Button(action: onReprompt) {
                ZStack {
                    LatinLetterGlyph(letter: board.deal.target, ink: .ink, lineWidth: 28)
                    LatinLetterGlyph(letter: board.deal.target, ink: Color(hex: 0x168F96),
                                     lineWidth: 28, reveal: paintProgress)
                }
                .frame(width: metrics.u(120), height: metrics.u(142))
                .background(RoundedRectangle(cornerRadius: metrics.u(15)).fill(Color(hex: DesignTokens.Palette.sunny)))
                .scaleEffect(plaqueNudge && !reduceMotion ? 1.08 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2).repeatCount(2, autoreverses: true),
                           value: plaqueNudge)
            }
            .buttonStyle(.plain)
            .canvasPlaced(x: 370, y: 10)
            HStack(spacing: metrics.u(12)) {
                ForEach(0..<2, id: \.self) { slot in
                    RoundedRectangle(cornerRadius: metrics.u(12))
                        .fill(.white)
                        .overlay {
                            if let card = board.deal.board.targetCards[safe: slot], board.found.contains(card) {
                                LetterWordArt(imageID: board.deal.words[slot].imageID).padding(metrics.u(5))
                            }
                        }
                        .frame(width: metrics.u(95), height: metrics.u(95))
                }
                CanvasText(TapLetterCopy.remaining(board.remaining), size: 24, weight: 900)
            }
            .canvasPlaced(x: 535, y: 20)
            if thinkPauseRemaining > 0 {
                VStack(alignment: .leading, spacing: metrics.u(3)) {
                    CanvasText("Pause and think!", size: 27, weight: 900)
                    CanvasText("\(thinkPauseRemaining)s", size: 17, weight: 800)
                    CanvasText("Look at the letters.", size: 17, weight: 700)
                    CanvasText("Half the fuel is gone.", size: 17, weight: 700)
                    CanvasText("\(fuelBefore) → \(pendingMinutes) min · then try again", size: 15, weight: 700)
                }
                .padding(metrics.u(12))
                .background(RoundedRectangle(cornerRadius: metrics.u(16)).fill(Color(hex: DesignTokens.Palette.sunny)))
                .canvasPlaced(x: 520, y: 5)
            }
        }
        .frame(width: metrics.u(1010), height: metrics.u(165))
        .canvasPlaced(x: 46, y: 545)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Each approved a–e word has its own image ID; unknown IDs show a safe picture placeholder.
struct LetterWordArt: View {
    let imageID: String
    private static let pictures: [String: String] = [
        "word.apple":"🍎", "word.ant":"🐜", "word.arrow":"↗️", "word.ambulance":"🚑",
        "word.anchor":"⚓️", "word.astronaut":"👩‍🚀", "word.avocado":"🥑", "word.ankle":"🦶",
        "word.ball":"⚽️", "word.bus":"🚌", "word.bed":"🛏️", "word.bee":"🐝",
        "word.boat":"⛵️", "word.book":"📚", "word.bear":"🐻", "word.bike":"🚲",
        "word.balloon":"🎈", "word.bird":"🐦", "word.banana":"🍌", "word.butterfly":"🦋",
        "word.cat":"🐈", "word.car":"🚗", "word.cake":"🎂", "word.cup":"☕️",
        "word.cow":"🐄", "word.cap":"🧢", "word.corn":"🌽", "word.carrot":"🥕",
        "word.castle":"🏰", "word.camel":"🐪", "word.caterpillar":"🐛", "word.crab":"🦀",
        "word.dog":"🐕", "word.duck":"🦆", "word.door":"🚪", "word.digger":"🚜",
        "word.doll":"🪆", "word.dinosaur":"🦕", "word.dolphin":"🐬", "word.dumptruck":"🚚",
        "word.deer":"🦌", "word.donkey":"🫏", "word.dice":"🎲", "word.drum":"🥁",
        "word.egg":"🥚", "word.elephant":"🐘", "word.elbow":"💪", "word.engine":"🚂",
        "word.envelope":"✉️", "word.excavator":"🚜", "word.escalator":"🛗", "word.elf":"🧝"
    ]
    var body: some View {
        Group {
            if let picture = Self.pictures[imageID] {
                Text(picture).font(.system(size: 74)).minimumScaleFactor(0.5)
            } else {
                Image(systemName: "photo")
                    .resizable().scaledToFit()
                    .foregroundStyle(Color(hex: 0x168F96))
            }
        }
        .accessibilityLabel(imageID.replacingOccurrences(of: "word.", with: ""))
    }
}
