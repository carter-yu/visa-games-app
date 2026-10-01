import Foundation
import VisaCore

final class ScopedPlaybackTests {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let policy = PlaybackPolicy()
    /// Well-formed 11-char YouTube-shaped id used only in offline tests.
    let sampleID = "dQw4w9WgXcQ"
    let otherID = "abcdefghijk"

    private func allowlist(with id: String, duration: TimeInterval = 120) -> VideoAllowlist {
        var list = VideoAllowlist()
        expectTrue(list.upsert(ApprovedVideo(
            id: id,
            titleEnglish: "Sample",
            titleCantonese: "樣本",
            durationSeconds: duration
        )))
        return list
    }

    func testAllowlistRejectsUnknownID() {
        let list = allowlist(with: sampleID)
        expectTrue(list.contains(id: sampleID))
        expectFalse(list.contains(id: otherID))
        let decision = policy.evaluateStart(
            videoID: otherID,
            allowlist: list,
            remainingViewingBudgetSeconds: 300,
            sessionEndsAt: now.addingTimeInterval(600),
            now: now
        )
        expectEqual(decision.allowed, false)
        expectEqual(decision.stopReason, .notAllowlisted)

        let engine = FakePlaybackEngine()
        let load = engine.load(
            videoID: otherID,
            allowlist: list,
            policy: policy,
            remainingViewingBudgetSeconds: 300,
            sessionEndsAt: now.addingTimeInterval(600),
            now: now
        )
        expectEqual(load.allowed, false)
        expectFalse(engine.isPlaying)
        expectEqual(engine.lastStopReason, .notAllowlisted)
    }

    func testBudgetStopAndSessionStop() {
        let list = allowlist(with: sampleID)
        let endsAt = now.addingTimeInterval(600)

        let noBudget = policy.evaluateStart(
            videoID: sampleID,
            allowlist: list,
            remainingViewingBudgetSeconds: 0,
            sessionEndsAt: endsAt,
            now: now
        )
        expectEqual(noBudget.stopReason, .budgetExhausted)

        let expired = policy.evaluateStart(
            videoID: sampleID,
            allowlist: list,
            remainingViewingBudgetSeconds: 120,
            sessionEndsAt: now.addingTimeInterval(-1),
            now: now
        )
        expectEqual(expired.stopReason, .sessionExpired)

        let engine = FakePlaybackEngine()
        let started = engine.load(
            videoID: sampleID,
            allowlist: list,
            policy: policy,
            remainingViewingBudgetSeconds: 30,
            sessionEndsAt: endsAt,
            now: now
        )
        expectTrue(started.allowed)
        expectTrue(engine.isPlaying)

        let afterBudget = engine.tick(
            remainingViewingBudgetSeconds: 0,
            sessionEndsAt: endsAt,
            now: now.addingTimeInterval(5),
            policy: policy
        )
        expectEqual(afterBudget.stopReason, .budgetExhausted)
        expectFalse(engine.isPlaying)

        _ = engine.load(
            videoID: sampleID,
            allowlist: list,
            policy: policy,
            remainingViewingBudgetSeconds: 30,
            sessionEndsAt: endsAt,
            now: now
        )
        let afterSession = engine.tick(
            remainingViewingBudgetSeconds: 30,
            sessionEndsAt: endsAt,
            now: endsAt,
            policy: policy
        )
        expectEqual(afterSession.stopReason, .sessionExpired)
        expectFalse(engine.isPlaying)
    }

