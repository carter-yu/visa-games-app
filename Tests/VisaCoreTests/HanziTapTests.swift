import Foundation
import VisaCore

/// Hanzi H1 pure core (0.38.0 / 82): deals, scheduler, confusable guard and isolated stores for 中文字 · 翻字卡
/// (`tapHanziAll`) and 搵完寫 (`tapHanziWrite`), against design hanzi-tap v2 (D1–D12) and the six-target addendum
/// (2026-11-06). Offline: reads the bundled pack, the Traditional-only fixture and the app source.
final class HanziTapTests {
    private static let week = ["人", "上", "下", "左", "右", "木"]
    private static let findOnly = ["入", "八", "本", "未"]
    private static let pairs: [String: Set<String>] = [
        "人": ["入", "八"], "上": ["下"], "下": ["上"], "左": ["右"], "右": ["左"], "木": ["本", "未"]
    ]
    private static let day = Date(timeIntervalSince1970: 1_800_000_000)
    private static let packURL = URL(fileURLWithPath: "Resources/HanziTap/hanzi-pack.json")

    private func loadPack() throws -> HanziPack { try HanziPack.load(url: Self.packURL) }

    /// The bundled pack with `edit` applied to its JSON; it must still load.
    private func editedPack(_ edit: (inout [String: Any]) -> Void) throws -> HanziPack {
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.packURL)) as! [String: Any]
        edit(&root)
        return try HanziPack.load(data: JSONSerialization.data(withJSONObject: root))
    }

    /// `glyphs` keep their pack entries but lose `displayFormVerified`.
    private func unverifiedPack(_ glyphs: [String]) throws -> HanziPack {
        try editedPack { root in
            var findOnly = root["findOnly"] as! [String: Any]
            for glyph in glyphs {
                var entry = findOnly[glyph] as! [String: Any]
                entry["displayFormVerified"] = false
                findOnly[glyph] = entry
            }
            root["findOnly"] = findOnly
        }
    }

    /// Scheduler rounds recorded as the app will: `clean` decides each finding result.
    private func play(_ rounds: ClosedRange<Int>, seed: (Int) -> String, settings: HanziTapSettings = .defaults,
                      progress: inout HanziProgress, pack: HanziPack, now: (Int) -> Date = { _ in HanziTapTests.day },
                      clean: (Int, HanziChoice) -> Bool = { _, _ in true }) -> [HanziChoice] {
        var choices: [HanziChoice] = []
        for n in rounds {
            let choice = HanziScheduler.next(seed: seed(n), n: n, settings: settings, progress: progress,
                                             pack: pack, now: now(n))
            progress.record(choice, clean: clean(n, choice), round: n, at: now(n))
            choices.append(choice)
        }
        return choices
    }

    /// Every week target with one clean find round, so no guard is up.
    private func liftedProgress(_ pack: HanziPack) -> HanziProgress {
        var progress = HanziProgress()
        _ = play(1...6, seed: { "lift-\($0)" }, progress: &progress, pack: pack)
        return progress
    }

    private func subsets(_ items: [String], _ size: Int) -> [[String]] {
        guard size > 0 else { return [[]] }
        guard items.count >= size else { return [] }
        let tail = Array(items.dropFirst())
        return subsets(tail, size - 1).map { [items[0]] + $0 } + subsets(tail, size)
    }

    /// The 2 × 5 contract (a) and the balanced set (b) for one board; display glyphs must lie in `allowed`.
    private func checkBoard(_ board: HanziBoard, target: String, allowed: Set<String>, _ label: String) {
        expectEqual(board.target, target, label)
        expectEqual(board.rows.count, 2, label)
        expectTrue(board.rows.allSatisfy { $0.count == 5 }, label)
        expectEqual(board.cards.count, 10, label)
        // (a) Exactly two targets, one in each row, in different columns; the rows differ.
        expectEqual(board.cards.filter { $0 == target }.count, 2, label)
        expectEqual(board.rows.map { row in row.filter { $0 == target }.count }, [1, 1], label)
        expectEqual(board.targetCards.count, 2, label)
        expectTrue(board.targetCards[0] < 5 && board.targetCards[1] >= 5, label)
        expectFalse(board.targetCards[1] - 5 == board.targetCards[0], label)
        expectFalse(board.rows[0] == board.rows[1], label)
        // (b) Both rows permute one set of five distinct glyphs (each shown twice) that leads with the target.
        expectEqual(board.glyphs.count, 5, label)
        expectEqual(Set(board.glyphs).count, 5, label)
        expectEqual(board.glyphs.first, target, label)
        expectEqual(Set(board.rows[0]), Set(board.glyphs), label)
        expectEqual(Set(board.rows[1]), Set(board.glyphs), label)
        for glyph in board.glyphs { expectEqual(board.cards.filter { $0 == glyph }.count, 2, label) }
        expectTrue(Set(board.glyphs).isSubset(of: allowed), "\(label): \(board.glyphs) outside \(allowed.sorted())")
    }

    /// Every lane (fix round 1): after a miss in round m the target's next deal, whichever lane would deal it, is its
    /// retry in round m + 3, and no other round is a retry. For runs in which no review round can postpone a retry.
    private func checkRetries(_ choices: [HanziChoice], missed: Set<Int>, _ label: String) {
        var pending: [String: Int] = [:]
        for (index, choice) in choices.enumerated() {
            let n = index + 1
            if let miss = pending.removeValue(forKey: choice.target) {
                expectEqual(n, miss + HanziScheduler.retryAfterInterveningRounds + 1,
                            "\(choice.target) missed in round \(miss), dealt again in round \(n): \(label)")
                expectEqual(choice.lane, .retry, "\(label) round \(n)")
            } else {
                expectFalse(choice.lane == .retry, "a retry with no miss: \(label) round \(n)")
            }
            if missed.contains(n) { pending[choice.target] = n }
        }
        expectTrue(pending.isEmpty, "every miss dealt again: \(label)")
    }

    /// (a) Every deal is 2 × 5 with exactly two targets, one per row, in different columns: all six targets over
    /// many seeds with the guard on, off and lifted, and every round the generator deals over scheduled runs.
    func testEveryDealIsTwoByFiveWithOneTargetPerRow() throws {
        let pack = try loadPack()
        let packSet = Set(pack.board.targetWeek + pack.dealableFindOnly)
        let lifted = liftedProgress(pack)
        expectTrue(Self.week.allSatisfy { lifted.state(for: $0).cleanRounds == 1 }, "one clean find round each")
        for number in 0..<300 {
            let seed = "seed-\(number)"
            for target in Self.week {
                for (progress, guardOn) in [(HanziProgress(), true), (HanziProgress(), false), (lifted, true)] {
                    let board = HanziBoardBuilder.make(seed: seed, target: target, week: Self.week,
                                                       confusableGuard: guardOn, progress: progress, pack: pack)
                    guard let board else {
                        expectTrue(false, "no deal for \(target) \(seed) guard \(guardOn)")
                        continue
                    }
                    checkBoard(board, target: target, allowed: packSet, "\(target) \(seed) guard \(guardOn)")
                    expectEqual(HanziBoardBuilder.make(seed: seed, target: target, week: Self.week, confusableGuard: guardOn,
                                                       progress: progress, pack: pack), board, "same seed, same board")
                }
            }
        }
        // Both kinds through the generator, per-round seeds, a deterministic mix of misses (retries included).
        var deals = 0
        var lanes = Set<String>()
        for number in 0..<120 {
            var progress = HanziProgress()
            var decks = HanziCueDecks()
            var misses = QuestionRNG(seed: "run-\(number)", salt: "hanzi-test-misses")
            var leads: [String: String] = [:]
            for n in 1...30 {
                let kind: ActivityKind = n % 2 == 0 ? .tapHanziWrite : .tapHanziAll
                let result = TapHanziGenerator.make(seed: "run-\(number)-\(n)", kind: kind, n: n, settings: .defaults,
                                                    progress: progress, decks: decks, pack: pack, now: Self.day)
                guard let deal = result.deal else {
                    expectTrue(false, "no deal in run \(number) round \(n): \(result)")
                    break
                }
                let target = deal.choice.target
                expectEqual(deal.kind, kind)
                checkBoard(deal.board, target: target, allowed: packSet, "run \(number) round \(n)")
                // Cue decks: both pictures, never one twice, leading with the other picture than last time.
                expectEqual(deal.cues.count, 2)
                expectEqual(Set(deal.cues), Set(pack.characters[target]!.cuePictures))
                if let previous = leads[target] { expectFalse(deal.cues[0] == previous, "\(target) lead alternates") }
                leads[target] = deal.cues[0]
                decks = deal.decks
                progress.record(deal.choice, clean: misses.below(4) != 0, round: n, at: Self.day)
                lanes.insert(deal.choice.lane.rawValue)
                deals += 1
            }
        }
        expectEqual(deals, 120 * 30)
        expectEqual(lanes, ["week", "retry"])
        // Nothing is dealt for another kind or without a pack.
        expectEqual(TapHanziGenerator.make(seed: "x", kind: .tapLetterAll, n: 1, settings: .defaults, progress: HanziProgress(),
                                           decks: HanziCueDecks(), pack: pack, now: Self.day), .unavailable(.notHanziKind))
        expectEqual(TapHanziGenerator.make(seed: "x", kind: .tapHanziAll, n: 1, settings: .defaults, progress: HanziProgress(),
                                           decks: HanziCueDecks(), pack: nil, now: Self.day), .unavailable(.packUnavailable))
    }

    /// (b) Balanced set: both rows permute the same five distinct glyphs, each shown twice, always with the target,
    /// drawn from the week and the validated find-only glyphs; the sixth week glyph sits a deal out (addendum §2).
    func testBothRowsPermuteOneFiveGlyphSetFromTheWeek() throws {
        let pack = try loadPack()
        expectEqual(pack.dealableFindOnly, Self.findOnly)
        let packSet = Set(Self.week + Self.findOnly)
        var displaySets: [String: Set<[String]>] = [:]
        for number in 0..<300 {
            for target in Self.week {
                guard let board = HanziBoardBuilder.make(seed: "set-\(number)", target: target, week: Self.week,
                                                         confusableGuard: true, progress: HanziProgress(), pack: pack) else {
                    expectTrue(false, "no deal for \(target)")
                    continue
                }
                checkBoard(board, target: target, allowed: packSet, "\(target) set-\(number)")
                displaySets[target, default: []].insert(board.glyphs.sorted())
            }
        }
        for target in Self.week { expectTrue(displaySets[target]!.count > 1, "the five-glyph set varies for \(target)") }

        // Any week of two to six targets handed to the builder, for its own targets and review targets outside it: the
        // set is the target, week glyphs and find-only glyphs. Only a two-target week with 人 or 木 guarded runs short
        // of five; it then uses all of those and tops up from the pack's other targets (run-1 code refused that deal).
        var toppedUp = Set<String>()
        for size in 2...6 {
            for week in subsets(Self.week, size) {
                for target in Self.week {
                    for guardOn in [true, false] {
                        let blocked = guardOn ? Self.pairs[target]! : []
                        let supply = Set([target] + week + Self.findOnly).subtracting(blocked)
                        for number in 0..<20 {
                            let label = "week \(week.joined()) target \(target) guard \(guardOn) w-\(number)"
                            guard let board = HanziBoardBuilder.make(seed: "w-\(number)", target: target, week: week,
                                                                     confusableGuard: guardOn, progress: HanziProgress(),
                                                                     pack: pack) else {
                                expectTrue(false, "no deal: \(label)")
                                continue
                            }
                            expectTrue(Set(board.glyphs).isDisjoint(with: blocked), label)
                            if supply.count >= 5 {
                                checkBoard(board, target: target, allowed: supply, label)
                            } else {
                                checkBoard(board, target: target, allowed: packSet.subtracting(blocked), label)
                                expectTrue(supply.isSubset(of: board.glyphs), label)
                                toppedUp.insert("\(week.joined()):\(target)")
                            }
                        }
                    }
                }
            }
        }
        expectEqual(toppedUp, ["人上:人", "人下:人", "人左:人", "人右:人", "人木:人", "人木:木",
                               "上木:木", "下木:木", "左木:木", "右木:木"])
        // Through the generator a two-target parent week is the pack's week (fix round 1, `HanziScheduler.minimumWeek`),
        // so only a direct builder call meets the top-up. Every round still deals.
        var progress = HanziProgress()
        var decks = HanziCueDecks()
        let pairWeek = HanziTapSettings(week: ["人", "木"])
        for n in 1...20 {
            guard let deal = TapHanziGenerator.make(seed: "pair-\(n)", kind: .tapHanziAll, n: n, settings: pairWeek,
                                                    progress: progress, decks: decks, pack: pack, now: Self.day).deal else {
                expectTrue(false, "人木 week round \(n)")
                break
            }
            expectEqual(deal.choice.week, Self.week, "人木 week round \(n)")
            checkBoard(deal.board, target: deal.choice.target, allowed: packSet, "人木 week round \(n)")
            decks = deal.decks
            progress.record(deal.choice, clean: n % 3 == 0, round: n, at: Self.day)
        }
    }

    /// (c) Confusable guard: before a target's first clean find round its paired glyphs stay off the board, a paired
    /// week glyph gives its place to a validated find-only glyph (入 八 本 未), the row keeps five distinct glyphs,
    /// and a find-only glyph is never a target and never gets writing progress.
    func testConfusableGuardSwapsInValidatedFindOnlyGlyphs() throws {
        let pack = try loadPack()
        expectEqual(Set(pack.board.confusablePairs.flatMap { $0 }).subtracting(Self.week), Set(Self.findOnly))
        var standIns: [String: Set<String>] = [:]
        for number in 0..<300 {
            for target in Self.week {
                let board = HanziBoardBuilder.make(seed: "guard-\(number)", target: target, week: Self.week,
                                                   confusableGuard: true, progress: HanziProgress(), pack: pack)!
                let pair = Self.pairs[target]!
                expectEqual(Set(board.guarded), pair, target)
                expectTrue(Set(board.glyphs).isDisjoint(with: pair), "\(target) keeps \(pair.sorted()) off")
                expectEqual(Set(board.replacements.keys), pair.filter(Self.week.contains), target)
                for (neighbour, standIn) in board.replacements {
                    expectTrue(pack.dealableFindOnly.contains(standIn) && board.glyphs.contains(standIn), "\(neighbour)→\(standIn)")
                    standIns[neighbour, default: []].insert(standIn)
                }
                expectEqual(Set(board.glyphs).count, 5)
            }
        }
        // 上／下 and 左／右 swap in every validated find-only glyph; 人 and 木 have no week pair to swap.
        expectEqual(standIns, ["上": Set(Self.findOnly), "下": Set(Self.findOnly), "左": Set(Self.findOnly), "右": Set(Self.findOnly)])

        // After a clean find round, or with the guard off, the pairs are dealt on purpose (as letters).
        let lifted = liftedProgress(pack)
        for target in Self.week {
            for (progress, guardOn) in [(lifted, true), (HanziProgress(), false)] {
                let board = HanziBoardBuilder.make(seed: "pair", target: target, week: Self.week, confusableGuard: guardOn,
                                                   progress: progress, pack: pack)!
                expectTrue(Self.pairs[target]!.isSubset(of: board.glyphs), "\(target) shows its pair")
                expectTrue(board.guarded.isEmpty && board.replacements.isEmpty, target)
            }
        }
        // A later miss leaves the guard down: it is up only before the first clean find round (fix round 1; run 2
        // re-armed it, as letters' mirror guard does). `testGuardStaysLiftedAfterALaterMiss` adds save, load and old data.
        var missed = lifted
        let choice = HanziScheduler.next(seed: "miss", n: 7, settings: .defaults, progress: missed, pack: pack, now: Self.day)
        missed.record(choice, clean: false, round: 7, at: Self.day)
        expectEqual(missed.state(for: choice.target).cleanRounds, 0)
        let stillLifted = HanziBoardBuilder.make(seed: "pair", target: choice.target, week: Self.week, confusableGuard: true,
                                                 progress: missed, pack: pack)!
        expectTrue(stillLifted.guarded.isEmpty && stillLifted.replacements.isEmpty, choice.target)
        expectTrue(Self.pairs[choice.target]!.isSubset(of: stillLifted.glyphs), choice.target)

        // No validated find-only glyph to stand in: a guarded week pair is refused, never a weaker board (guardMode).
        let unverified = try unverifiedPack(Self.findOnly)
        expectEqual(unverified.dealableFindOnly, [])
        for target in Self.week {
            let guarded = HanziBoardBuilder.make(seed: "x", target: target, week: Self.week, confusableGuard: true,
                                                 progress: HanziProgress(), pack: unverified)
            if ["上", "下", "左", "右"].contains(target) {
                expectNil(guarded)
            } else {
                expectTrue(guarded.map { Set($0.glyphs).isSubset(of: Self.week) } == true, target)
            }
            let open = HanziBoardBuilder.make(seed: "x", target: target, week: Self.week, confusableGuard: false,
                                              progress: HanziProgress(), pack: unverified)
            expectTrue(open.map { Set($0.glyphs).isSubset(of: Self.week) } == true, target)
        }
        var first = HanziProgress()
        let firstDeal = TapHanziGenerator.make(seed: "u1", kind: .tapHanziAll, n: 1, settings: .defaults, progress: first,
                                               decks: HanziCueDecks(), pack: unverified, now: Self.day).deal!
        expectEqual(firstDeal.choice.target, "人")
        first.record(firstDeal.choice, clean: true, round: 1, at: Self.day)
        expectEqual(TapHanziGenerator.make(seed: "u2", kind: .tapHanziAll, n: 2, settings: .defaults, progress: first,
                                           decks: HanziCueDecks(), pack: unverified, now: Self.day),
                    .unavailable(.insufficientBoardGlyphs))
        // One unverified display form (本) is never shown, guarded or not.
        let oneUnverified = try unverifiedPack(["本"])
        expectEqual(oneUnverified.dealableFindOnly, ["入", "八", "未"])
        for number in 0..<100 {
            for target in Self.week {
                for (progress, guardOn) in [(HanziProgress(), true), (lifted, true), (HanziProgress(), false)] {
                    let board = HanziBoardBuilder.make(seed: "n-\(number)", target: target, week: Self.week,
                                                       confusableGuard: guardOn, progress: progress, pack: oneUnverified)!
                    expectFalse(board.glyphs.contains("本"), "unverified 本 shown for \(target)")
                }
            }
        }

        // Find-only glyphs are never targets (even when a parent week names them), never built, flipped or written.
        // Fewer than three pack targets left is the pack's week (`HanziScheduler.minimumWeek`, fix round 1).
        let named = HanziTapSettings(week: ["入", "人", "本", "上", "大", "八", "人", "木"])
        expectEqual(named.validWeek(in: pack), ["人", "上", "木"])
        expectEqual(HanziTapSettings(week: ["入", "人", "本", "上"]).validWeek(in: pack), Self.week)
        expectEqual(HanziTapSettings(week: ["入", "人", "未"]).validWeek(in: pack), Self.week)
        for glyph in Self.findOnly + ["大", "a", ""] {
            expectNil(HanziBoardBuilder.make(seed: "x", target: glyph, week: Self.week, confusableGuard: false,
                                             progress: HanziProgress(), pack: pack))
            var decks = HanziCueDecks()
            expectEqual(decks.deal(glyph, pack: pack), [])
            expectEqual(decks, HanziCueDecks())
            var writes = HanziWriteProgress()
            expectFalse(writes.record(glyph, clean: true, pack: pack), glyph)
            expectEqual(writes, HanziWriteProgress())
        }
        for number in 0..<100 {
            for settings in [named, .defaults] {
                var progress = HanziProgress()
                var rng = QuestionRNG(seed: "\(number)", salt: "hanzi-test-find-only")
                let choices = play(1...30, seed: { "f-\(number)-\($0)" }, settings: settings, progress: &progress, pack: pack,
                                   clean: { _, _ in rng.below(3) != 0 })
                expectTrue(choices.allSatisfy { pack.isTarget($0.target) && !pack.isFindOnly($0.target) })
                expectTrue(progress.glyphs.keys.allSatisfy { Self.week.map(HanziProgress.key).contains($0) })
                expectTrue(progress.retryQueue.allSatisfy { pack.isTarget($0.glyph) })
            }
        }
    }

    /// (c) Fix round 1: the guard is up only before a target's first clean find round (design), kept as
    /// `hasCleanRound`. A miss before that round keeps it up; a later miss resets the streak and box but not the guard,
    /// across save and load. Progress saved before the field existed derives it from `cleanRounds`.
    func testGuardStaysLiftedAfterALaterMiss() throws {
        let pack = try loadPack()
        let pair = Self.pairs["人"]!
        func board(_ progress: HanziProgress) -> HanziBoard {
            HanziBoardBuilder.make(seed: "later-miss", target: "人", week: Self.week, confusableGuard: true,
                                   progress: progress, pack: pack)!
        }
        func isGuarded(_ progress: HanziProgress) -> Bool {
            Set(board(progress).guarded) == pair && Set(board(progress).glyphs).isDisjoint(with: pair)
        }
        func isLifted(_ progress: HanziProgress) -> Bool {
            board(progress).guarded.isEmpty && pair.isSubset(of: board(progress).glyphs)
        }
        var progress = HanziProgress()
        expectTrue(isGuarded(progress), "fresh")
        _ = play(1...1, seed: { "later-\($0)" }, progress: &progress, pack: pack, clean: { _, _ in false })
        expectFalse(progress.state(for: "人").hasCleanRound, "missed in round 1")
        expectTrue(isGuarded(progress), "a miss before the first clean find keeps the guard")
        let retried = play(2...4, seed: { "later-\($0)" }, progress: &progress, pack: pack)
        expectEqual(retried.map(\.target), ["上", "下", "人"])
        expectTrue(progress.state(for: "人").hasCleanRound && isLifted(progress), "the retry is the first clean find")
        // Every later 人 round is missed: streak, first clean day and box reset, retries follow, the guard stays down.
        let later = play(5...24, seed: { "later-\($0)" }, progress: &progress, pack: pack,
                         clean: { _, choice in choice.target != "人" })
        expectTrue(later.contains { $0.target == "人" && $0.lane == .week }, "人 missed in a week round")
        expectTrue(later.contains { $0.target == "人" && $0.lane == .retry }, "人 missed in a retry")
        let state = progress.state(for: "人")
        expectTrue(state.cleanRounds == 0 && state.firstCleanDay == nil && state.box == .learning, "reset by the misses")
        expectTrue(state.hasCleanRound && isLifted(progress), "a later miss does not re-arm the guard")

        // Saved and loaded between rounds, as the app will: equal, and the guard stays down.
        let defaults = UserDefaults(suiteName: "VisaGames.hanziGuard.\(UUID().uuidString)")!
        let store = HanziProgressStore(defaults: defaults)
        store.save(progress)
        let loaded = store.load()
        expectEqual(loaded, progress)
        expectTrue(loaded.state(for: "人").hasCleanRound && isLifted(loaded), "after save and load")
        expectEqual(board(loaded), board(progress))

        // Saved before fix round 1, with no `hasCleanRound`: derived from `cleanRounds`. Every other field decodes as
        // before. 人's streak was reset by a miss, so nothing records its clean find and it reads guarded; 上 does not.
        var root = try JSONSerialization.jsonObject(with: defaults.data(forKey: HanziProgressStore.key)!) as! [String: Any]
        var glyphs = root["glyphs"] as! [String: Any]
        for (key, value) in glyphs {
            var entry = value as! [String: Any]
            expectTrue(entry.removeValue(forKey: "hasCleanRound") != nil, "\(key) saves hasCleanRound")
            glyphs[key] = entry
        }
        root["glyphs"] = glyphs
        defaults.set(try JSONSerialization.data(withJSONObject: root), forKey: HanziProgressStore.key)
        let legacy = store.load()
        var derived = progress
        for (key, value) in derived.glyphs { derived.glyphs[key]?.hasCleanRound = value.cleanRounds > 0 }
        expectEqual(legacy, derived)
        expectTrue(!legacy.state(for: "人").hasCleanRound && isGuarded(legacy), "old 人 data")
        expectTrue(legacy.state(for: "上").hasCleanRound, "old 上 data")
        store.save(legacy)
        expectEqual(store.load(), legacy)
        // Any other field missing still fails closed: the whole store loads empty.
        var broken = glyphs["hanzi:人"] as! [String: Any]
        broken.removeValue(forKey: "cleanRounds")
        glyphs["hanzi:人"] = broken
        root["glyphs"] = glyphs
        defaults.set(try JSONSerialization.data(withJSONObject: root), forKey: HanziProgressStore.key)
        expectEqual(store.load(), HanziProgress())
    }

    /// (d) Scheduler: the first cycle in the week's order, then each cycle reshuffled; every target once per cycle
    /// before the next; never the same target twice in a row, across cycle boundaries too; deterministic per seed.
    func testSchedulerCyclesTheWeekWithoutImmediateRepeats() throws {
        let pack = try loadPack()
        expectEqual(HanziScheduler.retryAfterInterveningRounds, pack.board.scheduler.retryAfterInterveningRounds)
        expectEqual(HanziTapSettings.defaults.reviewEvery, pack.defaults.reviewEveryRounds)
        expectEqual(HanziTapSettings.defaults.confusableGuard, pack.defaults.confusableGuard)
        var cycleOneOrders = Set<[String]>()
        for number in 0..<200 {
            var progress = HanziProgress()
            let choices = play(1...36, seed: { "cycle-\(number)-\($0)" }, progress: &progress, pack: pack)
            // The default week holds every pack target, so no round is a review and with no miss none is a retry.
            expectTrue(choices.allSatisfy { $0.lane == .week && $0.week == Self.week })
            expectEqual(choices.prefix(6).map(\.target), Self.week, "first cycle in the week's order")
            for cycle in 0..<6 {
                let block = choices[(cycle * 6)..<(cycle * 6 + 6)]
                expectEqual(Set(block.map(\.target)), Set(Self.week), "cycle \(cycle) deals all six once")
                expectTrue(block.allSatisfy { $0.cycle == cycle }, "cycle \(cycle) number")
            }
            for (a, b) in zip(choices, choices.dropFirst()) { expectFalse(a.target == b.target, "no immediate repeat") }
            cycleOneOrders.insert(choices[6..<12].map(\.target))
        }
        expectTrue(cycleOneOrders.count > 1, "later cycles are reshuffled by seed")

        // With misses and retries: a week round never repeats a target already dealt in its cycle, a cycle starts
        // only after the previous one dealt all six (week or retry), and still no target twice in a row.
        var retries = 0
        for number in 0..<200 {
            var progress = HanziProgress()
            var rng = QuestionRNG(seed: "\(number)", salt: "hanzi-test-cycle-misses")
            let choices = play(1...48, seed: { "mix-\(number)-\($0)" }, progress: &progress, pack: pack,
                               clean: { _, _ in rng.below(3) != 0 })
            var dealt: [Int: [String]] = [:]
            for (index, choice) in choices.enumerated() {
                let label = "mix-\(number) round \(index + 1)"
                if index > 0 {
                    let previous = choices[index - 1]
                    expectFalse(choice.target == previous.target, "no immediate repeat at \(label)")
                    expectTrue(choice.cycle == previous.cycle || choice.cycle == previous.cycle + 1, label)
                }
                if choice.lane == .week { expectFalse(dealt[choice.cycle, default: []].contains(choice.target), "once per cycle: \(label)") }
                if choice.cycle > 0 { expectEqual(Set(dealt[choice.cycle - 1] ?? []), Set(Self.week), "cycle finished first: \(label)") }
                if choice.lane == .retry { retries += 1 }
                dealt[choice.cycle, default: []].append(choice.target)
            }
        }
        expectTrue(retries > 0)

        // Same seed and state → same choice; replaying a run gives the same choices and progress.
        for number in 0..<50 {
            var first = HanziProgress()
            var second = HanziProgress()
            var rngA = QuestionRNG(seed: "\(number)", salt: "hanzi-test-replay")
            var rngB = QuestionRNG(seed: "\(number)", salt: "hanzi-test-replay")
            let a = play(1...30, seed: { "det-\(number)-\($0)" }, progress: &first, pack: pack, clean: { _, _ in rngA.below(3) != 0 })
            let b = play(1...30, seed: { "det-\(number)-\($0)" }, progress: &second, pack: pack, clean: { _, _ in rngB.below(3) != 0 })
            expectEqual(a, b)
            expectEqual(first, second)
            let next = HanziScheduler.next(seed: "det-\(number)", n: 31, settings: .defaults, progress: first, pack: pack, now: Self.day)
            expectEqual(HanziScheduler.next(seed: "det-\(number)", n: 31, settings: .defaults, progress: second, pack: pack,
                                            now: Self.day), next)
        }
    }

    /// (d) A missed target comes back after exactly two intervening rounds; every fourth round deals an older target
    /// that is due (box spacing as letters), never the last target, and never moves the week's cycle.
    func testRetryAfterTwoRoundsAndReviewEveryFourth() throws {
        let pack = try loadPack()
        // Miss 人 in round 1: 上 and 下 intervene, round 4 retries 人, then the cycle carries on.
        var progress = HanziProgress()
        let choices = play(1...8, seed: { "retry-\($0)" }, progress: &progress, pack: pack, clean: { n, _ in n != 1 })
        expectEqual(Array(choices.prefix(7).map(\.target)), ["人", "上", "下", "人", "左", "右", "木"])
        expectEqual(choices.map(\.lane), [.week, .week, .week, .retry, .week, .week, .week, .week])
        expectEqual(choices[7].cycle, 1)
        expectFalse(choices[7].target == "木")
        expectTrue(progress.retryQueue.isEmpty)

        // Over many runs: every round that deals a missed target, in any lane, is its retry exactly three rounds on
        // (fix round 1: run 2 checked only retry rounds), and every miss is retried once misses stop.
        var retries = 0
        for number in 0..<200 {
            var progress = HanziProgress()
            var rng = QuestionRNG(seed: "\(number)", salt: "hanzi-test-retry")
            var missed = Set<Int>()
            let choices = play(1...60, seed: { "r-\(number)-\($0)" }, progress: &progress, pack: pack, clean: { n, _ in
                let clean = n > 40 || rng.below(3) != 0
                if !clean { missed.insert(n) }
                return clean
            })
            checkRetries(choices, missed: missed, "r-\(number)")
            retries += choices.filter { $0.lane == .retry }.count
            expectTrue(progress.retryQueue.isEmpty, "r-\(number) retried every miss")
        }
        expectTrue(retries > 0)

        // Review: 人 was played, then the parent's week leaves it out. Rounds eight days apart keep it due in every box.
        let without = HanziTapSettings(week: ["上", "下", "左", "右", "木"])
        var old = HanziProgress()
        _ = play(1...1, seed: { _ in "old" }, settings: HanziTapSettings(week: ["人", "上", "下"]), progress: &old, pack: pack)
        expectEqual(old.lastTarget, "人")
        var reviewing = old
        let reviewRounds = play(2...17, seed: { "rev-\($0)" }, settings: without, progress: &reviewing, pack: pack,
                                now: { HanziTapTests.day.addingTimeInterval(Double($0) * 8 * 86_400) })
        for (index, choice) in reviewRounds.enumerated() {
            let n = index + 2
            expectEqual(choice.lane == .review, n % 4 == 0, "review lane at round \(n)")
            expectTrue(choice.lane == .review ? choice.target == "人" : without.week.contains(choice.target), "round \(n)")
        }
        expectEqual(Array(reviewRounds.filter { $0.lane == .week }.prefix(5).map(\.target)), without.week,
                    "reviews keep the cycle")
        expectEqual(reviewing.state(for: "人").box, .known)

        // Due only once its box spacing has passed (practising 2 days, known 7), only on a fourth round, never the
        // last target, and never with review off (每 4 輪 1 輪 = 4, none = 0).
        // 人 found clean `times` times in the week 人上下, the last time a day later.
        func seen(_ times: Int) -> HanziProgress {
            var p = HanziProgress()
            var n = 0
            while p.state(for: "人").cleanRounds < times {
                n += 1
                let choice = HanziScheduler.next(seed: "box-\(n)", n: n, settings: HanziTapSettings(week: ["人", "上", "下"]),
                                                 progress: p, pack: pack, now: Self.day)
                let last = choice.target == "人" && p.state(for: "人").cleanRounds == times - 1
                p.record(choice, clean: true, round: n, at: last ? Self.day.addingTimeInterval(86_400) : Self.day)
            }
            return p
        }
        for (times, box, days) in [(2, LetterBox.practising, 2.0), (3, .known, 7.0)] {
            var p = seen(times)
            expectEqual(p.state(for: "人").box, box)
            p.lastTarget = "上"
            let lastSeen = p.state(for: "人").lastSeen!
            let dueAt = lastSeen.addingTimeInterval(days * 86_400)
            func lane(_ n: Int, _ settings: HanziTapSettings, _ now: Date) -> LetterLane {
                HanziScheduler.next(seed: "due", n: n, settings: settings, progress: p, pack: pack, now: now).lane
            }
            expectEqual(lane(8, without, lastSeen.addingTimeInterval((days - 0.5) * 86_400)), .week)
            expectEqual(lane(8, without, dueAt), .review)
            expectEqual(HanziScheduler.next(seed: "due", n: 8, settings: without, progress: p, pack: pack, now: dueAt).target, "人")
            expectEqual(lane(7, without, dueAt), .week)
            var none = without
            none.reviewEvery = 0
            expectEqual(lane(8, none, dueAt), .week)
            p.lastTarget = "人"
            expectEqual(lane(8, without, dueAt), .week)
        }
    }

    /// (d) Fix round 1: a missed target waits out two other rounds in every lane, also in the narrowest week the
    /// scheduler takes (`HanziScheduler.minimumWeek`, three targets) and across a cycle boundary. A shorter parent week
    /// is the pack's week; a pack whose own week is that short fails to load (`HanziGlyphTests`).
    func testMissWaitsTwoRoundsInNarrowWeeksAndAcrossCycles() throws {
        let pack = try loadPack()
        expectEqual(HanziScheduler.minimumWeek, HanziScheduler.retryAfterInterveningRounds + 1)
        expectEqual(HanziScheduler.minimumWeek, 3)
        // The review's counterexample: week 人上, 人 missed in round 1, then 上, then 人 again in round 3. Two targets
        // cannot hold a miss back without an immediate repeat, so every week under three is the pack's week.
        for size in 0...2 {
            for week in subsets(Self.week, size) {
                expectEqual(HanziTapSettings(week: week).validWeek(in: pack), Self.week, "week \(week.joined())")
            }
        }
        var pair = HanziProgress()
        let counter = play(1...4, seed: { "pair-\($0)" }, settings: HanziTapSettings(week: ["人", "上"]), progress: &pair,
                           pack: pack, clean: { n, _ in n != 1 })
        expectEqual(counter.map(\.target), ["人", "上", "下", "人"])
        expectEqual(counter.map(\.lane), [.week, .week, .week, .retry])

        // Every three-target week, misses at random over ten cycles: no target twice in a row, each once per cycle in
        // the week lane, and a missed target's next deal is its retry three rounds on (no review is due: nothing
        // outside the week has been played).
        var retries = 0
        for week in subsets(Self.week, 3) {
            let settings = HanziTapSettings(week: week)
            expectEqual(settings.validWeek(in: pack), week)
            for number in 0..<30 {
                let label = "week \(week.joined()) narrow-\(number)"
                var progress = HanziProgress()
                var rng = QuestionRNG(seed: label, salt: "hanzi-test-narrow")
                var missed = Set<Int>()
                let choices = play(1...30, seed: { "narrow-\(number)-\($0)" }, settings: settings, progress: &progress,
                                   pack: pack, clean: { n, _ in
                    let clean = n > 24 || rng.below(3) != 0
                    if !clean { missed.insert(n) }
                    return clean
                })
                checkRetries(choices, missed: missed, label)
                retries += choices.filter { $0.lane == .retry }.count
                expectTrue(progress.retryQueue.isEmpty, label)
                var dealt: [Int: Set<String>] = [:]
                for (index, choice) in choices.enumerated() {
                    let round = "\(label) round \(index + 1)"
                    expectTrue(week.contains(choice.target) && choice.lane != .review, round)
                    if index > 0 { expectFalse(choice.target == choices[index - 1].target, "no immediate repeat: \(round)") }
                    if choice.lane == .week { expectFalse(dealt[choice.cycle, default: []].contains(choice.target), "once per cycle: \(round)") }
                    dealt[choice.cycle, default: []].insert(choice.target)
                }
            }
        }
        expectTrue(retries > 0)

        // Cycle boundary, six targets: 木 missed in the first cycle's last round, or 右 and 木 in its last two. The
        // reshuffled second cycle never opens with them, each comes back as its retry three rounds on, and that
        // cycle still deals all six once.
        for number in 0..<100 {
            for misses in [[6], [5, 6]] {
                let label = "edge-\(number) misses \(misses)"
                var progress = HanziProgress()
                let choices = play(1...13, seed: { "edge-\(number)-\($0)" }, progress: &progress, pack: pack,
                                   clean: { n, _ in !misses.contains(n) })
                expectEqual(choices.prefix(6).map(\.target), Self.week, label)
                checkRetries(choices, missed: Set(misses), label)
                let opening = choices[6]
                expectTrue(opening.cycle == 1 && opening.lane == .week, label)
                expectFalse(misses.map { Self.week[$0 - 1] }.contains(opening.target), "\(label): round 7 deals \(opening.target)")
                expectEqual(Set(choices[6..<12].map(\.target)), Set(Self.week), label)
                expectTrue(choices[6..<12].allSatisfy { $0.cycle == 1 } && choices[12].cycle == 2, label)
            }
        }
    }

    /// (d) Fix round 1: a review and a due retry in one round. The review goes first; the retry keeps its place and due
    /// round in the queue and is dealt, as a retry, in the next round (with review off it would not have waited).
    func testReviewGoesBeforeADueRetryWhichKeepsItsPlace() throws {
        let pack = try loadPack()
        let without = HanziTapSettings(week: ["上", "下", "左", "右", "木"])
        let date: (Int) -> Date = { HanziTapTests.day.addingTimeInterval(Double($0) * 8 * 86_400) }
        var progress = HanziProgress()
        _ = play(1...1, seed: { _ in "old" }, settings: HanziTapSettings(week: ["人", "上", "下"]), progress: &progress,
                 pack: pack, now: date)
        // 人, outside the week, is reviewed in round 4; 左, missed in round 5, is due in round 8, the next review round.
        let lead = play(2...7, seed: { "clash-\($0)" }, settings: without, progress: &progress, pack: pack, now: date,
                        clean: { n, _ in n != 5 })
        expectEqual(lead.map(\.target), ["上", "下", "人", "左", "右", "木"])
        expectEqual(lead.map(\.lane), [.week, .week, .review, .week, .week, .week])
        expectEqual(progress.retryQueue, [HanziRetry(glyph: "左", dueRound: 8)])
        var noReview = without
        noReview.reviewEvery = 0
        let unpostponed = HanziScheduler.next(seed: "clash-8", n: 8, settings: noReview, progress: progress, pack: pack,
                                              now: date(8))
        expectTrue(unpostponed.target == "左" && unpostponed.lane == .retry, "review off: the retry is not postponed")
        let clash = play(8...8, seed: { "clash-\($0)" }, settings: without, progress: &progress, pack: pack, now: date)
        expectTrue(clash[0].target == "人" && clash[0].lane == .review, "round 8 reviews 人")
        expectEqual(progress.retryQueue, [HanziRetry(glyph: "左", dueRound: 8)], "the retry keeps its place and due round")
        let after = play(9...10, seed: { "clash-\($0)" }, settings: without, progress: &progress, pack: pack, now: date)
        expectTrue(after[0].target == "左" && after[0].lane == .retry, "round 9 retries 左")
        expectTrue(progress.retryQueue.isEmpty)
        // The first cycle dealt all five by round 7, so the retry is the next cycle's visit to 左 and round 10 deals
        // another target of that cycle.
        expectEqual(after.map(\.cycle), [1, 1])
        expectTrue(after[1].lane == .week && without.week.contains(after[1].target) && after[1].target != "左")
    }

    /// (e) Missing, corrupt or out-of-range data, or settings of another schema version, never turn anything on:
    /// settings load the defaults (pack week, review every 4, guard on, audio and jyutping OFF), the other stores,
    /// versioned by their `.v1` key, load empty when unreadable, and both games stay OFF.
    func testStoresFailClosedWithGamesAudioAndJyutpingOff() throws {
        let pack = try loadPack()
        let defaults = UserDefaults(suiteName: "VisaGames.hanziTap.\(UUID().uuidString)")!
        let store = HanziTapSettingsStore(defaults: defaults)
        func expectOff(_ value: HanziTapSettings, _ label: String) {
            expectEqual(value, .defaults, label)
            expectFalse(value.audioEnabled || value.jyutpingEnabled, label)
            expectEqual(value.validWeek(in: pack), Self.week, label)
            expectEqual(value.reviewEvery, 4, label)
            expectTrue(value.confusableGuard, label)
        }
        expectOff(store.load(), "missing")
        expectFalse(pack.defaults.audioEnabled || pack.defaults.jyutpingEnabled || pack.defaults.findEnabled
                    || pack.defaults.writeEnabled)
        // A valid v1 value round-trips, so each fallback below is the store's.
        let chosen = HanziTapSettings(week: ["上", "下", "左"], reviewEvery: 0, confusableGuard: false,
                                      audioEnabled: true, jyutpingEnabled: true)
        store.save(chosen)
        expectEqual(store.load(), chosen)
        func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
        let good: [String: Any] = ["schemaVersion": 1, "week": ["上", "下"], "reviewEvery": 4, "confusableGuard": true,
                                   "audioEnabled": true, "jyutpingEnabled": true]
        defaults.set(json(good), forKey: HanziTapSettingsStore.key)
        expectTrue(store.load().audioEnabled && store.load().jyutpingEnabled, "well-formed v1")
        var bad: [(String, Data)] = [("corrupt", Data("{\"schemaVersion\":1,".utf8)), ("empty", Data()),
                                     ("array", json(["上", "下"]))]
        for (key, value) in [("schemaVersion", 2), ("schemaVersion", 0), ("reviewEvery", 3), ("reviewEvery", -4)] {
            var object = good
            object[key] = value
            bad.append(("\(key) \(value)", json(object)))
        }
        for key in ["schemaVersion", "audioEnabled", "week"] {
            var object = good
            object.removeValue(forKey: key)
            bad.append(("no \(key)", json(object)))
        }
        var typed = good
        typed["jyutpingEnabled"] = "yes"
        bad.append(("typed", json(typed)))
        for (label, data) in bad {
            defaults.set(data, forKey: HanziTapSettingsStore.key)
            expectOff(store.load(), label)
        }
        defaults.set("audio on", forKey: HanziTapSettingsStore.key)
        expectOff(store.load(), "a string")

        // Progress, writing, cue and round stores: missing or unreadable → empty, never a partial value.
        let progressStore = HanziProgressStore(defaults: defaults)
        let writeStore = HanziWriteProgressStore(defaults: defaults)
        let deckStore = HanziCueDecksStore(defaults: defaults)
        let roundStore = HanziRoundIndexStore(defaults: defaults)
        expectEqual(progressStore.load(), HanziProgress())
        expectEqual(writeStore.load(), HanziWriteProgress())
        expectEqual(deckStore.load(), HanziCueDecks())
        expectEqual(roundStore.load(), 0)
        var progress = HanziProgress()
        _ = play(1...9, seed: { "store-\($0)" }, progress: &progress, pack: pack, clean: { n, _ in n % 4 != 0 })
        var writes = HanziWriteProgress()
        writes.record("上", clean: true, pack: pack)
        var decks = HanziCueDecks()
        _ = decks.deal("木", pack: pack)
        progressStore.save(progress)
        writeStore.save(writes)
        deckStore.save(decks)
        roundStore.save(9)
        expectEqual(progressStore.load(), progress)
        expectEqual(writeStore.load(), writes)
        expectEqual(deckStore.load(), decks)
        expectEqual(roundStore.load(), 9)
        // Versioned by key (fix round 1, narrowing run 2's claim): these values carry no version field, so a well-formed
        // blob under `.v1` loads as v1 even with a `schemaVersion` the settings store would reject, and a value under a
        // `.v2` key is never read. A new format must take a new key.
        let blobKeys = [HanziProgressStore.key, HanziWriteProgressStore.key, HanziCueDecksStore.key]
        let versionedKeys = blobKeys + [HanziRoundIndexStore.key]
        expectTrue(versionedKeys.allSatisfy { $0.hasPrefix("VisaGames.tapHanzi") && $0.hasSuffix(".v1") })
        for key in blobKeys {
            var object = try JSONSerialization.jsonObject(with: defaults.data(forKey: key)!) as! [String: Any]
            expectTrue(object["schemaVersion"] == nil, "\(key) has no version field")
            object["schemaVersion"] = 2
            defaults.set(json(object), forKey: key)
        }
        expectEqual(progressStore.load(), progress)
        expectEqual(writeStore.load(), writes)
        expectEqual(deckStore.load(), decks)
        for key in versionedKeys {
            let value = defaults.object(forKey: key)!
            defaults.removeObject(forKey: key)
            defaults.set(value, forKey: String(key.dropLast(3)) + ".v2")
        }
        expectEqual(progressStore.load(), HanziProgress())
        expectEqual(writeStore.load(), HanziWriteProgress())
        expectEqual(deckStore.load(), HanziCueDecks())
        expectEqual(roundStore.load(), 0)
        // Unreadable under `.v1` (truncated, a field of the wrong type, not an object): empty, never a partial value.
        let mistyped = json(["glyphs": ["hanzi:上": "known"], "streaks": ["hanzi:上": "two"], "leads": ["hanzi:上": 1]])
        for data in [Data("{\"glyphs\":".utf8), mistyped, json([1, 2])] {
            for key in blobKeys { defaults.set(data, forKey: key) }
            expectEqual(progressStore.load(), HanziProgress())
            expectEqual(writeStore.load(), HanziWriteProgress())
            expectEqual(deckStore.load(), HanziCueDecks())
        }
        roundStore.save(-3)
        expectEqual(roundStore.load(), 0)

        // Games: before H2–H4 neither kind is playable; both are default-off (D6) and need their own playtest, so a
        // fresh, corrupt or hand-edited assignment never deals or enables them.
        for kind in [ActivityKind.tapHanziAll, .tapHanziWrite] {
            expectFalse(ActivityCatalog.playableKinds.contains(kind) || ActivityCatalog.defaultOnKinds.contains(kind))
            expectTrue(ActivityCatalog.defaultOffKinds.contains(kind) && kind.requiresPlaytestBeforeStars && kind.isTapHanziFamily)
            expectEqual(MissionGameAssignment.defaultStars(for: kind), [])
        }
        let assignments = MissionGameAssignmentStore(defaults: defaults)
        var loaded = [assignments.load()]
        defaults.set(Data("{\"starsByKind\":".utf8), forKey: MissionGameAssignmentStore.key)
        loaded.append(assignments.load())
        defaults.set(json(["starsByKind": ["tapHanziAll": [1, 2, 3], "tapHanziWrite": [1, 2, 3]]]), forKey: MissionGameAssignmentStore.key)
        loaded.append(assignments.load())
        for assignment in loaded {
            expectFalse(assignment.enabledStars.keys.contains { $0.isTapHanziFamily })
            for kind in [ActivityKind.tapHanziAll, .tapHanziWrite] {
                expectTrue(assignment.isHiddenFromMissions(kind))
                for star in ChildDifficulty.allCases {
                    expectFalse(assignment.isEnabled(kind, star: star) || assignment.pool(for: star).contains(kind))
                    expectEqual(assignment.toggling(kind, star: star), .rejectedLastStar)
                }
            }
        }
    }

    /// (f) Prior Latin / letter data is untouched: every letter store keeps its key and bytes, Hanzi writes only its
    /// five `VisaGames.tapHanzi*` keys with `hanzi:` entries, build-81 kinds decode unchanged and the counts are real.
    func testLetterDataUntouchedAndActivityKindsHonest() throws {
        let pack = try loadPack()
        let defaults = UserDefaults(suiteName: "VisaGames.hanziIsolation.\(UUID().uuidString)")!
        func snapshot() -> [String: String] {
            var values: [String: String] = [:]
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("VisaGames.") {
                if let data = defaults.data(forKey: key) { values[key] = "data:" + data.base64EncodedString() }
                else { values[key] = "value:\(String(describing: defaults.object(forKey: key)))" }
            }
            return values
        }
        // A build-81 household: letter settings v1 / v2, progress, streaks, decks, round index, selection schedule,
        // stroke-order progress and the mission assignment.
        var letters = LetterProgress()
        letters.record("a", clean: true, round: 1, at: Self.day)
        letters.record("b", clean: false, round: 2, at: Self.day)
        var latinWrites = LetterWriteProgress()
        latinWrites.record("a", clean: true)
        latinWrites.record("a", clean: true)
        var wordDecks = LetterWordDecks()
        wordDecks.feature("d.duck", for: "d", at: Self.day)
        LetterProgressStore(defaults: defaults).save(letters)
        TapLetterSettingsStore(defaults: defaults).save(TapLetterSettings(thisWeek: ["f", "g", "h"]))
        LetterWriteProgressStore(defaults: defaults).save(latinWrites)
        LetterWordDecksStore(defaults: defaults).save(wordDecks)
        LetterRoundIndexStore(defaults: defaults).save(7)
        for key in ["VisaGames.tapLetterSettings.v2", "VisaGames.letterSelectionSchedule.v2", "VisaGames.strokeOrderProgress.v1"] {
            defaults.set(Data("{\"build\":81,\"key\":\"\(key)\"}".utf8), forKey: key)
        }
        MissionGameAssignmentStore(defaults: defaults).save(.defaults)
        let before = snapshot()
        let letterKeys = [LetterProgressStore.key, TapLetterSettingsStore.key, LetterWriteProgressStore.key,
                          LetterWordDecksStore.key, LetterRoundIndexStore.key, "VisaGames.tapLetterSettings.v2",
                          "VisaGames.letterSelectionSchedule.v2", "VisaGames.strokeOrderProgress.v1",
                          MissionGameAssignmentStore.key]
        expectTrue(Set(letterKeys).isSubset(of: before.keys), "snapshot holds every letter store: \(before.keys.sorted())")

        // Every Hanzi reader and writer over a run of both kinds, as H2–H4 will save a finished round.
        let settingsStore = HanziTapSettingsStore(defaults: defaults)
        let progressStore = HanziProgressStore(defaults: defaults)
        let writeStore = HanziWriteProgressStore(defaults: defaults)
        let deckStore = HanziCueDecksStore(defaults: defaults)
        let roundStore = HanziRoundIndexStore(defaults: defaults)
        settingsStore.save(HanziTapSettings(audioEnabled: true))
        for n in 1...14 {
            let kind: ActivityKind = n % 2 == 0 ? .tapHanziWrite : .tapHanziAll
            guard let deal = TapHanziGenerator.make(seed: "iso-\(n)", kind: kind, n: roundStore.load() + 1,
                                                    settings: settingsStore.load(), progress: progressStore.load(),
                                                    decks: deckStore.load(), pack: pack, now: Self.day).deal else {
                expectTrue(false, "isolation round \(n)")
                break
            }
            var progress = progressStore.load()
            progress.record(deal.choice, clean: n % 5 != 0, round: n, at: Self.day)
            progressStore.save(progress)
            deckStore.save(deal.decks)
            if kind == .tapHanziWrite {
                var writes = writeStore.load()
                writes.record(deal.choice.target, clean: n % 3 != 0, pack: pack)
                writeStore.save(writes)
            }
            roundStore.save(n)
        }
        let after = snapshot()
        for (key, value) in before { expectEqual(after[key], value, "\(key) unchanged") }
        let hanziKeys = ["VisaGames.tapHanziSettings.v1", "VisaGames.tapHanziProgress.v1", "VisaGames.tapHanziWriteProgress.v1",
                         "VisaGames.tapHanziRoundIndex.v1", "VisaGames.tapHanziCueDecks.v1"]
        expectEqual([HanziTapSettingsStore.key, HanziProgressStore.key, HanziWriteProgressStore.key, HanziRoundIndexStore.key,
                     HanziCueDecksStore.key], hanziKeys)
        expectEqual(Set(after.keys).subtracting(before.keys), Set(hanziKeys))
        // Inside the Hanzi stores every entry is a `hanzi:<week target>` key.
        let targetKeys = Set(Self.week.map(HanziProgress.key))
        func keys(_ storeKey: String, _ field: String) throws -> Set<String> {
            let object = try JSONSerialization.jsonObject(with: defaults.data(forKey: storeKey)!) as! [String: Any]
            return Set((object[field] as! [String: Any]).keys)
        }
        for (storeKey, field) in [(HanziProgressStore.key, "glyphs"), (HanziWriteProgressStore.key, "streaks"),
                                  (HanziCueDecksStore.key, "leads")] {
            let found = try keys(storeKey, field)
            expectTrue(!found.isEmpty && found.isSubset(of: targetKeys), "\(storeKey) \(found.sorted())")
        }
        expectEqual(LetterProgressStore(defaults: defaults).load(), letters)
        expectEqual(LetterWriteProgressStore(defaults: defaults).load(), latinWrites)
        expectEqual(LetterWordDecksStore(defaults: defaults).load(), wordDecks)
        expectEqual(LetterRoundIndexStore(defaults: defaults).load(), 7)
        expectEqual(TapLetterSettingsStore(defaults: defaults).load().thisWeek, ["f", "g", "h"])
        expectEqual(roundStore.load(), 14)

        // ActivityKind: the 25 build-81 raw values keep their order and decode unchanged; the Hanzi kinds append.
        let build81 = ["twoPictureChoose", "findTheSame", "countVehicles", "sequenceShortToLong", "halfMatch", "shapeCousin",
                       "capacityCompare", "moreFewer", "shadowMatch", "emptyBay", "lineMatch", "lineMatchGuidedStraight",
                       "lineMatchGuidedBridge", "traceLines", "traceShapesDotted", "traceShapesArrows", "traceShapesFree",
                       "tapCountAll", "tapCountTrace", "tapCountPick", "tapCountAllEnglish", "tapCountTraceEnglish",
                       "tapCountPickEnglish", "tapLetterAll", "tapLetterWrite"]
        expectEqual(ActivityKind.allCases.map(\.rawValue), build81 + ["tapHanziAll", "tapHanziWrite"])
        let decoded = try JSONDecoder().decode([ActivityKind].self, from: JSONEncoder().encode(build81))
        expectEqual(decoded, Array(ActivityKind.allCases.prefix(25)))
        expectThrowsError(try JSONDecoder().decode([ActivityKind].self, from: Data("[\"tapHanziRead\"]".utf8)))
        expectEqual(Set(ActivityCatalog.playableKinds.map(\.rawValue)), Set(build81))
        expectEqual(ActivityCatalog.playableKinds.count, 25)
        expectEqual(ActivityCatalog.defaultOnKinds.count, 10)
        // A build-81 assignment reloads as saved, with no Hanzi entry added.
        let assignment = MissionGameAssignmentStore(defaults: defaults).load()
        expectEqual(assignment, MissionGameAssignment.defaults)
        expectEqual(assignment.enabledStars.count, 25)
        // D1 names; the short labels and levels match the letter pair. HK Traditional only.
        expectEqual([ActivityKind.tapHanziAll.parentCardTitle, ActivityKind.tapHanziWrite.parentCardTitle],
                    ["中文字 · 翻字卡", "中文字 · 搵完寫"])
        expectEqual(ActivityKind.tapHanziAll.parentShortLabel, ActivityKind.tapLetterAll.parentShortLabel)
        expectEqual(ActivityKind.tapHanziWrite.parentShortLabel, ActivityKind.tapLetterWrite.parentShortLabel)
        expectEqual([ActivityKind.tapHanziAll.tapHanziLevel, ActivityKind.tapHanziWrite.tapHanziLevel], [.l1, .l2])
        expectEqual(ActivityKind.tapLetterAll.tapHanziLevel, nil)
        expectFalse(ActivityKind.tapLetterAll.isTapHanziFamily || ActivityKind.tapHanziAll.isTapLetterFamily)
        let fixture = URL(fileURLWithPath: "Tests/VisaCoreTests/Fixtures/traditional-check/simplified-only.txt")
        let simplified = Set(try String(contentsOf: fixture, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") }.joined().filter { !$0.isWhitespace })
        for kind in [ActivityKind.tapHanziAll, .tapHanziWrite] {
            for line in [kind.parentCardTitle, kind.parentShortLabel, kind.parentHelpTraditionalChinese,
                         ActivityCatalog.hintTraditionalChinese(for: kind)] {
                expectTrue(isTraditionalChineseOnly(line) && perfTraditionalOnly(line), line)
                expectFalse(line.contains { simplified.contains($0) }, "Simplified character in \(line)")
            }
        }
    }

    /// (g) Learned = two consecutive clean writes per glyph, by the letter completion rule, kept apart from Latin.
    func testLearnedIsTwoCleanWritesInARowIsolatedFromLatin() throws {
        let pack = try loadPack()
        var writes = HanziWriteProgress()
        for glyph in Self.week {
            expectFalse(writes.isLearned(glyph))
            expectTrue(writes.record(glyph, clean: true, pack: pack))
            expectFalse(writes.isLearned(glyph), "one clean write")
            writes.record(glyph, clean: false, pack: pack)
            expectEqual(writes.streak(glyph), 0, "a non-clean write resets")
            writes.record(glyph, clean: true, pack: pack)
            expectFalse(writes.isLearned(glyph), "clean, help, clean is not two in a row")
            writes.record(glyph, clean: true, pack: pack)
            expectTrue(writes.isLearned(glyph), glyph)
        }
        // Per glyph: learning 上 leaves 下 and the rest unlearned, and a reset touches only its own glyph.
        var one = HanziWriteProgress()
        one.record("上", clean: true, pack: pack)
        one.record("上", clean: true, pack: pack)
        one.record("下", clean: true, pack: pack)
        expectTrue(one.isLearned("上"))
        expectFalse(Self.week.filter { $0 != "上" }.contains { one.isLearned($0) })
        one.record("下", clean: false, pack: pack)
        expectTrue(one.isLearned("上"))
        expectEqual(one.streaks, ["hanzi:上": 2, "hanzi:下": 0])
        // Find-only and unknown glyphs are never written and never get a streak.
        for glyph in Self.findOnly + ["大", "a", "", "人人", "hanzi:人"] {
            let before = one
            expectFalse(one.record(glyph, clean: true, pack: pack), glyph)
            expectFalse(one.record(glyph, clean: true, pack: pack) || one.isLearned(glyph), glyph)
            expectEqual(one, before)
        }
        // Isolated from Latin: separate types, keys and store; a learned Latin glyph never reaches Hanzi or back.
        var latin = LetterWriteProgress()
        latin.record("a", clean: true)
        latin.record("a", clean: true)
        latin.record("上", clean: true)
        expectTrue(latin.isLearned("a"))
        expectFalse(one.isLearned("a"))
        expectFalse(latin.isLearned("上") || latin.isLearned("hanzi:上"))
        expectFalse(HanziWriteProgressStore.key == LetterWriteProgressStore.key)
        let defaults = UserDefaults(suiteName: "VisaGames.hanziWrite.\(UUID().uuidString)")!
        LetterWriteProgressStore(defaults: defaults).save(latin)
        HanziWriteProgressStore(defaults: defaults).save(one)
        expectEqual(LetterWriteProgressStore(defaults: defaults).load(), latin)
        expectEqual(HanziWriteProgressStore(defaults: defaults).load(), one)

        // Clean is the letter completion rule: no coach help (stall, ghost, re-demo), no wrong start, no reversal,
        // no off-path event.
        func board(_ glyph: String) -> ShapeTraceBoard {
            let shape = ShapeTraceShape(slot: "hanzi", kind: .numeral, strokes: HanziGlyphs.paths(glyph, in: pack), colorIndex: 0,
                                        frame: LineMatchRect(x: 0, y: 0, width: 300, height: 300))
            let question = ShapeTraceQuestion(itemID: HanziProgress.key(glyph), kind: .tapCountTrace, level: .l1,
                scene: .numeralBoard, shift: 0, big: false, slant: false, shapes: [shape], laneWidth: HanziGlyphs.laneWidth,
                promptKey: "", promptTraditionalChinese: "", promptEnglish: "")
            return ShapeTraceBoard(question: question, tolerance: .standard, directionHint: true)
        }
        var traced = board("人")
        var clock = 0.0
        var attempts = 0
        while !traced.isComplete, attempts < 4, let path = traced.currentPath {
            attempts += 1
            clock += 0.1
            _ = traced.penDown(at: path.start, now: clock)
            var distance = 0.0
            while distance <= path.length + 16 {
                clock += 0.02
                if case .strokeDone = traced.penMove(to: path.point(at: min(distance, path.length)), now: clock) { break }
                if traced.isComplete { break }
                distance += 6
            }
            traced.penUp()
        }
        expectTrue(traced.isComplete)
        expectTrue(HanziWriteProgress.isClean(guide: nil, trace: traced), "a traced 人 with no help is clean")
        let plan = TapCountGuidePlan(level: .standard, learned: false)
        var guide = TapCountGuideRun(plan: plan, demoDuration: 2, now: 0, demoLead: 0)
        expectTrue(HanziWriteProgress.isClean(guide: guide, trace: traced))
        guide.noteHelp(key: "ghost-1", kind: "ghost_to_end")
        expectFalse(HanziWriteProgress.isClean(guide: guide, trace: traced), "coach help")
        var reversed = board("人")
        let first = reversed.currentPath!
        _ = reversed.penDown(at: first.end, now: 1)
        expectTrue(reversed.wrongStarts > 0 && reversed.reverseDirections > 0)
        expectFalse(HanziWriteProgress.isClean(guide: nil, trace: reversed), "reverse start")
        let core = try String(contentsOfFile: "Sources/VisaCore/HanziTap.swift", encoding: .utf8)
        let app = try String(contentsOfFile: "Sources/VisaGames/AppDelegate.swift", encoding: .utf8)
        let rule = "trace.wrongStarts == 0 && trace.reverseDirections == 0 && trace.offPathCount == 0"
        expectTrue(core.contains("(guide?.clean ?? true) && " + rule), "Hanzi clean rule")
        expectTrue(app.contains("let clean = (tapLetterGuideRun?.clean ?? true) && " + rule), "letter completion rule")
    }
}
