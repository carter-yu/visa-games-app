import SwiftUI
import VisaCore

// MARK: - Board 4 prelude — pick a video (Holiday P0; layout v0.16.0)

/// After the stamp gate's 「出發！」, the child picks one allowlisted video from large preview
/// cards. One video still shows its card so the child feels the choice. Every pick goes through
/// the existing D8 allowlist gate (`AppModel.playAllowlisted`).
///
/// Layout (v0.16.0): **4×2** page grid filling width (no 300u card cap). Compact floating Stampy
/// HUD pinned top so the bubble never overlaps cards. Giant kid 「仲有」 arrows (≥96×160) **and**
/// ~15% next-page peek when more pages exist. Uses the right-side canvas that 3×2 left empty.
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

    /// Four columns × two rows — eight chunky TV cards per page; fill the artboard width.
    private let columnsPerPage = 4
    private let rowsPerPage = 2
    private var pageSize: Int { columnsPerPage * rowsPerPage }
    private var pageCount: Int { max(1, Int(ceil(Double(videos.count) / Double(pageSize)))) }
    private var showsPager: Bool { pageCount > 1 }
    private var hasNextPage: Bool { pageIndex < pageCount - 1 }
    private var hasPrevPage: Bool { pageIndex > 0 }

    /// Compact HUD band so Stampy + bubble sit above cards (never overlap).
    private var hudBandHeight: CGFloat { metrics.u(96) }

    private var pageVideos: [ApprovedVideo] {
        slice(page: pageIndex)
    }

    private var nextPageVideos: [ApprovedVideo] {
        guard hasNextPage else { return [] }
        return slice(page: pageIndex + 1)
    }

    private func slice(page: Int) -> [ApprovedVideo] {
        let start = page * pageSize
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
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: hudBandHeight)

                    if resumeCandidate != nil, onContinue != nil {
                        continueBanner
                            .padding(.horizontal, metrics.u(48))
                            .padding(.bottom, metrics.u(8))
                    }

                    pickerBoard
                        .padding(.horizontal, metrics.u(28))
                        .frame(maxHeight: .infinity)

                    footerBar
                        .padding(.horizontal, metrics.u(60))
                        .padding(.top, metrics.u(8))
                        .padding(.bottom, metrics.u(16))
                        .frame(minHeight: metrics.u(28))
                }
                .frame(
                    width: metrics.u(CGFloat(DesignTokens.referenceWidth)),
                    height: metrics.u(CGFloat(DesignTokens.referenceHeight)),
                    alignment: .top
                )

                floatingStampyHUD
                    .padding(.horizontal, metrics.u(36))
                    .padding(.top, metrics.u(12))
                    .frame(
                        width: metrics.u(CGFloat(DesignTokens.referenceWidth)),
                        alignment: .top
                    )
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

    /// Compact floating Stampy + bubble + ticket — pinned top, clear of the card grid.
    private var floatingStampyHUD: some View {
        HStack(alignment: .center, spacing: metrics.u(12)) {
            HStack(alignment: .center, spacing: metrics.u(10)) {
                VectorArtView(artwork: CanvasArt.stampy)
                    .frame(width: metrics.u(72), height: metrics.u(72))
                // scaleEffect does not shrink layout — pin a compact frame so the
                // bubble stays inside the HUD band and never covers the 4×2 cards.
                SpeechBubbleButton(prompt: .pickVideo, action: onSpeak)
                    .scaleEffect(0.58, anchor: .topLeading)
                    .frame(width: metrics.u(300), height: metrics.u(72), alignment: .topLeading)
            }
            Spacer(minLength: metrics.u(8))
            VectorArtView(artwork: ticket.artwork)
                .frame(width: metrics.u(110), height: metrics.u(70))
        }
        .frame(height: metrics.u(80), alignment: .center)
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var footerBar: some View {
        VStack(spacing: metrics.u(6)) {
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
        HStack(alignment: .center, spacing: metrics.u(10)) {
            if showsPager {
                pageArrow(direction: .previous, enabled: hasPrevPage) {
                    pageIndex = max(0, pageIndex - 1)
                }
            }

            GeometryReader { geo in
                let peekFraction: CGFloat = showsPager && hasNextPage ? 0.15 : 0
                let gap = metrics.u(10)
                let peekWidth = max(0, (geo.size.width - gap) * peekFraction)
                let mainWidth = geo.size.width - (peekWidth > 0 ? peekWidth + gap : 0)

                HStack(alignment: .center, spacing: gap) {
                    videoGrid(pageVideos)
                        .frame(width: mainWidth, height: geo.size.height)

                    if peekWidth > 0 {
                        videoGrid(nextPageVideos)
                            .frame(width: peekWidth * (1.0 / 0.15), height: geo.size.height, alignment: .leading)
                            .frame(width: peekWidth, alignment: .leading)
                            .clipped()
                            .opacity(0.55)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .overlay(alignment: .leading) {
                                // Soft edge so peek reads as “more this way”
                                LinearGradient(
                                    colors: [
                                        Color(hex: DesignTokens.Palette.sky).opacity(0.0),
                                        Color(hex: DesignTokens.Palette.sky).opacity(0.35)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: metrics.u(18))
                                .allowsHitTesting(false)
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsPager {
                pageArrow(direction: .next, enabled: hasNextPage) {
                    pageIndex = min(pageCount - 1, pageIndex + 1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// Deterministic 4×2 equal-width rows (no LazyVGrid — avoids intrinsic-width left cluster).
    /// Cards stretch to column width — **no 300u maxWidth cap** (v0.16.0).
    private func videoGrid(_ page: [ApprovedVideo]) -> some View {
        let gap = metrics.u(14)
        return VStack(spacing: metrics.u(12)) {
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private enum PageDirection { case previous, next }

    /// Giant kid 「仲有」 affordance — at least 96×160 artboard units.
    private func pageArrow(direction: PageDirection, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        let chevron = direction == .previous ? "chevron.left" : "chevron.right"
        let label = direction == .previous ? "仲有 · 上一頁" : "仲有 · 下一頁"
        return Button(action: action) {
            VStack(spacing: metrics.u(8)) {
                Image(systemName: chevron)
                    .font(.system(size: metrics.u(40), weight: .black))
                    .foregroundStyle(Color.ink)
                CanvasText("仲有", size: 22, weight: 900)
            }
            .frame(width: metrics.u(96), height: metrics.u(160))
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: Color(hex: enabled ? DesignTokens.Palette.sunny : DesignTokens.Palette.sand),
            cornerRadius: 28,
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
                    .accessibilityLabel("第 \(index + 1) 頁")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("影片頁 \(pageIndex + 1) / \(pageCount)")
    }

    private var continueBanner: some View {
        Button(action: { onContinue?() }) {
            HStack(spacing: metrics.u(16)) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: metrics.u(32), weight: .bold))
                    .foregroundStyle(Color.ink)
                CanvasText("繼續睇", size: 26, weight: 800)
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: metrics.u(24), weight: .bold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.horizontal, metrics.u(20))
            .padding(.vertical, metrics.u(12))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: Color(hex: DesignTokens.Palette.mint),
            cornerRadius: 22,
            shadowDepth: 6
        ))
        .accessibilityLabel("繼續睇")
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
            VStack(spacing: metrics.u(8)) {
                ZStack {
                    VideoPreviewThumbnail(video: video, ticket: ticket)
                    // Play badge so the card reads as "watch this" without text.
                    ZStack {
                        Circle().fill(Color(hex: DesignTokens.Palette.mint))
                        Circle().strokeBorder(Color.ink, lineWidth: metrics.u(3))
                        Image(systemName: "play.fill")
                            .font(.system(size: metrics.u(18), weight: .bold))
                            .foregroundStyle(Color.ink)
                            .offset(x: metrics.u(1))
                    }
                    .frame(width: metrics.u(48), height: metrics.u(48))
                }
                .aspectRatio(thumbAspect, contentMode: .fit)
                // v0.16.0: no 300u cap — stretch to column so 4×2 fills the right gutter.
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: metrics.u(12), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.u(12), style: .continuous)
                        .strokeBorder(Color.ink, lineWidth: metrics.u(3))
                )
                if let title {
                    Text(title)
                        .font(CanvasFont.font(size: metrics.u(16), weight: 800))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: metrics.u(3)) {
                        ForEach(0..<ticket.stars, id: \.self) { _ in
                            VectorArtView(artwork: CanvasArt.star)
                                .frame(width: metrics.u(16), height: metrics.u(16))
                        }
                    }
                    .frame(height: metrics.u(16))
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(metrics.u(10))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.paper),
                                       cornerRadius: 20, shadowDepth: 6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityLabel("揀呢條片：\(title ?? video.id)")
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
                .frame(width: metrics.u(120), height: metrics.u(76))
                .opacity(0.9)
        }
    }
}