    func testD8RejectsNonEmbedConstruction() {
        expectTrue(YouTubeEmbedURL.isValidVideoID(sampleID))
        expectFalse(YouTubeEmbedURL.isValidVideoID("short"))
        expectFalse(YouTubeEmbedURL.isValidVideoID("tooooooolongid"))
        expectFalse(YouTubeEmbedURL.isValidVideoID("bad id!!!!"))

        let embed = YouTubeEmbedURL.make(videoID: sampleID)
        expectTrue(embed != nil)
        if let embed {
            expectEqual(embed.host, YouTubeEmbedURL.embedHost)
            expectTrue(embed.path.hasPrefix("/embed/"))
            expectTrue(YouTubeEmbedURL.isAllowedEmbedURL(embed))
        }

        // Arbitrary / non-embed constructions must be rejected.
        let rejected = [
            "https://www.youtube.com/watch?v=\(sampleID)",
            "https://www.youtube.com/results?search_query=kids",
            "https://example.com/",
            "https://www.youtube-nocookie.com/watch?v=\(sampleID)",
            "http://www.youtube-nocookie.com/embed/\(sampleID)",
            "https://evil.example/embed/\(sampleID)",
            "javascript:alert(1)",
            "file:///etc/passwd",
            ""
        ]
        for url in rejected {
            expectTrue(YouTubeEmbedURL.rejectsArbitraryURL(url))
            expectEqual(policy.evaluateNavigation(to: url).stopReason, .navigationRejected)
        }

        // Even a well-formed embed string is not a free child-navigation grant.
        if let embed {
            expectEqual(policy.evaluateNavigation(to: embed.absoluteString).stopReason, .navigationRejected)
        }

        expectTrue(YouTubeEmbedURL.make(videoID: "https://www.youtube.com/watch?v=\(sampleID)") == nil)
    }

    func testExtractVideoIDForParentPaste() {
        let accepted = [
            sampleID,
            "  \(sampleID)\n",
            "https://www.youtube.com/watch?v=\(sampleID)",
            "https://youtube.com/watch?list=PL123&t=30&v=\(sampleID)",
            "http://m.youtube.com/watch?v=\(sampleID)&t=30",
            "https://youtu.be/\(sampleID)?t=30",
            "http://youtu.be/\(sampleID)",
            "https://www.youtube.com/embed/\(sampleID)?start=30",
            "https://www.youtube-nocookie.com/embed/\(sampleID)"
        ]
        for value in accepted {
            expectEqual(YouTubeEmbedURL.extractVideoID(from: value), sampleID)
        }

        let rejected = [
            "", "short", "dQw4w9WgXc!", "abcdefghijé",
            "https://www.youtube.com/results?search_query=kids",
            "https://www.youtube.com/channel/\(sampleID)",
            "https://www.youtube.com/playlist?list=\(sampleID)",
            "https://www.youtube.com/watch?list=PL123",
            "https://www.youtube.com/watch?v=short",
            "https://www.youtube.com/watch?v=\(sampleID)&v=\(otherID)",
            "https://youtu.be/\(sampleID)/extra",
            "https://evil.example/watch?v=\(sampleID)",
            "https://youtube.com.evil.example/watch?v=\(sampleID)",
            "https://user@youtube.com/watch?v=\(sampleID)",
            "ftp://youtube.com/watch?v=\(sampleID)"
        ]
        for value in rejected {
            expectNil(YouTubeEmbedURL.extractVideoID(from: value))
        }

        // A parent-paste URL must remain forbidden as a child navigation target.
        expectTrue(YouTubeEmbedURL.rejectsArbitraryURL("https://www.youtube.com/watch?v=\(sampleID)"))
    }

    func testApprovedVideoParentLabelAndUpsert() {
        var list = VideoAllowlist()
        expectFalse(list.upsert(ApprovedVideo(id: "", durationSeconds: 10)))
        expectFalse(list.upsert(ApprovedVideo(id: sampleID, durationSeconds: -1)))
        expectTrue(list.upsert(ApprovedVideo(
            id: "  \(sampleID)  ",
            titleEnglish: "A",
            titleCantonese: "甲",
            durationSeconds: 90
        )))
        expectEqual(list.videos.count, 1)
        expectEqual(list.video(id: sampleID)?.parentLabel, "甲 / A")
        expectEqual(list.video(id: sampleID)?.parentListTitle, "甲 / A")
        expectTrue(list.video(id: sampleID)?.hasParentTitle == true)
        expectTrue(list.upsert(ApprovedVideo(id: sampleID, titleEnglish: "B", durationSeconds: 91)))
        expectEqual(list.videos.count, 1)
        expectEqual(list.video(id: sampleID)?.titleEnglish, "B")
        // Untitled: parentLabel still falls back to id; list title uses bilingual placeholder
        // so the raw id can stay visible as a secondary line in parent UI.
        expectTrue(list.upsert(ApprovedVideo(id: sampleID, durationSeconds: 92)))
        expectEqual(list.video(id: sampleID)?.parentLabel, sampleID)
        expectEqual(list.video(id: sampleID)?.parentListTitle, "(未命名 / Untitled)")
        expectTrue(list.video(id: sampleID)?.hasParentTitle == false)
    }

