import AppKit
import SwiftUI
import VisaCore

// MARK: - Parent controls (v0.12.0)

/// Parent-authenticated settings. Rebuilt in v0.12.0: less text, canvas look (ink outlines,
/// chunky controls, canvas palette + fonts), allowlist as thumbnail cards, paste preview
/// before Add, and legalese / UAT tools folded into Advanced. Capabilities are unchanged:
/// theme, test 1-minute visa, test viewing budget, allowlist add / remove / preview, reset
/// entry activity, logs folder, storage reset, Return and Quit. Never reachable from the
/// child path except through the existing parent authentication (ADR 0007 §5).
struct ParentSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var showAdvanced = false

    /// Parent footer version (Info.plist `CFBundleShortVersionString` must match).
    static let versionLabel = "Visa Games v0.12.0"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    notices
                    quickActions
                    allowlistSection
                    advancedSection
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 940, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            bottomBar
        }
        .background(Color(hex: DesignTokens.Palette.paper).ignoresSafeArea())
        .environment(\.canvasMetrics, CanvasMetrics(scale: 1))
        .foregroundStyle(Color.ink)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VectorArtView(artwork: CanvasArt.stampy)
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                ParentLabel("家長設定", size: 30, weight: 900)
                ParentLabel("Parent controls", size: 16, weight: 700, color: .inkSoft)
            }
            Spacer(minLength: 12)
            ParentPill(text: "🔒 10 分鐘自動鎖 / Auto-lock 10 min", fill: Color(hex: DesignTokens.Palette.sky))
        }
    }

    // MARK: Notices (auth / storage first, then last action)

    @ViewBuilder
    private var notices: some View {
        if let message = model.message {
            ParentBanner(text: message, fill: Color(hex: DesignTokens.Palette.fireTicket))
        }
        if let playbackMessage = model.playbackMessage {
            ParentBanner(text: playbackMessage, fill: Color(hex: DesignTokens.Palette.taxiTicket))
        }
    }

    // MARK: Quick actions — test visa / budget + theme

    private var quickActions: some View {
        ParentSection(title: "測試同主題", subtitle: "Test & theme") {
            VStack(alignment: .leading, spacing: 16) {
                if !model.session.snapshot.configured {
                    ParentActionButton(
                        title: "完成設定", subtitle: "Finish setup", symbol: "checkmark.seal.fill",
                        fill: Color(hex: DesignTokens.Palette.mint), action: { model.setup() }
                    )
                } else {
                    HStack(spacing: 14) {
                        ParentActionButton(
                            title: "測試一分鐘簽證", subtitle: "Test 1-min visa", symbol: "timer",
                            fill: Color(hex: DesignTokens.Palette.sunny), action: { model.grant() }
                        )
                        ParentActionButton(
                            title: "測試觀看時間", subtitle: "Test viewing budget", symbol: "hourglass",
                            fill: Color(hex: DesignTokens.Palette.sunnyPale), action: { model.seedTestViewingBudget() }
                        )
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(ThemePaletteID.allCases, id: \.self) { palette in
                        ThemeChip(
                            pack: ThemePack.forID(palette),
                            selected: model.themePaletteID == palette,
                            action: { model.selectTheme(palette) }
                        )
                    }
                }
            }
        }
    }

    // MARK: Allowlist — paste preview + cards

    private var allowlistSection: some View {
        ParentSection(
            title: "准許影片",
            subtitle: "Allowlist · \(model.allowlist.videos.count)"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                pasteRow
                draftPreview
                addOverrides
                if let videoID = model.activePlayVideoID {
                    previewPlayer(videoID: videoID)
                }
                if model.allowlist.videos.isEmpty {
                    ParentLabel("未有影片，貼上連結加入。 / No videos yet — paste a link above.",
                                size: 16, weight: 600, color: .inkSoft)
                        .padding(.vertical, 8)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 18)],
                        alignment: .leading,
                        spacing: 22
                    ) {
                        ForEach(model.allowlist.videos) { video in
                            AllowlistVideoCard(
                                video: video,
                                isPlaying: model.activePlayVideoID == video.id,
                                onPlay: { _ = model.playAllowlisted(id: video.id) },
                                onDelete: { model.removeAllowlistedVideo(id: video.id) }
                            )
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private var hasAddOverride: Bool {
        !model.parentVideoTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || model.parentVideoDurationDraft.trimmingCharacters(in: .whitespacesAndNewlines) != "120"
    }

    /// New id → Add. Already listed → Update only when an Advanced override was typed
    /// (keeps the old re-add-to-rename capability without inviting accidental duplicates).
    private var addEnabled: Bool {
        guard !model.isFetchingAllowlistMetadata else { return false }
        switch model.parentDraftStatus {
        case .ready: return true
        case .alreadyAllowlisted: return hasAddOverride
        case .empty, .invalid: return false
        }
    }

    private var pasteRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.inkSoft)
            TextField("貼上 YouTube 網址或編號 / Paste YouTube URL or ID", text: $model.parentVideoIDDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 17, design: .rounded))
                .disabled(model.isFetchingAllowlistMetadata)
                .onSubmit { if addEnabled { model.addAllowlistedVideo() } }
            Button(action: { model.addAllowlistedVideo() }) {
                HStack(spacing: 6) {
                    if model.isFetchingAllowlistMetadata {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: model.parentDraftStatus.canAdd ? "plus" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 15, weight: .heavy))
                    }
                    ParentLabel(model.parentDraftStatus.canAdd || model.parentDraftStatus == .empty
                                ? "加入 Add" : "更新 Update", size: 16, weight: 800)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.mint),
                                           cornerRadius: 14, shadowDepth: 4, lineWidth: 3))
            .disabled(!addEnabled)
            .opacity(addEnabled ? 1 : 0.45)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .modifier(ChunkyPanel(fill: .white, cornerRadius: 16, shadowDepth: 4, lineWidth: 3))
    }

    @ViewBuilder
    private var draftPreview: some View {
        switch model.parentDraftStatus {
        case .empty:
            EmptyView()
        case .invalid:
            Label("認唔到呢條連結 / Not a YouTube video link", systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(hex: DesignTokens.Palette.stampRed))
        case .ready(let id), .alreadyAllowlisted(let id):
            HStack(alignment: .center, spacing: 14) {
                AllowlistThumbnail(videoID: id)
                    .frame(width: 176, height: 99)
                VStack(alignment: .leading, spacing: 6) {
                    if let title = model.parentDraftTitle {
                        Text(title)
                            .font(CanvasFont.font(size: 17, weight: 800))
                            .lineLimit(2)
                    } else if model.isFetchingDraftTitle {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            ParentLabel("取得片名中… / Fetching title…", size: 14, weight: 600, color: .inkSoft)
                        }
                    } else {
                        ParentLabel("未有片名 / No title found", size: 14, weight: 600, color: .inkSoft)
                    }
                    Text(id)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.inkSoft)
                    if case .alreadyAllowlisted = model.parentDraftStatus {
                        ParentPill(text: "已喺清單 / Already added", fill: Color(hex: DesignTokens.Palette.sand))
                    } else {
                        ParentPill(text: "預覽 / Preview — 撳「加入」 / press Add",
                                   fill: Color(hex: DesignTokens.Palette.mint).opacity(0.35))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.taxiTicket),
                                  cornerRadius: 16, shadowDepth: 4, lineWidth: 3))
        }
    }

    /// Optional per-add overrides (title / D4 budget-fit seconds). Same fields as before.
    private var addOverrides: some View {
        DisclosureGroup(isExpanded: $model.showAllowlistAdvanced) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("標題覆寫（可選） / Title override (optional)", text: $model.parentVideoTitleDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 460)
                    .disabled(model.isFetchingAllowlistMetadata)
                TextField("片長秒數（觀看預算） / Duration seconds (viewing budget)", text: $model.parentVideoDurationDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                    .disabled(model.isFetchingAllowlistMetadata)
                Text("預設 120 秒；卡上「~」= 未知真實片長。 / Default 120 s; “~” on a card = real length not known yet.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.inkSoft)
            }
            .padding(.top, 6)
        } label: {
            ParentLabel("片名／片長（可選） / Title & length (optional)", size: 14, weight: 700, color: .inkSoft)
        }
    }

    private func previewPlayer(videoID: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "play.tv.fill")
                ParentLabel(model.allowlist.video(id: videoID)?.parentListTitle ?? videoID,
                            size: 16, weight: 800, color: Color(hex: DesignTokens.Palette.paper))
                    .lineLimit(1)
                Spacer()
                Button(action: { model.stopParentPreview() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                        ParentLabel("停止 Stop", size: 14, weight: 800)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sand),
                                               cornerRadius: 12, shadowDepth: 3, lineWidth: 3))
            }
            ScopedPlayerView(
                videoID: videoID,
                onNavigationRejected: { model.stopScopedPlayback(reason: .navigationRejected) },
                onPlaybackEnded: { model.handleScopedPlaybackEnded(videoID: $0) },
                onDurationKnown: { model.recordPlayerDuration(videoID: $0, seconds: $1) }
            )
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.ink, lineWidth: 3))
        }
        .padding(12)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.ink), cornerRadius: 18,
                              shadowDepth: 4, lineWidth: 3))
        .foregroundStyle(Color(hex: DesignTokens.Palette.paper))
    }

    // MARK: Advanced — UAT tools, storage, legal

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 14) {
                Text("入口遊戲已開（兩圖／搵相同／數車／車隊排序）。YouTube 內容包仍待家長 D9 審核。 / Entry games live (two-picture / find-same / count / convoy order). YouTube pack still parent D9.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    ParentSmallButton(title: "重設入口活動（兒童 UAT）/ Reset entry activity (child UAT)",
                                      symbol: "arrow.counterclockwise",
                                      action: { model.resetEntryActivityForChildUAT() })
                    ParentSmallButton(title: "開啟日誌資料夾 / Open logs folder",
                                      symbol: "folder",
                                      action: { model.openScopedPlayerLogsFolder() })
                }
                // Same confirmation as the top banner, next to the UAT buttons (no scrolling back).
                if let playbackMessage = model.playbackMessage {
                    Text(playbackMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.message != nil {
                    ParentSmallButton(title: "清除簽證及重設儲存 / Clear visa and reset storage",
                                      symbol: "trash",
                                      fill: Color(hex: DesignTokens.Palette.fireTicket),
                                      action: { model.resetStorage() })
                }
                ParentLicenseFooter()
            }
            .padding(.top, 10)
        } label: {
            ParentLabel("進階 / Advanced", size: 18, weight: 800)
        }
        .padding(16)
        .modifier(ChunkyPanel(fill: .white, cornerRadius: 18, shadowDepth: 4, lineWidth: 3))
    }

    // MARK: Pinned bottom bar — Return always visible

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Button(action: { model.returnToChild() }) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18, weight: .heavy))
                    ParentLabel("返回 Return", size: 20, weight: 900)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 10)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.mint),
                                           cornerRadius: 18, shadowDepth: 5, lineWidth: 3))
            .accessibilityLabel("返回 Return")

            Spacer()

            Text(Self.versionLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.inkSoft)

            Button(action: { model.quitFromParent() }) {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                    ParentLabel("離開程式 Quit", size: 14, weight: 800)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.fireTicket),
                                           cornerRadius: 12, shadowDepth: 3, lineWidth: 3))
            .accessibilityLabel("離開程式 Quit app")
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(
            Color(hex: DesignTokens.Palette.sand)
                .overlay(Rectangle().fill(Color.ink).frame(height: 3), alignment: .top)
                .ignoresSafeArea()
        )
    }
}

