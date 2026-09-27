import AppKit
import SwiftUI
import VisaCore
import WebKit

/// Child/parent play stub: WKWebView loads ONLY a constructed youtube-nocookie embed URL.
/// Main-frame navigation is limited to the official `/embed/<id>` family for that id
/// (nocookie or youtube.com redirects). This is not a general browser (ADR 0003 D8).
struct ScopedPlayerView: NSViewRepresentable {
    let videoID: String
    var onNavigationRejected: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(videoID: videoID, onNavigationRejected: onNavigationRejected)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
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

        func loadEmbedIfPossible() {
            guard let url = YouTubeEmbedURL.make(videoID: videoID) else { return }
            loadedVideoID = videoID
            webView?.load(URLRequest(url: url))
        }

        private func rejectEscapeIfNeeded(url: URL?, isMainFrame: Bool) {
            // Stop playback only for clear main-frame escapes (watch/search/other id/external).
            // In-player chrome / consent / linkActivated noise is cancelled quietly.
            guard isMainFrame, let url, YouTubeEmbedURL.isClearEscapeURL(url, videoID: videoID) else {
                return
            }
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

            // Benign WK bootstrap intermediate — never stop playback for blank.
            if YouTubeEmbedURL.isBenignBlankURL(url) {
                decisionHandler(.allow)
                return
            }

            // linkActivated: allow only if destination is the official embed for this id;
            // otherwise cancel quietly (player chrome / consent). Stop only when the
            // destination is a clear main-frame escape.
            if navigationAction.navigationType == .linkActivated {
                if let url, YouTubeEmbedURL.isAllowedEmbedMainFrameURL(url, videoID: videoID) {
                    decisionHandler(.allow)
                    return
                }
                rejectEscapeIfNeeded(url: url, isMainFrame: isMainFrame)
                decisionHandler(.cancel)
                return
            }

            if isMainFrame {
                if let url, YouTubeEmbedURL.isAllowedEmbedMainFrameURL(url, videoID: videoID) {
                    decisionHandler(.allow)
                    return
                }
                // Main-frame leave from `/embed/<id>` (watch/search/other id/external) → stop.
                onNavigationRejected?()
                decisionHandler(.cancel)
                return
            }

            // Non-main-frame HTTPS loads are required for the official player internals.
            // Residual provider chrome risk is documented in ADR 0003.
            if url?.scheme?.lowercased() == "https" {
                decisionHandler(.allow)
                return
            }
            // Quiet cancel for non-https subframe noise — do not tear down playback.
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Deny popup / target=_blank windows. Quiet deny — do not stop the player
            // merely for refusing a popup.
            return nil
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