    func testYouTubeThumbnailURLDerivedFromID() {
        let url = YouTubeEmbedURL.thumbnailURL(videoID: sampleID)
        expectEqual(url?.absoluteString, "https://img.youtube.com/vi/\(sampleID)/hqdefault.jpg")
        expectNil(YouTubeEmbedURL.thumbnailURL(videoID: ""))
        expectNil(YouTubeEmbedURL.thumbnailURL(videoID: "short"))
        expectNil(YouTubeEmbedURL.thumbnailURL(videoID: "bad id!!!!"))
        // ApprovedVideo exposes the same derived URL; nothing persisted.
        let video = ApprovedVideo(id: sampleID, durationSeconds: 60)
        expectEqual(video.thumbnailURL?.absoluteString, url?.absoluteString)
        expectNil(ApprovedVideo(id: "not-valid!", durationSeconds: 60).thumbnailURL)
    }

    func testAllowedEmbedMainFrameURLPolicy() {
        expectTrue(YouTubeEmbedURL.isBenignBlankURL(nil))
        expectTrue(YouTubeEmbedURL.isBenignBlankURL(URL(string: "about:blank")))
        expectFalse(YouTubeEmbedURL.isBenignBlankURL(URL(string: "https://www.youtube.com/embed/\(sampleID)")))

        let allowed = [
            "https://www.youtube-nocookie.com/embed/\(sampleID)",
            "https://youtube-nocookie.com/embed/\(sampleID)?playsinline=1",
            "https://www.youtube.com/embed/\(sampleID)",
            "https://youtube.com/embed/\(sampleID)?rel=0",
            "https://m.youtube.com/embed/\(sampleID)"
        ]
        for value in allowed {
            let url = URL(string: value)!
            expectTrue(YouTubeEmbedURL.isAllowedEmbedMainFrameURL(url, videoID: sampleID))
            expectFalse(YouTubeEmbedURL.isClearEscapeURL(url, videoID: sampleID))
        }

        // Construction helper remains nocookie-only.
        let made = YouTubeEmbedURL.make(videoID: sampleID)!
        expectTrue(YouTubeEmbedURL.isAllowedEmbedURL(made))
        expectTrue(YouTubeEmbedURL.isAllowedEmbedMainFrameURL(made, videoID: sampleID))
        expectFalse(YouTubeEmbedURL.isAllowedEmbedURL(URL(string: "https://www.youtube.com/embed/\(sampleID)")!))

        let rejected = [
            "https://www.youtube.com/watch?v=\(sampleID)",
            "https://www.youtube.com/results?search_query=kids",
            "https://www.youtube.com/channel/\(sampleID)",
            "https://www.youtube.com/embed/\(otherID)",
            "https://www.youtube-nocookie.com/embed/\(otherID)",
            "http://www.youtube.com/embed/\(sampleID)",
            "https://evil.example/embed/\(sampleID)",
            "https://www.youtube.com/embed/\(sampleID)/extra"
        ]
        for value in rejected {
            let url = URL(string: value)!
            expectFalse(YouTubeEmbedURL.isAllowedEmbedMainFrameURL(url, videoID: sampleID))
            expectTrue(YouTubeEmbedURL.isClearEscapeURL(url, videoID: sampleID))
        }
    }

