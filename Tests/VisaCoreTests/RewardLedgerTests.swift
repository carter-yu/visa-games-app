import Foundation
import VisaCore

final class RewardLedgerTests {
    /// Fixed instant: 1970-01-01 00:16:40 UTC. Day-boundary tests use an injected Gregorian/UTC calendar.
    let now = Date(timeIntervalSince1970: 1_000)
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func makeLedger(
        initialAllowance: TimeInterval = 300,
        cap: TimeInterval = 1_200
    ) -> RewardLedger {
        RewardLedger(
            policy: RewardPolicy(
                initialAllowanceSeconds: initialAllowance,
                rewardCapSeconds: cap
            )
        )
    }

    func testEntryActivityUnlocksConfiguredInitialAllowance() {
        var ledger = makeLedger(initialAllowance: 300, cap: 1_200)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 0)
        let granted = ledger.completeEntryActivity(now: now, calendar: calendar)
        expectEqual(granted, 300)
        expectTrue(ledger.entryActivityCompleted)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 300)
        // Second entry completion does not stack another initial allowance.
        let again = ledger.completeEntryActivity(now: now, calendar: calendar)
        expectEqual(again, 300)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 300)
    }

    func testExactlyOnceGrantPerCompletionID() {
        var ledger = makeLedger(initialAllowance: 60, cap: 600)
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        let outcome = ledger.applyCompletion(
            id: "task-alpha",
            rewardSeconds: 120,
            kind: .unassisted,
            now: now,
            calendar: calendar
        )
        expectEqual(outcome, .awarded(120))
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 180)
        expectEqual(ledger.successRecords.count, 1)
        expectEqual(ledger.successRecords[0].completionID, "task-alpha")
        expectEqual(ledger.successRecords[0].awardedSeconds, 120)
    }

    func testDuplicateCompletionIDRejected() {
        var ledger = makeLedger(initialAllowance: 60, cap: 600)
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        _ = ledger.applyCompletion(
            id: "task-alpha",
            rewardSeconds: 120,
            kind: .unassisted,
            now: now,
            calendar: calendar
        )
        let duplicate = ledger.applyCompletion(
            id: "task-alpha",
            rewardSeconds: 120,
            kind: .assisted,
            now: now,
            calendar: calendar
        )
        expectEqual(duplicate, .duplicateRejected)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 180)
        expectEqual(ledger.successRecords.count, 1)
    }

    func testParentSetCapEnforcement() {
        var ledger = makeLedger(initialAllowance: 200, cap: 300)
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 200)
        let outcome = ledger.applyCompletion(
            id: "task-beta",
            rewardSeconds: 200,
            kind: .unassisted,
            now: now,
            calendar: calendar
        )
        // Only 100s fit under the 300s cap; excess is not banked.
        expectEqual(outcome, .awarded(100))
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 300)
        let atCap = ledger.applyCompletion(
            id: "task-gamma",
            rewardSeconds: 60,
            kind: .unassisted,
            now: now,
            calendar: calendar
        )
        expectEqual(atCap, .awarded(0))
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 300)
        expectEqual(ledger.successRecords.count, 2)
    }

    func testNoNextDayCarryover() {
        var ledger = makeLedger(initialAllowance: 300, cap: 1_200)
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 300)
        // Next calendar day in the injected UTC Gregorian calendar (absolute midnight boundary).
        let nextDay = now.addingTimeInterval(86_400)
        expectEqual(ledger.availableViewingSeconds(now: nextDay, calendar: calendar), 0)
        // Crossing the day does not invent a fresh allowance; only an explicit grant refills.
        let granted = ledger.applyCompletion(
            id: "task-next-day",
            rewardSeconds: 90,
            kind: .unassisted,
            now: nextDay,
            calendar: calendar
        )
        expectEqual(granted, .awarded(90))
        expectEqual(ledger.availableViewingSeconds(now: nextDay, calendar: calendar), 90)
    }

    func testLanguageReplayDoesNotReduceReward() {
        var ledger = makeLedger(initialAllowance: 60, cap: 600)
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        _ = ledger.applyCompletion(
            id: "task-lang",
            rewardSeconds: 120,
            kind: .unassisted,
            now: now,
            calendar: calendar
        )
        let before = ledger.availableViewingSeconds(now: now, calendar: calendar)
        ledger.recordLanguageReplay(completionID: "task-lang")
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), before)
        expectEqual(ledger.successRecords[0].awardedSeconds, 120)
    }

    func testAssistedSuccessRecordedSeparately() {
        var ledger = makeLedger(initialAllowance: 60, cap: 600)
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        _ = ledger.applyCompletion(
            id: "task-solo",
            rewardSeconds: 60,
            kind: .unassisted,
            now: now,
            calendar: calendar
        )
        _ = ledger.applyCompletion(
            id: "task-helped",
            rewardSeconds: 60,
            kind: .assisted,
            now: now,
            calendar: calendar
        )
        expectEqual(ledger.successRecords.count, 2)
        expectEqual(ledger.successRecords[0].kind, .unassisted)
        expectEqual(ledger.successRecords[1].kind, .assisted)
        expectEqual(ledger.successRecords[0].completionID, "task-solo")
        expectEqual(ledger.successRecords[1].completionID, "task-helped")
    }

    func testAnsweringDoesNotSpendViewingBudget() {
        var ledger = makeLedger(initialAllowance: 300, cap: 1_200)
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        let before = ledger.availableViewingSeconds(now: now, calendar: calendar)
        ledger.noteAnswering(durationSeconds: 180)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), before)
        expectEqual(before, 300)
    }

    func testResetEntryActivityForParentUATClearsFlagOnly() {
        var ledger = makeLedger(initialAllowance: 300, cap: 1_200)
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        expectTrue(ledger.entryActivityCompleted)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 300)
        _ = ledger.applyCompletion(
            id: "parent-test-budget",
            rewardSeconds: 60,
            kind: .unassisted,
            now: now,
            calendar: calendar
        )
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 360)
        expectEqual(ledger.successRecords.count, 1)

        ledger.resetEntryActivityForParentUAT()
        expectTrue(!ledger.entryActivityCompleted)
        // Viewing budget and awards kept for parent preview / child UAT.
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 360)
        expectEqual(ledger.successRecords.count, 1)
        expectEqual(ledger.successRecords[0].completionID, "parent-test-budget")
        // After UAT reset, D1 entry unlock can run again and grant initial allowance once more.
        let grantedAgain = ledger.completeEntryActivity(now: now, calendar: calendar)
        expectEqual(grantedAgain, 300)
        expectTrue(ledger.entryActivityCompleted)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 660)
    }

    /// Product rule: missing Snapshot.reward means entry is not completed; parent UAT reset
    /// must be able to persist a fresh ledger with entryActivityCompleted=false.
    func testNilRewardMeansEntryIncompleteAndFreshLedgerPersistsFlagFalse() {
        let snapshot = Snapshot(configured: true, endsAt: nil, reward: nil)
        // Same predicate AppModel.isEntryActivityCompleted uses.
        expectTrue(snapshot.reward?.entryActivityCompleted != true)

        var ledger = RewardLedger(policy: RewardPolicy(
            initialAllowanceSeconds: 60,
            rewardCapSeconds: 1_200
        ))
        expectTrue(!ledger.entryActivityCompleted)
        ledger.resetEntryActivityForParentUAT()
        expectTrue(!ledger.entryActivityCompleted)
        let exported = ledger.exportState()
        expectEqual(exported.entryActivityCompleted, false)
        expectEqual(exported.viewingSeconds, 0)
        expectEqual(exported.awardedCompletionIDs, [])

        var session = Session(snapshot: snapshot, now: now)
        session.replaceRewardState(exported)
        guard let persisted = session.snapshot.reward else {
            preconditionFailure("Expected reward state after parent UAT reset persist")
        }
        expectEqual(persisted.entryActivityCompleted, false)
        expectTrue(persisted.entryActivityCompleted != true)
    }

}
