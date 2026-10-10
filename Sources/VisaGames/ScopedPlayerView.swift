import AppKit
import SwiftUI
import VisaCore
import WebKit

/// Child/parent play stub: WKWebView loads a referrer-bearing HTML shell whose iframe
/// points ONLY at a constructed youtube-nocookie embed URL (Error 153 Referer fix).
/// Main-frame navigation is limited to the HTML shell host-root and the official
/// `/embed/<id>` family for that id. This is not a general browser (ADR 0003 D8).
///
/// v0.12.0: the shell reports YouTube IFrame API state through a read-only
/// `WKScriptMessageHandler` (`visaPlayer`). `onPlaybackEnded` fires once per load when the
/// allowlisted video reaches the ended state, so the app can leave the YouTube end card.
struct ScopedPlayerView: NSViewRepresentable {
    let videoID: String
    /// Resume offset for child Continue (embed `start=` + seekTo). Nil/0 = from beginning.
    var startSeconds: TimeInterval? = nil
    var onNavigationRejected: (() -> Void)?
    /// Main thread, at most once per loaded video id. Argument is that id.
    var onPlaybackEnded: ((String) -> Void)? = nil
    /// Real video length from the player (display-only metadata for parent cards).
    var onDurationKnown: ((String, TimeInterval) -> Void)? = nil
    /// Periodic currentTime while playing (child resume cursor). Parent preview may ignore.
    var onCurrentTime: ((String, TimeInterval) -> Void)? = nil
    /// v0.21.1: YouTube blocked the embed (bot-check / onError / watchdog). `(videoID, via)`.
    var onProviderBlocked: ((String, String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            videoID: videoID,
            startSeconds: startSeconds,
            onNavigationRejected: onNavigationRejected,
            onPlaybackEnded: onPlaybackEnded,
            onDurationKnown: onDurationKnown,
            onCurrentTime: onCurrentTime,
            onProviderBlocked: onProviderBlocked
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // v0.21.1: always the shared persistent store (never ephemeral) — consent / visitor
        // cookies survive relaunches. Source-guarded in VisaCoreChecks.
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = false
        // macOS: allow media without an extra gesture when parent/child already pressed Play.
        config.mediaTypesRequiringUserActionForPlayback = []
        // Weak proxy: WKUserContentController retains handlers strongly (avoid a cycle).
        config.userContentController.add(
            ScopedPlayerMessageProxy(target: context.coordinator),
            name: ScopedPlayerEvent.messageHandlerName
        )
        // Cross-frame scan for the bot-check panel inside the YouTube iframe.
        let scan = """
        (function () {
          if (window.__visaBlockedScan) { return; }
          window.__visaBlockedScan = true;
          function dig(root) {
            try {
              var t = ((root && (root.innerText || root.textContent)) || "").toLowerCase();
              if (t.indexOf("not a bot") !== -1 || t.indexOf("sign in to confirm") !== -1) {
                var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.visaPlayer;
                if (h) {
                  h.postMessage({ event: "providerBlocked", videoID: document.documentElement.getAttribute("data-visa-id") || "", via: "page" });
                }
              }
            } catch (e) {}
          }
          setInterval(function () { dig(document.body); }, 1500);
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: scan, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )
        config.applicationNameForUserAgent = SafariUserAgent.applicationName()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        view.allowsMagnification = false
        context.coordinator.attach(view)
        context.coordinator.loadEmbedIfPossible()
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.videoID = videoID
        context.coordinator.startSeconds = startSeconds
        context.coordinator.onNavigationRejected = onNavigationRejected
        context.coordinator.onPlaybackEnded = onPlaybackEnded
        context.coordinator.onDurationKnown = onDurationKnown
        context.coordinator.onCurrentTime = onCurrentTime
        context.coordinator.onProviderBlocked = onProviderBlocked
        context.coordinator.attach(nsView)
        let startChanged = context.coordinator.loadedStartSeconds != normalizedStart(startSeconds)
        if context.coordinator.loadedVideoID != videoID || startChanged {
            context.coordinator.loadEmbedIfPossible()
        }
    }

    private func normalizedStart(_ value: TimeInterval?) -> TimeInterval {
        guard let value, value.isFinite, value >= 1 else { return 0 }
        return value.rounded(.down)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
        nsView.stopLoading()
        nsView.navigationDelegate = nil
        nsView.uiDelegate = nil
        // Drops the `visaPlayer` bridge so no late JS message reaches a dead coordinator.
        nsView.configuration.userContentController.removeAllScriptMessageHandlers()
        // Silence audio right away (ended → picker, stop → TimesUp) instead of waiting for dealloc.
        nsView.pauseAllMediaPlayback(completionHandler: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var videoID: String
        var startSeconds: TimeInterval?
        var onNavigationRejected: (() -> Void)?
        var onPlaybackEnded: ((String) -> Void)?
        var onDurationKnown: ((String, TimeInterval) -> Void)?
        var onCurrentTime: ((String, TimeInterval) -> Void)?
        var onProviderBlocked: ((String, String) -> Void)?
        private(set) var loadedVideoID: String?
        private(set) var loadedStartSeconds: TimeInterval = 0
        private var endLatch = PlaybackEndLatch()
        private weak var webView: WKWebView?
        private var loadStartedAt: Date?
        private var readySeen = false
        private var playingSeen = false
        private var blockedReported = false
        private var watchdog: Timer?

        init(
            videoID: String,
            startSeconds: TimeInterval?,
            onNavigationRejected: (() -> Void)?,
            onPlaybackEnded: ((String) -> Void)?,
            onDurationKnown: ((String, TimeInterval) -> Void)?,
            onCurrentTime: ((String, TimeInterval) -> Void)?,
            onProviderBlocked: ((String, String) -> Void)?
        ) {
            self.videoID = videoID
            self.startSeconds = startSeconds
            self.onNavigationRejected = onNavigationRejected
            self.onPlaybackEnded = onPlaybackEnded
            self.onDurationKnown = onDurationKnown
            self.onCurrentTime = onCurrentTime
            self.onProviderBlocked = onProviderBlocked
        }

        func attach(_ view: WKWebView) {
            webView = view
            view.navigationDelegate = self
            view.uiDelegate = self
        }

        func detach() {
            webView?.navigationDelegate = nil
            webView?.uiDelegate = nil
            webView = nil
            onNavigationRejected = nil
            onPlaybackEnded = nil
            onDurationKnown = nil
            onCurrentTime = nil
            onProviderBlocked = nil
            loadedVideoID = nil
            loadedStartSeconds = 0
            endLatch.reset()
            stopWatchdog()
            readySeen = false
            playingSeen = false
            blockedReported = false
            loadStartedAt = nil
        }

        private func stopWatchdog() {
            watchdog?.invalidate()
            watchdog = nil
        }

        private func startWatchdog() {
            stopWatchdog()
            let timeout = ProviderBlockedPolicy.watchdogSeconds
            watchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async { self.checkWatchdog() }
            }
            // Keep the timer alive while scrolling / tracking run loops.
            if let watchdog { RunLoop.main.add(watchdog, forMode: .common) }
            _ = timeout
        }

        private func checkWatchdog() {
            guard let started = loadStartedAt, let current = loadedVideoID, !blockedReported else { return }
            let elapsed = Date().timeIntervalSince(started)
            if ProviderBlockedPolicy.watchdogFired(readySeen: readySeen, playingSeen: playingSeen, elapsed: elapsed) {
                reportBlocked(via: ProviderBlockedPolicy.DetectVia.watchdog.rawValue, videoID: current)
            }
        }

        private func reportBlocked(via: String, videoID: String) {
            guard !blockedReported else { return }
            blockedReported = true
            stopWatchdog()
            let ms = Int(((loadStartedAt.map { Date().timeIntervalSince($0) }) ?? 0) * 1000)
            ScopedPlayerLog.append("bot-check detected via=\(via) ms=\(ms) videoID=\(videoID)")
            let callback = onProviderBlocked
            DispatchQueue.main.async { callback?(videoID, via) }
        }

        /// IFrame API bridge (read-only). Called on the main thread by WebKit.
        func handleScriptMessage(_ message: WKScriptMessage) {
            guard message.name == ScopedPlayerEvent.messageHandlerName,
                  let current = loadedVideoID else { return }
            // providerBlocked may arrive from the YouTube iframe (non-main frame).
            let host = message.frameInfo.securityOrigin.host.lowercased()
            let youtubeHost = host.contains("youtube")
            if !message.frameInfo.isMainFrame {
                guard youtubeHost, let dict = message.body as? [String: Any],
                      (dict["event"] as? String) == "providerBlocked" else { return }
                let via = (dict["via"] as? String) ?? "page"
                reportBlocked(via: via.isEmpty ? "page" : via, videoID: current)
                return
            }
            // Page-scan posts may omit / mismatch videoID — accept providerBlocked loosely.
            if let dict = message.body as? [String: Any],
               (dict["event"] as? String) == "providerBlocked" {
                let via = (dict["via"] as? String) ?? "page"
                reportBlocked(via: via, videoID: current)
                return
            }
            guard let event = ScopedPlayerEvent.parse(message.body, expectedVideoID: current) else { return }
            switch event {
            case .stateChanged(let state):
                ScopedPlayerLog.append("player state=\(YouTubePlayerState.label(state)) videoID=\(current)")
                if state == YouTubePlayerState.playing {
                    playingSeen = true
                    stopWatchdog()
                }
            case .ready(let duration):
                readySeen = true
                ScopedPlayerLog.append("player ready duration=\(duration.map { String(Int($0.rounded())) } ?? "?") videoID=\(current)")
            case .duration(let seconds):
                ScopedPlayerLog.append("player duration=\(Int(seconds.rounded()))s videoID=\(current)")
                onDurationKnown?(current, seconds)
            case .currentTime(let seconds):
                onCurrentTime?(current, seconds)
            case .apiUnavailable(let detail):
                // Video still plays; only end detection is degraded (see PROGRESS UAT).
                ScopedPlayerLog.append("player api-unavailable detail=\(detail) videoID=\(current)")
            case .providerBlocked(let via):
                reportBlocked(via: via, videoID: current)
                return
            case .ended:
                break
            }
            guard event.indicatesEnded else { return }
            guard endLatch.shouldReportEnd(videoID: current, loadedVideoID: loadedVideoID) else {
                ScopedPlayerLog.append("player ended duplicate-ignored videoID=\(current)")
                return
            }
            ScopedPlayerLog.append("player ended → app videoID=\(current)")
            // Next main-loop turn: routing away dismantles this WKWebView and removes the
            // message handler, which must not happen while WebKit is still inside this call.
            guard let callback = onPlaybackEnded else { return }
            DispatchQueue.main.async {
                callback(current)
            }
        }

        func loadEmbedIfPossible() {
            let start = (startSeconds?.isFinite == true && (startSeconds ?? 0) >= 1)
                ? startSeconds!.rounded(.down) : 0
            guard let html = YouTubeEmbedURL.embedHTMLString(videoID: videoID, startSeconds: start > 0 ? start : nil),
                  let embedURL = YouTubeEmbedURL.make(videoID: videoID, startSeconds: start > 0 ? start : nil) else {
                ScopedPlayerLog.append("load skip invalid videoID=\(videoID)")
                return
            }
            let baseURL = YouTubeEmbedURL.embedHTMLBaseURL()
            loadedVideoID = videoID
            loadedStartSeconds = start
            endLatch.reset()
            readySeen = false
            playingSeen = false
            blockedReported = false
            loadStartedAt = Date()
            startWatchdog()
            let ua = SafariUserAgent.applicationName()
            ScopedPlayerLog.append(
                "load mode=htmlString videoID=\(videoID) start=\(Int(start))s embed=\(embedURL.host ?? "")\(embedURL.path) base=\(baseURL.host ?? "")\(baseURL.path) ua=\(ua) store=default"
            )
            webView?.loadHTMLString(html, baseURL: baseURL)
        }

        private func describe(_ url: URL?) -> String {
            guard let url else { return "nil" }
            let host = url.host ?? ""
            let path = url.path.isEmpty ? "/" : url.path
            return "\(host)\(path)"
        }

        private func rejectEscapeIfNeeded(url: URL?, isMainFrame: Bool) {
            // Stop playback only for clear main-frame escapes (watch/search/other id/external).
            // In-player chrome / consent / linkActivated noise is cancelled quietly.
            guard isMainFrame, let url, YouTubeEmbedURL.isClearEscapeURL(url, videoID: videoID) else {
                return
            }
            ScopedPlayerLog.append("nav escape-stop videoID=\(videoID) url=\(describe(url))")
            onNavigationRejected?()
        }

        // Match macOS 26+/WK SWIFT_UI_ACTOR decisionHandler so the method is the real delegate hook.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            let frameTag = isMainFrame ? "main" : "sub"

            // Benign WK bootstrap intermediate — never stop playback for blank.
            if YouTubeEmbedURL.isBenignBlankURL(url) {
                ScopedPlayerLog.append("nav allow \(frameTag) about:blank videoID=\(videoID)")
                decisionHandler(.allow)
                return
            }

            // HTML shell at nocookie host root (Referer origin for Error 153).
            if isMainFrame, let url, YouTubeEmbedURL.isAllowedEmbedShellMainFrameURL(url) {
                ScopedPlayerLog.append("nav allow \(frameTag) shell url=\(describe(url)) videoID=\(videoID)")
                decisionHandler(.allow)
                return
            }

            // linkActivated: allow only if destination is the official embed for this id;
            // otherwise cancel quietly (player chrome / consent). Stop only when the
            // destination is a clear main-frame escape.
            if navigationAction.navigationType == .linkActivated {
                if let url, YouTubeEmbedURL.isAllowedEmbedMainFrameURL(url, videoID: videoID) {
                    ScopedPlayerLog.append("nav allow linkActivated embed url=\(describe(url)) videoID=\(videoID)")
                    decisionHandler(.allow)
                    return
                }
                ScopedPlayerLog.append("nav cancel linkActivated url=\(describe(url)) videoID=\(videoID)")
                rejectEscapeIfNeeded(url: url, isMainFrame: isMainFrame)
                decisionHandler(.cancel)
                return
            }

            if isMainFrame {
                if let url, YouTubeEmbedURL.isAllowedEmbedMainFrameURL(url, videoID: videoID) {
                    ScopedPlayerLog.append("nav allow main embed url=\(describe(url)) videoID=\(videoID)")
                    decisionHandler(.allow)
                    return
                }
                // Main-frame leave from shell/`/embed/<id>` (watch/search/other id/external) → stop.
                ScopedPlayerLog.append("nav cancel-stop main url=\(describe(url)) videoID=\(videoID)")
                onNavigationRejected?()
                decisionHandler(.cancel)
                return
            }

            // Non-main-frame HTTPS loads are required for the official player internals
            // (including the iframe src=nocookie embed). Residual provider chrome: ADR 0003.
            if url?.scheme?.lowercased() == "https" {
                ScopedPlayerLog.append("nav allow sub https url=\(describe(url)) videoID=\(videoID)")
                decisionHandler(.allow)
                return
            }
            ScopedPlayerLog.append("nav cancel sub non-https url=\(describe(url)) videoID=\(videoID)")
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            ScopedPlayerLog.append("popup deny url=\(describe(navigationAction.request.url)) videoID=\(videoID)")
            return nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            ScopedPlayerLog.append(
                "wk didFail domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription) videoID=\(videoID)"
            )
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            ScopedPlayerLog.append(
                "wk didFailProvisional domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription) videoID=\(videoID)"
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let title = webView.title ?? ""
            if title.localizedCaseInsensitiveContains("153")
                || title.localizedCaseInsensitiveContains("configuration error") {
                ScopedPlayerLog.append(
                    "wk note possible Error 153 title=\(title) videoID=\(videoID)"
                )
            } else {
                ScopedPlayerLog.append("wk didFinish title=\(title.isEmpty ? "(empty)" : title) videoID=\(videoID)")
            }
        }
    }
}

/// Weak trampoline so `WKUserContentController` (strong owner) does not retain the coordinator.
private final class ScopedPlayerMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var target: ScopedPlayerView.Coordinator?

    init(target: ScopedPlayerView.Coordinator) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.handleScriptMessage(message)
    }
}

/// Placeholder shown when policy denies playback or no video is selected.
struct ScopedPlayerPlaceholder: View {
    let message: String
    let yellow: Color

    var body: some View {
        VStack(spacing: 12) {
            Text("准許播放區 / Scoped player")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(message)
                .font(.system(size: 22, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(yellow)
        }
        .frame(maxWidth: 720)
        .padding(24)
    }
}