    func testEmbedHTMLStringReferrerShell() {
        expectNil(YouTubeEmbedURL.embedHTMLString(videoID: "short"))
        expectNil(YouTubeEmbedURL.embedHTMLString(videoID: "bad id!!!!"))

        let html = YouTubeEmbedURL.embedHTMLString(videoID: sampleID)
        expectTrue(html != nil)
        if let html {
            expectTrue(html.contains("referrerpolicy=\"strict-origin-when-cross-origin\""))
            expectTrue(html.contains("name=\"referrer\" content=\"strict-origin-when-cross-origin\""))
            expectTrue(html.contains("/embed/" + sampleID))
            expectTrue(html.contains("www.youtube-nocookie.com"))
            expectFalse(html.contains("youtube.com/watch"))
        }

        let base = YouTubeEmbedURL.embedHTMLBaseURL()
        expectEqual(base.host, YouTubeEmbedURL.embedHost)
        expectTrue(base.path == "/" || base.path.isEmpty)
        expectTrue(YouTubeEmbedURL.isAllowedEmbedShellMainFrameURL(base))
        expectTrue(YouTubeEmbedURL.isAllowedEmbedShellMainFrameURL(URL(string: "https://youtube-nocookie.com/")!))
        expectFalse(YouTubeEmbedURL.isAllowedEmbedShellMainFrameURL(URL(string: "https://www.youtube.com/")!))
        expectFalse(YouTubeEmbedURL.isAllowedEmbedShellMainFrameURL(
            URL(string: "https://www.youtube.com/watch?v=" + sampleID)!
        ))
        expectFalse(YouTubeEmbedURL.isClearEscapeURL(base, videoID: sampleID))
    }

    func testYouTubeOEmbedURLAndParseFixture() {
        let url = YouTubeOEmbed.requestURL(videoID: sampleID)
        expectTrue(url != nil)
        if let url {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            expectEqual(components?.scheme, "https")
            expectEqual(components?.host, "www.youtube.com")
            expectEqual(components?.path, "/oembed")
            let items = components?.queryItems ?? []
            expectEqual(items.first(where: { $0.name == "format" })?.value, "json")
            expectEqual(
                items.first(where: { $0.name == "url" })?.value,
                "https://www.youtube.com/watch?v=\(sampleID)"
            )
        }
        expectNil(YouTubeOEmbed.requestURL(videoID: ""))
        expectNil(YouTubeOEmbed.requestURL(videoID: "short"))
        expectNil(YouTubeOEmbed.requestURL(videoID: "bad id!!!!"))

        // Fixture JSON only — no live network in unit tests. oEmbed has no duration field.
        let fixture = """
        {
          "title": "Sample Kids Song",
          "author_name": "Example",
          "thumbnail_url": "https://i.ytimg.com/vi/\(sampleID)/hqdefault.jpg",
          "type": "video",
          "provider_name": "YouTube"
        }
        """.data(using: .utf8)!
        let parsed = YouTubeOEmbed.parse(fixture)
        expectEqual(parsed?.title, "Sample Kids Song")
        expectEqual(
            parsed?.thumbnailURL?.absoluteString,
            "https://i.ytimg.com/vi/\(sampleID)/hqdefault.jpg"
        )

        let cjk = """
        {"title":"  兒童車車歌  ","thumbnail_url":"https://i.ytimg.com/vi/\(sampleID)/mqdefault.jpg"}
        """.data(using: .utf8)!
        expectEqual(YouTubeOEmbed.parse(cjk)?.title, "兒童車車歌")

        let emptyTitle = """
        {"title":"   ","thumbnail_url":"not a url"}
        """.data(using: .utf8)!
        let emptyParsed = YouTubeOEmbed.parse(emptyTitle)
        expectTrue(emptyParsed != nil)
        expectNil(emptyParsed?.title)
        expectNil(emptyParsed?.thumbnailURL)

        expectNil(YouTubeOEmbed.parse(Data("not-json".utf8)))
        expectNil(YouTubeOEmbed.parse(Data("{}".utf8))?.title)
    }