// MARK: - Building blocks

/// Canvas-font text for parent screens (wraps, unlike the one-line `CanvasText`).
private struct ParentLabel: View {
    let text: String
    let size: CGFloat
    let weight: Int
    var color: Color = .ink

    init(_ text: String, size: CGFloat, weight: Int, color: Color = .ink) {
        self.text = text
        self.size = size
        self.weight = weight
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(CanvasFont.font(size: size, weight: weight))
            .foregroundStyle(color)
    }
}

private struct ParentPill: View {
    let text: String
    let fill: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(Color.ink, lineWidth: 2))
    }
}

private struct ParentBanner: View {
    let text: String
    let fill: Color

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .modifier(ChunkyPanel(fill: fill, cornerRadius: 14, shadowDepth: 3, lineWidth: 3))
    }
}

/// Section heading (HK Trad big, English small) above a white chunky panel.
private struct ParentSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                ParentLabel(title, size: 22, weight: 900)
                ParentLabel(subtitle, size: 14, weight: 700, color: .inkSoft)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .modifier(ChunkyPanel(fill: .white, cornerRadius: 20, shadowDepth: 5, lineWidth: 3))
        }
    }
}

private struct ParentActionButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .heavy))
                VStack(alignment: .leading, spacing: 0) {
                    ParentLabel(title, size: 17, weight: 900)
                    ParentLabel(subtitle, size: 12, weight: 700, color: .inkSoft)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(ChunkyButtonStyle(fill: fill, cornerRadius: 16, shadowDepth: 5, lineWidth: 3))
        .accessibilityLabel("\(title) \(subtitle)")
    }
}

