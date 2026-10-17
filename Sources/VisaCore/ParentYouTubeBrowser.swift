import Foundation

// MARK: - Parent in-app YouTube browser (v0.27.0, ADR 0016)

/// What the parent browser is showing, derived from the main-frame URL only.
/// The video id always comes from the URL (never from page content), so adding keeps
/// working when YouTube shows its bot-check panel instead of the player.
public enum ParentYouTubePage: Equatable, Sendable {
    /// The app's own start page. YouTube's home feed is never loaded.
    case startPage
    /// One video: `/watch?v=<id>` or `youtu.be/<id>`.
    case video(id: String)
    /// `/shorts/<id>`: not supported for the allowlist.
    case shorts
    /// `/live/<id>`, or a watch page whose player reports a live stream.
    case live
    /// Search results, channels, playlists and anything else that is not one video.
    case other
}

/// The big bottom bar in the parent browser.
public enum ParentYouTubeAddBar: Equatable, Sendable {
    /// Grey: no single video on screen. 「揀一條片先」.
    case pickVideo
    /// Grey: Shorts or a live stream. Not supported.
    case unsupported(ParentYouTubePage)
    /// Yellow: 「＋ 加入呢條片」.
    case ready(videoID: String)
    /// Green, disabled: 「✓ 已經加咗」.
    case alreadyAdded(videoID: String)

    public var isEnabled: Bool {
        if case .ready = self { return true }
        return false
    }

    public var videoID: String? {
        switch self {
        case .ready(let id), .alreadyAdded(let id): return id
        case .pickVideo, .unsupported: return nil
        }
    }

    /// HK Traditional title (big).
    public var title: String {
        switch self {
        case .pickVideo: return "揀一條片先"
        case .unsupported(.shorts): return "唔支援 Shorts"
        case .unsupported: return "唔支援直播"
        case .ready: return "＋ 加入呢條片"
        case .alreadyAdded: return "✓ 已經加咗"
        }
    }

    /// English subtitle (small).
    public var subtitle: String {
        switch self {
        case .pickVideo: return "Open one video first"
        case .unsupported(.shorts): return "Shorts can't be added"
        case .unsupported: return "Live streams can't be added"
        case .ready: return "Add this video"
        case .alreadyAdded: return "Already on the allowlist"
        }
    }
}

/// Where a main-frame navigation may go. Subframes (the player, ads) are not judged here.
public enum ParentYouTubeNavigation: Equatable, Sendable {
    case allow
    /// YouTube home / feeds: cancel and show the app's own start page instead.
    case showStartPage
    /// Google / YouTube sign-in: always cancelled (ADR 0003, no signed-in account).
    case blockSignIn
    /// Any other site: cancelled. This is a YouTube finder, not a general browser.
    case block
}

public enum ParentYouTubeBrowser {
    /// Hosts the parent browser may show in the main frame.
    public static let browseHosts: Set<String> = ["www.youtube.com", "youtube.com", "m.youtube.com"]
    /// Short links redirect to `/watch`; consent pages may appear before the first page.
    public static let passThroughHosts: Set<String> = ["youtu.be", "www.youtu.be", "consent.youtube.com"]
    public static let signInHosts: Set<String> = ["accounts.google.com", "accounts.youtube.com"]
    public static let recentSearchLimit = 6
    public static let recentSearchMaxLength = 80
    public static let recentSearchesKey = "VisaGames.parentYouTubeRecentSearches.v1"

    /// Search results URL for a query. Nil for an empty query.
    public static func searchURL(query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/results"
        components.queryItems = [URLQueryItem(name: "search_query", value: String(trimmed.prefix(200)))]
        return components.url
    }

    /// Canonical watch page for a validated id.
    public static func watchURL(videoID: String) -> URL? {
        guard YouTubeEmbedURL.isValidVideoID(videoID) else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }

