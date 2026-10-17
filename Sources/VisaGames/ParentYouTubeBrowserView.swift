import AppKit
import SwiftUI
import VisaCore
import WebKit

// MARK: - Parent in-app YouTube finder (v0.27.1, ADR 0016; Opus mockups 01, 06–10)

/// Full-page YouTube finder drawn over the parent view, inside the same kiosk window.
/// Opening or closing it changes no window style, level, frame or presentation options
/// (ADR 0011). Parent-authenticated only; the child path never reaches it (ADR 0003).
/// The video id always comes from the page URL, so adding works even behind a bot check.
struct ParentYouTubeBrowserView: View {
    @ObservedObject var model: AppModel
    @StateObject private var browser = ParentBrowserController()
    @State private var searchText = ""
    @State private var botCheckPaste = ""
    @FocusState private var searchFocused: Bool

    private var confirmOpen: Bool { model.parentFinder.confirmVideoID != nil }

    private var page: ParentYouTubePage {
        browser.showingStart ? .startPage : ParentYouTubeBrowser.page(for: browser.currentURL)
    }

    private var addBar: ParentYouTubeAddBar {
        ParentYouTubeBrowser.addBar(page: page, liveDetected: browser.liveDetected, allowlist: model.allowlist)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                VStack(spacing: 0) {
                    toolbar
                    if let notice = browser.notice {
                        ParentBanner(text: notice, fill: Color(hex: DesignTokens.Palette.taxiTicket),
                                     onDismiss: { browser.notice = nil })
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                    }
                    if browser.botCheck && !browser.showingStart {
                        botCheckBanner
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                    }
                    ZStack {
                        ParentWebViewHost(webView: browser.webView)
                        if browser.showingStart {
                            startPage
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.ink, lineWidth: 3))
                    .padding(.horizontal, 20)
                    ZStack(alignment: .topLeading) {
                        addBarPanel
                        if let toast = model.parentFinder.visibleToast(now: model.now) {
                            toastView(toast)
                                .offset(x: 24, y: -58)
                        }
                    }
                    .padding(20)
                }
                if confirmOpen {
                    Color.ink.opacity(0.45)
                    confirmSheet
                }
            }
        }
        .background(Color(hex: DesignTokens.Palette.paper).ignoresSafeArea())
        .foregroundStyle(Color.ink)
        .background(shortcutButtons)
        .onAppear {
            let owner = model
            browser.onActivity = { [weak owner] in owner?.noteParentBrowserActivity() }
            browser.setAllowedIDs(model.allowlist.videos.map(\.id))
            searchFocused = true
        }
        .onChange(of: model.allowlist) { list in
            browser.setAllowedIDs(list.videos.map(\.id))
        }
        .onDisappear { browser.shutdown() }
    }

    // MARK: Top bar (01: 返回 · title · countdown · version · 離開程式)

    private var topBar: some View {
        ZStack {
            HStack(spacing: 14) {
                Button(action: { browser.pauseMedia(); model.returnToChild() }) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 18, weight: .heavy))
                        ParentLabel("返回 Return", size: 20, weight: 900)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.mint),
                                               cornerRadius: 18, shadowDepth: 5, lineWidth: 3))
                .accessibilityLabel("返回 Return")
                Spacer()
                if let remaining = model.parentAutoLockRemaining {
                    let label = ParentYouTubeBrowser.autoLockLabel(remaining: remaining)
                    ParentPill(text: "🔒 \(label) 後自動鎖 / Auto-lock in \(label)",
                               fill: Color(hex: DesignTokens.Palette.sky))
                }
                Text(ParentSettingsView.versionLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.inkSoft)
                Button(action: { browser.pauseMedia(); model.quitFromParent() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "power")
                        ParentLabel("離開程式 Quit", size: 14, weight: 800)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.fireTicket),
                                               cornerRadius: 12, shadowDepth: 3, lineWidth: 3))
            }
            HStack(spacing: 10) {
                VectorArtView(artwork: CanvasArt.stampy)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    ParentLabel("喺 YouTube 搵片", size: 22, weight: 900)
                    ParentLabel("Find on YouTube · parent only", size: 12, weight: 700, color: .inkSoft)
                }
            }
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(
            Color(hex: DesignTokens.Palette.sand)
                .overlay(Rectangle().fill(Color.ink).frame(height: 3), alignment: .bottom)
                .ignoresSafeArea()
        )
    }

    // MARK: Toolbar (back · forward · 首頁 · 重新載入 · search · A− 125% A+ · 完成)

    private var toolbar: some View {
        HStack(spacing: 10) {
            iconButton("chevron.left", label: "上一頁 Back", enabled: browser.canGoBackUI) { browser.goBack() }
            iconButton("chevron.right", label: "下一頁 Forward", enabled: browser.canGoForwardUI) { browser.goForward() }
            labelButton("house.fill", "首頁", "Home", highlighted: browser.showingStart) {
                browser.showStart()
                searchFocused = true
            }
            labelButton("arrow.clockwise", "重新載入", "Reload", highlighted: browser.botCheck && !browser.showingStart,
                        enabled: !browser.showingStart) { browser.reload() }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.inkSoft)
                TextField("搜尋 YouTube，或者貼上連結 / Search YouTube or paste a link", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, design: .rounded))
                    .focused($searchFocused)
                    .onSubmit { submitSearch() }
                if browser.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button(action: { submitSearch() }) {
                    ParentLabel("搜尋 Search", size: 14, weight: 800)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sunny),
                                               cornerRadius: 10, shadowDepth: 2, lineWidth: 2))
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .modifier(ChunkyPanel(fill: .white, cornerRadius: 14, shadowDepth: 3, lineWidth: 3))
            HStack(spacing: 0) {
                Button(action: { browser.zoom(by: -1) }) {
                    ParentLabel("A −", size: 14, weight: 800).frame(width: 40, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("字細啲 Smaller text")
                Rectangle().fill(Color.ink).frame(width: 2, height: 30)
                ParentLabel("字 \(ParentFinderZoom.label(browser.zoomValue))", size: 13, weight: 800)
                    .frame(width: 72)
                Rectangle().fill(Color.ink).frame(width: 2, height: 30)
                Button(action: { browser.zoom(by: 1) }) {
                    ParentLabel("A ＋", size: 14, weight: 800).frame(width: 40, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("字大啲 Larger text")
            }
            .padding(.vertical, 2)
            .modifier(ChunkyPanel(fill: .white, cornerRadius: 12, shadowDepth: 3, lineWidth: 3))
            Button(action: { close() }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .heavy))
                    VStack(alignment: .leading, spacing: 0) {
                        ParentLabel("完成，返去清單", size: 15, weight: 900)
                        ParentLabel("Done · back to list", size: 11, weight: 600, color: .inkSoft)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sunny),
                                           cornerRadius: 12, shadowDepth: 3, lineWidth: 3))
            .accessibilityLabel("完成，返去清單 / Done")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .disabled(confirmOpen)
    }

    private func iconButton(_ symbol: String, label: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .heavy))
                .frame(width: 34, height: 30)
        }
        .buttonStyle(ChunkyButtonStyle(fill: .white, cornerRadius: 12, shadowDepth: 3, lineWidth: 3))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    private func labelButton(_ symbol: String, _ zh: String, _ en: String, highlighted: Bool = false,
                             enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .heavy))
                ParentLabel(zh, size: 14, weight: 800)
                ParentLabel(en, size: 11, weight: 600, color: .inkSoft)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(ChunkyButtonStyle(fill: highlighted ? Color(hex: DesignTokens.Palette.sunny) : .white,
                                       cornerRadius: 12, shadowDepth: 3, lineWidth: 3))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel("\(zh) \(en)")
    }

    /// ⌘F / ⌘L search box, ⌘[ / ⌘] back / forward, ⌘R reload. ⌘↩ sits on the add bar.
    private var shortcutButtons: some View {
        ZStack {
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command)
            Button("") { searchFocused = true }.keyboardShortcut("l", modifiers: .command)
            Button("") { browser.goBack() }.keyboardShortcut("[", modifiers: .command)
            Button("") { browser.goForward() }.keyboardShortcut("]", modifiers: .command)
            Button("") { browser.reload() }.keyboardShortcut("r", modifiers: .command)
        }
        .disabled(confirmOpen)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: Start page (10; the app's own, never YouTube's feed)

    private var startPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    VectorArtView(artwork: CanvasArt.stampy)
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        ParentLabel("今日想搵咩片？", size: 32, weight: 900)
                        ParentLabel("What are we looking for today?", size: 15, weight: 700, color: .inkSoft)
                    }
                }
                if !model.parentRecentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            ParentLabel("最近搜尋", size: 17, weight: 900)
                            ParentLabel("Recent searches", size: 12, weight: 600, color: .inkSoft)
                            Spacer()
                            Button(action: { model.clearParentRecentSearches() }) {
                                ParentLabel("清除 Clear", size: 12, weight: 700, color: .inkSoft)
                            }
                            .buttonStyle(.plain)
                        }
                        HStack(spacing: 10) {
                            ForEach(model.parentRecentSearches, id: \.self) { query in
                                Button(action: { searchText = query; submitSearch() }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "clock.arrow.circlepath")
                                        Text(query).lineLimit(1)
                                    }
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.taxiTicket),
                                                               cornerRadius: 14, shadowDepth: 3, lineWidth: 2))
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ParentLabel("已經有條連結？", size: 17, weight: 900)
                        ParentLabel("Already have a link?", size: 12, weight: 600, color: .inkSoft)
                    }
                    HStack(spacing: 14) {
                        keycap("⌘")
                        ParentLabel("+", size: 18, weight: 900)
                        keycap("V")
                        VStack(alignment: .leading, spacing: 2) {
                            ParentLabel("喺上面搜尋格貼上，即刻開嗰條片", size: 16, weight: 800)
                            ParentLabel("Paste into the search box above: the video opens straight away",
                                        size: 12, weight: 600, color: .inkSoft)
                            ParentLabel("（iPhone 複製都得：通用剪貼板）", size: 12, weight: 600, color: .inkSoft)
                        }
                        Spacer(minLength: 8)
                        Button(action: { pasteIntoSearch() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.clipboard")
                                ParentLabel("貼上 Paste", size: 14, weight: 800)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(ChunkyButtonStyle(fill: .white, cornerRadius: 12, shadowDepth: 3, lineWidth: 3))
                    }
                    .padding(16)
                    .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.taxiTicket), cornerRadius: 16,
                                          shadowDepth: 3, lineWidth: 3))
                }
                VStack(alignment: .leading, spacing: 6) {
                    ParentLabel("點解唔顯示 YouTube 首頁？", size: 16, weight: 900)
                    ParentLabel("YouTube 首頁會推介咩都有，電視咁大，小朋友喺隔籬都會見到。", size: 14, weight: 600)
                    ParentLabel("所以開始頁係 app 自己畫：只有你嘅搜尋。", size: 14, weight: 600)
                    ParentLabel("YouTube’s home feed recommends anything, and the TV is big — the child sees it too.",
                                size: 12, weight: 600, color: .inkSoft)
                    ParentLabel("按「首頁」都係返嚟呢度，唔會開 youtube.com 首頁。 / Home always comes back here.",
                                size: 12, weight: 600, color: .inkSoft)
                }
                .padding(16)
                .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.hubcap), cornerRadius: 16,
                                      shadowDepth: 2, lineWidth: 2))
            }
            .padding(32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(hex: DesignTokens.Palette.paper))
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ink, lineWidth: 3))
    }

    // MARK: Bot check (06; the app's own banner, the page's Sign in stays off)

    private var botCheckBanner: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        ParentLabel("YouTube 要求驗證，呢度暫時播唔到片（唔係你撳錯嘢）", size: 18, weight: 900)
                        ParentLabel("YouTube is asking to check this isn’t a bot, so videos won’t play here for now. Nothing you did.",
                                    size: 12, weight: 600, color: .inkSoft)
                    }
                }
                ParentLabel("多數係因為 Mac mini 開咗 VPN（NordVPN），或者短時間開咗好多條片。", size: 14, weight: 600)
                ParentLabel("Usually the Mac mini’s VPN exit, or many videos opened in a short time.",
                            size: 12, weight: 600, color: .inkSoft)
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "link").foregroundStyle(Color.inkSoft)
                        TextField("貼上 YouTube 網址或編號 / Paste YouTube URL or ID", text: $botCheckPaste)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, design: .rounded))
                            .onSubmit { takePastedLink() }
                        Button(action: { takePastedLink() }) {
                            ParentLabel("加入 Add", size: 13, weight: 800)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.mint),
                                                       cornerRadius: 10, shadowDepth: 2, lineWidth: 2))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .modifier(ChunkyPanel(fill: .white, cornerRadius: 12, shadowDepth: 2, lineWidth: 2))
                    .frame(maxWidth: 480)
                    VStack(alignment: .leading, spacing: 0) {
                        ParentLabel("後備：手機複製連結，喺度 ⌘V", size: 12, weight: 700)
                        ParentLabel("Fallback: copy on the phone, Cmd-V here", size: 11, weight: 600, color: .inkSoft)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ParentLabel("可以試：", size: 15, weight: 900)
                botTip("1", "試吓熄 VPN，或者換另一個伺服器", "Turn the VPN off, or switch server")
                botTip("2", "等幾分鐘，再撳「重新載入」", "Wait a few minutes, then Reload")
                botTip("3", "用手機複製條連結，貼喺左邊", "Copy the link on your phone, paste it on the left")
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { browser.reload() }) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20, weight: .heavy))
                        VStack(alignment: .leading, spacing: 0) {
                            ParentLabel("重新載入", size: 20, weight: 900)
                            ParentLabel("Reload", size: 12, weight: 700, color: .inkSoft)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sunny),
                                               cornerRadius: 16, shadowDepth: 5, lineWidth: 3))
                ParentLabel("網頁「Sign in」已停用", size: 12, weight: 800)
                ParentLabel("The page’s Sign in is off here — no Google sign-in on the kiosk.",
                            size: 11, weight: 600, color: .inkSoft)
                    .frame(maxWidth: 230, alignment: .leading)
            }
        }
        .padding(16)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.taxiTicket), cornerRadius: 16,
                              shadowDepth: 4, lineWidth: 3))
    }

    private func botTip(_ number: String, _ zh: String, _ en: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(CanvasFont.font(size: 13, weight: 900))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color(hex: DesignTokens.Palette.sunny)))
                .overlay(Circle().strokeBorder(Color.ink, lineWidth: 2))
            VStack(alignment: .leading, spacing: 0) {
                ParentLabel(zh, size: 14, weight: 700)
                ParentLabel(en, size: 11, weight: 600, color: .inkSoft)
            }
        }
    }

    // MARK: Add bar (01 / 06 / 07 / 09 / 10)

    private var addBarPanel: some View {
        let state = addBar
        return HStack(spacing: 18) {
            addBarLeading(state)
            VStack(alignment: .leading, spacing: 5) {
                addBarText(state)
            }
            Spacer(minLength: 8)
            addBarMiddle(state)
            addBarButton(state)
        }
        .padding(14)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.taxiTicket), cornerRadius: 18,
                              shadowDepth: 4, lineWidth: 3))
    }

    @ViewBuilder
    private func addBarLeading(_ state: ParentYouTubeAddBar) -> some View {
        if let id = currentVideoID {
            ZStack(alignment: .bottomTrailing) {
                AllowlistThumbnail(videoID: id)
                if let seconds = browser.pageDuration {
                    Text(ApprovedVideo.clockLabel(seconds: seconds))
                        .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(5)
                }
            }
            .frame(width: 136, height: 77)
        } else {
            Image(systemName: browser.showingStart ? "play" : "magnifyingglass")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.inkSoft)
                .frame(width: 136, height: 77)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: DesignTokens.Palette.hubcap)))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.ink, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        }
    }

    private var currentVideoID: String? {
        if case .video(let id) = page { return id }
        return nil
    }

    @ViewBuilder
    private func addBarText(_ state: ParentYouTubeAddBar) -> some View {
        if let id = currentVideoID {
            Text(browser.pageTitle ?? model.allowlist.video(id: id)?.parentListTitle ?? "YouTube")
                .font(CanvasFont.font(size: 19, weight: 900))
                .lineLimit(1)
            HStack(spacing: 6) {
                if let channel = browser.channel {
                    ParentLabel("\(channel) ·", size: 12, weight: 700, color: .inkSoft)
                }
                Text(id).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.inkSoft)
                if let seconds = browser.pageDuration {
                    ParentLabel("· 片長 \(ApprovedVideo.clockLabel(seconds: seconds))", size: 12, weight: 700, color: .inkSoft)
                } else {
                    ParentLabel("· 片長未知 length unknown (~2:00)", size: 12, weight: 700, color: .inkSoft)
                }
            }
            switch state {
            case .ready where browser.botCheck:
                HStack(spacing: 8) {
                    ParentPill(text: "片編號已攞到，照樣加得 / ID found — can still add",
                               fill: Color(hex: DesignTokens.Palette.mint).opacity(0.45))
                    ParentLabel("小朋友嗰邊可能都播唔到，直至 VPN 熄咗 · may not play for your child until then",
                                size: 11, weight: 600, color: .inkSoft)
                }
            case .ready:
                ParentPill(text: "未喺清單 / Not in your list yet", fill: .white)
            case .alreadyAdded(let addedID):
                let line = ParentYouTubeBrowser.alreadyAddedLine(
                    cardNumber: model.allowlist.cardNumber(id: addedID) ?? 1,
                    addedAt: model.allowlist.video(id: addedID)?.addedAt)
                ParentPill(text: "✓ \(line.zh) / \(line.en)", fill: Color(hex: DesignTokens.Palette.mint).opacity(0.45))
            case .unsupported, .pickVideo:
                ParentPill(text: "\(state.title) / \(state.subtitle)", fill: Color(hex: DesignTokens.Palette.hubcap))
            }
        } else if browser.showingStart {
            ParentLabel("未揀片", size: 19, weight: 900)
            ParentLabel("No video open yet", size: 12, weight: 600, color: .inkSoft)
            ParentLabel("搜尋，或者貼上連結 · search or paste a link", size: 13, weight: 700)
        } else if case .unsupported = state {
            ParentLabel(state.title, size: 19, weight: 900)
            ParentLabel(state.subtitle, size: 12, weight: 600, color: .inkSoft)
            ParentLabel("撳返一條普通片就加得 · open a normal video to add it", size: 13, weight: 700)
        } else {
            if let query = browser.searchQuery {
                ParentLabel("搜尋結果：「\(query)」", size: 19, weight: 900)
                ParentLabel("Search results — no single video on this page", size: 12, weight: 600, color: .inkSoft)
            } else {
                ParentLabel("呢頁冇單一條片", size: 19, weight: 900)
                ParentLabel("No single video on this page", size: 12, weight: 600, color: .inkSoft)
            }
            ParentLabel("撳任何一條片打開佢，就加得 · open any video, then add it", size: 13, weight: 700)
        }
    }

    @ViewBuilder
    private func addBarMiddle(_ state: ParentYouTubeAddBar) -> some View {
        switch state {
        case .ready:
            VStack(alignment: .trailing, spacing: 0) {
                ParentLabel("准許影片 · \(model.allowlist.videos.count)", size: 14, weight: 800)
                ParentLabel("Allowlist · \(model.allowlist.videos.count)", size: 11, weight: 600, color: .inkSoft)
            }
        case .alreadyAdded(let id):
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { browser.pauseMedia(); model.showCardFromFinder(videoID: id) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle")
                        VStack(alignment: .leading, spacing: 0) {
                            ParentLabel("睇吓張卡", size: 15, weight: 900)
                            ParentLabel("Show card in the list", size: 11, weight: 600, color: .inkSoft)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                }
                .buttonStyle(ChunkyButtonStyle(fill: .white, cornerRadius: 12, shadowDepth: 3, lineWidth: 3))
                Button(action: { beginConfirm(id) }) {
                    ParentLabel("更新片名／片長 › · Update title & length", size: 12, weight: 700, color: .inkSoft)
                }
                .buttonStyle(.plain)
            }
        case .pickVideo, .unsupported:
            EmptyView()
        }
    }

    private func addBarButton(_ state: ParentYouTubeAddBar) -> some View {
        let fill: Color
        let symbol: String
        switch state {
        case .ready:
            fill = Color(hex: DesignTokens.Palette.mint)
            symbol = "plus"
        case .alreadyAdded:
            fill = Color(hex: DesignTokens.Palette.mint).opacity(0.3)
            symbol = "checkmark.circle"
        case .pickVideo, .unsupported:
            fill = Color(hex: DesignTokens.Palette.hubcap)
            symbol = "play"
        }
        let title: String
        switch state {
        case .ready: title = "加入呢條片"
        case .alreadyAdded: title = "已經加咗"
        default: title = state.title
        }
        return Button(action: { add(state) }) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .heavy))
                VStack(alignment: .leading, spacing: 0) {
                    ParentLabel(title, size: state.title.count > 8 ? 20 : 28, weight: 900,
                                color: state.isEnabled || state.videoID != nil ? .ink : .inkSoft)
                    ParentLabel(state.subtitle, size: 12, weight: 700, color: .inkSoft)
                }
            }
            .frame(width: 300, height: 66)
        }
        .buttonStyle(ChunkyButtonStyle(fill: fill, cornerRadius: 18, shadowDepth: state.isEnabled ? 5 : 2,
                                       lineWidth: 3))
        .disabled(!state.isEnabled || confirmOpen)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel("\(state.title) / \(state.subtitle)")
    }

    private func toastView(_ toast: ParentFinderState.Toast) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .bold))
            ParentLabel("已加入 · 准許影片而家 \(toast.allowlistCount) 條", size: 16, weight: 900)
            ParentLabel("Added · allowlist now \(toast.allowlistCount)", size: 11, weight: 600, color: .inkSoft)
            Button(action: { browser.pauseMedia(); model.showCardFromFinder(videoID: toast.videoID) }) {
                ParentLabel("睇吓張卡 ›", size: 13, weight: 800)
            }
            .buttonStyle(.plain)
            Button(action: { model.undoFinderAdd() }) {
                ParentLabel("復原 Undo", size: 13, weight: 800)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
            }
            .buttonStyle(ChunkyButtonStyle(fill: .white, cornerRadius: 10, shadowDepth: 2, lineWidth: 2))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.mint), cornerRadius: 14,
                              shadowDepth: 3, lineWidth: 3))
    }

    // MARK: Confirm card over the finder (08)

    private var confirmSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        ParentLabel("加入准許影片？", size: 24, weight: 900)
                        ParentLabel("Add to the allowlist?", size: 13, weight: 700, color: .inkSoft)
                    }
                    Spacer()
                    ParentPill(text: "⏸ 網頁影片已暫停 · video paused", fill: Color(hex: DesignTokens.Palette.sky))
                }
                confirmPreviewRow
                confirmLengthLine
                confirmEmbedLine
                VStack(alignment: .leading, spacing: 8) {
                    ParentLabel("片名／片長（可選） / Title & length (optional)", size: 14, weight: 800, color: .inkSoft)
                    TextField("標題覆寫（可選） / Title override (optional)", text: $model.parentVideoTitleDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 460)
                    HStack(spacing: 10) {
                        TextField("片長秒數 / Duration seconds", text: $model.parentVideoDurationDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                        if let seconds = TimeInterval(model.parentVideoDurationDraft.trimmingCharacters(in: .whitespaces)),
                           seconds > 0 {
                            ParentLabel("秒 ＝ \(ApprovedVideo.clockLabel(seconds: seconds))"
                                        + (model.parentDraftLengthLabel != nil ? "（由網頁填好） · filled in from the page" : ""),
                                        size: 13, weight: 700, color: .inkSoft)
                        }
                    }
                    Text("預設 120 秒；卡上「~」= 未知真實片長。 / Default 120 s; “~” on a card = real length not known yet.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.inkSoft)
                }
                HStack(spacing: 14) {
                    Button(action: { model.cancelFinderConfirm() }) {
                        VStack(spacing: 0) {
                            ParentLabel("取消", size: 17, weight: 900)
                            ParentLabel("Cancel", size: 11, weight: 600, color: .inkSoft)
                        }
                        .frame(width: 110, height: 52)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: .white, cornerRadius: 14, shadowDepth: 3, lineWidth: 3))
                    .keyboardShortcut(.cancelAction)
                    Button(action: { toggleTrial() }) {
                        HStack(spacing: 8) {
                            Image(systemName: isTrialPlaying ? "stop.fill" : "play.fill")
                            VStack(alignment: .leading, spacing: 0) {
                                ParentLabel(isTrialPlaying ? "停止試播" : "試播（小朋友播放器）", size: 16, weight: 900)
                                ParentLabel(isTrialPlaying ? "Stop preview" : "Preview in your child’s player",
                                            size: 11, weight: 600, color: .inkSoft)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sunny),
                                                   cornerRadius: 14, shadowDepth: 4, lineWidth: 3))
                    Spacer()
                    Button(action: { model.confirmFinderAdd() }) {
                        HStack(spacing: 10) {
                            if model.isFetchingAllowlistMetadata {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: isUpdate ? "arrow.triangle.2.circlepath" : "plus")
                                    .font(.system(size: 24, weight: .heavy))
                            }
                            ParentLabel(isUpdate ? "更新 Update" : "加入 Add", size: 22, weight: 900)
                        }
                        .frame(width: 220, height: 56)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.mint),
                                                   cornerRadius: 16, shadowDepth: 5, lineWidth: 3))
                    .disabled(!model.finderConfirmCanAdd)
                    .opacity(model.finderConfirmCanAdd ? 1 : 0.45)
                    .keyboardShortcut(.defaultAction)
                }
                if let trialID = model.parentDraftTrialVideoID, trialID == model.parentDraftStatus.videoID {
                    ScopedPlayerView(
                        videoID: trialID,
                        onNavigationRejected: { model.stopDraftTrial() },
                        onPlaybackEnded: { _ in model.stopDraftTrial() },
                        onDurationKnown: { model.noteDraftTrialDuration(videoID: $0, seconds: $1) },
                        onCurrentTime: nil,
                        onProviderBlocked: { id, _ in model.handleDraftTrialBlocked(videoID: id) }
                    )
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ink, lineWidth: 3))
                }
                VStack(alignment: .leading, spacing: 2) {
                    ParentLabel("加完：留喺 YouTube 繼續搵。新卡排喺清單最尾，返去清單時會閃一閃。", size: 12, weight: 700)
                    ParentLabel("After Add you stay in the finder. The card goes to the end of the list and flashes on return.",
                                size: 11, weight: 600, color: .inkSoft)
                    ParentLabel("鍵盤：Return ＝ 加入　Esc ＝ 取消 · keyboard: Return adds, Esc cancels",
                                size: 11, weight: 600, color: .inkSoft)
                }
            }
            .padding(22)
            .frame(width: 860, alignment: .leading)
            .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.paper), cornerRadius: 22,
                                  shadowDepth: 6, lineWidth: 3))
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
        }
    }

    private var isUpdate: Bool {
        if case .alreadyAllowlisted = model.parentDraftStatus { return true }
        return false
    }

    private var isTrialPlaying: Bool {
        model.parentDraftTrialVideoID != nil && model.parentDraftTrialVideoID == model.parentDraftStatus.videoID
    }

    private var confirmPreviewRow: some View {
        HStack(alignment: .center, spacing: 14) {
            if let id = model.parentDraftStatus.videoID {
                AllowlistThumbnail(videoID: id).frame(width: 176, height: 99)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let title = model.parentDraftTitle {
                    Text(title).font(CanvasFont.font(size: 18, weight: 900)).lineLimit(2)
                } else if model.isFetchingDraftTitle {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        ParentLabel("取得片名中… / Fetching title…", size: 14, weight: 600, color: .inkSoft)
                    }
                } else {
                    ParentLabel(browser.pageTitle ?? "未有片名 / No title found", size: 16, weight: 800)
                }
                Text(model.parentDraftStatus.videoID ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.inkSoft)
                if isUpdate {
                    ParentPill(text: "✓ 已經加咗 / Already added — 有改先撳得「更新」",
                               fill: Color(hex: DesignTokens.Palette.mint).opacity(0.45))
                } else {
                    ParentPill(text: "預覽 / Preview — 撳「加入」 / press Add",
                               fill: Color(hex: DesignTokens.Palette.mint).opacity(0.35))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.taxiTicket), cornerRadius: 16,
                              shadowDepth: 4, lineWidth: 3))
    }

    @ViewBuilder
    private var confirmLengthLine: some View {
        if let length = model.parentDraftLengthLabel {
            confirmLine("clock.fill", "片長 \(length)，由網頁讀到 —— 張卡會顯示真片長，唔使「~」",
                        "Length read from the page, so the card shows the real length (no “~”)", color: .ink)
        } else {
            confirmLine("clock", "片長未知：用預設 120 秒（卡上「~2:00」），試播後會更新",
                        "Length unknown: default 120 s until the player reports it", color: .inkSoft)
        }
    }

    @ViewBuilder
    private var confirmEmbedLine: some View {
        switch model.parentDraftEmbedCheck {
        case .embeddable:
            confirmLine("checkmark.seal.fill", "可以喺小朋友嘅播放器播（嵌入檢查 OK）",
                        "Embeddable: it will play in your child’s player", color: .ink)
        case .checking:
            confirmLine("hourglass", "檢查緊可唔可以喺小朋友嘅播放器播…", "Checking embedding…", color: .inkSoft)
        case .blocked:
            confirmLine("xmark.octagon.fill", "擁有者唔准喺其他地方播 —— 加咗小朋友都播唔到，所以「加入」灰咗",
                        "Owner blocks embedding: it would never play for your child, so Add is off",
                        color: Color(hex: DesignTokens.Palette.stampRed))
        case .unknown:
            confirmLine("questionmark.circle", "未能檢查嵌入，照樣加得；建議先試播",
                        "Couldn’t check embedding; you can still add — try Preview first", color: .inkSoft)
        }
    }

    private func confirmLine(_ symbol: String, _ zh: String, _ en: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 0) {
                ParentLabel(zh, size: 15, weight: 800, color: color)
                ParentLabel(en, size: 11, weight: 600, color: .inkSoft)
            }
        }
    }

    // MARK: Actions

    private func submitSearch() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let url = ParentYouTubeBrowser.destination(forSearchText: text) else {
            browser.notice = "Shorts 唔支援，揀普通片。 / Shorts not supported; pick a normal video."
            return
        }
        if YouTubeEmbedURL.extractVideoID(from: text) == nil { model.noteParentBrowserSearch(text) }
        browser.load(url)
    }

    private func pasteIntoSearch() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            browser.notice = "剪貼簿冇文字。 / Clipboard is empty."
            return
        }
        searchText = String(text.prefix(300))
        submitSearch()
    }

    private func takePastedLink() {
        if botCheckPaste.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            botCheckPaste = NSPasteboard.general.string(forType: .string) ?? ""
        }
        guard let id = YouTubeEmbedURL.extractVideoID(from: botCheckPaste) else {
            browser.notice = "認唔到呢條連結。 / Not a YouTube video link."
            return
        }
        botCheckPaste = ""
        beginConfirm(id, duration: nil)
    }

    private func add(_ state: ParentYouTubeAddBar) {
        guard case .ready(let id) = state else { return }
        beginConfirm(id, duration: browser.pageDuration)
    }

    private func beginConfirm(_ id: String, duration: TimeInterval?) {
        browser.pauseMedia()
        model.beginFinderConfirm(videoID: id, pageDurationSeconds: duration)
    }

    private func beginConfirm(_ id: String) {
        beginConfirm(id, duration: browser.pageDuration)
    }

    private func toggleTrial() {
        if isTrialPlaying { model.stopDraftTrial() } else { model.startDraftTrial() }
    }

    private func close() {
        browser.pauseMedia()
        model.closeParentBrowser()
    }
}

