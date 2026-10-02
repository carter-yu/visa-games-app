import SwiftUI
import VisaCore

// MARK: - Board 4 prelude — pick a video (Holiday P0, v0.11.6)

/// After the stamp gate's 「出發！」, the child picks one allowlisted video from large preview
/// cards. One video still shows its card so the child feels the choice. Every pick goes through
/// the existing D8 allowlist gate (`AppModel.playAllowlisted`).
///
/// Layout (v0.11.6): full 1280×720 artboard `VStack` (not `canvasPlaced` offsets + `LazyVGrid`).
/// Stampy header on top; 3×2 equal-width `HStack` rows centered in the remaining space; cards
/// stretch to fill columns. Fixes TV UAT left/down cluster with cyan gutter on the right.
struct VideoPickerView: View {
    let ticket: MissionTicket
    let videos: [ApprovedVideo]
    /// Last incomplete child-play video still on the allowlist (Continue offer).
    /// v0.15.0: mint Continue banner is **fallback only** — primary gate is Resume Choice
    /// after 「出發！」. When Resume Choice Right clears the cursor, this stays nil.
    var resumeCandidate: IncompletePlayback? = nil
    /// Parent-facing playback message (e.g. budget empty) when a pick is refused.
    let message: String?
    let onPick: (String) -> Void
    /// Resume the incomplete cursor (same id + startSeconds). Nil when no candidate.
    var onContinue: (() -> Void)? = nil
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
            // One full-artboard tree: Spacers vertically center the board under Stampy;
            // equal-width columns fill horizontally. Avoids LazyVGrid shrink-wrap + offset drift.
            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, metrics.u(60))
                    .padding(.top, metrics.u(20))
                    .frame(height: metrics.u(156), alignment: .top)

                Spacer(minLength: metrics.u(8))

                if resumeCandidate != nil, onContinue != nil {
                    continueBanner
                        .padding(.horizontal, metrics.u(60))
                        .padding(.bottom, metrics.u(12))
                }

                pickerBoard
                    .padding(.horizontal, metrics.u(48))

                Spacer(minLength: metrics.u(8))

                footerBar
                    .padding(.horizontal, metrics.u(60))
                    .padding(.bottom, metrics.u(20))
                    .frame(minHeight: metrics.u(36))
            }
            .frame(
                width: metrics.u(CGFloat(DesignTokens.referenceWidth)),
                height: metrics.u(CGFloat(DesignTokens.referenceHeight)),
                alignment: .top
            )
        }
        .onAppear {
            clampPageIndex()
            onAppearLog()
            // Let 「出發！」 finish before Stampy asks 「揀片睇！」.
            let work = DispatchWorkItem { onSpeak() }
            pendingSpeech = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        }
        // macOS 13-compatible onChange (single-arg form). The two-parameter
        // onChange(of:initial:_:) requires macOS 14+ and broke the Release bundle.
        .onChange(of: videos.count) { _ in
            clampPageIndex()
        }
        .onDisappear {
            pendingSpeech?.cancel()
            pendingSpeech = nil
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: metrics.u(16)) {
            VectorArtView(artwork: CanvasArt.stampy)
                .frame(width: metrics.u(130), height: metrics.u(130))
            SpeechBubbleButton(prompt: .pickVideo, action: onSpeak)
                .scaleEffect(0.85, anchor: .leading)
            Spacer(minLength: 0)
            VectorArtView(artwork: ticket.artwork)
                .frame(width: metrics.u(150), height: metrics.u(94))
        }
    }

    @ViewBuilder
    private var footerBar: some View {
        VStack(spacing: metrics.u(8)) {
            if showsPager {
                pageDots
            }
            if let message {
                CanvasText(message, size: 16, weight: 700, color: .inkSoft)
            }
        }
        .frame(maxWidth: .infinity)
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
                .frame(maxWidth: .infinity, alignment: .center)

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
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Deterministic 3×2 equal-width rows (not LazyVGrid — avoids intrinsic-width left cluster).
    private func videoGrid(_ page: [ApprovedVideo]) -> some View {
        let gap = metrics.u(20)
        return VStack(spacing: metrics.u(18)) {
            ForEach(0..<rowsPerPage, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<columnsPerPage, id: \.self) { col in
                        let index = row * columnsPerPage + col
                        Group {
                            if index < page.count {
                                VideoPreviewCard(video: page[index], ticket: ticket) {
                                    onPick(page[index].id)
                                }
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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

    private var continueBanner: some View {
        Button(action: { onContinue?() }) {
            HStack(spacing: metrics.u(16)) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: metrics.u(36), weight: .bold))
                    .foregroundStyle(Color.ink)
                VStack(alignment: .leading, spacing: metrics.u(4)) {
                    CanvasText("繼續睇", size: 28, weight: 800)
                    CanvasText("Continue watching", size: 16, weight: 600, color: .inkSoft)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: metrics.u(28), weight: .bold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.horizontal, metrics.u(24))
            .padding(.vertical, metrics.u(16))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: Color(hex: DesignTokens.Palette.mint),
            cornerRadius: 24,
            shadowDepth: 8
        ))
        .accessibilityLabel("繼續睇 / Continue watching")
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

    /// Thumbnail aspect from the original 248×132 TV preview (fills column width).
    private let thumbAspect: CGFloat = 248.0 / 132.0

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
                .aspectRatio(thumbAspect, contentMode: .fit)
                // Cap so 2 rows + header/footer still leave Spacer room to vertical-center on 720.
                .frame(maxWidth: metrics.u(300))
                .frame(maxWidth: .infinity)
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
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: metrics.u(4)) {
                        ForEach(0..<ticket.stars, id: \.self) { _ in
                            VectorArtView(artwork: CanvasArt.star)
                                .frame(width: metrics.u(22), height: metrics.u(22))
                        }
                    }
                    .frame(height: metrics.u(22))
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(metrics.u(14))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.paper),
                                       cornerRadius: 24, shadowDepth: 8))
        .frame(maxWidth: .infinity, alignment: .center)
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