    func testPlaybackShuffleAvoidsImmediateRepeatAndReshuffles() {
        let ids = ["vidAAAAAAA1", "vidAAAAAAA2", "vidAAAAAAA3"]
        var shuffle = VideoPlaybackShuffle()
        var rng = SeededGenerator(seed: 42)
        var seen: [String] = []
        for _ in 0..<9 {
            guard let id = shuffle.nextVideoID(from: ids, using: &rng) else {
                fatalError("expected id")
            }
            seen.append(id)
        }
        expectEqual(seen.count, 9)
        // Every id appears exactly 3 times across 3 full decks.
        for id in ids {
            expectEqual(seen.filter { $0 == id }.count, 3)
        }
        // Within each deck of 3, no duplicates; across deck boundaries avoid immediate repeat.
        for i in 1..<seen.count {
            if i % 3 != 0 {
                // interior of a deck — uniqueness checked via set size below
                _ = i
            } else {
                // Boundary between decks: must not immediately repeat lastPlayed.
                expectTrue(seen[i] != seen[i - 1])
            }
        }
        for deckStart in stride(from: 0, to: 9, by: 3) {
            let deck = Set(seen[deckStart..<deckStart + 3])
            expectEqual(deck.count, 3)
        }
        expectEqual(shuffle.lastPlayedVideoID, seen.last)
    }

    func testPlaybackShuffleSingleAndEmpty() {
        var shuffle = VideoPlaybackShuffle()
        var rng = SeededGenerator(seed: 7)
        expectNil(shuffle.nextVideoID(from: [], using: &rng))
        let only = "onlyVideo01"
        expectEqual(shuffle.nextVideoID(from: [only], using: &rng), only)
        expectEqual(shuffle.nextVideoID(from: [only], using: &rng), only)
        expectEqual(shuffle.lastPlayedVideoID, only)
        // Stale queue entry dropped when removed from allowlist.
        shuffle = VideoPlaybackShuffle(remainingIDs: ["goneVideo01", only], lastPlayedVideoID: "goneVideo01")
        expectEqual(shuffle.nextVideoID(from: [only], using: &rng), only)
    }

    func testShuffledDeckAvoidsImmediateFirstRepeat() {
        let ids = ["aaaaaaaaaa1", "aaaaaaaaaa2"]
        for seed in UInt64(1)...40 {
            var rng = SeededGenerator(seed: seed)
            let deck = VideoPlaybackShuffle.shuffledDeck(
                from: ids,
                avoidingImmediateRepeatOf: "aaaaaaaaaa1",
                using: &rng
            )
            expectEqual(Set(deck), Set(ids))
            expectEqual(deck.first, "aaaaaaaaaa2")
        }
    }


    // MARK: - v0.12.0 end-of-video bridge (IFrame API → WKScriptMessageHandler)

    func testEmbedHTMLUsesIFrameAPIBridge() {
        // Constructed embed keeps the same nocookie /embed/<id> path; adds JS API params only.
        let made = YouTubeEmbedURL.make(videoID: sampleID)
        expectTrue(made != nil)
        if let made {
            expectTrue(YouTubeEmbedURL.isAllowedEmbedURL(made))
            expectTrue(YouTubeEmbedURL.isAllowedEmbedMainFrameURL(made, videoID: sampleID))
            let items = URLComponents(url: made, resolvingAgainstBaseURL: false)?.queryItems ?? []
            expectEqual(items.first(where: { $0.name == "enablejsapi" })?.value, "1")
            expectEqual(items.first(where: { $0.name == "origin" })?.value, "https://www.youtube-nocookie.com")
            expectEqual(items.first(where: { $0.name == "rel" })?.value, "0")
            expectEqual(made.path, "/embed/\(sampleID)")
        }
        expectEqual(YouTubeEmbedURL.embedOrigin, "https://www.youtube-nocookie.com")
        expectEqual(YouTubeEmbedURL.iframeAPIScriptURL.absoluteString, "https://www.youtube.com/iframe_api")
        // The API script is not a main-frame navigation grant.
        expectFalse(YouTubeEmbedURL.isAllowedEmbedMainFrameURL(YouTubeEmbedURL.iframeAPIScriptURL, videoID: sampleID))
        expectTrue(YouTubeEmbedURL.isClearEscapeURL(YouTubeEmbedURL.iframeAPIScriptURL, videoID: sampleID))

        guard let html = YouTubeEmbedURL.embedHTMLString(videoID: sampleID) else {
            preconditionFailure("embed HTML missing")
        }
        expectTrue(html.contains("id=\"\(YouTubeEmbedURL.playerElementID)\""))
        expectTrue(html.contains("enablejsapi=1"))
        expectTrue(html.contains("https://www.youtube.com/iframe_api"))
        expectTrue(html.contains("onYouTubeIframeAPIReady"))
        expectTrue(html.contains("onStateChange"))
        expectTrue(html.contains("messageHandlers.\(ScopedPlayerEvent.messageHandlerName)"))
        expectTrue(html.contains("\"ended\""))
        expectTrue(html.contains("var videoID = \"\(sampleID)\""))
        // Iframe src stays the constructed URL (HTML-escaped ampersands).
        if let made {
            expectTrue(html.contains("src=\"" + made.absoluteString.replacingOccurrences(of: "&", with: "&amp;") + "\""))
        }
        // Still no watch page / no window.open / no top navigation in the shell script.
        expectFalse(html.contains("youtube.com/watch"))
        expectFalse(html.contains("window.open"))
        expectFalse(html.contains("location.href"))
        expectEqual(ScopedPlayerEvent.messageHandlerName, "visaPlayer")
    }

