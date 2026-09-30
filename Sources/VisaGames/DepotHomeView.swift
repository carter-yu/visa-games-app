import SwiftUI
import VisaCore

/// Board 1 of the concept canvas: depot scene, Stampy's replay bubble and three mission tickets.
/// Coordinates are the canvas's (ADR 0007). The passport button arrives with the passport (UX Phase 4).
struct DepotHomeView: View {
    let onSelect: (ChildDifficulty) -> Void
    let onSpeakPrompt: () -> Void
    let onParentUnlock: () -> Void

    var body: some View {
        CanvasStage {
            VectorArtView(artwork: CanvasArt.depotScene, contentMode: .fill)
        } content: {
            DepotSign()
                .canvasPlaced(x: 56, y: 34)
            GuideRow(prompt: .depotPickTicket, onSpeak: onSpeakPrompt)
                .canvasPlaced(x: 50, y: 178)
            TicketRow(onSelect: onSelect)
                .canvasPlaced(x: 96, y: 384)
            ParentCornerEntry(onUnlock: onParentUnlock)
                .canvasPlaced(x: 1220, y: 664)
        }
        .onAppear(perform: onSpeakPrompt)
    }
}

/// Hanging wooden sign 「簽證車廠 Visa Depot」.
private struct DepotSign: View {
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                CanvasText("簽證車廠", size: 40, weight: 900, lineHeight: 1.15, tracking: 2)
                CanvasText("Visa Depot", size: 20, weight: 800, lineHeight: 1.2)
            }
            .padding(.top, metrics.u(12 + 5))
            .padding(.horizontal, metrics.u(30 + 5))
            .padding(.bottom, metrics.u(8 + 5))
            .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.wood), cornerRadius: 20, shadowDepth: 6))
            HStack(spacing: metrics.u(130)) {
                SignPost()
                SignPost()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("簽證車廠 / Visa Depot")
    }
}

private struct SignPost: View {
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        let width = metrics.u(14), height = metrics.u(28), line = metrics.u(4)
        ZStack {
            Rectangle().fill(Color(hex: DesignTokens.Palette.woodDark))
            Path { path in
                path.move(to: CGPoint(x: line / 2, y: 0))
                path.addLine(to: CGPoint(x: line / 2, y: height - line / 2))
                path.addLine(to: CGPoint(x: width - line / 2, y: height - line / 2))
                path.addLine(to: CGPoint(x: width - line / 2, y: 0))
            }
            .stroke(Color.ink, lineWidth: line)
        }
        .frame(width: width, height: height)
    }
}

/// Stampy with the speech bubble. The bubble is the replay-voice button.
private struct GuideRow: View {
    let prompt: SpokenPrompt
    let onSpeak: () -> Void
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        HStack(alignment: .center, spacing: metrics.u(20)) {
            VectorArtView(artwork: CanvasArt.stampy)
                .frame(width: metrics.u(176), height: metrics.u(176))
            SpeechBubbleButton(prompt: prompt, action: onSpeak)
        }
    }
}

struct SpeechBubbleButton: View {
    let prompt: SpokenPrompt
    let action: () -> Void
    @Environment(\.canvasMetrics) private var metrics

    private static let waveHeights: [CGFloat] = [14, 30, 20, 36, 16]

    var body: some View {
        Button(action: action) {
            HStack(spacing: metrics.u(18)) {
                ZStack {
                    Circle().fill(Color(hex: DesignTokens.Palette.sunnyPale))
                    Circle().strokeBorder(Color.ink, lineWidth: metrics.u(4))
                    VectorArtView(artwork: CanvasArt.speaker)
                        .frame(width: metrics.u(34), height: metrics.u(34))
                }
                .frame(width: metrics.u(60), height: metrics.u(60))
                HStack(alignment: .center, spacing: metrics.u(5)) {
                    ForEach(Array(Self.waveHeights.enumerated()), id: \.offset) { _, height in
                        RoundedRectangle(cornerRadius: metrics.u(4), style: .circular)
                            .fill(Color(hex: DesignTokens.Palette.metro))
                            .frame(width: metrics.u(7), height: metrics.u(height))
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    CanvasText(prompt.traditionalChinese, size: 30, weight: 900, lineHeight: 1.2)
                    CanvasText(prompt.english, size: 18, weight: 700, color: .inkSoft, lineHeight: 1.6)
                }
            }
            .padding(.vertical, metrics.u(18 + 5))
            .padding(.leading, metrics.u(22 + 5))
            .padding(.trailing, metrics.u(30 + 5))
            .overlay(alignment: .topLeading) {
                BubbleTail()
                    .offset(x: metrics.u(-12), y: metrics.u(45))
            }
        }
        .buttonStyle(ChunkyButtonStyle(fill: .white, cornerRadius: 30, shadowDepth: 6, clipsContent: false))
        .accessibilityLabel("再聽一次：\(prompt.traditionalChinese) / Hear it again: \(prompt.english)")
    }
}

/// The bubble's pointer toward Stampy: a white square turned 45° with ink on two sides,
/// laid over the bubble's outline so the two read as one shape.
private struct BubbleTail: View {
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Color.white)
            Rectangle().fill(Color.ink).frame(width: metrics.u(5))
            Rectangle().fill(Color.ink).frame(height: metrics.u(5))
        }
        .frame(width: metrics.u(31), height: metrics.u(31))
        .rotationEffect(.degrees(45))
        .accessibilityHidden(true)
    }
}

