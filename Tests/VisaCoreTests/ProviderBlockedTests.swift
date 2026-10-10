import Foundation
import VisaCore

/// v0.21.1 YouTube blocked fallback: credit caps, 2-strike rule, watchdog.
final class ProviderBlockedTests {
    func testCreditCapsPerLoadAndPerVisa() {
        var state = ProviderBlockedPolicy.CreditState()
        expectEqual(ProviderBlockedPolicy.creditSeconds(elapsed: 5, state: state), 5)
        expectEqual(ProviderBlockedPolicy.creditSeconds(elapsed: 90, state: state), 60)
        state.creditedSeconds = 150
        expectEqual(ProviderBlockedPolicy.creditSeconds(elapsed: 60, state: state), 30)
        state.creditedSeconds = 180
        expectEqual(ProviderBlockedPolicy.creditSeconds(elapsed: 60, state: state), 0)
    }

    func testTwoStrikeRuleReturnsPickerThenTimesUp() {
        var state = ProviderBlockedPolicy.CreditState()
        let first = ProviderBlockedPolicy.applyBlocked(videoID: "dQw4w9WgXcQ", elapsed: 12, state: state)
        guard case .returnToPicker(let c1, let s1) = first else {
            expectTrue(false, "first should return to picker")
            return
        }
        expectEqual(c1, 12)
        expectEqual(s1.strikes, 1)
        expectTrue(s1.unavailableIDs.contains("dQw4w9WgXcQ"))
        state = s1
        let second = ProviderBlockedPolicy.applyBlocked(videoID: "aaaaaaaaaaa", elapsed: 40, state: state)
        guard case .timesUp(let c2, let bank, let s2) = second else {
            expectTrue(false, "second should times up")
            return
        }
        expectEqual(c2, 40)
        expectTrue(bank)
        expectEqual(s2.strikes, 2)
        expectEqual(s2.unavailableIDs.count, 2)
    }

    func testWatchdogReadyNeverPlaying() {
        expectFalse(ProviderBlockedPolicy.watchdogFired(readySeen: false, playingSeen: false, elapsed: 20))
        expectFalse(ProviderBlockedPolicy.watchdogFired(readySeen: true, playingSeen: true, elapsed: 20))
        expectFalse(ProviderBlockedPolicy.watchdogFired(readySeen: true, playingSeen: false, elapsed: 11))
        expectTrue(ProviderBlockedPolicy.watchdogFired(readySeen: true, playingSeen: false, elapsed: 12))
    }

    func testVisaCreditExtendsEndsAt() {
        let now = Date(timeIntervalSince1970: 2_000)
        var session = Session(snapshot: .init(configured: true), now: now)
        session.startPlayVisa(seconds: 600, now: now)
        let before = session.snapshot.endsAt!
        session.creditVisaSeconds(45, now: now)
        expectEqual(session.snapshot.endsAt!.timeIntervalSince(before), 45, accuracy: 0.01)
        session.endPlayVisa(now: before.addingTimeInterval(700))
        expectEqual(session.snapshot.endsAt, nil as Date?)
        session.creditVisaSeconds(30, now: now)
        expectEqual(session.snapshot.endsAt, nil as Date?)
    }

    func testRoutingAndIncompleteSkipProviderBlocked() {
        expectEqual(VideoEndRouting.afterPlaybackStopped(reason: .providerBlocked, isChildPlay: true), .videoPicker)
        expectFalse(IncompletePlaybackPolicy.shouldSaveOnStop(isChildPlay: true, reason: .providerBlocked, positionSeconds: 12))
        expectEqual(PerfVideoStopReason.blocked.rawValue, "blocked")
        expectEqual(PlaybackStopReason.providerBlocked.rawValue, "providerBlocked")
    }

    func testSafariUserAgentSuffix() {
        let ua = SafariUserAgent.applicationName(safariVersion: "18.2")
        expectEqual(ua, "Version/18.2 Safari/605.1.15")
        expectTrue(SafariUserAgent.applicationName().contains("Safari/605.1.15"))
    }

    func testWebsiteDataStoreDefaultSourceGuard() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let text = try String(contentsOf: root.appendingPathComponent("Sources/VisaGames/ScopedPlayerView.swift"), encoding: .utf8)
        expectTrue(text.contains("websiteDataStore = .default()"))
        expectFalse(text.contains("nonPersistent"))
        expectTrue(text.contains("applicationNameForUserAgent"))
        expectTrue(text.contains("onProviderBlocked"))
        expectTrue(text.contains("bot-check detected"))
    }
}
