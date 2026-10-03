import Foundation
import VisaCore

final class ChildUXProgressTests {
    func testAutoHintAfterTwoMisses() {
        expectFalse(ActivityHintPolicy.shouldAutoHint(afterMissCount: 0))
        expectFalse(ActivityHintPolicy.shouldAutoHint(afterMissCount: 1))
        expectTrue(ActivityHintPolicy.shouldAutoHint(afterMissCount: 2))
        expectTrue(ActivityHintPolicy.shouldAutoHint(afterMissCount: 3))
        expectEqual(ActivityHintPolicy.missesBeforeAutoHint, 2)
    }

    func testRoadTimerFractionAndMinutes() {
        let mid = RoadTimerProgress(elapsed: 300, total: 600, remaining: 300)
        expectClose(mid.fraction, 0.5)
        expectEqual(mid.remainingMinutesCeil, 5)
        expectFalse(mid.almostHome)

        let almost = RoadTimerProgress(elapsed: 560, total: 600, remaining: 40)
        expectClose(almost.fraction, 560.0 / 600.0)
        expectEqual(almost.remainingMinutesCeil, 1)
        expectTrue(almost.almostHome)

        let done = RoadTimerProgress(elapsed: 600, total: 600, remaining: 0)
        expectEqual(done.fraction, 1)
        expectEqual(done.remainingMinutesCeil, 0)
        expectFalse(done.almostHome)
    }

    func testRoadTimerFromEndsAt() {
        let now = Date(timeIntervalSince1970: 10_000)
        let ends = now.addingTimeInterval(90)
        let progress = RoadTimerProgress.from(endsAt: ends, totalSeconds: 600, now: now)
        expectEqual(progress.remainingMinutesCeil, 2)
        expectTrue(progress.almostHome == false) // 90s > 60
        let near = RoadTimerProgress.from(endsAt: now.addingTimeInterval(45), totalSeconds: 600, now: now)
        expectTrue(near.almostHome)
        expectEqual(near.remainingMinutesCeil, 1)
    }

    func testSpokenUXLinesAreTraditional() {
        for line in SpokenPrompt.allUXLines {
            expectFalse(line.traditionalChinese.isEmpty)
            expectFalse(line.english.isEmpty)
            expectTrue(isTraditionalChineseOnly(line.traditionalChinese))
        }
        expectEqual(SpokenPrompt.stamped.traditionalChinese, "蓋印！")
        expectEqual(SpokenPrompt.almostHome.traditionalChinese, "快到屋企喇！")
        expectEqual(SpokenPrompt.pickVideo.traditionalChinese, "揀片睇！")
        expectEqual(SpokenPrompt.pickVideo.english, "Pick a video!")
        expectTrue(SpokenPrompt.allUXLines.contains(.pickVideo))
        expectEqual(SpokenPrompt.resumeChoiceKeepWatching.traditionalChinese, "仲可以繼續睇！")
        expectEqual(SpokenPrompt.resumeChoiceKeepWatching.english, "You can keep watching!")
        expectEqual(SpokenPrompt.resumeChoiceOrPick.traditionalChinese, "定係揀第二條？")
        expectTrue(SpokenPrompt.allUXLines.contains(.resumeChoiceKeepWatching))
        expectTrue(SpokenPrompt.allUXLines.contains(.resumeChoiceOrPick))
        // Never Simplified forms.
        expectFalse(SpokenPrompt.resumeChoiceKeepWatching.traditionalChinese.contains("继续"))
        expectFalse(SpokenPrompt.resumeChoiceOrPick.traditionalChinese.contains("选"))
        let fire = SpokenPrompt.timesUp(for: MissionTicket.all[1])
        expectTrue(fire.traditionalChinese.contains("消防車"))
        expectTrue(fire.traditionalChinese.contains("瞓覺"))
        expectTrue(isTraditionalChineseOnly(fire.traditionalChinese))
    }

