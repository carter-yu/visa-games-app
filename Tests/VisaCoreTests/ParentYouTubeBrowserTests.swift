import Foundation
import VisaCore

/// v0.27.0 parent in-app YouTube finder (ADR 0016): URL → video id, add-bar states, the
/// already-added state, navigation policy, recent searches, page length, ⌘ shortcuts, and
/// source guards that keep ADR 0011's constant kiosk presentation and ADR 0003 intact.
final class ParentYouTubeBrowserTests {
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    private let id = "dQw4w9WgXcQ"

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func page(_ string: String?) -> ParentYouTubePage {
        ParentYouTubeBrowser.page(for: string.flatMap { URL(string: $0) })
    }

    func testURLVideoIDParsing() {
        expectEqual(page("https://www.youtube.com/watch?v=\(id)"), .video(id: id))
        expectEqual(page("https://m.youtube.com/watch?v=\(id)&t=42s"), .video(id: id))
        expectEqual(page("https://youtube.com/watch?list=PL123&v=\(id)&index=3"), .video(id: id))
        expectEqual(page("https://youtu.be/\(id)?si=abc"), .video(id: id))
        expectEqual(page("https://www.youtube.com/shorts/\(id)"), .shorts)
        expectEqual(page("https://www.youtube.com/live/\(id)"), .live)
        expectEqual(page("https://www.youtube.com/results?search_query=fire+truck"), .other)
        expectEqual(page("https://www.youtube.com/@SomeChannel/videos"), .other)
        expectEqual(page("https://www.youtube.com/playlist?list=PL123"), .other)
        expectEqual(page("https://www.youtube.com/watch?v=short"), .other)
        expectEqual(page("https://www.youtube.com/watch?v=\(id)&v=aaaaaaaaaaa"), .other)
        expectEqual(page("https://www.youtube.com/watch"), .other)
        expectEqual(page("https://evil.example/watch?v=\(id)"), .other)
        expectEqual(page("https://www.youtube.com/"), .startPage)
        expectEqual(page("https://www.youtube.com/feed/trending"), .startPage)
        expectEqual(page("about:blank"), .startPage)
        expectEqual(page(nil), .startPage)
        expectEqual(ParentYouTubeBrowser.watchURL(videoID: id)?.absoluteString, "https://www.youtube.com/watch?v=\(id)")
        expectNil(ParentYouTubeBrowser.watchURL(videoID: "bad id"))
    }

    func testAddBarStates() {
        let empty = VideoAllowlist()
        let ready = ParentYouTubeBrowser.addBar(page: .video(id: id), allowlist: empty)
        expectEqual(ready, .ready(videoID: id))
        expectTrue(ready.isEnabled)
        expectEqual(ready.title, "＋ 加入呢條片")
        expectEqual(ready.videoID, id)
        for page in [ParentYouTubePage.startPage, .other] {
            let bar = ParentYouTubeBrowser.addBar(page: page, allowlist: empty)
            expectEqual(bar, .pickVideo)
            expectFalse(bar.isEnabled)
            expectEqual(bar.title, "揀一條片先")
            expectNil(bar.videoID)
        }
        let shorts = ParentYouTubeBrowser.addBar(page: .shorts, allowlist: empty)
        expectEqual(shorts, .unsupported(.shorts))
        expectFalse(shorts.isEnabled)
        expectEqual(shorts.title, "唔支援 Shorts")
        expectEqual(ParentYouTubeBrowser.addBar(page: .live, allowlist: empty), .unsupported(.live))
        let liveWatch = ParentYouTubeBrowser.addBar(page: .video(id: id), liveDetected: true, allowlist: empty)
        expectEqual(liveWatch, .unsupported(.live))
        expectEqual(liveWatch.title, "唔支援直播")
        // Every bar has HK Traditional + ASCII English and no Simplified-only characters.
        let bars: [ParentYouTubeAddBar] = [ready, .pickVideo, shorts, liveWatch, .alreadyAdded(videoID: id)]
        for bar in bars {
            expectFalse(bar.title.isEmpty)
            expectTrue(bar.subtitle.unicodeScalars.allSatisfy { $0.isASCII })
            // Simplified-only characters, written as escapes so the source stays Traditional.
            for simplified in ["\u{8FD9}", "\u{6761}", "\u{9009}", "\u{8FC7}", "\u{8FD8}", "\u{62E9}", "\u{9891}", "\u{5F55}", "\u{8F7D}", "\u{8FB9}"] {
                expectFalse(bar.title.contains(simplified), "Simplified \(simplified) in \(bar.title)")
            }
        }
    }

