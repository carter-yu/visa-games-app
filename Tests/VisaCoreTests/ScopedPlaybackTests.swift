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
        expectTrue(list.upsert(ApprovedVideo(id: sampleID, titleEnglish: "B", durationSeconds: 91)))
        expectEqual(list.videos.count, 1)
        expectEqual(list.video(id: sampleID)?.titleEnglish, "B")
    }
}
