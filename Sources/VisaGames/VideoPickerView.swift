import SwiftUI
import VisaCore

// MARK: - Board 4 prelude — pick a video (Holiday P0, v0.11.0)

/// After the stamp gate's 「出發！」, the child picks one allowlisted video from large preview
/// cards. One video still shows its card so the child feels the choice. Every pick goes through
/// the existing D8 allowlist gate (`AppModel.playAllowlisted`).
struct VideoPickerView: View {
    let ticket: MissionTicket
    let videos: [ApprovedVideo]
    /// Parent-facing playback message (e.g. budget empty) when a pick is refused.
    let message: String?
    let onPick: (String) -> Void
    let onSpeak: () -> Void
    let onAppearLog: () -> Void
    @Environment(\.canvasMetrics) private var metrics
    @State private var pendingSpeech: DispatchWorkItem?

    var body: some View {
        CanvasStage {
            ZStack(alignment: .bottom) {
                Color(hex: DesignTokens.Palette.sky)
                Color(hex: DesignTokens.Palette.grass).frame(height: metrics.u(120))
                Color(hex: DesignTokens.Palette.road).frame(height: metrics.u(44))
            }
        } content: {
            HStack(spacing: metrics.u(16)) {
                VectorArtView(artwork: CanvasArt.stampy)
                    .frame(width: metrics.u(130), height: metrics.u(130))
                SpeechBubbleButton(prompt: .pickVideo, action: onSpeak)
                    .scaleEffect(0.85, anchor: .leading)
            }
            .canvasPlaced(x: 60, y: 30)

            VectorArtView(artwork: ticket.artwork)
                .frame(width: metrics.u(150), height: metrics.u(94))
                .canvasPlaced(x: 1060, y: 60)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: metrics.u(36)) {
                    ForEach(videos) { video in
                        VideoPreviewCard(video: video, ticket: ticket) { onPick(video.id) }
                    }
                }
                .padding(.horizontal, metrics.u(24))
                .padding(.top, metrics.u(8))
                .padding(.bottom, metrics.u(24))
                .frame(minWidth: metrics.u(1160))
            }
            .frame(width: metrics.u(1160), height: metrics.u(380))
            .canvasPlaced(x: 60, y: 210)

            if let message {
                CanvasText(message, size: 16, weight: 700, color: .inkSoft)
                    .canvasPlaced(x: 80, y: 600)
            }
        }
        .onAppear {
            onAppearLog()
            // Let 「出發！」 finish before Stampy asks 「揀片睇！」.
            let work = DispatchWorkItem { onSpeak() }
            pendingSpeech = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        }
        .onDisappear {
            pendingSpeech?.cancel()
            pendingSpeech = nil
        }
    }
}

private struct VideoPreviewCard: View {
    let video: ApprovedVideo
    let ticket: MissionTicket
    let action: () -> Void
    @Environment(\.canvasMetrics) private var metrics

    private var title: String? {
        let cantonese = video.titleCantonese?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cantonese.isEmpty { return cantonese }
        let english = video.titleEnglish?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return english.isEmpty ? nil : english
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: metrics.u(12)) {
                ZStack {
                    VideoPreviewThumbnail(video: video, ticket: ticket)
                    // Play badge so the card reads as "watch this" without text.
                    ZStack {
                        Circle().fill(Color(hex: DesignTokens.Palette.mint))
                        Circle().strokeBorder(Color.ink, lineWidth: metrics.u(4))
                        Image(systemName: "play.fill")
                            .font(.system(size: metrics.u(28), weight: .bold))
                            .foregroundStyle(Color.ink)
                            .offset(x: metrics.u(3))
                    }
                    .frame(width: metrics.u(72), height: metrics.u(72))
                }
                .frame(width: metrics.u(320), height: metrics.u(180))
                .clipShape(RoundedRectangle(cornerRadius: metrics.u(16), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.u(16), style: .continuous)
                        .strokeBorder(Color.ink, lineWidth: metrics.u(4))
                )
                if let title {
                    Text(title)
                        .font(CanvasFont.font(size: metrics.u(22), weight: 800))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: metrics.u(320))
                } else {
                    HStack(spacing: metrics.u(4)) {
                        ForEach(0..<ticket.stars, id: \.self) { _ in
                            VectorArtView(artwork: CanvasArt.star)
                                .frame(width: metrics.u(26), height: metrics.u(26))
                        }
                    }
                    .frame(height: metrics.u(26))
                }
            }
            .padding(metrics.u(18))
        }
        .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.paper),
                                       cornerRadius: 28, shadowDepth: 10))
        .accessibilityLabel("揀呢條片 / Pick this video: \(title ?? video.id)")
    }
}

/// Offline-safe preview: YouTube CDN thumbnail via AsyncImage; loading / failure / invalid id
/// falls back to the ticket's vehicle art (never blocks the picker).
private struct VideoPreviewThumbnail: View {
    let video: ApprovedVideo
    let ticket: MissionTicket
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        if let url = video.thumbnailURL {
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
                .frame(width: metrics.u(200), height: metrics.u(125))
                .opacity(0.9)
        }
    }
}
