import Foundation
import VisaCore

final class SessionTests {
    let now = Date(timeIntervalSince1970: 1_000)

    func testDifficultyAndRepeatedChildVisas() {
        let calendar = Calendar(identifier: .gregorian)
        var ledger = RewardLedger(policy: .init(initialAllowanceSeconds: 60, rewardCapSeconds: 1200))
        var session = Session(snapshot: .init(configured: true), now: now)
        for stars in 1...3 {
            let difficulty = ChildDifficulty(rawValue: stars)!
            expectEqual(difficulty.minutes, stars * 5)
            expectEqual(difficulty.seconds, Double(stars * 300))
            ledger.completeEntryActivity(now: now, calendar: calendar)
            let id = "round-\(stars)"
            ledger.applyCompletion(id: id, rewardSeconds: difficulty.seconds,
                                   kind: stars == 2 ? .assisted : .unassisted, now: now, calendar: calendar)
            expectEqual(ledger.applyCompletion(id: id, rewardSeconds: difficulty.seconds,
                                               kind: .unassisted, now: now, calendar: calendar), .duplicateRejected)
            session.replaceRewardState(ledger.exportState())
            session.startPlayVisa(seconds: difficulty.seconds, now: now)
            expectEqual(session.mode, .play)
            expectEqual(session.snapshot.endsAt, now.addingTimeInterval(difficulty.seconds))
            expectFalse(session.allowsExit)
            session.tick(now: now.addingTimeInterval(difficulty.seconds))
            expectEqual(session.mode, .lock)
            expectNil(session.snapshot.endsAt)
            expectTrue(session.snapshot.reward!.entryActivityCompleted)
        }
        expectEqual(ledger.successRecords.count, 3)
        expectEqual(ledger.successRecords[1].kind, .assisted)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 1200)
        expectNil(ChildDifficulty(rawValue: 0))
        expectNil(ChildDifficulty(rawValue: 4))
    }

    func testChildVisaFailsClosed() {
        for configured in [false, true] {
            var session = Session(snapshot: .init(configured: configured), now: now)
            for seconds in [0.0, -1, 3601, .infinity, .nan] {
                session.startPlayVisa(seconds: seconds, now: now)
                expectNil(session.snapshot.endsAt)
            }
            session.startPlayVisa(seconds: 600, now: Date(timeIntervalSince1970: .infinity))
            expectNil(session.snapshot.endsAt)
            if !configured {
                session.startPlayVisa(seconds: 600, now: now)
                expectEqual(session.mode, .setup)
                expectNil(session.snapshot.endsAt)
            }
            session.enterParent(authenticated: true, now: now)
            session.startPlayVisa(seconds: 600, now: now)
            expectEqual(session.mode, .parent)
            expectNil(session.snapshot.endsAt)
        }
        var session = Session(snapshot: .init(configured: true), now: now)
        session.startPlayVisa(seconds: 600, now: now)
        session.startPlayVisa(seconds: 1800, now: now)
        session.grant(seconds: 1800, now: now)
        expectEqual(session.snapshot.endsAt, now.addingTimeInterval(600))
    }

    func testFirstLaunchRequiresAuthenticatedSetup() {
        var session = Session(snapshot: .init(), now: now)
        expectEqual(session.mode, .setup)
        session.enterParent(authenticated: false, now: now)
        session.completeSetup()
        expectEqual(session.mode, .setup)
        session.enterParent(authenticated: true, now: now)
        session.completeSetup()
        expectEqual(session.mode, .lock)
        expectTrue(session.snapshot.configured)
    }

    func testChildCannotGrantTimeOrUnlockWithoutAuthentication() {
        var session = Session(snapshot: .init(configured: true), now: now)
        session.grant(seconds: 60, now: now)
        session.enterParent(authenticated: false, now: now)
        expectEqual(session.mode, .lock)
        expectNil(session.snapshot.endsAt)
        expectFalse(session.allowsExit)
    }

    func testAbsoluteExpiryAndRelaunch() {
        var session = Session(snapshot: .init(configured: true), now: now)
        session.enterParent(authenticated: true, now: now)
        session.grant(seconds: 60, now: now)
        expectEqual(session.snapshot.endsAt, now.addingTimeInterval(60))
        expectEqual(session.mode, .play)
        let restored = Session(snapshot: session.snapshot, now: now.addingTimeInterval(25))
        expectEqual(restored.mode, .play)
        expectEqual(restored.remaining(at: now.addingTimeInterval(25)), 35)
        let expired = Session(snapshot: session.snapshot, now: now.addingTimeInterval(60))
        expectEqual(expired.mode, .lock)
        expectNil(expired.snapshot.endsAt)
        session.tick(now: now.addingTimeInterval(100))
        expectEqual(session.mode, .lock)
    }

    func testParentRoundTripPreservesVisaButNeverPersistsUnlock() {
        var session = Session(snapshot: .init(configured: true, endsAt: now.addingTimeInterval(60)), now: now)
        session.enterParent(authenticated: true, now: now)
        expectTrue(session.allowsExit)
        expectEqual(Session(snapshot: session.snapshot, now: now).mode, .play)
        session.leaveParent(now: now.addingTimeInterval(10))
        expectEqual(session.remaining(at: now.addingTimeInterval(10)), 50)
        expectFalse(session.allowsExit)
        session.enterParent(authenticated: true, now: now)
        session.tick(now: now.addingTimeInterval(60))
        expectEqual(session.mode, .parent)
        session.leaveParent(now: now.addingTimeInterval(60))
        expectEqual(session.mode, .lock)
    }

    func testInvalidGrantAndUnconfiguredVisaFailClosed() {
        var session = Session(snapshot: .init(endsAt: now.addingTimeInterval(60)), now: now)
        expectNil(session.snapshot.endsAt)
        session.enterParent(authenticated: true, now: now)
        session.grant(seconds: 60, now: now)
        expectNil(session.snapshot.endsAt)
        session.completeSetup()
        session.enterParent(authenticated: true, now: now)
        for value in [0.0, -1, Double.infinity, Double.nan] {
            session.grant(seconds: value, now: now)
            expectNil(session.snapshot.endsAt)
        }
    }

    func testParentPreviewVisaKeepsParentWhileGrantStartsPlay() {
        var unconfigured = Session(snapshot: .init(), now: now)
        unconfigured.enterParent(authenticated: true, now: now)
        unconfigured.extendVisaKeepingParent(seconds: 600, now: now)
        expectNil(unconfigured.snapshot.endsAt)

        var session = Session(snapshot: .init(configured: true), now: now)
        session.extendVisaKeepingParent(seconds: 600, now: now)
        expectNil(session.snapshot.endsAt)

        session.enterParent(authenticated: true, now: now)
        session.extendVisaKeepingParent(seconds: 3_601, now: now)
        expectNil(session.snapshot.endsAt)
        session.extendVisaKeepingParent(seconds: 600, now: now)
        expectEqual(session.snapshot.endsAt, now.addingTimeInterval(600))
        expectEqual(session.mode, .parent)

        session.grant(seconds: 60, now: now)
        expectEqual(session.snapshot.endsAt, now.addingTimeInterval(60))
        expectEqual(session.mode, .play)
    }

    func testEscapePolicyInEveryMode() {
        var session = Session(snapshot: .init(), now: now)
        for configured in [false, true] {
            session = Session(snapshot: .init(configured: configured), now: now)
            expectTrue(session.blocksKey(isEscape: true, hasCommand: false))
            expectTrue(session.blocksKey(isEscape: false, hasCommand: true))
            expectFalse(session.blocksKey(isEscape: false, hasCommand: false))
            expectFalse(session.allowsExit)
        }
        session.enterParent(authenticated: true, now: now)
        expectFalse(session.blocksKey(isEscape: true, hasCommand: true))
        expectTrue(session.allowsExit)
        session.grant(seconds: 60, now: now)
        expectTrue(session.blocksKey(isEscape: true, hasCommand: true))
        expectFalse(session.allowsExit)
    }

    /// v0.12.0: child play visa can end early (budget empty / empty allowlist) and persist as lock.
    func testEndPlayVisaEndsOnlyChildPlay() {
        var session = Session(snapshot: .init(configured: true), now: now)
        // Lock: nothing to end.
        session.endPlayVisa(now: now)
        expectEqual(session.mode, .lock)
        expectNil(session.snapshot.endsAt)

        session.startPlayVisa(seconds: 600, now: now)
        expectEqual(session.mode, .play)
        session.endPlayVisa(now: now.addingTimeInterval(30))
        expectEqual(session.mode, .lock)
        expectNil(session.snapshot.endsAt)
        // Relaunch after an early end stays locked (endsAt cleared on disk too).
        let relaunched = Session(snapshot: session.snapshot, now: now.addingTimeInterval(31))
        expectEqual(relaunched.mode, .lock)

        // Parent preview visa is not ended by the child seam.
        var parent = Session(snapshot: .init(configured: true), now: now)
        parent.enterParent(authenticated: true, now: now)
        parent.extendVisaKeepingParent(seconds: 600, now: now)
        parent.endPlayVisa(now: now)
        expectEqual(parent.mode, .parent)
        expectEqual(parent.snapshot.endsAt, now.addingTimeInterval(600))
        expectTrue(parent.allowsExit)
    }

    func testAtomicPersistenceRoundTripAndCorruptFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(url: directory.appendingPathComponent("state.json"))
        expectEqual(try store.load(), Snapshot())
        let snapshot = Snapshot(configured: true, endsAt: now.addingTimeInterval(60))
        try store.save(snapshot)
        expectEqual(try store.load(), snapshot)
        var child = Session(snapshot: .init(configured: true), now: now)
        child.startPlayVisa(seconds: 1800, now: now)
        try store.save(child.snapshot)
        let restoredChild = Session(snapshot: try store.load(), now: now.addingTimeInterval(60))
        expectEqual(restoredChild.mode, .play)
        expectEqual(restoredChild.remaining(at: now.addingTimeInterval(60)), 1740)
        try Data("broken".utf8).write(to: store.url)
        expectThrowsError(try store.load())
        try Data("{\"schemaVersion\":99,\"configured\":true}".utf8).write(to: store.url)
        expectThrowsError(try store.load())
    }
}

