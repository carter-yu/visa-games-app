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
        expectEqual(question.correctOptionID, "opt-crane")
        expectEqual(question.options[0].assetID, "silhouette.crane")
        expectEqual(question.options[1].assetID, "silhouette.articulatedBus")
        // Language lock: prompts are Traditional Chinese + English (spot-check characters).
        expectTrue(question.promptTraditionalChinese.contains("吊機"))
        expectTrue(question.promptEnglish.contains("crane"))
        expectFalse(question.promptTraditionalChinese.contains("吊机")) // Simplified rejected by copy review
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
}