    func testPlayStageRoutesPickerBeforeWatch() {
        // Stamp gate always wins while awaiting 「出發！」.
        expectEqual(PlayStageRoute.route(awaitingDeparture: true, allowlistCount: 3, activeVideoID: nil), .stamp)
        expectEqual(PlayStageRoute.route(awaitingDeparture: true, allowlistCount: 0, activeVideoID: nil), .stamp)
        // After Go: empty allowlist keeps the empty stage (even with a stale resume flag).
        expectEqual(PlayStageRoute.route(awaitingDeparture: false, allowlistCount: 0, activeVideoID: nil), .emptyAllowlist)
        expectEqual(PlayStageRoute.route(awaitingDeparture: false, allowlistCount: 0, activeVideoID: nil, hasResumeCandidate: true), .emptyAllowlist)
        // Non-empty, nothing picked, no incomplete → picker (one video still shows the picker).
        expectEqual(PlayStageRoute.route(awaitingDeparture: false, allowlistCount: 1, activeVideoID: nil), .videoPicker)
        expectEqual(PlayStageRoute.route(awaitingDeparture: false, allowlistCount: 4, activeVideoID: nil), .videoPicker)
        // Picked → watch (watch wins over resume candidate).
        expectEqual(PlayStageRoute.route(awaitingDeparture: false, allowlistCount: 4, activeVideoID: "abc"), .watch)
        expectEqual(PlayStageRoute.route(awaitingDeparture: false, allowlistCount: 4, activeVideoID: "abc", hasResumeCandidate: true), .watch)
    }

    /// v0.15.0: after 「出發！」with an incomplete cursor → Resume Choice (not immediate picker).
    func testPlayStageRoutesResumeChoiceAfterGoWhenIncomplete() {
        // Stamp still wins while awaiting Go, even with incomplete.
        expectEqual(PlayStageRoute.route(
            awaitingDeparture: true, allowlistCount: 3, activeVideoID: nil, hasResumeCandidate: true
        ), .stamp)
        // After Go + incomplete → Resume Choice (primary path).
        expectEqual(PlayStageRoute.route(
            awaitingDeparture: false, allowlistCount: 3, activeVideoID: nil, hasResumeCandidate: true
        ), .resumeChoice)
        expectEqual(PlayStageRoute.route(
            awaitingDeparture: false, allowlistCount: 1, activeVideoID: nil, hasResumeCandidate: true
        ), .resumeChoice)
        // No incomplete → picker (fallback / first trip with no mid-stop).
        expectEqual(PlayStageRoute.route(
            awaitingDeparture: false, allowlistCount: 3, activeVideoID: nil, hasResumeCandidate: false
        ), .videoPicker)
        // After Right clears cursor, hasResumeCandidate=false → picker (no mint banner needed).
        expectEqual(PlayStageRoute.route(
            awaitingDeparture: false, allowlistCount: 6, activeVideoID: nil, hasResumeCandidate: false
        ), .videoPicker)
    }

    func testPlayPresentationResolvesTicket() {
        expectEqual(PlayPresentation.ticket(selectedStars: nil).difficulty, .easy)
        expectEqual(PlayPresentation.ticket(selectedStars: 1).difficulty, .easy)
        expectEqual(PlayPresentation.ticket(selectedStars: 2).difficulty, .medium)
        expectEqual(PlayPresentation.ticket(selectedStars: 3).difficulty, .challenge)
        expectEqual(PlayPresentation.ticket(selectedStars: 99).difficulty, .easy)
        expectEqual(PlayPresentation.stars(fromAwardedSeconds: 300), 1)
        expectEqual(PlayPresentation.stars(fromAwardedSeconds: 600), 2)
        expectEqual(PlayPresentation.stars(fromAwardedSeconds: 900), 3)
        expectTrue(PlayPresentation.stars(fromAwardedSeconds: 0) == nil)
        expectTrue(PlayPresentation.stars(fromAwardedSeconds: 60) == nil)
        // Legacy 10/20/30 awards no longer map (tiers superseded 2026-10-02).
        expectTrue(PlayPresentation.stars(fromAwardedSeconds: 1_200) == nil)
        expectTrue(PlayPresentation.stars(fromAwardedSeconds: 1_800) == nil)
        // Cold-start mid-visa with allowlist → picker (not stamp); empty → emptyAllowlist.
        expectEqual(PlayStageRoute.route(awaitingDeparture: false, allowlistCount: 2, activeVideoID: nil), .videoPicker)
        expectEqual(PlayStageRoute.route(awaitingDeparture: false, allowlistCount: 0, activeVideoID: nil), .emptyAllowlist)
    }

    // MARK: - v0.12.0 end-of-video flow (Carter UAT: stuck on YouTube end card with time left)