// A dependency-free runner supports Macs with Command Line Tools only.
func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs == rhs, "Expected \(rhs), got \(lhs)", file: file, line: line)
}
func expectTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true", file: file, line: line)
}
func expectFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(!value, "Expected false", file: file, line: line)
}
func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    precondition(value == nil, "Expected nil", file: file, line: line)
}
func expectThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do {
        _ = try expression()
        preconditionFailure("Expected an error", file: file, line: line)
    } catch {}
}

@main
struct TestRunner {
    static func main() throws {
        let session = SessionTests()
        session.testDifficultyAndRepeatedChildVisas()
        session.testChildVisaFailsClosed()
        session.testFirstLaunchRequiresAuthenticatedSetup()
        session.testChildCannotGrantTimeOrUnlockWithoutAuthentication()
        session.testAbsoluteExpiryAndRelaunch()
        session.testParentRoundTripPreservesVisaButNeverPersistsUnlock()
        session.testInvalidGrantAndUnconfiguredVisaFailClosed()
        session.testParentPreviewVisaKeepsParentWhileGrantStartsPlay()
        session.testEscapePolicyInEveryMode()
        try session.testAtomicPersistenceRoundTripAndCorruptFile()
        session.testEndPlayVisaEndsOnlyChildPlay()

        let reward = RewardLedgerTests()
        reward.testEntryActivityUnlocksConfiguredInitialAllowance()
        reward.testExactlyOnceGrantPerCompletionID()
        reward.testDuplicateCompletionIDRejected()
        reward.testParentSetCapEnforcement()
        reward.testNoNextDayCarryover()
        reward.testLanguageReplayDoesNotReduceReward()
        reward.testAssistedSuccessRecordedSeparately()
        reward.testAnsweringDoesNotSpendViewingBudget()
        reward.testResetEntryActivityForParentUATClearsFlagOnly()
        reward.testNilRewardMeansEntryIncompleteAndFreshLedgerPersistsFlagFalse()

        let persistence = RewardPersistenceTests()
        try persistence.testRewardStateRoundTripSaveLoad()
        try persistence.testDuplicateCompletionSurvivesRelaunchAsStillAwarded()
        try persistence.testDayCarryoverStillRejectedAfterReload()
        try persistence.testSessionEndsAtIndependentOfRewardBudgetOnReload()
        try persistence.testSchemaV1MigratesWithoutInventingReward()
        try persistence.testInvalidRewardStateFailsClosed()
        try persistence.testAnsweringStillDoesNotSpendBudgetAfterReload()
        try persistence.testLastIncompleteRoundTripAndRejectsCorrupt()

        let theme = ThemePreferenceTests()
        theme.testDefaultPalette()
        theme.testSelectEachPalette()
        theme.testPersistAndReload()
        theme.testInvalidRawValueFallsBackToDefault()
        theme.testBilingualTraditionalChineseLabels()
        theme.testEveryPaletteIncludesWarmYellowAccent()

        let scoped = ScopedPlaybackTests()
        scoped.testAllowlistRejectsUnknownID()
        scoped.testBudgetStopAndSessionStop()
        scoped.testD8RejectsNonEmbedConstruction()
        scoped.testExtractVideoIDForParentPaste()
        scoped.testApprovedVideoParentLabelAndUpsert()
        scoped.testYouTubeThumbnailURLDerivedFromID()
        scoped.testAllowedEmbedMainFrameURLPolicy()
        scoped.testEmbedHTMLStringReferrerShell()
        scoped.testYouTubeOEmbedURLAndParseFixture()
        scoped.testPlaybackShuffleAvoidsImmediateRepeatAndReshuffles()
        scoped.testPlaybackShuffleSingleAndEmpty()
        scoped.testShuffledDeckAvoidsImmediateFirstRepeat()
        scoped.testEmbedHTMLUsesIFrameAPIBridge()
        scoped.testScopedPlayerEventParsing()
        scoped.testParentAllowlistDraftStatus()
        try scoped.testApprovedVideoDurationLabelAndLegacyDecode()
        scoped.testEmbedStartSecondsQuery()
        scoped.testIncompletePlaybackValidationAndPolicy()

        let activity = ActivityTests()
        activity.testFirstEntryQuestionIsWellFormed()
        activity.testCorrectUnassistedEvaluation()
        activity.testCorrectAssistedWhenHintUsed()
        activity.testWrongAnswerIsIncorrectWithoutPenaltySemantics()
        activity.testMalformedQuestionFailsClosed()
        activity.testEntrySuccessUnlocksAllowanceOnceWithAssistedFlag()
        activity.testStubAudioDoesNotClaimPack()
        activity.testCatalogPlayableKindsAndRotation()
        activity.testFindSameQuestionWellFormedAndEvaluation()
        activity.testCountQuestionWellFormedAndEvaluation()
        activity.testSequenceConvoyPlayableAndEvaluation()
        activity.testCatalogHintsAreBilingualTraditional()
        activity.testHalfMatchWellFormedAndEvaluation()
        activity.testShapeCousinWellFormedAndEvaluation()
        activity.testCapacityCompareWellFormedAndEvaluation()
        activity.testMoreFewerWellFormedAndEvaluation()
        activity.testShadowMatchWellFormedAndEvaluation()
        activity.testEmptyBayWellFormedAndEvaluation()

        let canvas = CanvasFoundationTests()
        canvas.testPaletteMatchesCanvasTokens()
        canvas.testTargetsAndTimingTokens()
        canvas.testStageFitsReferenceInsideTVSafeArea()
        canvas.testStageFailsSafeForDegenerateSizes()
        try canvas.testSVGPathParsesAbsoluteRelativeAndSmoothCommands()
        try canvas.testSVGArcBecomesCubicsThatBulgeTheRightWay()
        canvas.testSVGPathRejectsMalformedData()
        canvas.testCanvasArtworkIsCompleteAndParsed()
        canvas.testMissionTicketsFollowCanvas()

        let voice = CantoneseVoiceTests()
        voice.testPicksHongKongCantoneseOnly()
        voice.testNeverFallsBackToMandarin()
        voice.testPrefersHigherQualityVoice()
        voice.testSpokenLinesAreBilingualTraditional()

        let pen = PenSparkTests()
        pen.testHoverInProximityShowsSparkAndRecordsHover()
        pen.testTouchShowsSparkWithoutHoverSupport()
        pen.testSparkHidesAfterIdle()
        pen.testMouseMoveOutsideProximityIsNotPenHoverEvidence()

        let ux = ChildUXProgressTests()
        ux.testAutoHintAfterTwoMisses()
        ux.testRoadTimerFractionAndMinutes()
        ux.testRoadTimerFromEndsAt()
        ux.testSpokenUXLinesAreTraditional()
        ux.testPlayStageRoutesPickerBeforeWatch()
        ux.testPlayStageRoutesResumeChoiceAfterGoWhenIncomplete()
        ux.testPlayPresentationResolvesTicket()
        ux.testVideoEndedRoutesPickerWhenTimeLeft()
        ux.testVideoEndedRoutesTimesUpWhenNoTimeLeft()
        ux.testPlaybackStopRouting()
        ux.testIncompletePlaybackPolicyMatchesProductLock()

        let wrong = WrongAnswerPolicyTests()
        wrong.testHalveChainsFifteenTenFiveToZero()
        wrong.testTapsIgnoredDuringPause()
        wrong.testEveryMissStartsPauseDurationAndDepotAtZero()
        wrong.testCorrectAwardsReducedPendingSeconds()
        wrong.testRoadTilesFollowEarnedMinutesStarsIndependent()
        wrong.testParentGrantPathUntouchedByPolicy()
        wrong.testTraditionalOnlyCopy()
        wrong.testReducedPendingAwardsViaLedgerWithoutBurningBankOnMiss()

        print("PASS: 11 session + 10 reward-ledger + 8 reward-persistence + 6 theme-preference + 18 scoped-playback + 18 activity + 9 canvas + 4 voice + 4 pen-spark + 11 ux-p2-p3 + 8 wrong-answer-policy checks")
    }
}