private struct TicketRow: View {
    let onSelect: (ChildDifficulty) -> Void
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.u(34)) {
            ForEach(MissionTicket.all, id: \.difficulty) { ticket in
                MissionTicketButton(ticket: ticket) { onSelect(ticket.difficulty) }
            }
        }
    }
}

/// Physical-ticket card: vehicle, stars, road tiles (one per 10 minutes) and a small minutes label.
struct MissionTicketButton: View {
    let ticket: MissionTicket
    let action: () -> Void
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Color(hex: ticket.headerColor)
                    VectorArtView(artwork: ticket.artwork)
                        .frame(width: metrics.u(208), height: metrics.u(130))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    DashedRule()
                        .stroke(Color.ink, style: StrokeStyle(lineWidth: metrics.u(5), dash: [metrics.u(15), metrics.u(10)]))
                        .frame(height: metrics.u(5))
                }
                .frame(height: metrics.u(156))
                VStack(spacing: metrics.u(8)) {
                    HStack(spacing: 0) {
                        HStack(spacing: metrics.u(4)) {
                            ForEach(0..<ticket.stars, id: \.self) { _ in
                                VectorArtView(artwork: CanvasArt.star)
                                    .frame(width: metrics.u(32), height: metrics.u(32))
                            }
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: metrics.u(6)) {
                            ForEach(0..<ticket.roadTiles, id: \.self) { _ in RoadTileView() }
                        }
                    }
                    HStack(spacing: 0) {
                        CanvasText(ticket.titleTraditionalChinese, size: 20, weight: 800, lineHeight: 1.6)
                        Spacer(minLength: 0)
                        CanvasText(ticket.minutesLabel, size: 20, weight: 800, lineHeight: 1.6)
                    }
                }
                .padding(.horizontal, metrics.u(26))
                .frame(maxHeight: .infinity)
            }
            .overlay(alignment: .topLeading) { TicketNotch().offset(x: metrics.u(-22), y: metrics.u(138)) }
            .overlay(alignment: .topTrailing) { TicketNotch().offset(x: metrics.u(22), y: metrics.u(138)) }
            .padding(metrics.u(5))
            .frame(width: metrics.u(340), height: metrics.u(288))
        }
        .buttonStyle(ChunkyButtonStyle(fill: Color(hex: ticket.bodyColor), cornerRadius: 30, shadowDepth: 10))
        .accessibilityLabel(ticket.accessibilityLabel)
    }
}

private struct DashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// Punched half-circle on each ticket edge.
private struct TicketNotch: View {
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: DesignTokens.Palette.sand))
            Circle().strokeBorder(Color.ink, lineWidth: metrics.u(5))
        }
        .frame(width: metrics.u(34), height: metrics.u(34))
    }
}

/// One road tile = 10 minutes (used on tickets now; stamp and road timer in UX Phase 3).
struct RoadTileView: View {
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.u(7), style: .circular)
        ZStack {
            shape.fill(Color(hex: DesignTokens.Palette.road))
            shape.strokeBorder(Color.ink, lineWidth: metrics.u(3))
            DashedRule()
                .stroke(Color(hex: DesignTokens.Palette.paper),
                        style: StrokeStyle(lineWidth: metrics.u(3), dash: [metrics.u(5), metrics.u(3.5)]))
                .frame(width: metrics.u(22), height: metrics.u(3))
        }
        .frame(width: metrics.u(44), height: metrics.u(24))
        .accessibilityHidden(true)
    }
}
