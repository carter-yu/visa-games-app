import SwiftUI
import VisaCore

/// Board 2 shell: Stampy + bubble, cone progress, fuel gauge, stimulus, choices.
/// Wrong-answer Think Pause overlays 「停一停，想一想！」 with a big countdown; hit-testing off.
struct ActivityBoardView<Stimulus: View, Choice: View>: View {
    let prompt: SpokenPrompt
    let coneTotal: Int
    let coneCompleted: Int
    let stampyOffsetTowardHint: CGFloat
    let pendingMinutes: Int
    let startingMinutes: Int
    let thinkPauseRemaining: Int
    let fuelFeedback: String?
    let choicesLocked: Bool
    let onSpeak: () -> Void
    @ViewBuilder let stimulus: () -> Stimulus
    @ViewBuilder let choices: () -> Choice
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        ZStack {
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

                VStack(alignment: .trailing, spacing: metrics.u(8)) {
                    ConeProgressView(total: coneTotal, completed: coneCompleted)
                    PendingFuelGauge(pendingMinutes: pendingMinutes, startingMinutes: startingMinutes)
                    if let fuelFeedback, !fuelFeedback.isEmpty, thinkPauseRemaining == 0 {
                        CanvasText(fuelFeedback, size: 18, weight: 800,
                                   color: Color(hex: DesignTokens.Palette.tomato))
                    }
                }
                .canvasPlaced(x: 980, y: 28)

                stimulus()
                    .frame(width: metrics.u(420), height: metrics.u(220))
                    .canvasPlaced(x: 430, y: 160)

                choices()
                    .canvasPlaced(x: 110, y: 430)
                    .allowsHitTesting(!choicesLocked)
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

/// Cute fuel / road drain for pending award minutes (not banked viewingSeconds).
struct PendingFuelGauge: View {
    let pendingMinutes: Int
    let startingMinutes: Int
    @Environment(\.canvasMetrics) private var metrics

    private var fraction: CGFloat {
        let start = max(startingMinutes, 1)
        return CGFloat(max(0, min(pendingMinutes, start))) / CGFloat(start)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: metrics.u(4)) {
            HStack(spacing: metrics.u(6)) {
                Image(systemName: "fuelpump.fill")
                    .font(.system(size: metrics.u(16), weight: .bold))
                    .foregroundStyle(Color(hex: DesignTokens.Palette.sunny))
                CanvasText("\(max(0, pendingMinutes)) 分鐘", size: 18, weight: 800)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(hex: DesignTokens.Palette.inkSoft).opacity(0.25))
                    Capsule()
                        .fill(Color(hex: DesignTokens.Palette.mint))
                        .frame(width: max(metrics.u(8), geo.size.width * fraction))
                    Capsule()
                        .strokeBorder(Color.ink, lineWidth: metrics.u(3))
                }
            }
            .frame(width: metrics.u(160), height: metrics.u(16))
        }
        .padding(.horizontal, metrics.u(12))
        .padding(.vertical, metrics.u(8))
        .background(
            RoundedRectangle(cornerRadius: metrics.u(16), style: .continuous)
                .fill(Color(hex: DesignTokens.Palette.paper).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.u(16), style: .continuous)
                        .strokeBorder(Color.ink, lineWidth: metrics.u(3))
                )
        )
        .accessibilityLabel("剩餘油量 \(pendingMinutes) 分鐘 / \(pendingMinutes) minutes fuel left")
    }
}

/// Soft Think Pause overlay — cute, not scary. Mash does not dismiss.
struct ThinkPauseOverlay: View {
    let remainingSeconds: Int
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        ZStack {
            Color.ink.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: metrics.u(18)) {
                CanvasText(WrongAnswerCopy.thinkPauseTraditionalChinese, size: 40, weight: 900)
                CanvasText(WrongAnswerCopy.thinkPauseEnglish, size: 20, weight: 700,
                           color: Color(hex: DesignTokens.Palette.inkSoft))
                Text("\(max(1, remainingSeconds))")
                    .font(.system(size: metrics.u(96), weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: DesignTokens.Palette.sunny))
                    .shadow(color: Color.ink.opacity(0.2), radius: 0, x: 0, y: metrics.u(6))
                    .accessibilityLabel("\(remainingSeconds)")
            }
            .padding(metrics.u(36))
            .background(
                RoundedRectangle(cornerRadius: metrics.u(36), style: .continuous)
                    .fill(Color(hex: DesignTokens.Palette.paper))
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.u(36), style: .continuous)
                            .strokeBorder(Color.ink, lineWidth: metrics.u(6))
                    )
                    .shadow(color: Color.ink.opacity(0.25), radius: 0, x: 0, y: metrics.u(10))
            )
        }
        .allowsHitTesting(true) // absorb taps; mash does not skip or re-penalize
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(WrongAnswerCopy.thinkPauseTraditionalChinese) \(remainingSeconds)")
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