    func testAlreadyAddedState() {
        var allowlist = VideoAllowlist()
        expectEqual(ParentYouTubeBrowser.addBar(page: .video(id: id), allowlist: allowlist), .ready(videoID: id))
        expectTrue(allowlist.upsert(ApprovedVideo(id: id, durationSeconds: 120)))
        let added = ParentYouTubeBrowser.addBar(page: .video(id: id), allowlist: allowlist)
        expectEqual(added, .alreadyAdded(videoID: id))
        expectFalse(added.isEnabled, "already added is shown but disabled")
        expectEqual(added.title, "✓ 已經加咗")
        expectEqual(added.videoID, id)
        // Already added wins over the live badge; another video is still addable.
        expectEqual(ParentYouTubeBrowser.addBar(page: .video(id: id), liveDetected: true, allowlist: allowlist),
                    .alreadyAdded(videoID: id))
        expectEqual(ParentYouTubeBrowser.addBar(page: .video(id: "aaaaaaaaaaa"), allowlist: allowlist),
                    .ready(videoID: "aaaaaaaaaaa"))
        // The hand-off URL lands on the existing preview card in the same states.
        let handOff = "https://www.youtube.com/watch?v=\(id)"
        expectEqual(ParentAllowlistDraft.evaluate(handOff, allowlist: allowlist), .alreadyAllowlisted(videoID: id))
        expectEqual(ParentAllowlistDraft.evaluate(handOff, allowlist: VideoAllowlist()), .ready(videoID: id))
    }

    func testNavigationPolicy() {
        func nav(_ s: String) -> ParentYouTubeNavigation { ParentYouTubeBrowser.navigation(for: URL(string: s)!) }
        expectEqual(nav("https://www.youtube.com/results?search_query=bus"), .allow)
        expectEqual(nav("https://www.youtube.com/watch?v=\(id)"), .allow)
        expectEqual(nav("https://m.youtube.com/@channel"), .allow)
        expectEqual(nav("https://youtu.be/\(id)"), .allow)
        expectEqual(nav("https://consent.youtube.com/m?continue=x"), .allow)
        expectEqual(nav("about:blank"), .allow)
        expectEqual(nav("https://www.youtube.com/"), .showStartPage)
        expectEqual(nav("https://www.youtube.com"), .showStartPage)
        expectEqual(nav("https://www.youtube.com/feed/subscriptions"), .showStartPage)
        expectEqual(nav("https://accounts.google.com/ServiceLogin?service=youtube"), .blockSignIn)
        expectEqual(nav("https://www.youtube.com/signin?action=x"), .blockSignIn)
        expectEqual(nav("https://www.youtube.com/account"), .blockSignIn)
        expectEqual(nav("https://www.google.com/search?q=x"), .block)
        expectEqual(nav("https://example.com/"), .block)
        expectEqual(nav("http://www.youtube.com/watch?v=\(id)"), .block)
        expectEqual(nav("file:///etc/passwd"), .block)
    }

