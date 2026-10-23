import Foundation
import VisaCore

final class LetterDealTests {
    func testPathSettingsAndProgress() {
        expectEqual(LetterPath.abc.groups[0], Array("abcde").map(String.init))
        expectEqual(LetterPath.jolly.groups[0], Array("satipn").map(String.init))
        expectEqual(LetterPath.lettersAndSounds.groups[0], Array("satp").map(String.init))
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settingsStore = TapLetterSettingsStore(defaults: defaults)
        expectEqual(settingsStore.load().thisWeek, Array("abcde").map(String.init))
        defaults.set(Data("bad".utf8), forKey: TapLetterSettingsStore.key)
        expectEqual(settingsStore.load(), .defaults)
        let progressStore = LetterProgressStore(defaults: defaults)
        expectEqual(progressStore.load(), LetterProgress())
        var progress = LetterProgress()
        let day = Date(timeIntervalSince1970: 86_400)
        progress.record("a", clean: true, round: 1, at: day)
        progress.record("a", clean: true, round: 2, at: day)
        expectEqual(progress.state(for: "a").box, .practising)
        progress.record("a", clean: true, round: 3, at: day.addingTimeInterval(86_400))
        expectEqual(progress.state(for: "a").box, .known)
        progress.record("a", clean: false, round: 4, at: day)
        expectEqual(progress.state(for: "a").box, .learning)
        expectEqual(progress.retryQueue.first?.dueRound, 7)
        progressStore.save(progress)
        expectEqual(progressStore.load(), progress)
    }

    func testSchedulerAndBoardAcrossSeeds() {
        let settings = TapLetterSettings.defaults
        for number in 0..<1_000 {
            let seed = "seed-\(number)"
            var progress = LetterProgress()
            var targets: [String] = []
            for round in 1...5 {
                let deal = LetterScheduler.next(seed: seed, n: round, settings: settings, progress: progress, now: Date(timeIntervalSince1970: 0))
                expectEqual(deal.lane, .week)
                targets.append(deal.target)
                let board = LetterBoardBuilder.make(seed: seed, target: deal.target, settings: settings, progress: progress)
                expectEqual(board.rows.count, 2)
                expectEqual(board.rows[0].filter { $0 == deal.target }.count, 1)
                expectEqual(board.rows[1].filter { $0 == deal.target }.count, 1)
                expectEqual(board.targetCards.count, 2)
                expectEqual(Set(board.rows.flatMap { $0 }), Set(board.letters))
                for letter in board.letters { expectEqual(board.rows.flatMap { $0 }.filter { $0 == letter }.count, 2) }
                expectEqual(board.rows[0].count, 5)
                expectEqual(board.rows[1].count, 5)
                expectFalse(board.rows[0] == board.rows[1])
                expectFalse(board.rows.contains(Array("abcde").map(String.init)))
                expectFalse(board.rows.contains(Array("edcba").map(String.init)))
                expectFalse(board.rows[0].firstIndex(of: deal.target) == board.rows[1].firstIndex(of: deal.target))
                expectEqual(board, LetterBoardBuilder.make(seed: seed, target: deal.target, settings: settings, progress: progress))
                progress.record(deal.target, clean: true, round: round, at: Date(timeIntervalSince1970: 0))
            }
            expectEqual(Set(targets).count, 5)
            expectEqual(targets, Array("abcde").map(String.init))
        }
        var progress = LetterProgress()
        progress.record("c", clean: false, round: 7, at: Date())
        progress.lastTarget = "b"
        expectEqual(LetterScheduler.next(seed: "x", n: 10, settings: settings, progress: progress, now: Date()).lane, .retry)
        let guarded = LetterBoardBuilder.make(seed: "x", target: "b", settings: settings, progress: LetterProgress())
        expectFalse(guarded.letters.contains("d"))
        expectTrue(guarded.letters.contains("f"))
        var old = LetterProgress()
        old.record("a", clean: true, round: 1, at: Date(timeIntervalSince1970: 0))
        let nextWeek = TapLetterSettings(thisWeek: Array("fghij").map(String.init))
        expectEqual(LetterScheduler.next(seed: "x", n: 4, settings: nextWeek, progress: old,
                                         now: Date(timeIntervalSince1970: 9 * 86_400)).lane, .review)
    }