    func testVideoEndedRoutesPickerWhenTimeLeft() {
        let now = Date(timeIntervalSince1970: 50_000)
        // ~5 min video ended inside a 20 min visa with 12 min left → back to the picker.
        expectEqual(VideoEndRouting.afterVideoEnded(
            isChildPlay: true, hasActiveVideo: true,
            remainingViewingBudgetSeconds: 1_200, sessionEndsAt: now.addingTimeInterval(720), now: now
        ), .videoPicker)
        // One second left still counts as time left.
        expectEqual(VideoEndRouting.afterVideoEnded(
            isChildPlay: true, hasActiveVideo: true,
            remainingViewingBudgetSeconds: 1, sessionEndsAt: now.addingTimeInterval(1), now: now
        ), .videoPicker)
        // Parent preview: just stop (never TimesUp / never ends a visa).
        expectEqual(VideoEndRouting.afterVideoEnded(
            isChildPlay: false, hasActiveVideo: true,
            remainingViewingBudgetSeconds: 0, sessionEndsAt: nil, now: now
        ), .stopPreview)
        // Stale / duplicate ended after the player was already cleared → ignore.
        expectEqual(VideoEndRouting.afterVideoEnded(
            isChildPlay: true, hasActiveVideo: false,
            remainingViewingBudgetSeconds: 600, sessionEndsAt: now.addingTimeInterval(600), now: now
        ), .ignore)
    }

    func testVideoEndedRoutesTimesUpWhenNoTimeLeft() {
        let now = Date(timeIntervalSince1970: 50_000)
        // Viewing budget empty while the road still has minutes → TimesUp, not a dead picker.
        expectEqual(VideoEndRouting.afterVideoEnded(
            isChildPlay: true, hasActiveVideo: true,
            remainingViewingBudgetSeconds: 0, sessionEndsAt: now.addingTimeInterval(720), now: now
        ), .timesUp)
        // Visa already over (or exactly now).
        expectEqual(VideoEndRouting.afterVideoEnded(
            isChildPlay: true, hasActiveVideo: true,
            remainingViewingBudgetSeconds: 600, sessionEndsAt: now, now: now
        ), .timesUp)
        expectEqual(VideoEndRouting.afterVideoEnded(
            isChildPlay: true, hasActiveVideo: true,
            remainingViewingBudgetSeconds: 600, sessionEndsAt: nil, now: now
        ), .timesUp)
        // Non-finite budget fails closed.
        expectEqual(VideoEndRouting.afterVideoEnded(
            isChildPlay: true, hasActiveVideo: true,
            remainingViewingBudgetSeconds: .nan, sessionEndsAt: now.addingTimeInterval(60), now: now
        ), .timesUp)
    }

    func testPlaybackStopRouting() {
        // Mid-video tick stop for no time left → TimesUp in child play.
        expectEqual(VideoEndRouting.afterPlaybackStopped(reason: .budgetExhausted, isChildPlay: true), .timesUp)
        expectEqual(VideoEndRouting.afterPlaybackStopped(reason: .sessionExpired, isChildPlay: true), .timesUp)
        // D8 navigation reject keeps the existing behaviour: back to the picker.
        expectEqual(VideoEndRouting.afterPlaybackStopped(reason: .navigationRejected, isChildPlay: true), .videoPicker)
        expectEqual(VideoEndRouting.afterPlaybackStopped(reason: .notAllowlisted, isChildPlay: true), .videoPicker)
        expectEqual(VideoEndRouting.afterPlaybackStopped(reason: .invalidVideoID, isChildPlay: true), .videoPicker)
        // Parent preview never ends a visa.
        for reason in [PlaybackStopReason.budgetExhausted, .sessionExpired, .navigationRejected] {
            expectEqual(VideoEndRouting.afterPlaybackStopped(reason: reason, isChildPlay: false), .stopPreview)
        }
        // Picker → watch → (ended, time left) → picker again.
        expectEqual(PlayStageRoute.route(awaitingDeparture: false, allowlistCount: 3, activeVideoID: nil), .videoPicker)
    }

    func testIncompletePlaybackPolicyMatchesProductLock() {
        // Parent never saves; child time-out with position does.
        expectFalse(IncompletePlaybackPolicy.shouldSaveOnStop(
            isChildPlay: false, reason: .sessionExpired, positionSeconds: 20
        ))
        expectTrue(IncompletePlaybackPolicy.shouldSaveOnStop(
            isChildPlay: true, reason: .sessionExpired, positionSeconds: 20
        ))
    }

