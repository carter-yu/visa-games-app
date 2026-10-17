import Foundation

// MARK: - Parent in-app YouTube finder (v0.27.0 / v0.27.1, ADR 0016; notes D1–D17)

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
        case .unsupported(.shorts): return "Shorts 唔支援，揀普通片"
        case .unsupported: return "直播唔加得"
        case .ready: return "＋ 加入呢條片"
        case .alreadyAdded: return "✓ 已經加咗"
        }
    }

    /// English subtitle (small).
    public var subtitle: String {
        switch self {
        case .pickVideo: return "Open a video first"
        case .unsupported(.shorts): return "Shorts not supported"
        case .unsupported: return "Live streams have no fixed length"
        case .ready: return "Add this video"
        case .alreadyAdded: return "Already added"
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

    /// Read-only page probe (`visaBrowser` handler). Posts the URL, the visible player-error
    /// `innerText` of shown panels only, the player length, the watch page's ISO duration, the
    /// live badge, the page title and the channel. It also:
    /// - hides YouTube's own search bar, Shorts shelves, comments and the fullscreen button (D8);
    /// - greys out YouTube's Sign in buttons (the navigation policy is what blocks them, D7);
    /// - marks thumbnails and the watch title of videos already on the allowlist (D10), from
    ///   `window.__visaAllowed`. Any failure only means no mark; adding never depends on it.
    public static let messageHandlerName = "visaBrowser"
    public static let probeScript = """
    (function () {
      if (window.__visaBrowserProbe) { return; }
      window.__visaBrowserProbe = true;
      var css = 'a[href*="accounts.google.com"], a[href*="ServiceLogin"], ytd-masthead #buttons ytd-button-renderer, ytm-topbar-menu-button-renderer { pointer-events: none !important; opacity: 0.35 !important; }'
        + ' ytd-masthead #center, ytd-searchbox, ytm-search, #search-form { display: none !important; }'
        + ' ytd-reel-shelf-renderer, ytd-rich-shelf-renderer[is-shorts], ytm-reel-shelf-renderer, ytd-guide-entry-renderer a[title="Shorts"], ytd-mini-guide-entry-renderer[aria-label="Shorts"] { display: none !important; }'
        + ' ytd-comments, #comments, ytm-comment-section-renderer, .ytp-fullscreen-button { display: none !important; }'
        + ' a.visa-has-badge { position: relative !important; }'
        + ' .visa-added { position: absolute; top: 6px; left: 6px; z-index: 9; background: #3CC49A; color: #3A2718; border: 2px solid #3A2718; border-radius: 10px; padding: 1px 8px; font: 700 13px -apple-system, sans-serif; }'
        + ' .visa-added-title { display: inline-block; margin-left: 10px; vertical-align: middle; background: #3CC49A; color: #3A2718; border: 2px solid #3A2718; border-radius: 12px; padding: 1px 10px; font: 700 14px -apple-system, sans-serif; }';
      var style = document.createElement("style");
      style.appendChild(document.createTextNode(css));
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
      function firstText(selector) {
        var el = document.querySelector(selector);
        return el ? String(el.innerText || "").trim().slice(0, 200) : "";
      }
      function mark() {
        var ids = window.__visaAllowed || [];
        var set = {};
        for (var k = 0; k < ids.length; k++) { set[ids[k]] = true; }
        var links = document.querySelectorAll('a[href*="watch?v="]');
        for (var i = 0; i < links.length; i++) {
          var a = links[i];
          var m = /[?&]v=([A-Za-z0-9_-]{11})/.exec(a.getAttribute("href") || "");
          var badge = a.querySelector(".visa-added");
          var wanted = !!(m && set[m[1]] && a.querySelector("img"));
          if (wanted && !badge) {
            var b = document.createElement("span");
            b.className = "visa-added";
            b.appendChild(document.createTextNode("\\u2713 \\u5DF2\\u52A0"));
            a.classList.add("visa-has-badge");
            a.appendChild(b);
          } else if (!wanted && badge) {
            badge.parentNode.removeChild(badge);
          }
        }
        var vm = /[?&]v=([A-Za-z0-9_-]{11})/.exec(location.search);
        var h1 = document.querySelector("ytd-watch-metadata h1, h1.ytd-watch-metadata, h1.title");
        if (h1) {
          var tag = h1.querySelector(".visa-added-title");
          var on = !!(vm && set[vm[1]]);
          if (on && !tag) {
            var t = document.createElement("span");
            t.className = "visa-added-title";
            t.appendChild(document.createTextNode("\\u2713 \\u5DF2\\u55BA\\u51C6\\u8A31\\u5F71\\u7247"));
            h1.appendChild(t);
          } else if (!on && tag) {
            tag.parentNode.removeChild(tag);
          }
        }
      }
      window.__visaMark = mark;
      function probe() {
        try {
          mark();
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
            live: !!(player && player.classList && player.classList.contains("ytp-live")),
            title: firstText("ytd-watch-metadata h1 yt-formatted-string, h1.ytd-watch-metadata, h1.title"),
            channel: firstText("ytd-watch-metadata ytd-channel-name a, #owner ytd-channel-name a, ytm-slim-owner-renderer .slim-owner-channel-name")
          });
        } catch (e) {}
      }
      document.addEventListener("yt-navigate-finish", function () { setTimeout(probe, 300); });
      window.addEventListener("popstate", function () { setTimeout(probe, 300); });
      probe();
      setInterval(probe, 1500);
    })();
    """

    /// `window.__visaAllowed = [...]` for the D10 marks. Only valid 11-character ids are
    /// written, so nothing from storage can inject script.
    public static func allowedIDsScript(ids: [String]) -> String {
        let valid = ids.filter { $0.utf8.count == 11 && YouTubeEmbedURL.isValidVideoID($0) }.sorted()
        let list = valid.map { "\"\($0)\"" }.joined(separator: ",")
        return "window.__visaAllowed = [\(list)]; if (window.__visaMark) { window.__visaMark(); }"
    }

    /// Strip YouTube's " - YouTube" suffix from a page title.
    public static func cleanPageTitle(_ title: String?) -> String? {
        guard var text = title?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasSuffix(" - YouTube") { text = String(text.dropLast(" - YouTube".count)) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == "YouTube" ? nil : String(text.prefix(200))
    }

    /// Top-bar countdown (D5): `m:ss`, never negative.
    public static func autoLockLabel(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        let seconds = total % 60
        return "\(total / 60):" + (seconds < 10 ? "0\(seconds)" : "\(seconds)")
    }

    /// 07: 「已經喺准許影片 · 第 2 張卡 · 10 月 3 日加」 and its English line.
    public static func alreadyAddedLine(cardNumber: Int, addedAt: Date?,
                                        calendar: Calendar = .current) -> (zh: String, en: String) {
        guard let addedAt else {
            return ("已經喺准許影片 · 第 \(cardNumber) 張卡", "card \(cardNumber)")
        }
        let parts = calendar.dateComponents([.month, .day], from: addedAt)
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return ("已經喺准許影片 · 第 \(cardNumber) 張卡 · \(month) 月 \(day) 日加",
                "card \(cardNumber), added \(day) \(months[max(0, min(11, month - 1))])")
    }
}

/// oEmbed embeddability check for the add card (08). oEmbed answers 401 / 403 when the owner
/// blocks embedding (or the video is private) and 404 when it is gone: such a video would never
/// play in the child's player, so 加入 is greyed out. A network failure stays `unknown` and
/// adding is still allowed (the pre-0.27 behaviour: oEmbed failure never blocked an add).
public enum ParentEmbedCheck: Equatable, Sendable {
    case unknown
    case checking
    case embeddable
    case blocked

    public static func from(httpStatus: Int?) -> ParentEmbedCheck {
        guard let status = httpStatus else { return .unknown }
        if (200..<300).contains(status) { return .embeddable }
        if status == 401 || status == 403 || status == 404 { return .blocked }
        return .unknown
    }

    public var allowsAdd: Bool {
        switch self {
        case .embeddable, .unknown: return true
        case .checking, .blocked: return false
        }
    }
}

/// Finder flow (D3, D4, D13): open → 「＋ 加入呢條片」 opens the confirm card over the finder →
/// 加入 saves and the parent STAYS in the finder with a 3-second toast (undo while it shows) →
/// closing returns to the list and flashes the last card added this visit.
public struct ParentFinderState: Equatable, Sendable {
    public struct Toast: Equatable, Sendable {
        public let videoID: String
        public let allowlistCount: Int
        public let until: Date
    }

    public static let toastSeconds: TimeInterval = 3

    public private(set) var isOpen = false
    /// Video id on the confirm card, or nil.
    public private(set) var confirmVideoID: String?
    public private(set) var toast: Toast?
    public private(set) var addedThisVisit: [String] = []

    public init() {}

    public mutating func open() {
        self = ParentFinderState()
        isOpen = true
    }

    public mutating func beginConfirm(videoID: String) {
        guard isOpen, YouTubeEmbedURL.isValidVideoID(videoID) else { return }
        confirmVideoID = videoID
    }

    public mutating func cancelConfirm() {
        confirmVideoID = nil
    }

    /// The add landed. The finder stays open (D4); the card closes; a toast shows.
    public mutating func didAdd(videoID: String, allowlistCount: Int, now: Date) {
        guard isOpen, confirmVideoID == videoID else { return }
        confirmVideoID = nil
        toast = Toast(videoID: videoID, allowlistCount: allowlistCount,
                      until: now.addingTimeInterval(Self.toastSeconds))
        addedThisVisit.removeAll { $0 == videoID }
        addedThisVisit.append(videoID)
    }

    public func visibleToast(now: Date) -> Toast? {
        guard let toast, now < toast.until else { return nil }
        return toast
    }

    /// 復原 while the toast shows: returns the id to remove from the allowlist.
    public mutating func undo(now: Date) -> String? {
        guard let toast = visibleToast(now: now) else { return nil }
        self.toast = nil
        addedThisVisit.removeAll { $0 == toast.videoID }
        return toast.videoID
    }

    /// Close (done / Return / auto-lock). Returns the card to flash in the list (D13).
    public mutating func close() -> String? {
        let flash = addedThisVisit.last
        self = ParentFinderState()
        return flash
    }

    /// 睇吓張卡: close and flash that card.
    public mutating func showCard(videoID: String) -> String {
        _ = close()
        return videoID
    }
}

/// Web text size (D11): 125% by default, A− / A+ steps, remembered.
public enum ParentFinderZoom {
    public static let steps: [Double] = [1.0, 1.1, 1.25, 1.5, 1.75]
    public static let defaultValue = 1.25
    public static let key = "VisaGames.parentFinderZoom.v1"

    public static func clamp(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return defaultValue }
        return steps.min(by: { abs($0 - value) < abs($1 - value) }) ?? defaultValue
    }

    public static func step(_ value: Double, by delta: Int) -> Double {
        let current = clamp(value)
        let index = steps.firstIndex(of: current) ?? 2
        return steps[max(0, min(steps.count - 1, index + delta))]
    }

    public static func label(_ value: Double) -> String { "\(Int((clamp(value) * 100).rounded()))%" }
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