    func testWordBankAndDeck() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        expectEqual(bank.letters.count, 26)
        var decks = LetterWordDecks()
        let first = bank.deal(letter: "d", box: .learning, seed: "x", decks: &decks, now: Date())
        expectEqual(first[0].word, "dog")
        expectFalse(first[0].id == first[1].id)
        for index in 0..<30 {
            let pair = bank.deal(letter: "d", box: .learning, seed: "\(index)", decks: &decks, now: Date())
            expectFalse(pair[0].id == pair[1].id)
            expectFalse(pair.contains { $0.tier == "extra" })
        }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = LetterWordDecksStore(defaults: defaults)
        store.save(decks)
        expectEqual(store.load(), decks)
        defaults.set(Data("broken".utf8), forKey: LetterWordDecksStore.key)
        expectEqual(store.load(), LetterWordDecks())
        var fresh = LetterWordDecks()
        let day = Date(timeIntervalSince1970: 0)
        fresh.feature("d.duck", for: "d", at: day)
        let starred = bank.deal(letter: "d", box: .learning, seed: "star", decks: &fresh, now: day)
        expectEqual(starred[1].id, "d.duck")
        expectTrue(fresh.hide("d.duck", for: "d", bank: bank))
        let hidden = bank.deal(letter: "d", box: .practising, seed: "hidden", decks: &fresh, now: day)
        expectFalse(hidden.contains { $0.id == "d.duck" })
        var expired = LetterWordDecks()
        expired.feature("d.duck", for: "d", at: day)
        expectFalse(expired.schoolWords["d"]!.contains { $0.expiresAt > day.addingTimeInterval(8 * 86_400) })
        expectTrue(bank.deal(letter: "f", box: .learning, seed: "anchor-only", decks: &fresh, now: day).isEmpty)
        let generated = TapLetterGenerator.make(seed: "deal", n: 1, settings: .defaults,
                                               progress: LetterProgress(), decks: LetterWordDecks(),
                                               bank: bank, now: day)
        expectEqual(generated?.target, "a")
        expectEqual(generated?.words.count, 2)
    }

    func testBankSchemaAndContent() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        var ids = Set<String>()
        var images = Set<String>()
        var voices = Set<String>()
        let simplified = "\u{9E2D}\u{9E1F}\u{9F9F}\u{9C7C}\u{9A6C}\u{9E21}\u{95E8}\u{4E66}\u{82F9}\u{94C3}\u{949F}\u{7EA2}\u{7EFF}\u{7F51}\u{811A}\u{8138}\u{996D}\u{98CE}\u{98DE}\u{8F66}\u{540E}\u{53F6}\u{867E}\u{8721}\u{70DB}"
        let brands = ["jeep", "lego", "oreo", "band-aid"]
        for (letter, entry) in bank.letters {
            guard let words = entry.words else { continue }
            expectTrue(words.filter { $0.tier == "core" }.count >= 2)
            expectEqual(words.filter { $0.anchor == true }.count, 1)
            for word in words {
                expectTrue(letter == "x" ? word.word.contains("x") : word.word.hasPrefix(letter))
                expectTrue(ids.insert(word.id).inserted)
                expectTrue(images.insert(word.imageID).inserted)
                expectTrue(voices.insert(word.voiceKey).inserted)
                expectFalse(brands.contains(word.word.lowercased()))
                expectFalse(word.glossZH.contains { simplified.contains($0) })
                expectEqual(word.highlight.count, 2)
                let chars = Array(word.word)
                expectTrue(word.highlight[0] >= 0 && word.highlight[0] < chars.count)
                expectEqual(String(chars[word.highlight[0]]), letter)
            }
        }
    }
}