private struct ParentSmallButton: View {
    let title: String
    let symbol: String
    var fill: Color = Color(hex: DesignTokens.Palette.paper)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .buttonStyle(ChunkyButtonStyle(fill: fill, cornerRadius: 12, shadowDepth: 3, lineWidth: 2))
    }
}

private struct ThemeChip: View {
    let pack: ThemePack
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color(rgb: pack.sand))
                    Circle().fill(Color(rgb: pack.accent)).padding(6)
                    Circle().strokeBorder(Color.ink, lineWidth: 2)
                }
                .frame(width: 28, height: 28)
                Text(pack.parentLabel)
                    .font(.system(size: 13, weight: selected ? .heavy : .semibold, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: DesignTokens.Palette.mint))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: selected ? Color(hex: DesignTokens.Palette.sunnyPale) : Color(hex: DesignTokens.Palette.paper),
            cornerRadius: 14, shadowDepth: selected ? 2 : 4, lineWidth: selected ? 3 : 2
        ))
        .accessibilityLabel(pack.parentLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One allowlisted video: thumbnail + duration chip, title, Preview + Delete.
private struct AllowlistVideoCard: View {
    let video: ApprovedVideo
    let isPlaying: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onPlay) {
                ZStack(alignment: .bottomTrailing) {
                    AllowlistThumbnail(videoID: video.id)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .contentShape(Rectangle())
                        .overlay(
                            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.circle.fill")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.92))
                                .shadow(color: .black.opacity(0.4), radius: 4)
                        )
                    Text(video.parentDurationLabel)
                        .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(8)
                        .help(video.hasPlayerDuration
                              ? "片長 / Length"
                              : "未知真實片長（觀看預算 \(Int(video.durationSeconds)) 秒） / Real length unknown (budget \(Int(video.durationSeconds)) s)")
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("試播 \(video.parentListTitle) / Preview")

            Text(video.parentListTitle)
                .font(CanvasFont.font(size: 15, weight: 800))
                .foregroundStyle(Color.ink)
                .lineLimit(2, reservesSpace: true)
                .help(video.id)

            HStack(spacing: 10) {
                Button(action: onPlay) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                        Text("試播 Preview")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sunny),
                                               cornerRadius: 12, shadowDepth: 3, lineWidth: 2))
                Spacer()
                Button { confirmDelete = true } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.fireTicketHeader),
                                               cornerRadius: 12, shadowDepth: 3, lineWidth: 2))
                .accessibilityLabel("移除 \(video.parentListTitle) / Remove")
                .confirmationDialog(
                    "移除呢條片？ / Remove this video?",
                    isPresented: $confirmDelete
                ) {
                    Button("移除 / Remove", role: .destructive, action: onDelete)
                    Button("取消 / Cancel", role: .cancel) {}
                } message: {
                    Text(video.parentListTitle)
                }
            }
        }
        .padding(12)
        .modifier(ChunkyPanel(
            fill: isPlaying ? Color(hex: DesignTokens.Palette.sunnyPale) : Color(hex: DesignTokens.Palette.paper),
            cornerRadius: 18, shadowDepth: 5, lineWidth: 3
        ))
    }
}

