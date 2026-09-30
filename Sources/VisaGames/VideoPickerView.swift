import SwiftUI
import VisaCore

// MARK: - Board 4 prelude — pick a video (Holiday P0, v0.11.1)

/// After the stamp gate's 「出發！」, the child picks one allowlisted video from large preview
/// cards. One video still shows its card so the child feels the choice. Every pick goes through
/// the existing D8 allowlist gate (`AppModel.playAllowlisted`).
///
/// Layout (v0.11.1): 3×2 page grid so up to six cards fit fully on the 1280×720 safe canvas —
/// no mid-card clip and no dead blue gutter. More than six videos page with chunky arrows.
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
    @State private var pageIndex = 0

    /// Three columns × two rows — six chunky TV cards per page, all fully on-canvas.
    private let columnsPerPage = 3
    private let rowsPerPage = 2
    private var pageSize: Int { columnsPerPage * rowsPerPage }
    private var pageCount: Int { max(1, Int(ceil(Double(videos.count) / Double(pageSize)))) }
    private var showsPager: Bool { pageCount > 1 }

    private var pageVideos: [ApprovedVideo] {
        let start = pageIndex * pageSize
        guard start < videos.count else { return [] }
        let end = min(start + pageSize, videos.count)
        return Array(videos[start..<end])
    }

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
            .canvasPlaced(x: 60, y: 24)

            VectorArtView(artwork: ticket.artwork)
                .frame(width: metrics.u(150), height: metrics.u(94))
                .canvasPlaced(x: 1060, y: 40)

            pickerBoard
                .canvasPlaced(x: showsPager ? 36 : 60, y: 168)

            if showsPager {
                pageDots
                    .frame(width: metrics.u(1160), alignment: .center)
                    .canvasPlaced(x: 60, y: 608)
            }

            if let message {
                CanvasText(message, size: 16, weight: 700, color: .inkSoft)
                    .canvasPlaced(x: 80, y: 640)
            }
        }
        .onAppear {
            clampPageIndex()
            onAppearLog()
            // Let 「出發！」 finish before Stampy asks 「揀片睇！」.
            let work = DispatchWorkItem { onSpeak() }
            pendingSpeech = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        }
        .onChange(of: videos.count) { _, _ in
            clampPageIndex()
        }
        .onDisappear {
            pendingSpeech?.cancel()
            pendingSpeech = nil
        }
    }

    private var pickerBoard: some View {
        HStack(spacing: metrics.u(12)) {
            if showsPager {
                pageArrow(
                    systemName: "chevron.left",
                    label: "上一頁 / Previous videos",
                    enabled: pageIndex > 0
                ) {
                    pageIndex = max(0, pageIndex - 1)
                }
            }

            videoGrid(pageVideos)
                .frame(
                    width: metrics.u(showsPager ? 1000 : 1160),
                    height: metrics.u(430),
                    alignment: .top
                )

            if showsPager {
                pageArrow(
                    systemName: "chevron.right",
                    label: "下一頁 / More videos",
                    enabled: pageIndex < pageCount - 1
                ) {
                    pageIndex = min(pageCount - 1, pageIndex + 1)
                }
            }
        }
    }

    private func videoGrid(_ page: [ApprovedVideo]) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: metrics.u(200)), spacing: metrics.u(20)),
            count: columnsPerPage
        )
        return LazyVGrid(columns: columns, alignment: .center, spacing: metrics.u(18)) {
            ForEach(page) { video in
                VideoPreviewCard(video: video, ticket: ticket) { onPick(video.id) }
            }
        }
        .padding(.horizontal, metrics.u(8))
        .padding(.top, metrics.u(4))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Clip only at page edges so a card never draws half-off into empty sky.
        .clipped()
    }

    private func pageArrow(systemName: String, label: String, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: metrics.u(36), weight: .black))
                .foregroundStyle(Color.ink)
                .frame(width: metrics.u(72), height: metrics.u(120))
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: Color(hex: enabled ? DesignTokens.Palette.sunny : DesignTokens.Palette.sand),
            cornerRadius: 24,
            shadowDepth: 8
        ))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(label)
    }

    private var pageDots: some View {
        HStack(spacing: metrics.u(12)) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == pageIndex
                          ? Color(hex: DesignTokens.Palette.sunny)
                          : Color(hex: DesignTokens.Palette.paper))
                    .overlay(Circle().strokeBorder(Color.ink, lineWidth: metrics.u(3)))
                    .frame(width: metrics.u(18), height: metrics.u(18))
                    .accessibilityLabel("第 \(index + 1) 頁 / Page \(index + 1)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("影片頁 \(pageIndex + 1) / \(pageCount) · Video page \(pageIndex + 1) of \(pageCount)")
    }

    private func clampPageIndex() {
        let maxPage = max(0, pageCount - 1)
        if pageIndex > maxPage { pageIndex = maxPage }
    }
}

private struct VideoPreviewCard: View {
    let video: ApprovedVideo
    let ticket: MissionTicket
    let action: () -> Void
    @Environment(\.canvasMetrics) private var metrics

    /// Thumbnail width sized so three cards + gaps fit inside the 1160 / 1000 board.
    private let thumbWidth: CGFloat = 248
    private let thumbHeight: CGFloat = 132

    private var title: String? {
        let cantonese = video.titleCantonese?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cantonese.isEmpty { return cantonese }
        let english = video.titleEnglish?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return english.isEmpty ? nil : english
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: metrics.u(10)) {
                ZStack {
                    VideoPreviewThumbnail(video: video, ticket: ticket)
                    // Play badge so the card reads as "watch this" without text.
                    ZStack {
                        Circle().fill(Color(hex: DesignTokens.Palette.mint))
                        Circle().strokeBorder(Color.ink, lineWidth: metrics.u(4))
                        Image(systemName: "play.fill")
                            .font(.system(size: metrics.u(24), weight: .bold))
                            .foregroundStyle(Color.ink)
                            .offset(x: metrics.u(2))
                    }
                    .frame(width: metrics.u(64), height: metrics.u(64))
                }
                .frame(width: metrics.u(thumbWidth), height: metrics.u(thumbHeight))
                .clipShape(RoundedRectangle(cornerRadius: metrics.u(14), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.u(14), style: .continuous)
                        .strokeBorder(Color.ink, lineWidth: metrics.u(4))
                )
                if let title {
                    Text(title)
                        .font(CanvasFont.font(size: metrics.u(20), weight: 800))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: metrics.u(thumbWidth))
                } else {
                    HStack(spacing: metrics.u(4)) {
                        ForEach(0..<ticket.stars, id: \.self) { _ in
                            VectorArtView(artwork: CanvasArt.star)
                                .frame(width: metrics.u(22), height: metrics.u(22))
                        }
                    }
                    .frame(height: metrics.u(22))
                }
            }
            .padding(metrics.u(14))
        }
        .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.paper),
                                       cornerRadius: 24, shadowDepth: 8))
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
                .frame(width: metrics.u(160), height: metrics.u(100))
                .opacity(0.9)
        }
    }
}
