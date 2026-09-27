import AppKit
import SwiftUI
import VisaCore
import WebKit

/// Child/parent play stub: WKWebView loads ONLY a constructed youtube-nocookie embed URL.
/// Main-frame navigation away from that embed is cancelled. This is not a general browser (ADR 0003 D8).
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

        private func isCurrentEmbed(_ url: URL?) -> Bool {
            guard let url, let expected = YouTubeEmbedURL.make(videoID: videoID) else { return false }
            return YouTubeEmbedURL.isAllowedEmbedURL(url)
                && url.path == expected.path
                && url.host?.lowercased() == expected.host?.lowercased()
        }

        // Match macOS 26+/WK SWIFT_UI_ACTOR decisionHandler so the method is the real delegate hook.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            // Always deny explicit user link activation — no free browsing.
            if navigationAction.navigationType == .linkActivated {
                onNavigationRejected?()
                decisionHandler(.cancel)
                return
            }

            let url = navigationAction.request.url
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true

            if isMainFrame {
                // Main frame may only show the constructed nocookie embed for this id.
                if isCurrentEmbed(url) {
                    decisionHandler(.allow)
                    return
                }
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
            onNavigationRejected?()
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Deny popup / target=_blank windows.
            onNavigationRejected?()
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
