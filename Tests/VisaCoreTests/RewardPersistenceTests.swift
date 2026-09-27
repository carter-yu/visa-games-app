import Foundation
import VisaCore

/// P1-2: durable RewardLedger state persisted atomically with Snapshot.
final class RewardPersistenceTests {
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

    private func makeStore() throws -> (SnapshotStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SnapshotStore(url: directory.appendingPathComponent("state.json"))
        return (store, directory)
    }

    func testRewardStateRoundTripSaveLoad() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var ledger = makeLedger(initialAllowance: 300, cap: 1_200)
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        _ = ledger.applyCompletion(
            id: "task-persist",
            rewardSeconds: 120,
            kind: .unassisted,
            now: now,
            calendar: calendar
        )

        let snapshot = Snapshot(
            configured: true,
            endsAt: now.addingTimeInterval(600),
            reward: ledger.exportState()
        )
        try store.save(snapshot)
        let loaded = try store.load()

        expectEqual(loaded.schemaVersion, 2)
        expectTrue(loaded.configured)
        expectEqual(loaded.endsAt, now.addingTimeInterval(600))
        guard let reward = loaded.reward else {
            preconditionFailure("Expected reward state after round-trip")
        }
        expectEqual(reward.entryActivityCompleted, true)
        expectEqual(reward.viewingSeconds, 420)
        expectEqual(Set(reward.awardedCompletionIDs), Set(["task-persist"]))
        expectEqual(reward.successRecords.count, 1)
        expectEqual(reward.initialAllowanceSeconds, 300)
        expectEqual(reward.rewardCapSeconds, 1_200)