    /// What the search box should do with typed or pasted text: a video link (or bare id)
    /// opens that video; anything else is a YouTube search.
    public static func destination(forSearchText text: String) -> URL? {
        if let id = YouTubeEmbedURL.extractVideoID(from: text) { return watchURL(videoID: id) }
        let page = self.page(for: URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)))
        if case .shorts = page { return nil }
        return searchURL(query: text)
    }

    /// Classify a main-frame URL. `nil` / `about:blank` is the start page.
    public static func page(for url: URL?) -> ParentYouTubePage {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return .startPage }
        if host == "youtu.be" || host == "www.youtu.be" {
            if let id = YouTubeEmbedURL.extractVideoID(from: url.absoluteString) { return .video(id: id) }
            return .other
        }
        guard browseHosts.contains(host) else { return .other }
        let path = url.path
        if isHomeFeed(path: path) { return .startPage }
        if path == "/watch" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let ids = items.filter { $0.name == "v" }
            if ids.count == 1, let id = ids[0].value, id.utf8.count == 11, YouTubeEmbedURL.isValidVideoID(id) {
                return .video(id: id)
            }
            return .other
        }
        if path.hasPrefix("/shorts/") || path == "/shorts" { return .shorts }
        if path.hasPrefix("/live/") { return .live }
        return .other
    }

    /// YouTube's home and feed pages, which are never shown.
    static func isHomeFeed(path: String) -> Bool {
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        return trimmed.isEmpty || trimmed == "/" || trimmed == "/feed" || trimmed.hasPrefix("/feed/")
    }

    /// Main-frame navigation policy.
    public static func navigation(for url: URL) -> ParentYouTubeNavigation {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" { return .allow }
        guard scheme == "https", let host = url.host?.lowercased() else { return .block }
        if signInHosts.contains(host) { return .blockSignIn }
        if passThroughHosts.contains(host) { return .allow }
        guard browseHosts.contains(host) else { return .block }
        let path = url.path.lowercased()
        if path.hasPrefix("/signin") || path.hasPrefix("/logout") || path.hasPrefix("/account")
            || path.hasPrefix("/servicelogin") {
            return .blockSignIn
        }
        if isHomeFeed(path: url.path) { return .showStartPage }
        return .allow
    }

    /// The bottom bar for a page. `liveDetected` comes from the watch page's player badge.
    public static func addBar(page: ParentYouTubePage, liveDetected: Bool = false,
                              allowlist: VideoAllowlist) -> ParentYouTubeAddBar {
        switch page {
        case .video(let id):
            if allowlist.contains(id: id) { return .alreadyAdded(videoID: id) }
            if liveDetected { return .unsupported(.live) }
            return .ready(videoID: id)
        case .shorts: return .unsupported(.shorts)
        case .live: return .unsupported(.live)
        case .startPage, .other: return .pickVideo
        }
    }

    /// Newest first, case-insensitive de-dupe, trimmed, at most `recentSearchLimit`.
    public static func recentSearches(adding query: String, to existing: [String]) -> [String] {
        let trimmed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(recentSearchMaxLength))
        guard !trimmed.isEmpty, YouTubeEmbedURL.extractVideoID(from: trimmed) == nil,
              !trimmed.lowercased().hasPrefix("http") else { return Array(existing.prefix(recentSearchLimit)) }
        var result = [trimmed]
        for item in existing where item.lowercased() != trimmed.lowercased() {
            result.append(item)
        }
        return Array(result.prefix(recentSearchLimit))
    }

    /// Page length in seconds: the player's `duration` when finite, else the watch page's
    /// `itemprop=duration` (ISO 8601, e.g. `PT4M13S`). Nil when unknown or live.
    public static func pageDurationSeconds(playerDuration: Double?, isoDuration: String?) -> TimeInterval? {
        if let playerDuration, playerDuration.isFinite, playerDuration > 0, playerDuration < 86_400 {
            return playerDuration.rounded()
        }
        if let iso = isoDuration, let seconds = parseISODuration(iso), seconds > 0 { return seconds }
        return nil
    }

    /// `PT#H#M#S` (also `P#DT…`). Nil when malformed.
    public static func parseISODuration(_ text: String) -> TimeInterval? {
        let upper = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard upper.hasPrefix("P") else { return nil }
        var total: TimeInterval = 0
        var number = ""
        var inTime = false
        var sawUnit = false
        for character in upper.dropFirst() {
            if character == "T" { inTime = true; continue }
            if character.isNumber || character == "." { number.append(character); continue }
            guard let value = Double(number) else { return nil }
            number = ""
            sawUnit = true
            switch (character, inTime) {
            case ("D", false): total += value * 86_400
            case ("H", true): total += value * 3_600
            case ("M", true): total += value * 60
            case ("S", true): total += value
            default: return nil
            }
        }
        guard number.isEmpty, sawUnit else { return nil }
        return total
    }

    /// Pause and mute every `<video>` on the page (leaving the browser, opening the add card).
    public static let pauseMediaScript = """
    (function () { try { document.querySelectorAll("video, audio").forEach(function (m) { m.pause(); m.muted = true; }); } catch (e) {} })();
    """

    /// Read-only page probe. Posts the visible player-error text (never `textContent`), the
    /// player length, the watch page's ISO duration and the live badge to `visaBrowser`.
    /// It also greys out YouTube's own Sign in buttons; the navigation policy is what blocks them.
    public static let messageHandlerName = "visaBrowser"
    public static let probeScript = """
    (function () {
      if (window.__visaBrowserProbe) { return; }
      window.__visaBrowserProbe = true;
      var style = document.createElement("style");
      style.appendChild(document.createTextNode('a[href*="accounts.google.com"], a[href*="ServiceLogin"], ytd-masthead #buttons ytd-button-renderer, ytm-topbar-menu-button-renderer { pointer-events: none !important; opacity: 0.35 !important; }'));
      (document.head || document.documentElement).appendChild(style);
      function visibleText(selector) {
        var out = "";
        var nodes = document.querySelectorAll(selector);
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          if (el.getClientRects().length === 0) { continue; }
          out += " " + (el.innerText || "");
        }
        return out.slice(0, 600);
      }
      function probe() {
        try {
          var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.visaBrowser;
          if (!h) { return; }
          var video = document.querySelector("video.html5-main-video") || document.querySelector("video");
          var meta = document.querySelector('meta[itemprop="duration"]');
          var player = document.getElementById("movie_player");
          h.postMessage({
            href: String(location.href),
            errorText: visibleText(".ytp-error, .ytp-error-content, yt-playability-error-supported-renderers"),
            duration: video && isFinite(video.duration) ? video.duration : 0,
            iso: meta ? String(meta.getAttribute("content") || "") : "",
            live: !!(player && player.classList && player.classList.contains("ytp-live"))
          });
        } catch (e) {}
      }
      setInterval(probe, 1500);
    })();
    """
}

/// Parent shortcut keys the kiosk window gets no menu for (ADR 0011: no menu code).
public enum ParentEditingShortcut: String, Equatable, Sendable {
    case paste, copy, cut, selectAll, undo

    /// Only plain ⌘ + key, only while the session allows exit (parent mode).
    public static func shortcut(characters: String?, command: Bool, otherModifiers: Bool,
                                allowsExit: Bool) -> ParentEditingShortcut? {
        guard allowsExit, command, !otherModifiers, let key = characters?.lowercased() else { return nil }
        switch key {
        case "v": return .paste
        case "c": return .copy
        case "x": return .cut
        case "a": return .selectAll
        case "z": return .undo
        default: return nil
        }
    }
}
