import Foundation
import VisaCore

final class TapLetterBoardTests {
    func testTwoTargetsAndPerCardPenalty() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let deal = TapLetterGenerator.make(seed: "letter-ui", n: 1, settings: .defaults,
            progress: LetterProgress(), decks: LetterWordDecks(), bank: bank, now: Date())!
        var board = TapLetterBoard(deal: deal)
        expectEqual(board.remaining, 2)
        let wrong = (0..<10).first { !deal.board.targetCards.contains($0) }!
        expectEqual(board.tap(wrong, at: 1), .miss)
        expectEqual(board.misses, 1)
        expectEqual(board.tap(wrong, at: 1.5), .knownWrongRetap)
        expectEqual(board.misses, 1)
        expectEqual(board.tap(deal.board.targetCards[0], at: 2), .found)
        expectEqual(board.tap(deal.board.targetCards[0], at: 2.2), .doubleTapIgnored)
        expectEqual(board.tap(deal.board.targetCards[0], at: 2.5), .foundRetap)
        expectEqual(board.remaining, 1)
        expectEqual(board.tap(deal.board.targetCards[1], at: 3), .allFound)
        expectEqual(board.remaining, 0)
    }

    func testCopyAndRegistration() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let rounds = LetterRoundIndexStore(defaults: defaults)
        expectEqual(rounds.load(), 0)
        rounds.save(4)
        expectEqual(rounds.load(), 4)
        rounds.save(-3)
        expectEqual(rounds.load(), 0)
        expectEqual(TapLetterCopy.remaining(2), "2 more to find")
        expectEqual(TapLetterCopy.remaining(1), "1 more to find")
        expectEqual(TapLetterCopy.remaining(0), "All found!")
        expectEqual(TapLetterCopy.hint("a"), "Here's an a!")
        expectEqual(TapLetterCopy.hint("d"), "Here's a d!")
        expectEqual(ActivityKind.tapLetterAll.parentCardTitle, "英文字母 ABC · 翻字卡")
        expectEqual(ActivityKind.tapLetterAll.parentCardEnglish, "Letters ABC · Find & flip")
        expectEqual(ActivityKind.tapLetterAll.tapLetterLevel, .l1)
        expectTrue(ActivityCatalog.playableKinds.contains(.tapLetterAll))
        expectTrue(ActivityCatalog.defaultOffKinds.contains(.tapLetterAll))
        expectEqual(ActivityKind.tapLetterWrite.parentCardTitle, "英文字母 ABC · 搵完寫")
        expectEqual(ActivityKind.tapLetterWrite.parentCardEnglish, "Letters ABC · Find & write")
        expectEqual(ActivityKind.tapLetterWrite.tapLetterLevel, .l2)
        expectTrue(ActivityCatalog.playableKinds.contains(.tapLetterWrite))
        expectTrue(ActivityCatalog.defaultOffKinds.contains(.tapLetterWrite))
    }
}

extension TapLetterBoardTests {
    func testLatinRevealTimingAndWritingGuides() {
        for letter in "abcde" {
            guard let glyph = StrokeGlyph.latin(letter) else { expectTrue(false, "Latin glyph"); continue }
            for dosage in StrokeOrderDosage.allCases {
                let timeline = StrokeOrderTimeline(glyph: glyph, dosage: dosage)
                expectTrue(timeline.duration > 0)
                let reveal = StrokeOrderReveal(dosage: dosage, duration: timeline.duration, startAt: 10.2)
                let finish = reveal.finishDelay(now: 10, minimum: 2.4, flash: 0.8)
                expectTrue(finish >= timeline.duration + 0.9)
                expectTrue(finish > timeline.duration, "stamp waits for the full pen timeline")
                expectTrue(reveal.writing(now: 10.2))
                expectFalse(reveal.writing(now: 10.2 + timeline.duration))
            }
            let teach = StrokeOrderTimeline(glyph: glyph, dosage: .teach)
            let glance = StrokeOrderTimeline(glyph: glyph, dosage: .glance)
            expectTrue(teach.duration > glance.duration)
        }
        expectEqual(StrokeOrderPlan.star1(setting: .remind, learned: false), .remind)
        expectEqual(StrokeOrderPlan.star1(setting: .remind, learned: true), .glance)
        expectEqual(StrokeOrderPlan.star1(setting: .off, learned: false), nil)
    }

    func testWritePhaseAndCopy() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let deal = TapLetterGenerator.make(seed: "letter-write", n: 1, settings: .defaults,
            progress: LetterProgress(), decks: LetterWordDecks(), bank: bank, now: Date())!
        var round = TapLetterWriteRound(deal: deal)
        expectEqual(round.phase, .finding)
        expectEqual(round.tap(deal.board.targetCards[0], at: 1), .found)
        expectEqual(round.tap(deal.board.targetCards[1], at: 2), .allFound)
        expectEqual(round.phase, .transition)
        expectTrue(!round.canStamp)
        expectEqual(round.phase, .transition)
        expectEqual(round.tap(deal.board.targetCards[0], at: 3), .ignored)
        round.beginWriting()
        expectEqual(round.phase, .writing)
        expectTrue(round.endDemoNoPaint())
        expectEqual(round.trace.progress, 0)
        expectTrue(!round.canStamp)
        var clock = 3.0
        var attempts = 0
        while !round.canStamp && attempts < round.trace.shapes[0].strokes.count + 2 {
            attempts += 1
            guard let path = round.trace.currentPath else { break }
            var trace = round.trace
            clock += 0.1
            _ = trace.penDown(at: path.start, now: clock)
            round.acceptTrace(trace)
            var distance = 0.0
            while distance <= path.length + 16 && !round.canStamp {
                trace = round.trace
                clock += 0.02
                _ = trace.penMove(to: path.point(at: min(distance, path.length)), now: clock)
                round.acceptTrace(trace)
                distance += 6
            }
            trace = round.trace
            trace.penUp()
            round.acceptTrace(trace)
        }
        expectTrue(round.canStamp)
        expectEqual(round.phase, .done)
        expectEqual(round.board.misses, 0)
        expectEqual(TapLetterCopy.writePrompt("d"), "Now write d!")
        expectEqual(TapLetterCopy.writeDone("d"), "You wrote d!")
        expectEqual(TapLetterCopy.cueDownAgain, "Stop! Now straight down!")
        expectEqual(TapLetterCopy.mnemonic("e"), ["Across the middle…", "Then round like a c!"])
        var writing = LetterWriteProgress()
        writing.record("d", clean: true)
        expectTrue(!writing.isLearned("d"))
        writing.record("d", clean: true)
        expectTrue(writing.isLearned("d"))
        writing.record("d", clean: false)
        expectTrue(!writing.isLearned("d"))
    }
}