    func testScopedPlayerEventParsing() {
        let body: [String: Any] = ["event": "ended", "videoID": sampleID]
        expectEqual(ScopedPlayerEvent.parse(body, expectedVideoID: sampleID), .ended)
        // Stale page for another id is ignored (never routes the current player).
        expectNil(ScopedPlayerEvent.parse(body, expectedVideoID: otherID))
        expectNil(ScopedPlayerEvent.parse(["event": "ended"], expectedVideoID: sampleID))
        expectNil(ScopedPlayerEvent.parse("ended", expectedVideoID: sampleID))
        expectNil(ScopedPlayerEvent.parse(["event": "navigate", "videoID": sampleID], expectedVideoID: sampleID))

        let state0 = ScopedPlayerEvent.parse(["event": "state", "videoID": sampleID, "state": 0], expectedVideoID: sampleID)
        expectEqual(state0, .stateChanged(0))
        expectTrue(state0?.indicatesEnded == true)
        let playing = ScopedPlayerEvent.parse(["event": "state", "videoID": sampleID, "state": 1.0], expectedVideoID: sampleID)
        expectEqual(playing, .stateChanged(1))
        expectTrue(playing?.indicatesEnded == false)
        expectEqual(YouTubePlayerState.label(0), "ended")
        expectEqual(YouTubePlayerState.label(1), "playing")
        expectEqual(YouTubePlayerState.label(42), "unknown(42)")

        expectEqual(
            ScopedPlayerEvent.parse(["event": "ready", "videoID": sampleID, "duration": 312.4], expectedVideoID: sampleID),
            .ready(durationSeconds: 312.4)
        )
        expectEqual(
            ScopedPlayerEvent.parse(["event": "ready", "videoID": sampleID, "duration": 0], expectedVideoID: sampleID),
            .ready(durationSeconds: nil)
        )
        expectEqual(
            ScopedPlayerEvent.parse(["event": "duration", "videoID": sampleID, "seconds": 300], expectedVideoID: sampleID),
            .duration(300)
        )
        expectNil(ScopedPlayerEvent.parse(["event": "duration", "videoID": sampleID, "seconds": -3], expectedVideoID: sampleID))
        expectEqual(
            ScopedPlayerEvent.parse(["event": "apiError", "videoID": sampleID, "detail": "timeout"], expectedVideoID: sampleID),
            .apiUnavailable("timeout")
        )

        // Debounce: one ended per load; a new load re-arms.
        var latch = PlaybackEndLatch()
        expectTrue(latch.shouldReportEnd(videoID: sampleID, loadedVideoID: sampleID))
        expectFalse(latch.shouldReportEnd(videoID: sampleID, loadedVideoID: sampleID))
        expectFalse(latch.shouldReportEnd(videoID: otherID, loadedVideoID: sampleID))
        latch.reset()
        expectTrue(latch.shouldReportEnd(videoID: sampleID, loadedVideoID: sampleID))
        var unloaded = PlaybackEndLatch()
        expectFalse(unloaded.shouldReportEnd(videoID: sampleID, loadedVideoID: nil))
    }