/// Parent-only thumbnail: YouTube thumbnail CDN via AsyncImage (never child playback).
/// Network failure / invalid id → placeholder (never crash). Fills its frame.
private struct AllowlistThumbnail: View {
    let videoID: String

    var body: some View {
        ZStack {
            Color(hex: DesignTokens.Palette.glass)
            if let url = YouTubeEmbedURL.thumbnailURL(videoID: videoID) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .empty:
                        ProgressView().controlSize(.small)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.ink, lineWidth: 2))
        .accessibilityLabel("預覽圖 / Preview")
    }

    private var placeholder: some View {
        Image(systemName: "play.rectangle.fill")
            .font(.system(size: 26))
            .foregroundStyle(Color.inkSoft)
    }
}

/// Parent-visible home-use + original-art license note (HK Trad + English).
/// Names third-party companies only here for non-affiliation clarity — never on the child path.
private struct ParentLicenseFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("關於插圖／版權說明 / About artwork & license")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text("本應用程式僅作家中教育用途。畫面上嘅插圖同友善車輛角色均為原創作品，並非任何第三方商標角色。本應用程式與 Takara Tomy、HIT Entertainment、Mattel 或其他玩具／動畫品牌無關，亦無授權關係。家中免責聲明並不授予使用第三方角色肖像嘅權利。")
                .font(.system(size: 13, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text("This app is for home educational use. On-screen art and friendly vehicle characters are original works, not third-party trademark characters. Visa Games is not affiliated with Takara Tomy, HIT Entertainment, Mattel, or other toy/animation brands. A home-use disclaimer does not grant rights to use third-party character likenesses.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.ink.opacity(0.05))
        )
        .accessibilityLabel("Artwork and license notice")
    }
}