/// Hosts the controller's single web view (kept in the hierarchy; the start page covers it).
private struct ParentWebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Finder website data (D6)

/// The finder's own persistent website data store, separate from the child player's shared
/// `.default()` store (ScopedPlayerView is unchanged). 進階 has 「清除搵片器資料」.
@MainActor
enum ParentFinderWebData {
    static let storeID = UUID(uuidString: "6C0B7E3A-2F1D-4B8E-9A52-0F7D1C4E9B21")!

    static func makeStore() -> WKWebsiteDataStore {
        if #available(macOS 14.0, *) {
            return WKWebsiteDataStore(forIdentifier: storeID)
        }
        // macOS 13: never share the child's store; fall back to a per-visit store.
        return WKWebsiteDataStore.nonPersistent()
    }

    /// Clears only the finder's store. The child player's `.default()` store is not touched.
    static func clear(onDone: @escaping @MainActor () -> Void) {
        let store = makeStore()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            onDone()
        }
    }
}

// MARK: - Controller

/// Owns the parent finder's WKWebView. Main-frame navigation is limited to YouTube pages
/// (`ParentYouTubeBrowser.navigation`); home feeds show the app's start page; sign-in,
/// other sites and new-window links are refused. No KVO, no Tasks: state refreshes from
/// WebKit delegate callbacks and the read-only `visaBrowser` probe (ADR 0010).
@MainActor
final class ParentBrowserController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published private(set) var currentURL: URL?
    @Published private(set) var showingStart = true
    @Published private(set) var canGoBackUI = false
    @Published private(set) var canGoForwardUI = false
    @Published private(set) var isLoading = false
    @Published private(set) var botCheck = false
    @Published private(set) var liveDetected = false
    @Published private(set) var pageDuration: TimeInterval?
    @Published private(set) var pageTitle: String?
    @Published private(set) var channel: String?
    @Published private(set) var zoomValue: Double
    @Published var notice: String?
    var onActivity: (() -> Void)?
    private var hasWebPage = false
    private var isShutDown = false
    private var allowedIDsScript = ParentYouTubeBrowser.allowedIDsScript(ids: [])

    var searchQuery: String? {
        guard let url = currentURL, url.path == "/results" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "search_query" }?.value
    }

    override init() {
        let config = WKWebViewConfiguration()
        // D6: the finder's own persistent store; the child player keeps `.default()`.
        config.websiteDataStore = ParentFinderWebData.makeStore()
        config.preferences.isElementFullscreenEnabled = false
        // Rule 4: nothing plays (not even hover previews) until the parent presses play.
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.applicationNameForUserAgent = SafariUserAgent.applicationName()
        webView = WKWebView(frame: .zero, configuration: config)
        zoomValue = ParentFinderZoom.clamp(UserDefaults.standard.object(forKey: ParentFinderZoom.key) as? Double)
        super.init()
        webView.configuration.userContentController.add(ParentBrowserMessageProxy(target: self),
                                                         name: ParentYouTubeBrowser.messageHandlerName)
        webView.configuration.userContentController.addUserScript(
            WKUserScript(source: ParentYouTubeBrowser.probeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = false
        webView.pageZoom = CGFloat(zoomValue)
    }

    func load(_ url: URL) {
        guard !isShutDown else { return }
        notice = nil
        showingStart = false
        hasWebPage = true
        webView.load(URLRequest(url: url))
        refreshNavState()
        onActivity?()
    }

    func showStart() {
        pauseMedia()
        showingStart = true
        currentURL = nil
        resetPageState()
        refreshNavState()
        onActivity?()
    }

    func goBack() {
        if showingStart { return }
        if webView.canGoBack { webView.goBack() } else { showStart() }
        onActivity?()
    }

    func goForward() {
        if showingStart, hasWebPage {
            showingStart = false
            currentURL = webView.url
            refreshNavState()
        } else if webView.canGoForward {
            webView.goForward()
        }
        onActivity?()
    }

    func reload() {
        guard !showingStart else { return }
        botCheck = false
        webView.reload()
        onActivity?()
    }

    /// D11: A− / A+, remembered.
    func zoom(by delta: Int) {
        zoomValue = ParentFinderZoom.step(zoomValue, by: delta)
        webView.pageZoom = CGFloat(zoomValue)
        UserDefaults.standard.set(zoomValue, forKey: ParentFinderZoom.key)
        onActivity?()
    }

    /// D10 marks: ids already on the allowlist.
    func setAllowedIDs(_ ids: [String]) {
        allowedIDsScript = ParentYouTubeBrowser.allowedIDsScript(ids: ids)
        guard !isShutDown, hasWebPage else { return }
        webView.evaluateJavaScript(allowedIDsScript, completionHandler: nil)
    }

    /// Leaving the finder or opening the add card: pause and mute page media.
    func pauseMedia() {
        webView.evaluateJavaScript(ParentYouTubeBrowser.pauseMediaScript, completionHandler: nil)
        webView.pauseAllMediaPlayback(completionHandler: nil)
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        pauseMedia()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        onActivity = nil
    }

    private func resetPageState() {
        botCheck = false
        liveDetected = false
        pageDuration = nil
        pageTitle = nil
        channel = nil
    }

    private func refreshNavState() {
        canGoBackUI = !showingStart
        canGoForwardUI = showingStart ? hasWebPage : webView.canGoForward
    }

    /// URL changes arrive from navigation callbacks and from the probe (YouTube is a single-page app).
    private func noteURL(_ url: URL?) {
        guard !isShutDown, !showingStart, let url else { return }
        if case .showStartPage = ParentYouTubeBrowser.navigation(for: url) {
            showStart()
            return
        }
        if url != currentURL {
            let oldPage = ParentYouTubeBrowser.page(for: currentURL)
            let newPage = ParentYouTubeBrowser.page(for: url)
            if oldPage != newPage { resetPageState() }
            currentURL = url
            onActivity?()
        }
        refreshNavState()
    }

    func handleProbe(_ message: WKScriptMessage) {
        guard !isShutDown, message.frameInfo.isMainFrame,
              let dict = message.body as? [String: Any] else { return }
        if let href = dict["href"] as? String { noteURL(URL(string: href)) }
        guard !showingStart, case .video = ParentYouTubeBrowser.page(for: currentURL) else {
            if botCheck { botCheck = false }
            return
        }
        let errorText = (dict["errorText"] as? String) ?? ""
        let blocked = ProviderBlockedPolicy.pageTextIndicatesBotCheck(errorText)
        if blocked != botCheck {
            botCheck = blocked
            if blocked { VisaGamesLog.append("parent browser bot-check — YouTube 要求驗證") }
        }
        let live = (dict["live"] as? Bool) ?? false
        if live != liveDetected { liveDetected = live }
        let seconds = live ? nil : ParentYouTubeBrowser.pageDurationSeconds(
            playerDuration: dict["duration"] as? Double, isoDuration: dict["iso"] as? String)
        if let seconds, seconds != pageDuration { pageDuration = seconds }
        let title = ParentYouTubeBrowser.cleanPageTitle(dict["title"] as? String)
            ?? ParentYouTubeBrowser.cleanPageTitle(webView.title)
        if title != pageTitle { pageTitle = title }
        let owner = (dict["channel"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(80)) }
        if owner != channel { channel = owner }
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        guard isMainFrame else {
            // Player internals and consent frames. Main-frame policy is what keeps this YouTube-only.
            let scheme = url.scheme?.lowercased() ?? ""
            decisionHandler(scheme == "https" || scheme == "about" || scheme == "blob" ? .allow : .cancel)
            return
        }
        switch ParentYouTubeBrowser.navigation(for: url) {
        case .allow:
            decisionHandler(.allow)
        case .showStartPage:
            decisionHandler(.cancel)
            showStart()
        case .blockSignIn:
            decisionHandler(.cancel)
            notice = "家長頁唔使登入 YouTube，登入已停用。 / Sign-in is turned off here."
            VisaGamesLog.append("parent browser sign-in blocked")
        case .block:
            decisionHandler(.cancel)
            notice = "呢度只開 YouTube。 / Only YouTube pages open here."
            VisaGamesLog.append("parent browser blocked host=\(url.host ?? "?")")
        }
    }

    /// Rule 3 / difference 19: `target=_blank` and `window.open` are refused, never a new window.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        notice = "新視窗連結唔會開，請撳返普通連結。 / Links that open a new window are off here."
        VisaGamesLog.append("parent browser popup refused")
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        noteURL(webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        noteURL(webView.url)
        webView.evaluateJavaScript(allowedIDsScript, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        refreshNavState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        refreshNavState()
        let ns = error as NSError
        // -999 = cancelled by our own policy; anything else is a network problem.
        if ns.code != NSURLErrorCancelled, ns.domain == NSURLErrorDomain {
            notice = "連唔到 YouTube，請檢查網絡再重新載入。 / Can't reach YouTube. Check the network and reload."
        }
    }
}

/// Weak trampoline so `WKUserContentController` does not retain the controller.
private final class ParentBrowserMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var target: ParentBrowserController?

    init(target: ParentBrowserController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.handleProbe(message)
    }
}