    func testSearchDestinationsAndRecentSearches() {
        let search = ParentYouTubeBrowser.searchURL(query: "  救援隊 fire truck ")
        expectEqual(search?.host, "www.youtube.com")
        expectEqual(search?.path, "/results")
        expectTrue(search?.absoluteString.contains("search_query=") ?? false)
        expectNil(ParentYouTubeBrowser.searchURL(query: "   "))
        expectEqual(ParentYouTubeBrowser.destination(forSearchText: "https://youtu.be/\(id)")?.absoluteString,
                    "https://www.youtube.com/watch?v=\(id)")
        expectEqual(ParentYouTubeBrowser.destination(forSearchText: id)?.absoluteString,
                    "https://www.youtube.com/watch?v=\(id)")
        expectNil(ParentYouTubeBrowser.destination(forSearchText: "https://www.youtube.com/shorts/\(id)"))
        expectEqual(ParentYouTubeBrowser.destination(forSearchText: "bus song")?.path, "/results")

        var recents: [String] = []
        for query in ["巴士", "fire truck", "Bus", "a", "b", "c", "d"] {
            recents = ParentYouTubeBrowser.recentSearches(adding: query, to: recents)
        }
        expectEqual(recents.count, ParentYouTubeBrowser.recentSearchLimit)
        expectEqual(recents.first, "d")
        recents = ParentYouTubeBrowser.recentSearches(adding: "FIRE TRUCK", to: recents)
        expectEqual(recents.first, "FIRE TRUCK")
        expectEqual(recents.filter { $0.lowercased() == "fire truck" }.count, 1)
        // Links and ids are never stored as searches.
        expectEqual(ParentYouTubeBrowser.recentSearches(adding: "https://youtu.be/\(id)", to: ["x"]), ["x"])
        expectEqual(ParentYouTubeBrowser.recentSearches(adding: id, to: ["x"]), ["x"])
        expectEqual(ParentYouTubeBrowser.recentSearches(adding: "  ", to: ["x"]), ["x"])
    }

    func testPageLength() {
        expectEqual(ParentYouTubeBrowser.parseISODuration("PT4M13S"), 253)
        expectEqual(ParentYouTubeBrowser.parseISODuration("PT1H2M3S"), 3_723)
        expectEqual(ParentYouTubeBrowser.parseISODuration("PT45S"), 45)
        expectEqual(ParentYouTubeBrowser.parseISODuration("P0DT0H3M0S"), 180)
        expectNil(ParentYouTubeBrowser.parseISODuration("4:13"))
        expectNil(ParentYouTubeBrowser.parseISODuration("PT"))
        expectNil(ParentYouTubeBrowser.parseISODuration("PT4X"))
        expectEqual(ParentYouTubeBrowser.pageDurationSeconds(playerDuration: 252.6, isoDuration: "PT9M"), 253)
        expectEqual(ParentYouTubeBrowser.pageDurationSeconds(playerDuration: 0, isoDuration: "PT9M"), 540)
        expectEqual(ParentYouTubeBrowser.pageDurationSeconds(playerDuration: .infinity, isoDuration: nil), nil as TimeInterval?)
        expectEqual(ParentYouTubeBrowser.pageDurationSeconds(playerDuration: nil, isoDuration: ""), nil as TimeInterval?)
    }

    func testEditingShortcutsOnlyInParent() {
        func shortcut(_ key: String, command: Bool = true, other: Bool = false, parent: Bool = true) -> ParentEditingShortcut? {
            ParentEditingShortcut.shortcut(characters: key, command: command, otherModifiers: other, allowsExit: parent)
        }
        expectEqual(shortcut("v"), .paste)
        expectEqual(shortcut("V"), .paste)
        expectEqual(shortcut("c"), .copy)
        expectEqual(shortcut("x"), .cut)
        expectEqual(shortcut("a"), .selectAll)
        expectEqual(shortcut("z"), .undo)
        expectNil(shortcut("q"))
        expectNil(shortcut("v", command: false))
        expectNil(shortcut("v", other: true))
        expectNil(shortcut("v", parent: false))
    }

