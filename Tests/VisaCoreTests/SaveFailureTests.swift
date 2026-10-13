import Foundation
import VisaCore

/// v0.21.4: a failed save must never block games → stamp → picker → playback.
final class SaveFailureTests {
    struct WriteFail: Error {}

    func testFailedWriteKeepsChildFlowAndPlaybackAllowed() {
        var failing = true
        var written: [Snapshot] = []
        let store = ResilientSnapshotStore { snap in
            if failing { throw NSError(domain: NSCocoaErrorDomain, code: 513,
                                       userInfo: [NSFilePathErrorKey: "/x/state.json"]) }
            written.append(snap)
        }
        let now = Date(timeIntervalSince1970: 5_000)
        let calendar = Calendar(identifier: .gregorian)
        var session = Session(snapshot: .init(configured: true), now: now)
        // Child finishes a game: reward + visa, every save fails.
        var ledger = RewardLedger(policy: .init(initialAllowanceSeconds: 60, rewardCapSeconds: 1200))
        ledger.completeEntryActivity(now: now, calendar: calendar)
        ledger.applyCompletion(id: "r1", rewardSeconds: 300, kind: .unassisted, now: now, calendar: calendar)
        session.replaceRewardState(ledger.exportState())
        expectEqual(store.commit(session.snapshot, now: now), .queued(error: store.lastError!))
        session.startPlayVisa(seconds: 300, now: now)
        _ = store.commit(session.snapshot, now: now)
        expectTrue(store.isDegraded)
        expectTrue(store.lastError!.contains("NSCocoaErrorDomain#513"))
        expectTrue(store.lastError!.contains("/x/state.json"))
        // In-memory session still in play; picker → playback allowed.
        expectEqual(session.mode, .play)
        var allow = VideoAllowlist()
        expectTrue(allow.upsert(ApprovedVideo(id: "dQw4w9WgXcQ", titleEnglish: "t", titleCantonese: "片", durationSeconds: 120)))
        let budget = ledger.availableViewingSeconds(now: now, calendar: calendar)
        let decision = PlaybackPolicy().evaluateStart(videoID: "dQw4w9WgXcQ", allowlist: allow,
                                                      remainingViewingBudgetSeconds: budget,
                                                      sessionEndsAt: session.snapshot.endsAt, now: now)
        expectTrue(decision.allowed)
        // Retry not due yet; then disk recovers.
        expectNil(store.retryIfDue(now: now.addingTimeInterval(5)))
        failing = false
        expectEqual(store.retryIfDue(now: now.addingTimeInterval(20)), .recovered)
        expectFalse(store.isDegraded)
        expectEqual(written.last, session.snapshot)
    }

    func testAppModelNeverResetsSessionOrGatesChildOnSaveFailure() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let text = try String(contentsOf: root.appendingPathComponent("Sources/VisaGames/AppDelegate.swift"), encoding: .utf8)
        expectTrue(text.contains("resilientStore.commit(next.snapshot)"))
        expectFalse(text.contains("session = Session(snapshot: Snapshot(configured: true), now: Date())\n                resetTaskRound()"))
        expectFalse(text.contains("guard !storageFailed, session.mode == .lock"))
        expectFalse(text.contains("guard !storageFailed else { return refused }"))
        expectFalse(text.contains("select") && text.contains("blocked — 已封鎖 storageFailed=true"))
        expectFalse(text.contains("message = \"未能儲存，請家長處理。"))
        expectTrue(text.contains("resilientStore.retryIfDue"))
    }
}
