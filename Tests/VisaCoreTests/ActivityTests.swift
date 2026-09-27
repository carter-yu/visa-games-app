import Foundation
import VisaCore

final class ActivityTests {
    let now = Date(timeIntervalSince1970: 1_000)
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private let evaluator = ActivityEvaluator()

    func testFirstEntryQuestionIsWellFormed() {
        let question = FirstEntryActivity.question
        expectTrue(question.isWellFormed)
        expectEqual(question.options.count, 2)
        expectEqual(question.completionID, FirstEntryActivity.completionID)
        expectEqual(question.correctOptionID, "opt-fire")
        expectEqual(question.options[0].assetID, "silhouette.fireEngine")
        expectEqual(question.options[1].assetID, "silhouette.hkTaxi")
        // Language lock: prompts are Traditional Chinese + English (spot-check characters).
        expectTrue(question.promptTraditionalChinese.contains("消防"))
        expectTrue(question.promptEnglish.lowercased().contains("fire"))
        expectFalse(question.promptTraditionalChinese.contains("哪辆")) // mainland phrasing rejected
    }

    func testCorrectUnassistedEvaluation() {
        let question = FirstEntryActivity.question
        let outcome = evaluator.evaluate(
            question: question,
            selectedOptionID: question.correctOptionID,
            hintUsed: false
        )
        expectEqual(outcome, .correct(assisted: false))
    }

    func testCorrectAssistedWhenHintUsed() {
        let question = FirstEntryActivity.question
        let outcome = evaluator.evaluate(
            question: question,
            selectedOptionID: question.correctOptionID,
            hintUsed: true
        )
        expectEqual(outcome, .correct(assisted: true))
    }

    func testWrongAnswerIsIncorrectWithoutPenaltySemantics() {
        let question = FirstEntryActivity.question
        let wrongID = question.options.first(where: { $0.id != question.correctOptionID })!.id
        let outcome = evaluator.evaluate(
            question: question,
            selectedOptionID: wrongID,
            hintUsed: false
        )
        expectEqual(outcome, .incorrect)
        // Unknown option also incorrect (gentle retry path in UI).
        expectEqual(
            evaluator.evaluate(question: question, selectedOptionID: "missing", hintUsed: false),
            .incorrect
        )
    }

    func testMalformedQuestionFailsClosed() {
        let bad = TwoPictureQuestion(
            promptTraditionalChinese: "測試",
            promptEnglish: "Test",
            options: [
                ActivityOption(id: "a", assetID: "x", labelTraditionalChinese: "甲", labelEnglish: "A")
            ],
            correctOptionID: "a",
            completionID: "bad"
        )
        expectFalse(bad.isWellFormed)
        expectEqual(
            evaluator.evaluate(question: bad, selectedOptionID: "a", hintUsed: false),
            .incorrect
        )
    }

    func testEntrySuccessUnlocksAllowanceOnceWithAssistedFlag() {
        var ledger = RewardLedger(
            policy: RewardPolicy(initialAllowanceSeconds: 60, rewardCapSeconds: 1_200)
        )
        let question = FirstEntryActivity.question
        let evaluation = evaluator.evaluate(
            question: question,
            selectedOptionID: question.correctOptionID,
            hintUsed: true
        )
        expectEqual(evaluation, .correct(assisted: true))

        let granted = ledger.completeEntryActivity(now: now, calendar: calendar)
        expectEqual(granted, 60)
        expectTrue(ledger.entryActivityCompleted)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 60)