    /// ADR 0011 / 0016: the finder lives inside the parent view; nothing touches window chrome,
    /// presentation options or menus, and the model never does AppKit work synchronously.
    func testPresentationAndContainmentSourceGuards() throws {
        let view = try source("Sources/VisaGames/ParentYouTubeBrowserView.swift")
        let core = try source("Sources/VisaCore/ParentYouTubeBrowser.swift")
        let settings = try source("Sources/VisaGames/ParentSettingsView.swift")
        let app = try source("Sources/VisaGames/AppDelegate.swift")
        for banned in ["presentationOptions", "styleMask", ".level", "setFrame(", "NSMenu", "mainMenu",
                       "collectionBehavior", "toggleFullScreen", "NSWindow", "orderFront", "makeKey",
                       "Task {", "Task(", "DispatchQueue", "assumeIsolated", "unowned", "nonPersistent",
                       ".observe(", "NSWorkspace", "openURL"] {
            expectFalse(view.contains(banned), "browser view must not use \(banned)")
            expectFalse(core.contains(banned), "browser core must not use \(banned)")
        }
        expectTrue(view.contains("websiteDataStore = .default()"))
        expectTrue(view.contains("isElementFullscreenEnabled = false"))
        expectTrue(view.contains("pauseAllMediaPlayback"))
        expectTrue(view.contains("ParentYouTubeBrowser.pauseMediaScript"))
        expectTrue(view.contains("case .blockSignIn:"))
        expectTrue(view.contains("ParentYouTubeBrowser.navigation(for: url)"))
        expectTrue(view.contains(".onDisappear { browser.shutdown() }"))
        expectFalse(core.contains("textContent"), "probe reads visible innerText only")
        // Pausing happens before every way out: close, add, pasted link.
        for action in ["private func close()", "private func add(", "private func takePastedLink()"] {
            guard let start = view.range(of: action) else { expectTrue(false, "missing \(action)"); continue }
            let tail = view[start.upperBound...].prefix(420)
            expectTrue(tail.contains("browser.pauseMedia()"), "\(action) pauses media")
        }
        // Reachable only from the parent view, only in parent mode.
        expectTrue(settings.contains("if model.session.mode == .parent, model.parentBrowserOpen, model.playtestKind == nil {"))
        expectTrue(settings.contains("model.openParentBrowser()"))
        expectTrue(settings.contains("喺 YouTube 搜片"))
        for folder in ["Sources/VisaGames", "Sources/VisaCore"] {
            for name in try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)
            where name.hasSuffix(".swift") && name != "ParentSettingsView.swift" && name != "ParentYouTubeBrowserView.swift" {
                let text = try source("\(folder)/\(name)")
                expectFalse(text.contains("ParentYouTubeBrowserView("), "\(name) must not show the finder")
                expectFalse(text.contains("ParentBrowserController("), "\(name) must not own a browser")
            }
        }
        // Model entry points are parent-gated and do no AppKit work.
        func body(_ header: String) -> String {
            guard let start = app.range(of: header),
                  let end = app.range(of: "\n    }\n", range: start.upperBound..<app.endIndex) else { return "" }
            return String(app[start.upperBound..<end.lowerBound])
        }
        let open = body("func openParentBrowser()")
        expectTrue(open.drop(while: { $0 != "{" }).dropFirst().trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("guard session.mode == .parent"))
        let take = body("func takeVideoFromParentBrowser(")
        expectTrue(take.contains("guard session.mode == .parent"))
        expectTrue(take.contains("parentVideoIDDraft = "), "hands off to the preview card; no direct save")
        expectFalse(take.contains("allowlistStore.save"))
        for header in ["func openParentBrowser()", "func closeParentBrowser(", "func takeVideoFromParentBrowser(",
                       "func noteParentBrowserActivity()", "func startDraftTrial()"] {
            let text = body(header)
            expectFalse(text.isEmpty, "\(header) found")
            for banned in ["NSApp", "window", "DispatchQueue", "Task", "presentationOptions"] {
                expectFalse(text.contains(banned), "\(header) must not use \(banned)")
            }
        }
        expectTrue(body("func returnToChild(").contains("parentBrowserOpen = false"))
        // ⌘ shortcuts run only after the child key block, only with allowsExit.
        guard let block = app.range(of: "if self.model.session.blocksKey("),
              let editing = app.range(of: "Self.editingAction(for: event, allowsExit: self.model.session.allowsExit)") else {
            expectTrue(false, "key monitor wiring not found")
            return
        }
        expectTrue(block.upperBound < editing.lowerBound)
    }
}
