import AppKit
import SwiftUI
import VisaCore
import WebKit

// MARK: - Parent in-app YouTube finder (v0.27.0, ADR 0016; Opus mockups 01, 06–10)

/// Full-page YouTube finder drawn over the parent view, inside the same kiosk window.
/// Opening or closing it changes no window style, level, frame or presentation options
/// (ADR 0011). Parent-authenticated only; the child path never reaches it (ADR 0003).
/// The video id always comes from the page URL, so adding works even behind a bot check.
struct ParentYouTubeBrowserView: View {
    @ObservedObject var model: AppModel
    @StateObject private var browser = ParentBrowserController()
    @State private var searchText = ""
    @State private var botCheckPaste = ""

    private var addBar: ParentYouTubeAddBar {
        guard !browser.showingStart else { return .pickVideo }
        return ParentYouTubeBrowser.addBar(page: ParentYouTubeBrowser.page(for: browser.currentURL),
                                           liveDetected: browser.liveDetected,
                                           allowlist: model.allowlist)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let notice = browser.notice {
                ParentBanner(text: notice, fill: Color(hex: DesignTokens.Palette.taxiTicket),
                             onDismiss: { browser.notice = nil })
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            if browser.botCheck && !browser.showingStart {
                botCheckBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            ZStack {
                ParentWebViewHost(webView: browser.webView)
                if browser.showingStart {
                    startPage
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ink, lineWidth: 3))
            .padding(.horizontal, 16)
            addBarView
                .padding(16)
        }
        .background(Color(hex: DesignTokens.Palette.paper).ignoresSafeArea())
        .foregroundStyle(Color.ink)
        .onAppear {
            browser.onActivity = { [weak model] in model?.noteParentBrowserActivity() }
        }
        .onDisappear { browser.shutdown() }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            toolButton("chevron.left", label: "返回 Back", enabled: browser.canGoBackUI) { browser.goBack() }
            toolButton("chevron.right", label: "前進 Forward", enabled: browser.canGoForwardUI) { browser.goForward() }
            toolButton("arrow.clockwise", label: "重新載入 Reload", enabled: !browser.showingStart) { browser.reload() }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.inkSoft)
                TextField("搜尋 YouTube / Search YouTube", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, design: .rounded))
                    .onSubmit { submitSearch() }
                if browser.isLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .modifier(ChunkyPanel(fill: .white, cornerRadius: 14, shadowDepth: 3, lineWidth: 3))
            Button(action: { submitSearch() }) {
                ParentLabel("搜尋 Search", size: 15, weight: 800)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sunny),
                                           cornerRadius: 12, shadowDepth: 3, lineWidth: 3))
            Button(action: { close() }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                    VStack(alignment: .leading, spacing: 0) {
                        ParentLabel("返准許清單", size: 15, weight: 800)
                        ParentLabel("Back to allowlist", size: 11, weight: 600, color: .inkSoft)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sand),
                                           cornerRadius: 12, shadowDepth: 3, lineWidth: 3))
            .accessibilityLabel("關閉 YouTube，返准許清單 / Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func toolButton(_ symbol: String, label: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .heavy))
                .frame(width: 38, height: 32)
        }
        .buttonStyle(ChunkyButtonStyle(fill: .white, cornerRadius: 12, shadowDepth: 3, lineWidth: 3))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    // MARK: Start page (the app's own; YouTube's home feed is never loaded)

    private var startPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    ParentLabel("喺 YouTube 搵片", size: 30, weight: 900)
                    ParentLabel("Find a video on YouTube", size: 15, weight: 600, color: .inkSoft)
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.inkSoft)
                    TextField("例如：救援隊、巴士兒歌 / e.g. rescue team", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, design: .rounded))
                        .onSubmit { submitSearch() }
                    Button(action: { pasteIntoSearch() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                            ParentLabel("貼上 Paste", size: 15, weight: 800)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: .white, cornerRadius: 12, shadowDepth: 3, lineWidth: 3))
                    Button(action: { submitSearch() }) {
                        ParentLabel("搜尋 Search", size: 17, weight: 900)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sunny),
                                                   cornerRadius: 14, shadowDepth: 4, lineWidth: 3))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .modifier(ChunkyPanel(fill: .white, cornerRadius: 18, shadowDepth: 4, lineWidth: 3))
                ParentLabel("有連結？⌘V 貼落搜尋格，或者撳「貼上」，會直接開嗰條片。 / Have a link? ⌘V or Paste opens that video.",
                            size: 14, weight: 600, color: .inkSoft)
                if !model.parentRecentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ParentLabel("最近搜尋 Recent", size: 16, weight: 800)
                            Spacer()
                            Button(action: { model.clearParentRecentSearches() }) {
                                ParentLabel("清除 Clear", size: 13, weight: 700, color: .inkSoft)
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
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                }
                                .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.taxiTicket),
                                                               cornerRadius: 12, shadowDepth: 3, lineWidth: 2))
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    tip("1", "搜尋，撳入一條片。", "Search, then open one video.")
                    tip("2", "撳底下黃色「＋ 加入呢條片」。", "Press the yellow Add bar below.")
                    tip("3", "睇吓片名同縮圖，可以試播，再撳「加入」。", "Check the title, preview, then Add.")
                }
                .padding(14)
                .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.taxiTicket), cornerRadius: 16,
                                      shadowDepth: 3, lineWidth: 3))
                ParentLabel("唔會顯示 YouTube 首頁推介，亦唔使登入。 / No YouTube home feed, no sign-in.",
                            size: 13, weight: 600, color: .inkSoft)
            }
            .padding(28)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(hex: DesignTokens.Palette.paper))
    }

    private func tip(_ number: String, _ zh: String, _ en: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(CanvasFont.font(size: 15, weight: 900))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color(hex: DesignTokens.Palette.sunny)))
                .overlay(Circle().strokeBorder(Color.ink, lineWidth: 2))
            ParentLabel(zh, size: 16, weight: 700)
            ParentLabel(en, size: 13, weight: 600, color: .inkSoft)
        }
    }

    // MARK: Bot check (the app's own banner; the page's Sign in stays disabled)

    private var botCheckBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(hex: DesignTokens.Palette.stampRed))
                VStack(alignment: .leading, spacing: 2) {
                    ParentLabel("YouTube 要求驗證 · 唔係你撳錯嘢", size: 18, weight: 900)
                    ParentLabel("YouTube wants a bot check. You did nothing wrong.", size: 13, weight: 600, color: .inkSoft)
                }
                Spacer()
                Button(action: { browser.reload() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        ParentLabel("重新載入 Reload", size: 14, weight: 800)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(ChunkyButtonStyle(fill: .white, cornerRadius: 12, shadowDepth: 3, lineWidth: 3))
            }
            ParentLabel("• 條片照樣加得：撳底下「＋ 加入呢條片」。 / You can still add it below.", size: 14, weight: 600)
            ParentLabel("• 唔使登入。等一陣再重新載入，或者試關 VPN。 / No sign-in needed. Wait and reload, or try VPN off.",
                        size: 14, weight: 600)
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundStyle(Color.inkSoft)
                TextField("或者貼上 YouTube 連結 / Or paste a YouTube link", text: $botCheckPaste)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, design: .rounded))
                    .onSubmit { takePastedLink() }
                Button(action: {
                    botCheckPaste = NSPasteboard.general.string(forType: .string) ?? ""
                    takePastedLink()
                }) {
                    ParentLabel("貼上 Paste", size: 14, weight: 800)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sunny),
                                               cornerRadius: 10, shadowDepth: 3, lineWidth: 2))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .modifier(ChunkyPanel(fill: .white, cornerRadius: 12, shadowDepth: 2, lineWidth: 2))
        }
        .padding(14)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.fireTicket), cornerRadius: 16,
                              shadowDepth: 4, lineWidth: 3))
    }

    // MARK: Add bar

    private var addBarView: some View {
        let state = addBar
        let fill: Color
        switch state {
        case .ready: fill = Color(hex: DesignTokens.Palette.sunny)
        case .alreadyAdded: fill = Color(hex: DesignTokens.Palette.mint)
        case .pickVideo, .unsupported: fill = Color(hex: DesignTokens.Palette.hubcap)
        }
        return Button(action: { add(state) }) {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    ParentLabel(state.title, size: 26, weight: 900,
                                color: state.isEnabled || state.videoID != nil ? .ink : .inkSoft)
                    ParentLabel(state.subtitle, size: 13, weight: 600, color: .inkSoft)
                }
                if let id = state.videoID {
                    Text(id)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.inkSoft)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(ChunkyButtonStyle(fill: fill, cornerRadius: 18, shadowDepth: state.isEnabled ? 5 : 2,
                                       lineWidth: 3))
        .disabled(!state.isEnabled)
        .accessibilityLabel("\(state.title) / \(state.subtitle)")
    }

    // MARK: Actions

    private func submitSearch() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let url = ParentYouTubeBrowser.destination(forSearchText: text) else {
            browser.notice = "Shorts 加唔到，請揀普通片。 / Shorts can't be added; pick a normal video."
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
        guard let id = YouTubeEmbedURL.extractVideoID(from: botCheckPaste) else {
            browser.notice = "認唔到呢條連結。 / Not a YouTube video link."
            return
        }
        botCheckPaste = ""
        browser.pauseMedia()
        model.takeVideoFromParentBrowser(videoID: id, pageDurationSeconds: nil)
    }

    private func add(_ state: ParentYouTubeAddBar) {
        guard case .ready(let id) = state else { return }
        browser.pauseMedia()
        model.takeVideoFromParentBrowser(videoID: id, pageDurationSeconds: browser.pageDuration)
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

// MARK: - Controller

/// Owns the parent browser's WKWebView. Main-frame navigation is limited to YouTube pages
/// (`ParentYouTubeBrowser.navigation`); home feeds show the app's start page; sign-in and
/// other sites are cancelled; pop-ups open in place only when allowed. No KVO, no Tasks:
/// state refreshes from WebKit delegate callbacks and the read-only `visaBrowser` probe.
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
    @Published var notice: String?
    var onActivity: (() -> Void)?
    private var hasWebPage = false
    private var isShutDown = false

    override init() {
        let config = WKWebViewConfiguration()
        // Same shared store as the scoped player (consent cookies). Never signed in (ADR 0003).
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = false
        // No sound until the parent presses play on the TV.
        config.mediaTypesRequiringUserActionForPlayback = .audio
        config.applicationNameForUserAgent = SafariUserAgent.applicationName()
        webView = WKWebView(frame: .zero, configuration: config)
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

    /// Leaving the browser or opening the add card: pause and mute page media.
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
            notice = "呢度只可以睇 YouTube。 / Only YouTube pages open here."
            VisaGamesLog.append("parent browser blocked host=\(url.host ?? "?")")
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target=_blank: open in place when the policy allows it; never a new window.
        if let url = navigationAction.request.url, case .allow = ParentYouTubeBrowser.navigation(for: url) {
            webView.load(URLRequest(url: url))
        }
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