    /// v0.19.0: one Fisher–Yates of the full allowlist per visit seed. Pages are slices.
    func testVideoPickerDeckIsStableAndNotAlwaysCatalogOrder() {
        let catalog = (0..<11).map { "id-\($0)" }
        var differed = false
        var sample = catalog
        for index in 0..<48 {
            let seed = "visit-\(index)"
            let once = VideoPickerDeck.ordered(catalog, seed: seed)
            let twice = VideoPickerDeck.ordered(catalog, seed: seed)
            expectEqual(once, twice)
            expectEqual(Set(once), Set(catalog))
            if once != catalog {
                differed = true
                sample = once
                // Page 1 is the first 8 of that deck, not a shuffle of a page.
                expectEqual(VideoPickerDeck.page(once, index: 0), Array(once.prefix(8)))
                expectEqual(VideoPickerDeck.page(once, index: 1), Array(once.dropFirst(8)))
                expectEqual(VideoPickerDeck.page(once, index: 1).count, 3)
                break
            }
        }
        expectTrue(differed)
        expectEqual(sample.count, 11)

        // 0 videos: not a picker page. 1 video: one card, no pager. 2–8: one page. 9+: pager.
        expectEqual(VideoPickerDeck.pageCount(itemCount: 0), 0)
        expectFalse(VideoPickerDeck.showsPager(itemCount: 0))
        expectEqual(VideoPickerDeck.ordered(["only"], seed: "solo"), ["only"])
        expectEqual(VideoPickerDeck.pageCount(itemCount: 1), 1)
        expectFalse(VideoPickerDeck.showsPager(itemCount: 1))
        expectEqual(VideoPickerDeck.pageCount(itemCount: 8), 1)
        expectFalse(VideoPickerDeck.showsPager(itemCount: 8))
        let eight = (0..<8).map { "e\($0)" }
        var eightDiffered = false
        for index in 0..<24 {
            let seed = "page-\(index)"
            let eightDeck = VideoPickerDeck.ordered(eight, seed: seed)
            expectEqual(eightDeck, VideoPickerDeck.ordered(eight, seed: seed))
            expectEqual(Set(eightDeck), Set(eight))
            expectEqual(VideoPickerDeck.page(eightDeck, index: 0), eightDeck)
            expectTrue(VideoPickerDeck.page(eightDeck, index: 1).isEmpty)
            if eightDeck != eight { eightDiffered = true }
        }
        expectTrue(eightDiffered)
        expectEqual(VideoPickerDeck.pageCount(itemCount: 9), 2)
        expectTrue(VideoPickerDeck.showsPager(itemCount: 9))
        // Same items, different visit seed, can differ. A refresh of one seed cannot.
        let other = VideoPickerDeck.ordered(catalog, seed: "visit-other")
        expectEqual(other, VideoPickerDeck.ordered(catalog, seed: "visit-other"))
    }

    /// v0.19.0: dock is a pure function of the visit seed, one of three x positions, y fixed.
    func testBayDockIsStableAcrossRefreshAndUsesThreeBays() {
        let seed = "stamp-gate"
        let dock = BayDock.chosen(seed: seed)
        expectEqual(dock, BayDock.chosen(seed: seed))
        expectEqual(BayDock.canvasY, 560)
        let allowed = [BayDock.left.leadingX, BayDock.center.leadingX, BayDock.right.leadingX]
        expectEqual(allowed, [72, 400, 760])
        expectTrue(allowed.contains(dock.leadingX))
        for bay in BayDock.allCases {
            expectTrue(bay.leadingX + BayDock.pairBudget <= BayDock.clearLeadingEdge)
            expectEqual(BayDock.canvasY, 560)
        }
        var seen = Set<Int>()
        for index in 0..<80 {
            let bay = BayDock.chosen(seed: "dock-\(index)")
            expectEqual(bay, BayDock.chosen(seed: "dock-\(index)"))
            expectTrue(allowed.contains(bay.leadingX))
            seen.insert(bay.leadingX)
        }
        expectEqual(seen, Set(allowed))
        // Time's up uses its own seed string; a stamp seed and a times-up seed are independent calls.
        let timesUp = BayDock.chosen(seed: "times-up-visit")
        expectEqual(timesUp, BayDock.chosen(seed: "times-up-visit"))
        expectTrue(allowed.contains(timesUp.leadingX))
    }
}


private func expectClose(_ actual: Double, _ expected: Double, file: StaticString = #file, line: UInt = #line) {
    precondition(abs(actual - expected) < 0.0001, "Expected \(expected), got \(actual)", file: file, line: line)
}
