import SwiftUI
import VisaCore

/// Board 2 shell: Stampy + bubble, cone progress, stimulus panel, up to 3 text-free choice cards.
struct ActivityBoardView<Stimulus: View, Choice: View>: View {
    let prompt: SpokenPrompt
    let coneTotal: Int
    let coneCompleted: Int
    let stampyOffsetTowardHint: CGFloat
    let onSpeak: () -> Void
    @ViewBuilder let stimulus: () -> Stimulus
    @ViewBuilder let choices: () -> Choice
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        CanvasStage {
            // Sky + thin sand strip (board 2).
            ZStack(alignment: .bottom) {
                Color(hex: DesignTokens.Palette.sky)
                LinearGradient(
                    colors: [Color(hex: DesignTokens.Palette.sky), Color(hex: 0x7EC8E8)],
                    startPoint: .top, endPoint: .bottom
                )
                .opacity(0.35)
                // Soft clouds
                HStack(spacing: metrics.u(120)) {
                    CloudBlob().frame(width: metrics.u(120), height: metrics.u(50))
                    CloudBlob().frame(width: metrics.u(90), height: metrics.u(40))
                    CloudBlob().frame(width: metrics.u(110), height: metrics.u(48))
                }
                .offset(y: -metrics.u(220))
                .opacity(0.9)
                Color(hex: DesignTokens.Palette.sand)
                    .frame(height: metrics.u(70))
            }
        } content: {
            HStack(alignment: .center, spacing: metrics.u(16)) {
                VectorArtView(artwork: CanvasArt.stampy)
                    .frame(width: metrics.u(110), height: metrics.u(110))
                    .offset(x: stampyOffsetTowardHint)
                SpeechBubbleButton(prompt: prompt, action: onSpeak)
                    .scaleEffect(0.85, anchor: .leading)
            }
            .canvasPlaced(x: 40, y: 28)

            ConeProgressView(total: coneTotal, completed: coneCompleted)
                .canvasPlaced(x: 1080, y: 36)

            stimulus()
                .frame(width: metrics.u(420), height: metrics.u(220))
                .canvasPlaced(x: 430, y: 160)

            choices()
                .canvasPlaced(x: 110, y: 430)
        }
        .onAppear(perform: onSpeak)
    }
}

private struct CloudBlob: View {
    var body: some View {
        ZStack {
            Capsule().fill(Color.white.opacity(0.95))
            HStack(spacing: -8) {
                Circle().fill(Color.white)
                Circle().fill(Color.white).frame(width: 36, height: 36)
                Circle().fill(Color.white)
            }
        }
        .foregroundStyle(Color.white)
    }
}

/// Large stimulus panel with ink outline (shadow / target / convoy).
struct StimulusPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.u(28), style: .continuous)
                .fill(Color(hex: DesignTokens.Palette.paper))
            RoundedRectangle(cornerRadius: metrics.u(28), style: .continuous)
                .strokeBorder(Color.ink, lineWidth: metrics.u(5))
            content()
                .padding(metrics.u(18))
        }
    }
}