    func testParentAllowlistDraftStatus() {
        let list = allowlist(with: sampleID)
        expectEqual(ParentAllowlistDraft.evaluate("", allowlist: list), .empty)
        expectEqual(ParentAllowlistDraft.evaluate("   ", allowlist: list), .empty)
        expectEqual(ParentAllowlistDraft.evaluate("not a video", allowlist: list), .invalid)
        expectEqual(ParentAllowlistDraft.evaluate("https://example.com/watch?v=\(otherID)", allowlist: list), .invalid)
        expectEqual(ParentAllowlistDraft.evaluate("https://youtu.be/\(otherID)", allowlist: list), .ready(videoID: otherID))
        expectEqual(ParentAllowlistDraft.evaluate(" \(otherID) ", allowlist: list), .ready(videoID: otherID))
        expectEqual(
            ParentAllowlistDraft.evaluate("https://www.youtube.com/watch?v=\(sampleID)", allowlist: list),
            .alreadyAllowlisted(videoID: sampleID)
        )
        expectEqual(ParentAllowlistDraft.ready(videoID: otherID).videoID, otherID)
        expectNil(ParentAllowlistDraft.invalid.videoID)
        expectTrue(ParentAllowlistDraft.ready(videoID: otherID).canAdd)
        expectFalse(ParentAllowlistDraft.alreadyAllowlisted(videoID: sampleID).canAdd)
        expectFalse(ParentAllowlistDraft.invalid.canAdd)
    }

    func testApprovedVideoDurationLabelAndLegacyDecode() throws {
        expectEqual(ApprovedVideo.clockLabel(seconds: 0), "0:00")
        expectEqual(ApprovedVideo.clockLabel(seconds: 65), "1:05")
        expectEqual(ApprovedVideo.clockLabel(seconds: 312.6), "5:13")
        expectEqual(ApprovedVideo.clockLabel(seconds: 3_725), "1:02:05")
        expectEqual(ApprovedVideo.clockLabel(seconds: .nan), "0:00")

        // Nominal budget duration is marked approximate until the player reports a real length.
        var video = ApprovedVideo(id: sampleID, durationSeconds: 120)
        expectEqual(video.parentDurationLabel, "~2:00")
        expectFalse(video.hasPlayerDuration)
        video.playerDurationSeconds = 301
        expectEqual(video.parentDurationLabel, "5:01")
        expectTrue(video.hasPlayerDuration)

        var list = allowlist(with: sampleID)
        expectTrue(list.recordPlayerDuration(id: sampleID, seconds: 301))
        expectEqual(list.video(id: sampleID)?.playerDurationSeconds, 301)
        // Sub-second jitter does not churn storage; unknown ids and bad values are ignored.
        expectFalse(list.recordPlayerDuration(id: sampleID, seconds: 301.4))
        expectFalse(list.recordPlayerDuration(id: otherID, seconds: 50))
        expectFalse(list.recordPlayerDuration(id: sampleID, seconds: 0))
        expectFalse(list.recordPlayerDuration(id: sampleID, seconds: .infinity))
        // D4 budget-fit duration untouched.
        expectEqual(list.video(id: sampleID)?.durationSeconds, 120)

        // Pre-v0.12.0 allowlist JSON (no playerDurationSeconds) still decodes.
        let legacy = Data(#"{"videos":[{"id":"\#(sampleID)","titleEnglish":"Old","durationSeconds":120}]}"#.utf8)
        let decoded = try JSONDecoder().decode(VideoAllowlist.self, from: legacy)
        expectEqual(decoded.videos.count, 1)
        expectNil(decoded.videos[0].playerDurationSeconds)
        expectEqual(decoded.videos[0].parentDurationLabel, "~2:00")
        // Round-trip keeps the measured duration.
        let again = try JSONDecoder().decode(VideoAllowlist.self, from: JSONEncoder().encode(list))
        expectEqual(again.video(id: sampleID)?.playerDurationSeconds, 301)
    }
}
