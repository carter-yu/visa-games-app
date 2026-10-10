import SwiftUI
import VisaCore

/// v0.21.1: YouTube bot-check / blocked embed — child-safe board (HK Trad + English).
/// Full-board button returns to the picker. No links, no Google pages.
struct ProviderBlockedView: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = DesignTokens.stageLayout(screenWidth: Double(proxy.size.width),
                                                  screenHeight: Double(proxy.size.height))
            let metrics = CanvasMetrics(scale: CGFloat(layout.scale))
            Button(action: onContinue) {
                ZStack {
                    Color(hex: DesignTokens.Palette.sky)
                    VStack(spacing: metrics.u(18)) {
                        Spacer(minLength: metrics.u(40))
                        Image(systemName: "play.slash.fill")
                            .font(.system(size: metrics.u(72), weight: .bold))
                            .foregroundStyle(Color(hex: DesignTokens.Palette.ink))
                        CanvasText("呢條片而家睇唔到，揀過第二條啦！", size: 36, weight: 900,
                                   color: Color(hex: DesignTokens.Palette.ink))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, metrics.u(48))
                        CanvasText("This video can't play right now. Pick another one.", size: 18, weight: 600,
                                   color: Color.inkSoft)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, metrics.u(48))
                        Spacer()
                        HStack(spacing: metrics.u(12)) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: metrics.u(22), weight: .heavy))
                            CanvasText("返去揀片", size: 28, weight: 900,
                                       color: Color(hex: DesignTokens.Palette.ink))
                        }
                        .padding(.horizontal, metrics.u(36))
                        .padding(.vertical, metrics.u(16))
                        .background(
                            RoundedRectangle(cornerRadius: metrics.u(22), style: .continuous)
                                .fill(Color(hex: DesignTokens.Palette.sunnyPale))
                                .overlay(
                                    RoundedRectangle(cornerRadius: metrics.u(22), style: .continuous)
                                        .strokeBorder(Color(hex: DesignTokens.Palette.ink), lineWidth: metrics.u(4))
                                )
                        )
                        .padding(.bottom, metrics.u(48))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返去揀片 Pick another video")
            .environment(\.canvasMetrics, metrics)
        }
        .ignoresSafeArea()
    }
}