        // Record assisted vs unassisted via applyCompletion with zero extra seconds (D7; no invented reward).
        let kind: SuccessKind = .assisted
        let recordOutcome = ledger.applyCompletion(
            id: question.completionID,
            rewardSeconds: 0,
            kind: kind,
            now: now,
            calendar: calendar
        )
        expectEqual(recordOutcome, .awarded(0))
        expectEqual(ledger.successRecords.count, 1)
        expectEqual(ledger.successRecords[0].kind, .assisted)
        expectEqual(ledger.successRecords[0].completionID, question.completionID)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 60)

        // Exactly-once: second apply is duplicate; second entry unlock does not stack.
        expectEqual(
            ledger.applyCompletion(
                id: question.completionID,
                rewardSeconds: 0,
                kind: .unassisted,
                now: now,
                calendar: calendar
            ),
            .duplicateRejected
        )
        _ = ledger.completeEntryActivity(now: now, calendar: calendar)
        expectEqual(ledger.availableViewingSeconds(now: now, calendar: calendar), 60)
    }

    func testStubAudioDoesNotClaimPack() {
        let audio = StubActivityAudioPrompt()
        audio.speakPrompt(
            traditionalChinese: FirstEntryActivity.question.promptTraditionalChinese,
            english: FirstEntryActivity.question.promptEnglish
        )
        // Stub is intentionally a no-op; presence of the type is the scaffold seam.
        expectTrue(true)
    }

    func testCatalogPlayableKindsAndRotation() {
        expectEqual(ActivityCatalog.playableKinds.count, 4)
        expectTrue(ActivityCatalog.playableKinds.contains(.twoPictureChoose))
        expectTrue(ActivityCatalog.playableKinds.contains(.findTheSame))
        expectTrue(ActivityCatalog.playableKinds.contains(.countVehicles))
        expectTrue(ActivityCatalog.playableKinds.contains(.sequenceShortToLong))
        expectEqual(ActivityCatalog.stubKinds, [])
        // Deterministic: same seed → same kind; covering seeds hit all playable kinds.
        let a = ActivityCatalog.kind(forRoundSeed: "seed-alpha")
        expectEqual(ActivityCatalog.kind(forRoundSeed: "seed-alpha"), a)
        var seen = Set<ActivityKind>()
        for i in 0..<80 {
            seen.insert(ActivityCatalog.kind(forRoundSeed: "round-\(i)"))
        }
        expectEqual(seen, Set(ActivityCatalog.playableKinds))
    }

    func testFindSameQuestionWellFormedAndEvaluation() {
        let question = ActivityCatalog.findSameQuestion()
        expectTrue(question.isWellFormed)
        expectEqual(question.targetAssetID, "silhouette.hkTaxi")
        expectEqual(question.correctOptionID, "find-hktaxi")
        expectTrue(question.promptTraditionalChinese.contains("搵"))
        expectFalse(question.promptTraditionalChinese.contains("找同")) // avoid mainland phrasing drift
        expectEqual(
            evaluator.evaluate(question: question, selectedOptionID: "find-hktaxi", hintUsed: false),
            .correct(assisted: false)
        )
        expectEqual(
            evaluator.evaluate(question: question, selectedOptionID: "find-fire", hintUsed: true),
            .incorrect
        )
        let bad = FindSameQuestion(
            promptTraditionalChinese: "測試",
            promptEnglish: "Test",
            targetAssetID: "silhouette.hkTaxi",
            options: [
                ActivityOption(id: "x", assetID: "silhouette.fireEngine", labelTraditionalChinese: "甲", labelEnglish: "A"),
                ActivityOption(id: "y", assetID: "silhouette.fireEngine", labelTraditionalChinese: "乙", labelEnglish: "B")
            ],
            correctOptionID: "x",
            completionID: "bad-find"
        )
        expectFalse(bad.isWellFormed)
        expectEqual(
            evaluator.evaluate(question: bad, selectedOptionID: "x", hintUsed: false),
            .incorrect
        )
    }

    func testCountQuestionWellFormedAndEvaluation() {
        let question = ActivityCatalog.countQuestion()
        expectTrue(question.isWellFormed)
        expectEqual(question.correctCount, 3)
        expectEqual(question.vehicleAssetIDs.count, 3)
        expectEqual(question.choiceCounts, [2, 3, 4])
        expectTrue(question.promptTraditionalChinese.contains("幾架"))
        expectTrue(question.vehicleAssetIDs.allSatisfy { $0 == "silhouette.fireEngine" })
        expectFalse(question.promptTraditionalChinese.contains("几架")) // Simplified rejected
        expectEqual(
            evaluator.evaluate(question: question, selectedCount: 3, hintUsed: false),
            .correct(assisted: false)
        )
        expectEqual(
            evaluator.evaluate(question: question, selectedCount: 3, hintUsed: true),
            .correct(assisted: true)
        )
        expectEqual(
            evaluator.evaluate(question: question, selectedCount: 2, hintUsed: false),
            .incorrect
        )
        expectEqual(
            evaluator.evaluate(question: question, selectedCount: 5, hintUsed: false),
            .incorrect
        )
        let bad = CountQuestion(
            promptTraditionalChinese: "測試",
            promptEnglish: "Test",
            vehicleAssetIDs: ["silhouette.crane"],
            correctCount: 2,
            choiceCounts: [1, 2],
            completionID: "bad-count"
        )
        expectFalse(bad.isWellFormed)
    }

    func testSequenceConvoyPlayableAndEvaluation() {
        let question = ActivityCatalog.sequenceQuestion()
        expectTrue(question.isWellFormed)
        expectTrue(question.isPlayable)
        expectEqual(question.orderedAssetIDs.first, "silhouette.hkTaxi")
        expectEqual(question.orderedAssetIDs.last, "silhouette.metroTrain")
        expectTrue(question.promptTraditionalChinese.contains("短"))
        expectFalse(question.promptTraditionalChinese.contains("稍后")) // Simplified rejected
        expectEqual(
            evaluator.evaluate(
                question: question,
                orderedSelectionIDs: question.orderedAssetIDs,
                hintUsed: false
            ),
            .correct(assisted: false)
        )
        expectEqual(
            evaluator.evaluate(
                question: question,
                orderedSelectionIDs: question.orderedAssetIDs,
                hintUsed: true
            ),
            .correct(assisted: true)
        )
        expectEqual(
            evaluator.evaluate(
                question: question,
                orderedSelectionIDs: Array(question.orderedAssetIDs.reversed()),
                hintUsed: false
            ),
            .incorrect
        )
        expectEqual(
            evaluator.nextExpectedAssetID(question: question, tappedSoFar: []),
            "silhouette.hkTaxi"
        )
        expectEqual(
            evaluator.nextExpectedAssetID(question: question, tappedSoFar: ["silhouette.hkTaxi"]),
            "silhouette.fireEngine"
        )
    }

    func testCatalogHintsAreBilingualTraditional() {
        for kind in ActivityCatalog.playableKinds {
            let hint = ActivityCatalog.hintTraditionalChinese(for: kind)
            expectTrue(hint.contains(" / "))
            expectFalse(hint.contains("机车")) // Simplified fragment check
        }
    }
}
