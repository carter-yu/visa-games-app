import Foundation

/// D8 helpers: construct only the official YouTube nocookie embed URL for a validated id.
/// Rejects arbitrary http(s) URLs, watch pages, search URLs, and malformed ids.
public enum YouTubeEmbedURL: Sendable {
    /// Host used for scoped embeds (privacy-enhanced / nocookie pattern).
    public static let embedHost = "www.youtube-nocookie.com"

    /// Tight allowlist of https hosts that may host the official `/embed/<id>` main frame
    /// after YouTube redirects the constructed nocookie URL. Not a general browsing permit.
    public static let allowedEmbedMainFrameHosts: Set<String> = [
        "www.youtube-nocookie.com",
        "youtube-nocookie.com",
        "www.youtube.com",
        "youtube.com",
        "m.youtube.com"
    ]

    /// YouTube video ids are 11 characters from [A-Za-z0-9_-].
    public static func isValidVideoID(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return trimmed.unicodeScalars.count == 11 && trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Parse a parent-pasted ID or known YouTube URL. This does not grant navigation permission.
    public static func extractVideoID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidVideoID(trimmed) { return trimmed }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(),
              components.user == nil, components.password == nil, components.port == nil else { return nil }

        let id: String?
        switch host {
        case "youtube.com", "www.youtube.com", "m.youtube.com":
            if components.path == "/watch" {
                let matches = components.queryItems?.filter { $0.name == "v" } ?? []
                id = matches.count == 1 ? matches[0].value : nil
            } else if components.path.hasPrefix("/embed/") {
                id = String(components.path.dropFirst("/embed/".count))
            } else {
                id = nil
            }
        case "www.youtube-nocookie.com", "youtube-nocookie.com":
            id = components.path.hasPrefix("/embed/")
                ? String(components.path.dropFirst("/embed/".count)) : nil
        case "youtu.be", "www.youtu.be":
            id = components.path.hasPrefix("/") ? String(components.path.dropFirst()) : nil
        default:
            id = nil
        }
        guard let id, id.utf8.count == 11, isValidVideoID(id) else { return nil }
        return id
    }

    /// Parent allowlist preview only: official YouTube thumbnail CDN URL.
    /// Pattern: `https://img.youtube.com/vi/<id>/hqdefault.jpg`.
    /// Thumbnail CDN only — not browse/search/watch. Returns nil for invalid ids.
    public static func thumbnailURL(videoID: String) -> URL? {
        guard isValidVideoID(videoID) else { return nil }
        let id = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
    }

