import SwiftUI
import VisaCore

/// No eligible target can be dealt. The usual three-second corner hold remains the only parent entry.
/// Build 79 (UX review M3): built like its sibling child board `ProviderBlockedView` — stage-scaled
/// canvas type and symbol, HK Cantonese with an English line. Nothing here is tappable; the parent
/// corner layer above it keeps the hold. Hanzi H4: the advice line comes from `TicketUnavailableCopy`, which names
/// the settings to check (the letters', or 中文字設定 with the Hanzi card that could not be dealt).
struct LetterUnavailableTicketView: View {
    /// What could not be dealt (`AppModel.unavailableTicketKinds`); empty keeps the letter advice.
    var kinds: [ActivityKind] = []

    var body: some View {
        let lines = TicketUnavailableCopy.lines(for: kinds)
        GeometryReader { proxy in
            let layout = DesignTokens.stageLayout(screenWidth: Double(proxy.size.width),
                                                  screenHeight: Double(proxy.size.height))
            let metrics = CanvasMetrics(scale: CGFloat(layout.scale))
            ZStack {
                Color(hex: DesignTokens.Palette.sky)
                VStack(spacing: metrics.u(18)) {
                    Spacer(minLength: metrics.u(40))
                    Image(systemName: "ticket.fill")
                        .font(.system(size: metrics.u(72), weight: .bold))
                        .foregroundStyle(Color(hex: DesignTokens.Palette.ink))
                    CanvasText("呢張遊戲票暫時玩唔到", size: 36, weight: 900,
                               color: Color(hex: DesignTokens.Palette.ink))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, metrics.u(48))
                    CanvasText("This ticket can't be played right now.", size: 18, weight: 600,
                               color: Color.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, metrics.u(48))
                    if !lines.cards.isEmpty {
                        CanvasText(lines.cards.joined(separator: "、"), size: 26, weight: 800,
                                   color: Color(hex: DesignTokens.Palette.ink))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, metrics.u(48))
                    }
                    CanvasText(lines.advice, size: 26, weight: 800,
                               color: Color(hex: DesignTokens.Palette.ink))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, metrics.u(48))
                        .padding(.top, metrics.u(10))
                    CanvasText(lines.adviceEnglish,
                               size: 16, weight: 600, color: Color.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, metrics.u(48))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .environment(\.canvasMetrics, metrics)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
