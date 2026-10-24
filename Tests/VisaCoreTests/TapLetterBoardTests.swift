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
    }
}
