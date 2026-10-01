import AppKit
import SwiftUI
import VisaCore
import WebKit

/// Child/parent play stub: WKWebView loads a referrer-bearing HTML shell whose iframe
/// points ONLY at a constructed youtube-nocookie embed URL (Error 153 Referer fix).
/// Main-frame navigation is limited to the HTML shell host-root and the official
/// `/embed/<id>` family for that id. This is not a general browser (ADR 0003 D8).
struct ScopedPlayerView: NSViewRepresentable {
    let videoID: String
    var onNavigationRejected: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(videoID: videoID, onNavigationRejected: onNavigationRejected)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        // macOS: allow media without an extra gesture when parent/child already pressed Play.
        config.mediaTypesRequiringUserActionForPlayback = []
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
        context.coordinator.onNavigationRejected = onNavigationRejected
        context.coordinator.attach(nsView)
        if context.coordinator.loadedVideoID != videoID {
            context.coordinator.loadEmbedIfPossible()
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
        nsView.stopLoading()
        nsView.navigationDelegate = nil
        nsView.uiDelegate = nil
        nsView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var videoID: String
        var onNavigationRejected: (() -> Void)?
        private(set) var loadedVideoID: String?
        private weak var webView: WKWebView?

        init(videoID: String, onNavigationRejected: (() -> Void)?) {
            self.videoID = videoID
            self.onNavigationRejected = onNavigationRejected
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
            loadedVideoID = nil
        }

        func loadEmbedIfPossible() {
            guard let html = YouTubeEmbedURL.embedHTMLString(videoID: videoID),
                  let embedURL = YouTubeEmbedURL.make(videoID: videoID) else {
                ScopedPlayerLog.append("load skip invalid videoID=\(videoID)")
                return
            }
            let baseURL = YouTubeEmbedURL.embedHTMLBaseURL()
            loadedVideoID = videoID
            ScopedPlayerLog.append(
                "load mode=htmlString videoID=\(videoID) embed=\(embedURL.host ?? "")\(embedURL.path) base=\(baseURL.host ?? "")\(baseURL.path)"
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
