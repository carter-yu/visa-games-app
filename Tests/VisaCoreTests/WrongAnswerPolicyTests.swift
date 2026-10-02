import Foundation
import VisaCore

final class WrongAnswerPolicyTests {
    func testHalveChainsFifteenTenFiveToZero() {
        // 15 → 7 → 3 → 1 → 0
        var pending = 15
        pending = WrongAnswerPolicy.halvedPendingMinutes(pending)
        expectEqual(pending, 7)
        pending = WrongAnswerPolicy.halvedPendingMinutes(pending)
        expectEqual(pending, 3)
        pending = WrongAnswerPolicy.halvedPendingMinutes(pending)
        expectEqual(pending, 1)
        pending = WrongAnswerPolicy.halvedPendingMinutes(pending)
        expectEqual(pending, 0)
        expectEqual(WrongAnswerPolicy.halvedPendingMinutes(0), 0)

        // 10 → 5 → 2 → 1 → 0
        pending = 10
        expectEqual(WrongAnswerPolicy.halvedPendingMinutes(pending), 5)
        pending = 5
        expectEqual(WrongAnswerPolicy.halvedPendingMinutes(pending), 2)
        pending = 2
        expectEqual(WrongAnswerPolicy.halvedPendingMinutes(pending), 1)
        pending = 1
        expectEqual(WrongAnswerPolicy.halvedPendingMinutes(pending), 0)

        // 5 → 2 → 1 → 0
        pending = 5
        expectEqual(WrongAnswerPolicy.halvedPendingMinutes(pending), 2)
        pending = 2
        expectEqual(WrongAnswerPolicy.halvedPendingMinutes(pending), 1)
        pending = 1
        expectEqual(WrongAnswerPolicy.halvedPendingMinutes(pending), 0)
    }

    func testTapsIgnoredDuringPause() {
        expectFalse(WrongAnswerPolicy.shouldAcceptChoiceInput(choicesLocked: true))
        expectTrue(WrongAnswerPolicy.shouldAcceptChoiceInput(choicesLocked: false))
    }

    func testEveryMissStartsPauseDurationAndDepotAtZero() {
        expectEqual(WrongAnswerPolicy.thinkPauseSeconds, 10)
        expectFalse(WrongAnswerPolicy.shouldReturnToDepot(pendingMinutes: 15))
        expectFalse(WrongAnswerPolicy.shouldReturnToDepot(pendingMinutes: 1))
        expectTrue(WrongAnswerPolicy.shouldReturnToDepot(pendingMinutes: 0))
        expectTrue(WrongAnswerPolicy.shouldReturnToDepot(pendingMinutes: -1))
    }

    func testCorrectAwardsReducedPendingSeconds() {
        expectEqual(WrongAnswerPolicy.awardSeconds(fromPendingMinutes: 15), 900)
        expectEqual(WrongAnswerPolicy.awardSeconds(fromPendingMinutes: 7), 420)
        expectEqual(WrongAnswerPolicy.awardSeconds(fromPendingMinutes: 3), 180)
        expectEqual(WrongAnswerPolicy.awardSeconds(fromPendingMinutes: 1), 60)
        expectEqual(WrongAnswerPolicy.awardSeconds(fromPendingMinutes: 0), 0)
        // Zero pending never starts a play visa (caller must not call startPlayVisa).
        expectTrue(WrongAnswerPolicy.shouldReturnToDepot(pendingMinutes: 0))
    }

    func testRoadTilesFollowEarnedMinutesStarsIndependent() {
        expectEqual(WrongAnswerPolicy.roadTiles(forEarnedMinutes: 15), 3)
        expectEqual(WrongAnswerPolicy.roadTiles(forEarnedMinutes: 10), 2)
        expectEqual(WrongAnswerPolicy.roadTiles(forEarnedMinutes: 5), 1)
        expectEqual(WrongAnswerPolicy.roadTiles(forEarnedMinutes: 7), 2) // ceil 7/5
        expectEqual(WrongAnswerPolicy.roadTiles(forEarnedMinutes: 3), 1)
        expectEqual(WrongAnswerPolicy.roadTiles(forEarnedMinutes: 1), 1)
        expectEqual(WrongAnswerPolicy.roadTiles(forEarnedMinutes: 0), 0)
        // Stars stay difficulty-chosen (ticket), not re-derived from reduced minutes.
        expectEqual(ChildDifficulty.challenge.rawValue, 3)
        expectEqual(ChildDifficulty.challenge.minutes, 15)
    }

    func testParentGrantPathUntouchedByPolicy() {
        // Policy never mutates Session / RewardLedger — parent grant remains a separate seam.
        var session = Session(snapshot: Snapshot(configured: true), now: Date(timeIntervalSince1970: 5_000))
        let now = Date(timeIntervalSince1970: 5_000)
        session.enterParent(authenticated: true, now: now)
        session.grant(seconds: 60, now: now)
        expectEqual(session.mode, .play)
        expectEqual(session.snapshot.endsAt, now.addingTimeInterval(60))
        // Halving pending does not change banked viewing or an active grant visa.
        let _ = WrongAnswerPolicy.halvedPendingMinutes(15)
        expectEqual(session.mode, .play)
        expectEqual(session.remaining(at: now), 60)
    }

    func testTraditionalOnlyCopy() {
        for line in WrongAnswerCopy.allTraditionalLines {
            expectFalse(line.isEmpty)
            expectTrue(isTraditionalChineseOnly(line))
        }
        expectEqual(WrongAnswerCopy.fuelHalvedTraditionalChinese, "油少咗半！再諗諗～")
        expectEqual(WrongAnswerCopy.thinkPauseTraditionalChinese, "停一停，想一想！")
        expectEqual(WrongAnswerCopy.returnDepotTraditionalChinese, "油用晒喇，返車廠再試啦！")
        // Spot-check: no common Simplified fragments.
        expectFalse(WrongAnswerCopy.fuelHalvedTraditionalChinese.contains("油少了"))
        expectTrue(WrongAnswerCopy.thinkPauseTraditionalChinese.contains("停一停"))
        expectTrue(WrongAnswerCopy.returnDepotTraditionalChinese.contains("車廠"))
        expectTrue(SpokenPrompt.outOfFuelDepot.traditionalChinese == WrongAnswerCopy.returnDepotTraditionalChinese)
        expectTrue(isTraditionalChineseOnly(SpokenPrompt.outOfFuelDepot.traditionalChinese))
    }

    func testReducedPendingAwardsViaLedgerWithoutBurningBankOnMiss() {
        // D2: answering / misses do not burn banked viewingSeconds.
        var ledger = RewardLedger(policy: RewardPolicy(initialAllowanceSeconds: 60, rewardCapSeconds: 1_200))
        let now = Date(timeIntervalSince1970: 9_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 60)
        ledger.noteAnswering(durationSeconds: 120)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 60)

        // Simulate three misses on a 15-min ticket → pending 1, then success awards 60s.
        var pending = 15
        pending = WrongAnswerPolicy.halvedPendingMinutes(pending) // 7
        pending = WrongAnswerPolicy.halvedPendingMinutes(pending) // 3
        pending = WrongAnswerPolicy.halvedPendingMinutes(pending) // 1
        expectEqual(pending, 1)
        let outcome = ledger.applyCompletion(
            id: "round-reduced",
            rewardSeconds: WrongAnswerPolicy.awardSeconds(fromPendingMinutes: pending),
            kind: .assisted,
            now: now,
            calendar: calendar
        )
        expectEqual(outcome, .awarded(60))
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 120)
    }
}