        var restored = RewardLedger(state: reward)
        restored.normalizeAfterLoad(now: now, calendar: calendar)
        expectEqual(restored.availableViewingSeconds(now: now, calendar: calendar), 420)
        expectTrue(restored.entryActivityCompleted)
    }

    func testDuplicateCompletionSurvivesRelaunchAsStillAwarded() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var ledger = makeLedger(initialAllowance: 60, cap: 600)
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        _ = ledger.applyCompletion(
            id: "task-alpha",
            rewardSeconds: 120,
            kind: .unassisted,
            now: now,
            calendar: calendar
        )
        try store.save(Snapshot(configured: true, endsAt: nil, reward: ledger.exportState()))

        let loaded = try store.load()
        var restored = RewardLedger(state: loaded.reward!)
        restored.normalizeAfterLoad(now: now, calendar: calendar)
        expectEqual(restored.availableViewingSeconds(now: now, calendar: calendar), 180)

        let duplicate = restored.applyCompletion(
            id: "task-alpha",
            rewardSeconds: 120,
            kind: .assisted,
            now: now,
            calendar: calendar
        )
        expectEqual(duplicate, .duplicateRejected)
        expectEqual(restored.availableViewingSeconds(now: now, calendar: calendar), 180)
        expectEqual(restored.successRecords.count, 1)
    }

    func testDayCarryoverStillRejectedAfterReload() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var ledger = makeLedger(initialAllowance: 300, cap: 1_200)
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 300)
        try store.save(Snapshot(configured: true, reward: ledger.exportState()))

        let nextDay = now.addingTimeInterval(86_400)
        let loaded = try store.load()
        var restored = RewardLedger(state: loaded.reward!)
        restored.normalizeAfterLoad(now: nextDay, calendar: calendar)
        // Crossing the day does not invent a fresh allowance after reload.
        expectEqual(restored.availableViewingSeconds(now: nextDay, calendar: calendar), 0)
        expectTrue(restored.entryActivityCompleted)

        let granted = restored.applyCompletion(
            id: "task-next-day",
            rewardSeconds: 90,
            kind: .unassisted,
            now: nextDay,
            calendar: calendar
        )
        expectEqual(granted, .awarded(90))
        expectEqual(restored.availableViewingSeconds(now: nextDay, calendar: calendar), 90)
    }

    func testSessionEndsAtIndependentOfRewardBudgetOnReload() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var ledger = makeLedger(initialAllowance: 300, cap: 1_200)
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        let endsAt = now.addingTimeInterval(60)
        try store.save(Snapshot(configured: true, endsAt: endsAt, reward: ledger.exportState()))

        let loaded = try store.load()
        // Absolute session deadline remains independent of viewing budget.
        expectEqual(loaded.endsAt, endsAt)
        expectEqual(loaded.reward?.viewingSeconds, 300)

        let stillValid = Session(snapshot: loaded, now: now.addingTimeInterval(30))
        expectEqual(stillValid.mode, .play)
        expectEqual(stillValid.remaining(at: now.addingTimeInterval(30)), 30)
        expectEqual(
            RewardLedger(state: loaded.reward!)
                .availableViewingSeconds(now: now.addingTimeInterval(30), calendar: calendar),
            300
        )

        let expired = Session(snapshot: loaded, now: now.addingTimeInterval(60))
        expectEqual(expired.mode, .lock)
        expectNil(expired.snapshot.endsAt)
        // Expiry of endsAt does not clear durable reward records on the snapshot load path;
        // Session only clears endsAt. Reward day normalization is separate.
        expectEqual(expired.snapshot.reward?.viewingSeconds, 300)
    }

    func testSchemaV1MigratesWithoutInventingReward() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Encode a v1 payload with Foundation JSONSerialization / manual JSON for Date as timeInterval.
        let endsAt = now.addingTimeInterval(120)
        let encoder = JSONEncoder()
        // Use SnapshotV1-equivalent dictionary via a temporary Codable helper.
        struct Legacy: Codable {
            var schemaVersion = 1
            var configured = true
            var endsAt: Date?
        }
        try encoder.encode(Legacy(endsAt: endsAt)).write(to: store.url, options: .atomic)

        let loaded = try store.load()
        expectEqual(loaded.schemaVersion, 2)
        expectTrue(loaded.configured)
        expectEqual(loaded.endsAt, endsAt)
        expectNil(loaded.reward)

        try store.save(loaded)
        let again = try store.load()
        expectEqual(again.schemaVersion, 2)
        expectNil(again.reward)
        expectEqual(again.endsAt, endsAt)
    }

    func testInvalidRewardStateFailsClosed() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let negativeViewing = """
        {"schemaVersion":2,"configured":true,"endsAt":null,"reward":{"initialAllowanceSeconds":300,"rewardCapSeconds":1200,"entryActivityCompleted":true,"awardedCompletionIDs":[],"successRecords":[],"viewingSeconds":-1,"budgetDayStart":null}}
        """
        try Data(negativeViewing.utf8).write(to: store.url)
        expectThrowsError(try store.load())

        let nanAllowance = """
        {"schemaVersion":2,"configured":true,"endsAt":null,"reward":{"initialAllowanceSeconds":null,"rewardCapSeconds":1200,"entryActivityCompleted":false,"awardedCompletionIDs":[],"successRecords":[],"viewingSeconds":0,"budgetDayStart":null}}
        """
        try Data(nanAllowance.utf8).write(to: store.url)
        expectThrowsError(try store.load())

        let emptyCompletionID = """
        {"schemaVersion":2,"configured":true,"endsAt":null,"reward":{"initialAllowanceSeconds":300,"rewardCapSeconds":1200,"entryActivityCompleted":true,"awardedCompletionIDs":[""],"successRecords":[],"viewingSeconds":0,"budgetDayStart":null}}
        """
        try Data(emptyCompletionID.utf8).write(to: store.url)
        expectThrowsError(try store.load())

        let partialJSON = """
        {"schemaVersion":2,"configured":true,"reward":{"initialAllowanceSeconds":300
        """
        try Data(partialJSON.utf8).write(to: store.url)
        expectThrowsError(try store.load())

        let unsupported = """
        {"schemaVersion":99,"configured":true}
        """
        try Data(unsupported.utf8).write(to: store.url)
        expectThrowsError(try store.load())
    }

    func testAnsweringStillDoesNotSpendBudgetAfterReload() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var ledger = makeLedger(initialAllowance: 300, cap: 1_200)
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        ledger.noteAnswering(durationSeconds: 180)
        try store.save(Snapshot(configured: true, reward: ledger.exportState()))

        var restored = RewardLedger(state: try store.load().reward!)
        restored.normalizeAfterLoad(now: now, calendar: calendar)
        restored.noteAnswering(durationSeconds: 60)
        expectEqual(restored.availableViewingSeconds(now: now, calendar: calendar), 300)
    }
}