    /// Build `https://www.youtube-nocookie.com/embed/<id>` with modest embed params.
    /// Optional `startSeconds` (≥ 1) adds the official `start=` query for resume (v0.13.0).
    /// Returns nil when the id is not a valid YouTube video id.
    public static func make(videoID: String, startSeconds: TimeInterval? = nil) -> URL? {
        guard isValidVideoID(videoID) else { return nil }
        let id = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents()
        components.scheme = "https"
        components.host = embedHost
        components.path = "/embed/\(id)"
        var items = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "modestbranding", value: "1"),
            URLQueryItem(name: "controls", value: "1"),
            // v0.12.0: IFrame API state events (ended → picker / Time's up). `origin` is the
            // HTML shell origin so the player only posts state back to our own page.
            URLQueryItem(name: "enablejsapi", value: "1"),
            URLQueryItem(name: "origin", value: embedOrigin)
        ]
        if let startSeconds, startSeconds.isFinite, startSeconds >= 1 {
            items.append(URLQueryItem(name: "start", value: "\(Int(startSeconds.rounded(.down)))"))
        }
        components.queryItems = items
        return components.url
    }

    /// Origin of the `loadHTMLString` shell (`embedHTMLBaseURL()` without the trailing slash).
    public static var embedOrigin: String { "https://\(embedHost)" }

    /// DOM id of the scoped iframe that the IFrame API attaches to.
    public static let playerElementID = "visa-player"

    /// Official YouTube IFrame API loader. Loaded as a `<script>` subresource of the shell —
    /// never a main-frame navigation target (main-frame policy is unchanged).
    public static let iframeAPIScriptURL = URL(string: "https://www.youtube.com/iframe_api")!

    /// True only for our constructed nocookie embed path for a valid id (ignoring benign query differences).
    public static func isAllowedEmbedURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        guard components.scheme?.lowercased() == "https" else { return false }
        guard components.host?.lowercased() == embedHost else { return false }
        let path = components.path
        guard path.hasPrefix("/embed/") else { return false }
        let id = String(path.dropFirst("/embed/".count))
        // Reject nested paths such as /embed/id/extra
        guard !id.contains("/"), isValidVideoID(id) else { return false }
        return true
    }

    /// `about:blank` (and nil) are benign WK intermediates during embed bootstrap — not escapes.
    public static func isBenignBlankURL(_ url: URL?) -> Bool {
        guard let url else { return true }
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "about" {
            let path = url.path.isEmpty ? (url.absoluteString.lowercased()) : url.path.lowercased()
            // about:blank absoluteString is typically "about:blank"
            return url.absoluteString.lowercased() == "about:blank" || path == "blank" || path.isEmpty
        }
        return false
    }

    /// Main-frame allow for the **same** allowlisted video id on official YouTube embed hosts.
    /// Construction still goes through nocookie `make(videoID:)`; this only permits the
    /// official embed redirect family (`/embed/<exact-id>`), not watch/search/channel pages.
    public static func isAllowedEmbedMainFrameURL(_ url: URL, videoID: String) -> Bool {
        let expectedID = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidVideoID(expectedID) else { return false }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        guard components.scheme?.lowercased() == "https" else { return false }
        guard let host = components.host?.lowercased(),
              allowedEmbedMainFrameHosts.contains(host) else { return false }
        let path = components.path
        guard path.hasPrefix("/embed/") else { return false }
        let id = String(path.dropFirst("/embed/".count))
        guard !id.contains("/"), isValidVideoID(id), id == expectedID else { return false }
        return true
    }

    /// True when a cancelled main-frame destination is a clear leave-embed escape
    /// (watch/search/channel/other-id/external). Used to decide whether to stop playback.
    public static func isClearEscapeURL(_ url: URL, videoID: String) -> Bool {
        if isBenignBlankURL(url) { return false }
        if isAllowedEmbedMainFrameURL(url, videoID: videoID) { return false }
        if isAllowedEmbedShellMainFrameURL(url) { return false }
        // Any other absolute http(s) (or non-embed path on YouTube hosts) is an escape.
        let scheme = (url.scheme ?? "").lowercased()
        return scheme == "http" || scheme == "https" || scheme == "javascript" || scheme == "file"
    }

    /// Returns true when `string` must be rejected as a non-embed / arbitrary navigation target.
    public static func rejectsArbitraryURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        // Bare valid video ids are not arbitrary URLs; construction goes through `make(videoID:)`.
        if isValidVideoID(trimmed) { return false }
        guard let url = URL(string: trimmed) else { return true }
        return !isAllowedEmbedURL(url)
    }

    /// HTTPS origin used as `loadHTMLString` baseURL so WK sends a YouTube-acceptable Referer.
    /// Path is host root (`/`) on the nocookie host only — not a general browse grant.
    public static func embedHTMLBaseURL() -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = embedHost
        components.path = "/"
        return components.url!
    }

    /// True for the intentional HTML-shell document at nocookie host root (Error 153 Referer fix).
    /// Does not allow youtube.com homepage, watch, search, or other paths.
    public static func isAllowedEmbedShellMainFrameURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        guard components.scheme?.lowercased() == "https" else { return false }
        guard let host = components.host?.lowercased(),
              host == embedHost || host == "youtube-nocookie.com" else { return false }
        let path = components.path
        return path.isEmpty || path == "/"
    }

    /// Minimal parent HTML wrapping the official nocookie iframe with referrerpolicy.
    /// Returns nil when the id is invalid. Iframe `src` is always `make(videoID:)`.
    ///
    /// v0.12.0: the shell also loads the official YouTube IFrame API and attaches it to that
    /// same iframe, so `onStateChange` (ended = 0) reaches Swift through the
    /// `ScopedPlayerEvent.messageHandlerName` script handler. Raw widget messages from the
    /// official embed origin are a backup path. The script only *reports* state: it never
    /// navigates, opens windows, or loads another video id (ADR 0003 D8).
    public static func embedHTMLString(videoID: String, startSeconds: TimeInterval? = nil) -> String? {
        guard let embedURL = make(videoID: videoID, startSeconds: startSeconds) else { return nil }
        let id = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        // Escape only what we interpolate; id was validated by make(videoID:).
        let src = embedURL.absoluteString.replacingOccurrences(of: "&", with: "&amp;")
        let handler = ScopedPlayerEvent.messageHandlerName
        let elementID = playerElementID
        let apiURL = iframeAPIScriptURL.absoluteString
        let resumeStart: Int = {
            guard let startSeconds, startSeconds.isFinite, startSeconds >= 1 else { return 0 }
            return Int(startSeconds.rounded(.down))
        }()
        return #"""
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <title>Visa Games scoped embed</title>
        <style>
          html, body { margin: 0; padding: 0; height: 100%; background: #000; overflow: hidden; }
          iframe { border: 0; width: 100%; height: 100%; display: block; }
        </style>
        </head>
        <body>
        <iframe
          id="\#(elementID)"
          src="\#(src)"
          title="Scoped YouTube embed"
          referrerpolicy="strict-origin-when-cross-origin"
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
          allowfullscreen
        ></iframe>
        <script>
        (function () {
          "use strict";
          var videoID = "\#(id)";
          var resumeStart = \#(resumeStart);
          var endedSent = false;
          var durationSent = false;
          var lastState = null;
          var player = null;
          var timeTimer = null;
          function clearTimeTimer() {
            if (timeTimer) { clearInterval(timeTimer); timeTimer = null; }
          }
          function reportCurrentTime() {
            if (!player || typeof player.getCurrentTime !== "function") { return; }
            try {
              var seconds = player.getCurrentTime();
              if (typeof seconds === "number" && seconds > 0) {
                post("currentTime", { seconds: seconds });
              }
            } catch (e) {}
          }
          function startTimeTimer() {
            clearTimeTimer();
            timeTimer = setInterval(reportCurrentTime, 1000);
            reportCurrentTime();
          }
          function post(name, extra) {
            try {
              var handlers = window.webkit && window.webkit.messageHandlers;
              if (!handlers || !handlers.\#(handler)) { return; }
              var message = { event: name, videoID: videoID };
              if (extra) { for (var key in extra) { message[key] = extra[key]; } }
              window.webkit.messageHandlers.\#(handler).postMessage(message);
            } catch (e) {}
          }
          function reportDuration(seconds) {
            if (durationSent || typeof seconds !== "number" || !(seconds > 0)) { return; }
            durationSent = true;
            post("duration", { seconds: seconds });
          }
          function reportState(state) {
            if (typeof state !== "number" || state === lastState) { return; }
            lastState = state;
            post("state", { state: state });
            if (state === 0 && !endedSent) {
              endedSent = true;
              clearTimeTimer();
              post("ended");
            }
            if (state === 1) {
              startTimeTimer();
              if (player && typeof player.getDuration === "function") {
                try { reportDuration(player.getDuration()); } catch (e) {}
              }
            } else if (state === 2 || state === 3) {
              reportCurrentTime();
            }
          }
          window.onYouTubeIframeAPIReady = function () {
            try {
              player = new YT.Player("\#(elementID)", {
                events: {
                  onReady: function (event) {
                    var seconds = 0;
                    try { seconds = event.target.getDuration(); } catch (e) {}
                    post("ready", { duration: seconds });
                    reportDuration(seconds);
                    if (resumeStart > 0 && typeof event.target.seekTo === "function") {
                      try { event.target.seekTo(resumeStart, true); } catch (e) {}
                    }
                  },
                  onStateChange: function (event) { reportState(event.data); }
                }
              });
            } catch (e) {
              post("apiError", { detail: "player-init" });
            }
          };
          window.addEventListener("message", function (event) {
            if (!/^https:\/\/(www\.)?youtube(-nocookie)?\.com$/.test(event.origin)) { return; }
            var data = event.data;
            if (typeof data === "string") {
              try { data = JSON.parse(data); } catch (e) { return; }
            }
            if (!data || typeof data !== "object") { return; }
            if (data.event === "onStateChange") {
              reportState(data.info);
            } else if (data.event === "infoDelivery" && data.info && typeof data.info === "object") {
              if (typeof data.info.playerState === "number") { reportState(data.info.playerState); }
              if (typeof data.info.duration === "number") { reportDuration(data.info.duration); }
            }
          });
          var tag = document.createElement("script");
          tag.src = "\#(apiURL)";
          tag.onerror = function () { post("apiError", { detail: "script-load" }); };
          document.head.appendChild(tag);
        })();
        </script>
        </body>
        </html>
        """#
    }
}
