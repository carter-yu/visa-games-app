import SwiftUI
import VisaCore

// MARK: - Resume Choice — fork after 「出發！」when incomplete cursor exists (v0.15.0)

/// Dedicated left/right board: continue the paused film, or pick another.
/// Same dusk Depot family as TimesUp — vehicle-world props, not mint chrome.
/// Carter lock 2026-10-02: Right clears the incomplete cursor immediately.
struct ResumeChoiceView: View {
    let ticket: MissionTicket
    let incomplete: IncompletePlayback
    let onContinue: () -> Void
    let onPickOther: () -> Void
    let onSpeak: () -> Void
    var onSpeakOrPick: (() -> Void)? = nil
    let onAppearLog: () -> Void

    @Environment(\.canvasMetrics) private var metrics
    @State private var pendingSpeech: DispatchWorkItem?

    var body: some View {
        CanvasStage {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [Color(hex: 0x1B2A4A), Color(hex: DesignTokens.Palette.metro)],
                    startPoint: .top, endPoint: .bottom
                )
                ForEach(0..<14, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 3, height: 3)
                        .offset(x: CGFloat((i * 89) % 1100) - 550,
                                y: CGFloat((i * 53) % 240) - 260)
                }
                Text("🌙")
                    .font(.system(size: 36))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(36)
                Ellipse()
                    .fill(Color(hex: DesignTokens.Palette.grass).opacity(0.85))
                    .frame(height: metrics.u(150))
                    .offset(y: metrics.u(36))
                Color(hex: DesignTokens.Palette.sand)
                    .frame(height: metrics.u(96))
            }
        } content: {
            HStack(alignment: .bottom, spacing: metrics.u(16)) {
                VectorArtView(artwork: CanvasArt.stampy)
                    .frame(width: metrics.u(130), height: metrics.u(130))
                SpeechBubbleButton(prompt: .resumeChoiceKeepWatching, action: onSpeak)
                    .scaleEffect(0.82, anchor: .leading)
            }
            .canvasPlaced(x: 48, y: 36)

            HStack(alignment: .center, spacing: metrics.u(28)) {
                continuePane
                pickPane
            }
            .canvasPlaced(x: 96, y: 190)
        }
        .onAppear {
            onAppearLog()
            onSpeak()
            if let onSpeakOrPick {
                let work = DispatchWorkItem { onSpeakOrPick() }
                pendingSpeech = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
            }
        }
        .onDisappear {
            pendingSpeech?.cancel()
            pendingSpeech = nil
        }
    }

    private var continuePane: some View {
        Button(action: onContinue) {
            VStack(spacing: metrics.u(14)) {
                ZStack {
                    ResumeChoiceThumbnail(videoID: incomplete.videoID, ticket: ticket)
                    // Mint play badge — picture does the work for a ~4yo.
                    ZStack {
                        Circle().fill(Color(hex: DesignTokens.Palette.mint))
                        Circle().strokeBorder(Color.ink, lineWidth: metrics.u(5))
                        Image(systemName: "play.fill")
                            .font(.system(size: metrics.u(36), weight: .bold))
                            .foregroundStyle(Color.ink)
                            .offset(x: metrics.u(3))
                    }
                    .frame(width: metrics.u(88), height: metrics.u(88))
                    VectorArtView(artwork: ticket.artwork)
                        .frame(width: metrics.u(72), height: metrics.u(44))
                        .opacity(0.9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(metrics.u(12))
                    pausedChip
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(metrics.u(12))
                }
                .frame(width: metrics.u(460), height: metrics.u(260))
                .clipShape(RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous)
                        .strokeBorder(Color.ink, lineWidth: metrics.u(5))
                )

                VStack(spacing: 2) {
                    CanvasText("繼續睇", size: 30, weight: 900)
                    CanvasText("Continue watching", size: 16, weight: 700, color: .inkSoft)
                }
            }
            .padding(metrics.u(18))
            .frame(width: metrics.u(520), height: metrics.u(380))
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: Color(hex: DesignTokens.Palette.paper),
            cornerRadius: 28,
            shadowDepth: 10
        ))
        .accessibilityLabel("繼續睇 / Continue watching")
    }

    private var pickPane: some View {
        Button(action: onPickOther) {
            VStack(spacing: metrics.u(14)) {
                ZStack {
                    Color(hex: DesignTokens.Palette.sunnyPale)
                    // Stacked film-card silhouettes — reads as the picker bay.
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: metrics.u(12), style: .continuous)
                            .fill(Color(hex: DesignTokens.Palette.paper))
                            .overlay(
                                RoundedRectangle(cornerRadius: metrics.u(12), style: .continuous)
                                    .strokeBorder(Color.ink, lineWidth: metrics.u(4))
                            )
                            .frame(width: metrics.u(220), height: metrics.u(140))
                            .rotationEffect(.degrees(Double(i - 1) * 8))
                            .offset(x: CGFloat(i - 1) * metrics.u(18),
                                    y: CGFloat(i - 1) * metrics.u(10))
                    }
                    ZStack {
                        Circle().fill(Color(hex: DesignTokens.Palette.sunny))
                        Circle().strokeBorder(Color.ink, lineWidth: metrics.u(5))
                        CanvasText("揀", size: 40, weight: 900)
                    }
                    .frame(width: metrics.u(88), height: metrics.u(88))
                }
                .frame(width: metrics.u(460), height: metrics.u(260))
                .clipShape(RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous)
                        .strokeBorder(Color.ink, lineWidth: metrics.u(5))
                )

                VStack(spacing: 2) {
                    CanvasText("揀片睇", size: 30, weight: 900)
                    CanvasText("Pick a video", size: 16, weight: 700, color: .inkSoft)
                }
            }
            .padding(metrics.u(18))
            .frame(width: metrics.u(520), height: metrics.u(380))
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: Color(hex: DesignTokens.Palette.sand),
            cornerRadius: 28,
            shadowDepth: 10
        ))
        .accessibilityLabel("揀片睇 / Pick a video")
    }

    private var pausedChip: some View {
        HStack(spacing: metrics.u(6)) {
            Image(systemName: "pause.fill")
                .font(.system(size: metrics.u(12), weight: .bold))
            CanvasText("停喺呢度", size: 14, weight: 800)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, metrics.u(12))
        .padding(.vertical, metrics.u(6))
        .background(
            Capsule()
                .fill(Color(hex: DesignTokens.Palette.sunny))
                .overlay(Capsule().strokeBorder(Color.ink, lineWidth: metrics.u(3)))
        )
        .accessibilityHidden(true)
    }
}

/// v1 still: YouTube CDN thumbnail for the incomplete id (never blocks on network).
private struct ResumeChoiceThumbnail: View {
    let videoID: String
    let ticket: MissionTicket
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        if let url = YouTubeEmbedURL.thumbnailURL(videoID: videoID) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(hex: DesignTokens.Palette.sunnyPale)
            VectorArtView(artwork: ticket.artwork)
                .frame(width: metrics.u(200), height: metrics.u(120))
                .opacity(0.9)
        }
    }
}
