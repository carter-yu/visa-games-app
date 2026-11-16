import Foundation
import VisaCore

/// patterns-sorting P0 (0.41.0): round state, speech and finish of the new cards (design §5.2–§5.7, §6.1, App. A;
/// §10.1 T6, T8, T10, T13, T14, T16). Pure VisaCore with `Session`, `RewardLedger` and `ChildFinishHold` in a kiosk
/// model like the 中文字 one (`HanziFindTests`); the app's wiring order is pinned by the P1 source guards.
final class PatternSortRoundTests {
    private static let day = Date(timeIntervalSince1970: 1_800_000_000)
    private static let methods = SortSettings.defaultMethods.union([.facing])

    private func oddQuestion(_ step: PatternSortStep = PatternSortStep(.l2, 0), seed: String = "board") -> OddOneOutQuestion {
        OddOneOutGenerator.make(seed: seed, step: step, methods: Self.methods)
    }

    private func wrongCards(_ q: OddOneOutQuestion) -> [Int] { q.cards.indices.filter { $0 != q.answer } }

    // MARK: T13 round boards

    /// T13: the four boards and the after-pause step (thresholds fixed at deal; stale calls ignored).
    func testRoundBoardsAndTheAfterPauseStep() {
        // 邊個唔同類: a new wrong card is a miss and leaves a pause; while it is pending every tap is ignored; after it,
        // a known-wrong re-tap is no miss and leaves no pause; a second, different wrong card is a new miss.
        let q = oddQuestion()
        let wrong = wrongCards(q)
        var board = OddOneOutBoard(question: q, deal: "deal-A", guidance: .standard, methods: Self.methods)
        expectEqual(board.tap(wrong[0], at: 0), .miss)
        expectTrue(board.pause.pausePending)
        expectEqual(board.tap(q.answer, at: 1), .ignored, "pause pending")
        expectEqual(board.tap(wrong[1], at: 2), .ignored, "pause pending")
        expectEqual(board.afterPause(miss: 1, currentDeal: "deal-A"), .tryAgain, "標準: no hint after 1")
        expectEqual(board.tap(wrong[0], at: 20), .knownWrongRetap)
        expectFalse(board.pause.pausePending)
        expectEqual(board.misses, 1)
        expectEqual(board.tap(wrong[0], at: 20.2), .doubleTapIgnored)
        expectEqual(board.tap(wrong[1], at: 21), .miss)
        expectEqual(board.misses, 2)
        expectEqual(board.afterPause(miss: 1, currentDeal: "deal-A"), .ignored, "an old miss number")
        expectEqual(board.afterPause(miss: 2, currentDeal: "deal-B"), .ignored, "a replaced board")
        expectEqual(board.afterPause(miss: 2, currentDeal: "deal-A"), .hint)
        expectEqual(board.afterPause(miss: 2, currentDeal: "deal-A"), .ignored, "once per pause")
        expectEqual(board.hintCard, q.answer)
        expectEqual(board.tap(q.answer, at: 40), .correct)
        expectTrue(board.isComplete && board.assisted && !board.firstTry)
        expectEqual(board.tap(q.answer, at: 50), .ignored, "correct fires once")
        expectEqual(board.tap(wrong[2], at: 60), .ignored)
        expectEqual(board.afterPause(miss: 2, currentDeal: "deal-A"), .ignored, "after completion")
        // 多啲 hints after the first pause; 少啲 after the second; first try is no miss.
        var more = OddOneOutBoard(question: q, deal: "d", guidance: .more, methods: Self.methods)
        _ = more.tap(wrong[0], at: 0)
        expectEqual(more.afterPause(miss: 1, currentDeal: "d"), .hint)
        // Miss → hint → a different wrong card (astra R1): a new miss while the hint stays on; the app records it with
        // its lane's hint flag, set when the hint appeared (source guard in OddOneOutWiringTests).
        expectEqual(more.tap(wrong[1], at: 10), .miss)
        expectTrue(more.hintOn && more.misses == 2)
        var less = OddOneOutBoard(question: q, deal: "d", guidance: .less, methods: Self.methods)
        _ = less.tap(wrong[0], at: 0)
        expectEqual(less.afterPause(miss: 1, currentDeal: "d"), .tryAgain)
        _ = less.tap(wrong[1], at: 5)
        expectEqual(less.afterPause(miss: 2, currentDeal: "d"), .hint)
        var clean = OddOneOutBoard(question: q, deal: "d", guidance: .standard, methods: Self.methods)
        expectEqual(clean.tap(q.answer, at: 0), .correct)
        expectTrue(clean.firstTry)
        expectEqual([PatternSortHelp.hintThreshold(.more), PatternSortHelp.hintThreshold(.standard),
                     PatternSortHelp.hintThreshold(.less)], [1, 2, 2])
        expectEqual(ActivityKind.allCases.filter(\.usesBoardAfterPause), [.patternNext, .oddOneOut, .sortGarages])

        // 接落去: a right first blank survives a later miss; known-wrong per blank; complete once, at the last blank.
        let pattern = PatternGenerator.make(seed: "round", step: PatternSortStep(.l2, 2), materials: .vehicles)
        expectEqual(pattern.row.task, .add2)
        var round = PatternRound(question: pattern, deal: "p", guidance: .standard)
        let first = pattern.answers[0], second = pattern.answers[1]
        let wrongForSecond = pattern.choices.indices.first { $0 != second }!
        expectEqual(round.tap(choice: first, at: 0), .filled)
        expectEqual(round.tap(choice: wrongForSecond, at: 1), .miss)
        expectEqual(round.filled, [first], "the right first blank stays")
        expectEqual(round.afterPause(miss: 1, currentDeal: "p"), .tryAgain)
        expectEqual(round.tap(choice: wrongForSecond, at: 20), .knownWrongRetap)
        expectEqual(round.tap(choice: second, at: 21), .complete)
        expectEqual(round.tap(choice: second, at: 22), .ignored)
        expectTrue(round.isComplete && round.misses == 1)

        // 分車房: known-wrong per vehicle, empty again for the next one; the hint stays on for later vehicles.
        let sort = SortGaragesGenerator.make(seed: "board", step: PatternSortStep(.l2, 1), methods: SortSettings.defaultMethods)
        var garages = SortGaragesBoard(question: sort, deal: "s", guidance: .more)
        let right0 = sort.garages[0]
        expectEqual(garages.choose(garage: 1 - right0, at: 0), .miss)
        expectEqual(garages.afterPause(miss: 1, currentDeal: "s"), .hint)
        expectEqual(garages.hintGarage, right0)
        expectEqual(garages.choose(garage: 1 - right0, at: 15), .knownWrongRetap)
        expectEqual(garages.choose(garage: right0, at: 16), .parked)
        expectEqual(garages.knownWrong, [], "starts empty for the next vehicle")
        expectEqual(garages.hintGarage, sort.garages[1], "the hint stays on")
        for item in 1..<sort.queue.count {
            let outcome = garages.choose(garage: sort.garages[item], at: 20 + Double(item))
            expectEqual(outcome, item == sort.queue.count - 1 ? .complete : .parked)
        }
        expectEqual(garages.choose(garage: 0, at: 99), .ignored, "complete fires once")
        expectEqual(garages.placed.count, sort.queue.count)
        var quick = SortGaragesBoard(question: sort, deal: "s", guidance: .standard)
        _ = quick.choose(garage: sort.garages[0], at: 0)
        expectEqual(quick.choose(garage: sort.garages[0], at: 0.3), .doubleTapIgnored, "the same garage within 0.4 s")

        // 自己排: undo with 1–7 placed; the 8th piece completes once; then place and undo are ignored.
        var make = PatternMakeBoard(palette: PatternMakeGenerator.palette(seed: "m", materials: .shapes), deal: "m")
        expectEqual(make.undo(), .ignored)
        for index in 0..<7 { expectEqual(make.place(index % 3), .placed) }
        expectEqual(make.undo(), .undone)
        expectEqual(make.place(1), .placed)
        expectEqual(make.place(2), .complete)
        expectEqual([make.place(0), make.undo()], [.ignored, .ignored])
        expectEqual([make.placed.count, make.undos], [8, 1])
        print("  pattern sort: boards — known-wrong across pauses, 0.4 s guard, one completion; hint after 1 at 多啲, 2 at 標準 / 少啲; stale steps ignored")
    }

    // MARK: T14 read-through

    /// T14: engine choice for voice × clips × zh-HK voice; the cursor follows starts, ends at the finish or the
    /// deadline, clears on a cancel without ending, and ignores an old deal or generation.
    func testReadThroughEngineAndCursor() {
        let units = OddOneOutCopy.readThrough(oddQuestion(PatternSortStep(.l1, 0)), guidance: .standard)
        expectEqual(units.count, 2)
        expectEqual(units[0].light, OddOneOutCopy.panelLight)
        for voiceOn in [false, true] {
            for clips in ["none", "some", "all"] {
                for cantonese in [false, true] {
                    let has: (String) -> Bool = { key in clips == "all" || (clips == "some" && key == units[0].key) }
                    let engine = ReadThroughEngine.choose(voiceOn: voiceOn, units: units, hasClip: has, cantoneseVoice: cantonese)
                    let expected: ReadThroughEngine = !voiceOn ? .silentBeat : clips == "all" ? .clips
                        : cantonese ? .systemVoice : .silentBeat
                    expectEqual(engine, expected, "voice \(voiceOn) clips \(clips) zh-HK \(cantonese)")
                }
            }
        }
        expectEqual(ReadThroughEngine.choose(voiceOn: true, units: units, hasClip: { $0 == units[0].key }, cantoneseVoice: false),
                    .silentBeat, "some clips and no Cantonese voice: never a half-spoken row")
        // Clips, all or nothing (astra R1): unit i keeps index i and the end follows the last clip; a clip that does not
        // load (the first, the last, every one) sends the whole sequence to the no-clip engine, never an early end.
        guard case .clips(let starts, let end) = ReadThroughClipPlan.plan(durations: [1.0, 2.0], units: units,
                                                                            cantoneseVoice: false) else {
            expectTrue(false, "every clip loaded: clips")
            return
        }
        expectEqual(starts.count, units.count)
        expectEqual(starts[0], 0, accuracy: 1e-9)
        expectEqual(starts[1], 1.1, accuracy: 1e-9)
        expectEqual(end, 3.2, accuracy: 1e-9)
        for cantonese in [false, true] {
            let whole = ReadThroughClipPlan.fallback(cantonese ? .systemVoice : .silentBeat)
            for (durations, what) in [([nil, 2.0], "first unit"), ([1.0, nil], "last unit"), ([nil, nil], "every unit"),
                                      ([1.0], "a unit missing")] as [([TimeInterval?], String)] {
                expectEqual(ReadThroughClipPlan.plan(durations: durations, units: units, cantoneseVoice: cantonese), whole,
                            "\(what), zh-HK \(cantonese)")
            }
        }
        expectEqual(ReadThroughClipPlan.plan(durations: [], units: [], cantoneseVoice: true), .fallback(.silentBeat))
        // Silent timing: 0.8 s per word, 1.6 s per line, at least 2.4 s; the deadline 4 s later.
        let words = [0, 1, 2].map { (index: Int) -> ReadThroughUnit in
            ReadThroughUnit(key: "w\(index)", text: "巴士", kind: .word, light: index)
        }
        expectEqual(ReadThroughTiming.silentLength(words), 2.4, accuracy: 1e-9)
        expectEqual(ReadThroughTiming.silentLength(words + words), 4.8, accuracy: 1e-9)
        expectEqual(ReadThroughTiming.silentLength(units), 3.2, accuracy: 1e-9)
        expectEqual(ReadThroughTiming.deadline(units), 7.2, accuracy: 1e-9)
        for (start, expected) in zip(ReadThroughTiming.beatStarts(words + [units[0]]), [0, 0.8, 1.6, 2.4]) {
            expectEqual(start, expected, accuracy: 1e-9)
        }
        for engine in ReadThroughEngine.allCases {
            var cursor = ReadThroughCursor()
            cursor.start(units: words, deal: "D", generation: 3, engine: engine)
            expectTrue(cursor.unitStarted(0, deal: "D", generation: 3))
            expectEqual(cursor.light, 0)
            expectTrue(cursor.unitStarted(1, deal: "D", generation: 3))
            expectEqual(cursor.light, 1)
            expectFalse(cursor.unitStarted(2, deal: "D", generation: 2), "old generation")
            expectFalse(cursor.unitStarted(2, deal: "E", generation: 3), "old deal")
            expectEqual(cursor.light, 1)
            expectTrue(cursor.cancelled(deal: "D", generation: 3))
            expectNil(cursor.light)
            expectEqual(cursor.state, .playing(index: 1), "a cancel is never an end")
            // Replay: a new generation from item 1; the old one's events do nothing.
            cursor.start(units: words, deal: "D", generation: 4, engine: engine)
            expectFalse(cursor.finished(deal: "D", generation: 3))
            expectTrue(cursor.unitStarted(0, deal: "D", generation: 4))
            expectTrue(cursor.finished(deal: "D", generation: 4))
            expectEqual(cursor.state, .done)
            expectFalse(cursor.deadline(deal: "D", generation: 4), "already done")
            // The deadline ends a sequence that gets no events.
            cursor.start(units: words, deal: "D", generation: 5, engine: engine)
            expectFalse(cursor.deadline(deal: "D", generation: 4))
            expectTrue(cursor.deadline(deal: "D", generation: 5))
            expectEqual(cursor.state, .done)
            expectNil(cursor.light)
        }
        print("  pattern sort: read-through — 12 engine cases (some clips + no voice → silent beat), cursor stale tokens, cancel ≠ end, deadline")
    }

    // MARK: T16 reveal and stamp

    /// AppModel's reveal → stamp path on the real session and ledger (design §5.7): `solve` begins the reveal on a
    /// fresh speech generation, `stamp` is `applyEntrySuccess` (lock, open round, not yet completed, the lane's deal),
    /// parent entry runs in the app's order (hold, generation bump, the engine's stop events, then the mode change).
    struct Kiosk {
        enum Engine: CaseIterable { case systemVoice, clips, silentBeat }

        let now: Date
        var session: Session
        var ledger = RewardLedger(policy: RewardPolicy(initialAllowanceSeconds: 60, rewardCapSeconds: 1_200))
        var board: OddOneOutBoard
        var dealSeed: String
        var roundOpen = true
        var completed = false
        var reveal = RoundReveal(lane: .child)
        var generation = 0
        var cursor = ReadThroughCursor()
        var visas = 0
        var stamps = 0

        init(board: OddOneOutBoard, now: Date) {
            self.board = board
            self.now = now
            dealSeed = board.deal
            session = Session(snapshot: Snapshot(configured: true), now: now)
        }

        mutating func solve(_ engine: Engine) {
            guard board.tap(board.question.answer, at: 100) == .correct else { return }
            generation += 1
            reveal.begin(deal: dealSeed, generation: generation)
            cursor.start(units: OddOneOutCopy.reveal(board.question), deal: dealSeed, generation: generation,
                         engine: engine == .systemVoice ? .systemVoice : engine == .clips ? .clips : .silentBeat)
        }

        mutating func apply(_ outcome: RoundRevealOutcome) {
            guard case .stamp(let deal) = outcome else { return }
            stamps += 1
            guard deal == dealSeed, board.isComplete, roundOpen, !completed, session.mode == .lock else { return }
            completed = true
            let calendar = Calendar(identifier: .gregorian)
            ledger.completeEntryActivity(now: now, calendar: calendar)
            ledger.applyCompletion(id: deal, rewardSeconds: 300, kind: board.assisted ? .assisted : .unassisted,
                                   now: now, calendar: calendar)
            session.startPlayVisa(seconds: 300, now: now)
            guard session.mode == .play else { return }
            visas += 1
            roundOpen = false
        }

        /// The sequence's end event as each engine reports it (`didFinish`, the last clip's end, the last beat).
        mutating func ended(generation: Int) {
            _ = cursor.finished(deal: dealSeed, generation: generation)
            apply(reveal.sequenceEnded(deal: dealSeed, generation: generation, currentGeneration: self.generation,
                                       mode: session.mode))
        }

        mutating func deadline(_ deal: String? = nil) { apply(reveal.deadline(deal: deal ?? dealSeed, mode: session.mode)) }

        /// `enterParentAfterAuthentication`: the hold first, then the generation bump and speech stop, and only then
        /// the mode change. `late` runs before the mode changes (an event already in flight).
        mutating func enterParent(_ engine: Engine, late: (inout Kiosk, Int) -> Void = { _, _ in }) {
            reveal.enterParent()
            let old = generation
            generation += 1
            switch engine {
            case .systemVoice:
                _ = cursor.cancelled(deal: dealSeed, generation: old)
                _ = reveal.cancelled(deal: dealSeed, generation: old)
            case .clips: break            // `stop()` fires no callback for clips
            case .silentBeat: _ = cursor.cancelled(deal: dealSeed, generation: old)   // the dropped beat
            }
            late(&self, old)
            session.enterParent(authenticated: true, now: now)
        }

        mutating func returnToChild() {
            session.leaveParent(now: now)
            apply(reveal.returnToChild(openDeal: roundOpen ? dealSeed : nil, mode: session.mode))
        }

        mutating func reset() {
            roundOpen = false
            dealSeed = ""
            completed = false
            reveal.reset()
        }
    }

    /// T16: the reveal starts only at `correct`, stamps exactly once at the end or the deadline, never on a cancel,
    /// holds at parent entry for its own deal in every engine (late events before the mode change, under parent
    /// controls and after Return stamp nothing), stamps once on Return, and is isolated from a playtest.
    func testRevealStampsOnceAndHoldsAtParentEntry() {
        let q = oddQuestion(PatternSortStep(.l1, 0), seed: "reveal")
        let fresh = OddOneOutBoard(question: q, deal: "round-A", guidance: .standard, methods: Self.methods)

        // The pure transitions.
        var reveal = RoundReveal(lane: .child)
        expectTrue(reveal.begin(deal: "A", generation: 1))
        expectFalse(reveal.begin(deal: "A", generation: 2), "once")
        expectEqual(reveal.phase, .revealing(deal: "A", generation: 1))
        expectEqual(reveal.cancelled(deal: "A", generation: 1), .ignored)
        expectEqual(reveal.phase, .revealing(deal: "A", generation: 1), "a cancel is never an end")
        expectEqual(reveal.sequenceEnded(deal: "A", generation: 1, currentGeneration: 2, mode: .lock), .ignored, "old generation")
        expectEqual(reveal.sequenceEnded(deal: "B", generation: 1, currentGeneration: 1, mode: .lock), .ignored, "old deal")
        expectEqual(reveal.deadline(deal: "B", mode: .lock), .ignored)
        expectEqual(reveal.sequenceEnded(deal: "A", generation: 1, currentGeneration: 1, mode: .lock), .stamp("A"))
        expectEqual(reveal.deadline(deal: "A", mode: .lock), .ignored, "the end and the deadline stamp once")
        expectEqual(reveal.phase, .stamped(deal: "A"))
        var timed = RoundReveal(lane: .child)
        timed.begin(deal: "A", generation: 1)
        expectEqual(timed.deadline(deal: "A", mode: .lock), .stamp("A"))
        expectEqual(timed.sequenceEnded(deal: "A", generation: 1, currentGeneration: 1, mode: .lock), .ignored)
        var outside = RoundReveal(lane: .child)
        outside.begin(deal: "A", generation: 1)
        expectEqual(outside.deadline(deal: "A", mode: .parent), .held, "outside the lock it holds")
        expectEqual(outside.hold.round, "A")

        for engine in Kiosk.Engine.allCases {
            // Parent entry during the reveal: held at once for the same deal; nothing in flight stamps.
            var kiosk = Kiosk(board: fresh, now: Self.day)
            kiosk.solve(engine)
            expectEqual(kiosk.board.tap(q.answer, at: 101), .ignored, "taps during the reveal")
            kiosk.enterParent(engine) { k, old in
                expectEqual(k.reveal.phase, .held(deal: "round-A"))
                expectEqual(k.reveal.hold.round, "round-A", "the hold names the deal")
                k.ended(generation: old)       // didFinish / clip end / last beat before the mode changes
                k.deadline()
            }
            expectEqual(kiosk.session.mode, .parent)
            kiosk.ended(generation: kiosk.generation - 1)
            kiosk.deadline()
            expectEqual([kiosk.stamps, kiosk.visas, kiosk.ledger.successRecords.count], [0, 0, 0], "\(engine)")
            kiosk.returnToChild()
            expectEqual(kiosk.session.mode, .play, "Return stamps once")
            expectEqual([kiosk.stamps, kiosk.visas], [1, 1])
            expectEqual(kiosk.ledger.successRecords.map(\.completionID), ["round-A"])
            // A second visit, a second Return and late events add nothing.
            kiosk.enterParent(engine)
            kiosk.deadline()
            kiosk.returnToChild()
            kiosk.ended(generation: 1)
            expectEqual([kiosk.stamps, kiosk.visas, kiosk.ledger.successRecords.count], [1, 1, 1], "\(engine)")

            // Parent entry before completion holds nothing; the round then finishes in the lock as usual.
            var early = Kiosk(board: fresh, now: Self.day)
            early.enterParent(engine)
            expectEqual(early.reveal.phase, .idle)
            early.returnToChild()
            early.solve(engine)
            early.ended(generation: early.generation)
            expectEqual([early.stamps, early.visas], [1, 1])

            // A reset under parent controls: no stamp, no hold on Return.
            var cleared = Kiosk(board: fresh, now: Self.day)
            cleared.solve(engine)
            cleared.enterParent(engine)
            cleared.reset()
            cleared.returnToChild()
            expectEqual([cleared.stamps, cleared.visas], [0, 0])
            expectEqual(cleared.reveal.phase, .idle)

            // Another deal open on Return: the held one is dropped.
            var replaced = Kiosk(board: fresh, now: Self.day)
            replaced.solve(engine)
            replaced.enterParent(engine)
            replaced.dealSeed = "round-B"
            replaced.returnToChild()
            expectEqual([replaced.stamps, replaced.visas], [0, 0])
            expectEqual(replaced.reveal.phase, .idle)
            expectNil(replaced.reveal.hold.round)

            // Return into a running test visa releases nothing; that visa's reset drops the hold.
            var test = Kiosk(board: fresh, now: Self.day)
            test.solve(engine)
            test.enterParent(engine)
            test.session.grant(seconds: 60, now: Self.day)
            test.returnToChild()
            expectEqual(test.session.mode, .play)
            expectEqual(test.reveal.hold.round, "round-A", "a running visa releases nothing")
            test.session.endPlayVisa(now: Self.day)
            test.reset()
            test.returnToChild()
            expectEqual([test.stamps, test.visas, test.ledger.successRecords.count], [0, 0, 0])

            // Playtest isolation: a playtest of the same card, dealt, revealed, completed and discarded during the
            // visit, never holds, and the child's held deal still stamps once on Return.
            var child = Kiosk(board: fresh, now: Self.day)
            child.solve(engine)
            child.enterParent(engine)
            var playtest = RoundReveal(lane: .playtest)
            var playtestBoard = OddOneOutBoard(question: q, deal: "playtest-1", guidance: .standard, methods: Self.methods)
            expectEqual(playtestBoard.tap(q.answer, at: 0), .correct)
            expectTrue(playtest.begin(deal: "playtest-1", generation: 9))
            playtest.enterParent()
            expectEqual(playtest.phase, .revealing(deal: "playtest-1", generation: 9), "a playtest never holds")
            expectEqual(playtest.deadline(deal: "playtest-1", mode: .parent), .finishLocally("playtest-1"))
            playtest.reset()
            expectEqual(child.reveal.phase, .held(deal: "round-A"))
            child.returnToChild()
            expectEqual([child.stamps, child.visas], [1, 1])
        }
        // Silent timing of the 邊個唔同類 reveal: two lines, 3.2 s (≥ 2.4 s).
        expectEqual(ReadThroughTiming.silentLength(OddOneOutCopy.reveal(q)), 3.2, accuracy: 1e-9)
        print("  pattern sort: reveal — stamps once (end or deadline), holds at parent entry in 3 engines, one stamp on Return, playtest isolated")
    }

    // MARK: Lanes and the miss wait (astra R2)

    /// AppModel's two 邊個唔同類 lanes around a new wrong card's 0.6 s wait, on the real `BoardPendingMiss`, `Session` and
    /// boards, step by step in the app's order: a deal or a reset drops only its own lane's wait
    /// (`resetOddOneOutTransient(lane:)`, `resetTaskRound`), `discardPlaytestCover` drops only the 試玩's, a miss begins a
    /// ticket on its lane's board and deal, and the delayed callback settles that ticket against the lane's open deal
    /// before the miss is applied (`handleEvaluation` / `playtestHandle`). A lane takes input only while its own board is
    /// not waiting (`oddOneOutMissPending`). The app's calls are pinned by `OddOneOutWiringTests`.
    struct Lanes {
        var gate = BoardPendingMiss()
        var session = Session(snapshot: Snapshot(configured: true), now: Date(timeIntervalSince1970: 1_800_000_000))
        var child: OddOneOutBoard?
        var childSeed = ""
        var playtest: OddOneOutBoard?
        var playtestSeed = ""
        var tickets: [BoardPendingMiss.Ticket] = []
        /// Misses applied by a callback, as `lane:deal`.
        var applied: [String] = []

        mutating func dealChild(_ board: OddOneOutBoard) {
            childSeed = board.deal
            child = board
            gate.drop(lane: .child)
        }

        mutating func resetChild() {
            childSeed = ""
            child = nil
            gate.drop(lane: .child)
        }

        /// `startPlaytest`: the old cover is discarded first, then the new deal drops the 試玩 lane's wait.
        mutating func startPlaytest(_ board: OddOneOutBoard) {
            discardPlaytest()
            playtestSeed = board.deal
            playtest = board
            gate.drop(lane: .playtest)
        }

        mutating func discardPlaytest() {
            guard playtest != nil else { return }
            playtestSeed = ""
            playtest = nil
            gate.drop(lane: .playtest)
        }

        /// The lane's tap / replay / idle guard: its mode, its board, and no wait on that board's deal.
        func inputOpen(_ lane: RoundRevealLane) -> Bool {
            guard let board = lane == .child ? child : playtest,
                  session.mode == (lane == .child ? .lock : .parent) else { return false }
            return !gate.isPending(lane: lane, deal: board.deal)
        }

        /// `oddOneOutTap`: nil while the lane's input is closed; a new wrong card begins its lane's ticket.
        mutating func tap(_ lane: RoundRevealLane, card: Int, at time: Double) -> OddOneOutTap? {
            guard inputOpen(lane), var board = lane == .child ? child : playtest else { return nil }
            let outcome = board.tap(card, at: time)
            if lane == .child { child = board } else { playtest = board }
            if outcome == .miss { tickets.append(gate.begin(lane: lane, deal: board.deal)) }
            return outcome
        }

        /// The 0.6 s callback: settle against the lane's open deal first, apply only then.
        mutating func callback(_ ticket: BoardPendingMiss.Ticket) {
            guard gate.settle(ticket, openDeal: ticket.lane == .child ? childSeed : playtestSeed) else { return }
            applied.append("\(ticket.lane.rawValue):\(ticket.deal)")
        }
    }

    /// Astra R2: a new wrong card's wait belongs to its lane and deal. The reviewed sequence (an unfinished child round →
    /// parent → a 試玩 miss → the 試玩 discarded before its callback → Return → the child answers), a child's own wait
    /// kept through a 試玩, stale callbacks after a reset and a new deal, a 試玩 restart, and the gate's own tokens.
    func testPendingMissIsBoundToItsLaneAndDeal() {
        let q = oddQuestion(PatternSortStep(.l2, 0), seed: "lanes")
        let wrong = wrongCards(q)
        func board(_ deal: String) -> OddOneOutBoard {
            OddOneOutBoard(question: q, deal: deal, guidance: .standard, methods: Self.methods)
        }

        // The reviewed sequence.
        var lanes = Lanes()
        lanes.dealChild(board("child-1"))
        lanes.session.enterParent(authenticated: true, now: Self.day)
        lanes.startPlaytest(board("playtest-1"))
        expectEqual(lanes.tap(.playtest, card: wrong[0], at: 0), .miss)
        let playtestMiss = lanes.tickets[0]
        expectNil(lanes.tap(.playtest, card: q.answer, at: 0.2))
        expectTrue(lanes.gate.isPending(lane: .playtest, deal: "playtest-1"))
        expectFalse(lanes.gate.isPending(lane: .child, deal: "child-1"), "the 試玩's wait is not the child's")
        lanes.discardPlaytest()
        lanes.session.leaveParent(now: Self.day)
        expectEqual(lanes.session.mode, .lock)
        expectTrue(lanes.inputOpen(.child), "Return: the child's unfinished board is open")
        expectEqual(lanes.tap(.child, card: q.answer, at: 1), .correct, "the child answers")
        lanes.callback(playtestMiss)
        expectEqual(lanes.applied, [], "the discarded 試玩's late callback applies nothing")
        expectTrue(lanes.gate.isEmpty)

        // A child's own wait survives parent entry, a 試玩 (dealt, missed, discarded) and Return, and applies once.
        var held = Lanes()
        held.dealChild(board("child-2"))
        expectEqual(held.tap(.child, card: wrong[0], at: 0), .miss)
        let childMiss = held.tickets[0]
        held.session.enterParent(authenticated: true, now: Self.day)
        held.startPlaytest(board("playtest-2"))
        expectTrue(held.gate.isPending(lane: .child, deal: "child-2"), "the 試玩's deal keeps the child's wait")
        expectTrue(held.inputOpen(.playtest), "and the child's wait never blocks the 試玩")
        expectEqual(held.tap(.playtest, card: wrong[1], at: 0.1), .miss)
        let heldPlaytestMiss = held.tickets[1]
        held.discardPlaytest()
        expectTrue(held.gate.isPending(lane: .child, deal: "child-2"), "the discard keeps the child's wait")
        held.callback(childMiss)
        held.callback(heldPlaytestMiss)
        held.callback(childMiss)
        expectEqual(held.applied, ["child:child-2"], "once, on the child's own deal")
        held.session.leaveParent(now: Self.day)
        expectTrue(held.inputOpen(.child))
        expectTrue(held.gate.isEmpty)

        // Stale callbacks: a reset and a new deal before the callback; the old wait never blocks or unlocks the new deal.
        var stale = Lanes()
        stale.dealChild(board("child-3"))
        expectEqual(stale.tap(.child, card: wrong[0], at: 0), .miss)
        let oldMiss = stale.tickets[0]
        stale.resetChild()
        stale.dealChild(board("child-4"))
        expectTrue(stale.inputOpen(.child), "an old deal's wait never blocks a newer deal")
        expectEqual(stale.tap(.child, card: wrong[1], at: 1), .miss)
        let newMiss = stale.tickets[1]
        stale.callback(oldMiss)
        expectFalse(stale.inputOpen(.child), "nor unlocks the newer deal's wait")
        stale.callback(newMiss)
        expectEqual(stale.applied, ["child:child-4"])
        // A deal replaced without a drop: its wait is stale on the new deal, and its callback clears it.
        stale.childSeed = "child-5"
        stale.child = board("child-5")
        expectEqual(stale.tap(.child, card: wrong[0], at: 2), .miss)
        let replaced = stale.tickets[2]
        stale.childSeed = "child-6"
        stale.child = board("child-6")
        expectTrue(stale.inputOpen(.child))
        stale.callback(replaced)
        expectEqual(stale.applied, ["child:child-4"])
        expectTrue(stale.gate.isEmpty, "nothing left waiting")

        // A 試玩 restarted during its own wait: the new 試玩 deal is open and the old callback applies nothing.
        var restart = Lanes()
        restart.session.enterParent(authenticated: true, now: Self.day)
        restart.startPlaytest(board("playtest-3"))
        expectEqual(restart.tap(.playtest, card: wrong[0], at: 0), .miss)
        restart.startPlaytest(board("playtest-4"))
        expectTrue(restart.inputOpen(.playtest))
        restart.callback(restart.tickets[0])
        expectEqual(restart.applied, [])

        // The gate's tokens: a dropped ticket on the same lane and deal is stale and leaves the newer one waiting; a
        // ticket whose deal is gone applies nothing and leaves nothing behind.
        var gate = BoardPendingMiss()
        let first = gate.begin(lane: .child, deal: "D")
        gate.drop(lane: .child)
        let second = gate.begin(lane: .child, deal: "D")
        expectFalse(gate.settle(first, openDeal: "D"), "a dropped ticket, same lane and deal")
        expectTrue(gate.isPending(lane: .child, deal: "D"), "the newer wait stays")
        expectFalse(gate.isPending(lane: .playtest, deal: "D"), "lanes apart")
        expectTrue(gate.settle(second, openDeal: "D"))
        let gone = gate.begin(lane: .playtest, deal: "P")
        expectFalse(gate.settle(gone, openDeal: ""), "its deal is gone")
        expectTrue(gate.isEmpty, "cleared before deciding")
        print("  pattern sort: lanes — a 試玩 miss discarded before its callback never blocks the child's round; waits per lane and deal; stale callbacks do nothing")
    }

    /// Astra R3: `SystemSpeechPrompt`'s system-voice routing on the real `SpeechUnitReport` / `SpeechSequenceUnits`, with
    /// a stand-in utterance class and the delegate's main-actor hop held open (the reports wait in `hop` as they would in
    /// the delegate's `Task`). A stopped or replaced sequence's late `didStart` / `didFinish` / `didCancel` never reaches
    /// the replacement (another lane's deal, or the same deal's newer generation); each waiting report keeps its
    /// original utterance alive until it has been routed, so no replacement can sit at its address; the replacement's
    /// own reports still route. `Speaker` mirrors `speakSequence` / `stop()` / `sequenceUtterance`.
    func testDelayedSpeechReportsNeverReachAReplacement() {
        final class Utterance {}
        struct Speaker {
            var deal = ""
            var generation = 0
            var sequence: SpeechSequenceUnits<Utterance>?
            var events: [String] = []

            mutating func speak(deal: String, generation: Int, units: [Utterance]) {
                stop()
                var state = SpeechSequenceUnits<Utterance>()
                for unit in units { state.append(unit) }
                self.deal = deal
                self.generation = generation
                sequence = state
            }

            mutating func stop() {
                guard sequence != nil else { return }
                sequence = nil
                events.append("cancelled \(deal) \(generation)")
            }

            mutating func deliver(_ report: SpeechUnitReport<Utterance>) {
                guard let state = sequence else { return }
                switch state.route(report) {
                case .started(let index): events.append("started \(index) \(deal) \(generation)")
                case .finished:
                    sequence = nil
                    events.append("finished \(deal) \(generation)")
                case .cancelled:
                    sequence = nil
                    events.append("cancelled \(deal) \(generation)")
                case .ignored: break
                }
            }
        }

        // The child's reveal speaks two units; the first starts. The delegate's later reports wait on the hop.
        var speaker = Speaker()
        weak var oldFirst: Utterance?
        weak var oldLast: Utterance?
        var hop: [SpeechUnitReport<Utterance>] = []
        do {
            let first = Utterance(), last = Utterance()
            oldFirst = first
            oldLast = last
            speaker.speak(deal: "round-A", generation: 3, units: [first, last])
            speaker.deliver(SpeechUnitReport(first, .started))
            hop = [SpeechUnitReport(first, .finished), SpeechUnitReport(last, .started), SpeechUnitReport(last, .finished),
                   SpeechUnitReport(first, .cancelled), SpeechUnitReport(last, .cancelled)]
        }
        expectEqual(speaker.events, ["started 0 round-A 3"])
        // A stop, then a replacement on the 試玩's deal: the old sequence's utterances leave its state, but every waiting
        // report still holds its own, so no replacement utterance can be allocated where one of them is.
        speaker.stop()
        expectTrue(oldFirst != nil && oldLast != nil, "the waiting reports keep the old utterances alive")
        let newFirst = Utterance(), newLast = Utterance()
        for old in [oldFirst, oldLast] {
            for fresh in [newFirst, newLast] {
                expectTrue(old.map { ObjectIdentifier($0) != ObjectIdentifier(fresh) } ?? false, "no reused identity")
            }
        }
        speaker.speak(deal: "playtest-1", generation: 4, units: [newFirst, newLast])
        let before = speaker.events
        for report in hop { speaker.deliver(report) }
        expectEqual(speaker.events, before, "late old didFinish / didStart / didCancel change nothing")
        expectTrue(speaker.sequence != nil, "the replacement keeps speaking")
        hop = []
        expectTrue(oldFirst == nil && oldLast == nil, "released once routed")
        // The replacement's own reports still route: a start lights its item, a finish before the last ends nothing,
        // the last unit's finish ends it.
        speaker.deliver(SpeechUnitReport(newFirst, .started))
        speaker.deliver(SpeechUnitReport(newFirst, .finished))
        expectTrue(speaker.sequence != nil, "a finish before the last unit")
        speaker.deliver(SpeechUnitReport(newLast, .finished))
        expectEqual(Array(speaker.events.dropFirst(before.count)), ["started 0 playtest-1 4", "finished playtest-1 4"])

        // A replay on the same deal (a newer generation): the old generation's late cancel and last finish are ignored;
        // the replay's own cancel still cancels it.
        var replay = Speaker()
        weak var replayed: Utterance?
        var late: [SpeechUnitReport<Utterance>] = []
        do {
            let unit = Utterance()
            replayed = unit
            replay.speak(deal: "round-B", generation: 5, units: [unit])
            late = [SpeechUnitReport(unit, .cancelled), SpeechUnitReport(unit, .finished)]
        }
        let again = Utterance()
        replay.speak(deal: "round-B", generation: 6, units: [again])
        expectTrue(replayed != nil, "still waiting")
        for report in late { replay.deliver(report) }
        expectTrue(replay.sequence != nil, "the newer generation keeps speaking")
        replay.deliver(SpeechUnitReport(again, .cancelled))
        expectEqual(replay.events, ["cancelled round-B 5", "cancelled round-B 6"])
        late = []
        expectNil(replayed)
        print("  pattern sort: speech reports — late reports of a stopped or replaced sequence never reach the replacement; each keeps its utterance alive until routed")
    }

    /// Astra R2: a sequence's deadline stops the speaker's sequence only while it is still the current one for its deal
    /// and generation (`ReadThroughDeadline.stopsSpeech`, what `SystemSpeechPrompt.stopSequence` checks), then ends the
    /// cursor and the reveal — once, and held under parent controls as before. `Speaker` is the one sequence slot.
    func testDeadlineStopsOnlyItsOwnSequence() {
        struct Speaker {
            var deal: String?
            var generation: Int?
            var playing = false

            mutating func start(_ deal: String, _ generation: Int) {
                self.deal = deal
                self.generation = generation
                playing = true
            }

            mutating func stopSequence(deal: String, generation: Int) -> Bool {
                guard ReadThroughDeadline.stopsSpeech(currentDeal: self.deal, currentGeneration: self.generation,
                                                      deal: deal, generation: generation) else { return false }
                self.deal = nil
                self.generation = nil
                playing = false
                return true
            }
        }
        let q = oddQuestion(PatternSortStep(.l1, 0), seed: "deadline")
        let units = OddOneOutCopy.reveal(q)
        expectEqual(ReadThroughTiming.deadline(units), 7.2, accuracy: 1e-9)

        // Overlong clips (longer than the 7.2 s deadline) on the child's reveal: the deadline stops them first, then the
        // light and the reveal end; the stamp comes once.
        var speaker = Speaker()
        var cursor = ReadThroughCursor()
        var reveal = RoundReveal(lane: .child)
        expectTrue(reveal.begin(deal: "A", generation: 1))
        speaker.start("A", 1)
        cursor.start(units: units, deal: "A", generation: 1, engine: .clips)
        expectTrue(cursor.unitStarted(0, deal: "A", generation: 1))
        expectTrue(speaker.stopSequence(deal: "A", generation: 1), "the overlong sequence stops")
        expectFalse(speaker.playing)
        expectTrue(cursor.deadline(deal: "A", generation: 1))
        expectEqual(reveal.deadline(deal: "A", mode: .lock), .stamp("A"))
        expectEqual(reveal.deadline(deal: "A", mode: .lock), .ignored, "once")
        expectFalse(speaker.stopSequence(deal: "A", generation: 1), "a second deadline stops nothing")

        // Stale deadlines: a replay (newer generation) or the other lane's sequence keeps playing.
        var later = Speaker()
        later.start("A", 2)
        expectFalse(later.stopSequence(deal: "A", generation: 1), "an older generation's deadline")
        expectFalse(later.stopSequence(deal: "playtest-1", generation: 2), "another deal's deadline")
        expectTrue(later.playing)
        var idle = Speaker()
        expectFalse(idle.stopSequence(deal: "A", generation: 1), "nothing current")

        // Under parent controls the reveal still holds (no stamp) and stamps once on Return; the 試玩 finishes locally.
        var parent = RoundReveal(lane: .child)
        var parentSpeaker = Speaker()
        expectTrue(parent.begin(deal: "B", generation: 3))
        parentSpeaker.start("B", 3)
        expectTrue(parentSpeaker.stopSequence(deal: "B", generation: 3))
        expectEqual(parent.deadline(deal: "B", mode: .parent), .held)
        expectEqual(parent.returnToChild(openDeal: "B", mode: .lock), .stamp("B"))
        expectEqual(parent.returnToChild(openDeal: "B", mode: .lock), .ignored)
        var playtest = RoundReveal(lane: .playtest)
        var playtestSpeaker = Speaker()
        expectTrue(playtest.begin(deal: "P", generation: 4))
        playtestSpeaker.start("P", 4)
        expectTrue(playtestSpeaker.stopSequence(deal: "P", generation: 4))
        expectEqual(playtest.deadline(deal: "P", mode: .parent), .finishLocally("P"))
        expectEqual(playtest.deadline(deal: "P", mode: .parent), .ignored)
        print("  pattern sort: deadline — stops only its own sequence (deal + generation) before the reveal ends; once; held under parent controls")
    }

    // MARK: T6 ladder

    /// T6: up after 2 first-try rounds, down after a fuel-out or 2 hinted rounds, tier floor and ceiling, 14-day
    /// warm-up, playtest never writes, decode fallback; the read-through rule.
    func testStepLadderAndTheReadThroughRule() {
        let all = Self.methods
        var p = PatternSortProgress()
        let now = Self.day
        func step() -> String { p.liveStep(.oddOneOut, .l2, methods: all)?.code ?? "-" }
        /// A round dealt at the live step and finished under the same settings.
        func play(_ outcome: PatternSortRoundOutcome) {
            p.record(.oddOneOut, p.liveStep(.oddOneOut, .l2, methods: all)!, outcome: outcome, methods: all, now: now)
        }
        expectEqual(step(), "L2.a")
        play(.firstTry)
        expectEqual(step(), "L2.a", "one first-try round is not enough")
        play(.firstTry)
        expectEqual(step(), "L2.b")
        play(.firstTry)
        play(.solved)
        play(.firstTry)
        expectEqual(step(), "L2.b", "a run is in a row")
        play(.firstTry)
        expectEqual(step(), "L2.c")
        play(.firstTry)
        play(.firstTry)
        expectEqual(step(), "L2.c", "never leaves the tier")
        expectEqual(p.liveStep(.oddOneOut, .l3, methods: all)?.code, "L3.a", "other tiers untouched")
        play(.hinted)
        expectEqual(step(), "L2.c")
        play(.hinted)
        expectEqual(step(), "L2.b", "down after 2 hinted")
        play(.fuelOut)
        expectEqual(step(), "L2.a", "down after a fuel-out")
        play(.fuelOut)
        expectEqual(step(), "L2.a", "the floor")
        // Read-through: always at 多啲, never at 少啲; at 標準 until the step's run reaches 2 (only at the top or a sole
        // step).
        var r = PatternSortProgress()
        let a1 = PatternSortStep(.l1, 0), b1 = PatternSortStep(.l1, 1), c1 = PatternSortStep(.l1, 2)
        func playL1(_ outcome: PatternSortRoundOutcome) {
            r.record(.oddOneOut, r.liveStep(.oddOneOut, .l1, methods: all)!, outcome: outcome, methods: all, now: now)
        }
        expectTrue(r.readThrough(.oddOneOut, a1, guidance: .standard))
        expectTrue(r.readThrough(.oddOneOut, a1, guidance: .more))
        expectFalse(r.readThrough(.oddOneOut, a1, guidance: .less))
        for _ in 0..<2 { playL1(.firstTry) }
        expectTrue(r.readThrough(.oddOneOut, b1, guidance: .standard), "moved up: on again")
        for _ in 0..<4 { playL1(.firstTry) }
        expectEqual(r.liveStep(.oddOneOut, .l1, methods: all), c1)
        expectFalse(r.readThrough(.oddOneOut, c1, guidance: .standard), "learned at the top")
        expectTrue(r.readThrough(.oddOneOut, c1, guidance: .more))
        playL1(.solved)
        expectTrue(r.readThrough(.oddOneOut, c1, guidance: .standard), "a round not first-try turns it back on")
        // Astra R1, between rounds: a run belongs to the step that earned it. L1.a learned with only 顏色, then only
        // 形狀: L1.c is new, so 標準 reads it through, and one round there is not two.
        let colourOnly: Set<PatternSortMethod> = [.colour], shapeOnly: Set<PatternSortMethod> = [.shape]
        var s = PatternSortProgress()
        for _ in 0..<2 { s.record(.oddOneOut, a1, outcome: .firstTry, methods: colourOnly, now: now) }
        expectEqual(s.liveStep(.oddOneOut, .l1, methods: colourOnly), a1, "a sole eligible step stays")
        expectFalse(s.readThrough(.oddOneOut, a1, guidance: .standard), "L1.a learned")
        expectEqual(s.liveStep(.oddOneOut, .l1, methods: shapeOnly), c1)
        expectTrue(s.readThrough(.oddOneOut, c1, guidance: .standard), "the colour run never counts at L1.c")
        s.record(.oddOneOut, c1, outcome: .firstTry, methods: shapeOnly, now: now)
        expectTrue(s.readThrough(.oddOneOut, c1, guidance: .standard), "one round at L1.c is not two")
        expectEqual(s.state(.oddOneOut, .l1).step, 0, "the stored step stays until L1.c moves")
        s.record(.oddOneOut, c1, outcome: .firstTry, methods: shapeOnly, now: now)
        expectFalse(s.readThrough(.oddOneOut, c1, guidance: .standard))
        expectEqual(s.state(.oddOneOut, .l1).step, 2)
        // Between rounds with every method: one first try at L1.a, then 顏色 off → L1.b needs two of its own.
        let noColour = all.subtracting([.colour])
        var t = PatternSortProgress()
        t.record(.oddOneOut, a1, outcome: .firstTry, methods: all, now: now)
        expectEqual(t.liveStep(.oddOneOut, .l1, methods: noColour), b1)
        t.record(.oddOneOut, b1, outcome: .firstTry, methods: noColour, now: now)
        expectEqual(t.liveStep(.oddOneOut, .l1, methods: noColour), b1, "the L1.a round never counts at L1.b")
        // Astra R1, during an open deal: one first try at L1.a, another L1.a board dealt with every method, 顏色 off
        // before it is solved. The round counts at its own step under its own settings (as the app records it), so
        // L1.b comes next and is never skipped; with 顏色 back on, L1.a stays learned.
        var u = PatternSortProgress()
        u.record(.oddOneOut, a1, outcome: .firstTry, methods: all, now: now)
        let dealtStep = u.liveStep(.oddOneOut, .l1, methods: all)!
        var open = OddOneOutBoard(question: OddOneOutGenerator.make(seed: "open", step: dealtStep, methods: all),
                                  deal: "open", guidance: .standard, methods: all)
        expectEqual(open.question.step, a1)
        expectEqual(open.tap(open.question.answer, at: 0), .correct)
        u.record(.oddOneOut, open.question.step, outcome: PatternSortFacts.outcome(misses: open.misses, assisted: open.assisted),
                 methods: open.methods, now: now)
        expectEqual(u.liveStep(.oddOneOut, .l1, methods: noColour), b1, "L1.b next, not L1.c")
        expectEqual(u.state(.oddOneOut, .l1).step, 1, "recorded under the dealt settings")
        expectTrue(u.readThrough(.oddOneOut, b1, guidance: .standard))
        expectEqual(u.liveStep(.oddOneOut, .l1, methods: all), b1, "顏色 back on: L1.a stays learned")
        // A step the settings did not make eligible (the 形狀 fallback) only stamps the day.
        var v = PatternSortProgress()
        v.record(.oddOneOut, c1, outcome: .firstTry, methods: colourOnly, now: now)
        expectEqual(v.state(.oddOneOut, .l1), PatternSortTierProgress(lastPlayed: now))
        // Warm-up: after 14 days without the card, one step back, once.
        var w = PatternSortProgress()
        for _ in 0..<2 { w.record(.oddOneOut, a1, outcome: .firstTry, methods: all, now: now) }
        expectFalse(w.warmUp(.oddOneOut, .l1, methods: all, now: now.addingTimeInterval(13 * 86_400)))
        expectTrue(w.warmUp(.oddOneOut, .l1, methods: all, now: now.addingTimeInterval(14 * 86_400)))
        expectEqual(w.liveStep(.oddOneOut, .l1, methods: all)?.code, "L1.a")
        expectFalse(w.warmUp(.oddOneOut, .l1, methods: all, now: now.addingTimeInterval(14 * 86_400 + 60)), "once")
        // The store: round-trip and fail-closed. A playtest never writes (it reads the child's step only).
        let defaults = UserDefaults(suiteName: "VisaGames.patternSortProgress.\(UUID().uuidString)")!
        let store = PatternSortProgressStore(defaults: defaults)
        store.save(p)
        expectEqual(store.load(), p)
        defaults.set(Data("{\"tiers\":7}".utf8), forKey: PatternSortProgressStore.key)
        expectEqual(store.load(), PatternSortProgress())
        var reset = r
        reset.reset([.oddOneOut, .sortGarages])
        expectEqual(reset.liveStep(.oddOneOut, .l1, methods: all)?.code, "L1.a")
        print("  pattern sort: step ladder — up after 2, down after a fuel-out or 2 hinted, floor / ceiling, warm-up once; read-through 多啲 / 標準 / 少啲")
    }

    // MARK: T8 facts

    /// T8: item ids, slots, written chance, tags and the condition fields.
    func testFactsChanceTagsAndConditionFields() {
        let q = oddQuestion(PatternSortStep(.l3, 0), seed: "facts")
        let facts = PatternSortFacts.facts(oddOneOut: q, methods: SortSettings.defaults.methodsCode, voice: true, readThrough: false)
        expectTrue(facts.item.hasPrefix("oddOneOut.L3.a.site+colour."), facts.item)
        expectTrue(facts.item.contains(".vs."))
        expectEqual(facts.slots, ["card-0", "card-1", "card-2", "card-3"])
        expectEqual(facts.correctChoice, "card-\(q.answer)")
        expectEqual(facts.dealtFields["chance"], .double(0.25))
        expectEqual(facts.dealtFields["ladder_step"], .string("L3.a"))
        expectEqual(facts.dealtFields["methods"], .string("colour group kind shape size"))
        expectEqual(facts.dealtFields["voice"], .string("on"))
        expectEqual(facts.dealtFields["read_through"], .string("off"))
        expectEqual(facts.dealtFields["odd_attr"], .string("site"))
        expectEqual(facts.dealtFields["gen"], .string(QuestionGeneration.variants))
        expectEqual(facts.tags(for: facts.correctChoice!), [])
        for card in q.cards.indices where card != q.answer {
            expectTrue(facts.tags(for: "card-\(card)").contains("odd_same_group"))
            expectEqual(facts.tags(for: "card-\(card)").contains("screen_order"), card == 0)
        }
        // Namespaced (astra R1): no 邊個唔同類 tag reuses an approved tag of the older games (`same_shape` reads
        // 同款唔同色); their weekly words wait for P3, so the weekly report names none of them.
        let expectedTags = [(PatternSortStep(.l1, 0), "odd_same_colour"), (PatternSortStep(.l1, 1), "odd_same_size"),
                            (PatternSortStep(.l1, 2), "odd_same_shape"), (PatternSortStep(.l2, 0), "odd_same_kind"),
                            (PatternSortStep(.l2, 1), "odd_same_group"), (PatternSortStep(.l3, 2), "odd_same_facing")]
        for (step, tag) in expectedTags {
            let round = oddQuestion(step, seed: "tags")
            for card in round.cards.indices where card != round.answer {
                expectEqual(PatternSortFacts.oddOneOutTags(round, card: card).first, tag, step.code)
            }
            expectTrue(WeeklyTextCatalog.tagName(tag) == nil, tag)
        }
        let star = oddQuestion(PatternSortStep(.l1, 1), seed: "facts")
        expectEqual(PatternSortFacts.facts(oddOneOut: star, methods: "size", voice: false, readThrough: true)
            .dealtFields["chance"], .double(1.0 / 3))
        // 接落去: 1/2 at ★ 1a, 1/3, 1/9 for add 2; repeat_last, wrong_phase, not_in_pattern.
        let a1 = PatternGenerator.make(seed: "f", step: PatternSortStep(.l1, 0), materials: .vehicles)
        expectEqual(PatternSortFacts.facts(pattern: a1, materials: .vehicles, voice: true, readThrough: true).dealtFields["chance"], .double(0.5))
        let add2 = PatternGenerator.make(seed: "f", step: PatternSortStep(.l2, 2), materials: .vehicles)
        let add2Facts = PatternSortFacts.facts(pattern: add2, materials: .both, voice: true, readThrough: true)
        expectEqual(add2Facts.dealtFields["chance"], .double(1.0 / 9))
        expectEqual(add2Facts.dealtFields["materials"], .string("both"))
        expectEqual(add2Facts.dealtFields["pattern_task"], .string("add2"))
        expectTrue(add2.itemID.hasPrefix("patternNext.L2.c.AB.add2.vehicles."))
        let row = PatternRow(unit: .ab, n: 6, phase: 0, task: .add1)
        let a = PatternSortLook(.vehicle(.bus), .blue), b = PatternSortLook(.vehicle(.digger), .blue)
        let c = PatternSortLook(.vehicle(.mixer), .blue)
        let fixed = PatternQuestion(step: PatternSortStep(.l1, 1), row: row, material: .vehicles, attribute: .kind,
                                    units: [a, b], outside: c, choices: [a, b, c])
        expectEqual(PatternSortFacts.patternTags(fixed, blank: 0, choice: 0), ["repeat_last", "wrong_phase", "screen_order"])
        expectEqual(PatternSortFacts.patternTags(fixed, blank: 0, choice: 2), ["not_in_pattern"])
        expectEqual(PatternSortFacts.patternTags(fixed, blank: 0, choice: 1), [])
        // 分車房: 1/2ⁿ and repeat_last_garage.
        let sort = SortGaragesGenerator.make(seed: "f", step: PatternSortStep(.l2, 0), methods: SortSettings.defaultMethods)
        let sortFacts = PatternSortFacts.facts(sort: sort, methods: "kind", voice: true, readThrough: true)
        expectEqual(sortFacts.dealtFields["chance"], .double(1.0 / 64))
        expectEqual(sortFacts.slots, ["garage-0", "garage-1"])
        let second = sort.garages[1]
        expectEqual(PatternSortFacts.sortTags(sort, item: 1, garage: sort.garages[0]),
                    second == sort.garages[0] ? [] : ["repeat_last_garage"])
        // 自己排: practice, chance 1, `n_slots` 8; result fields.
        let palette = PatternMakeGenerator.palette(seed: "f", materials: .shapes)
        let makeFacts = PatternSortFacts.facts(make: palette, materials: .shapes, voice: false)
        expectEqual(makeFacts.chance, 1)
        expectEqual(makeFacts.dealtFields["n_slots"], .int(8))
        expectEqual(PatternSortFacts.outcome(misses: 0, assisted: false), .firstTry)
        expectEqual(PatternSortFacts.outcome(misses: 1, assisted: false), .solved)
        expectEqual(PatternSortFacts.outcome(misses: 2, assisted: true), .hinted)
        var board = OddOneOutBoard(question: q, deal: "d", guidance: .more, methods: Self.methods)
        _ = board.tap(q.answer, at: 0)
        expectEqual(PatternSortFacts.resultFields(oddOneOut: board, guidance: .more)["guide_level"], .string("more"))
        // A written chance wins over the catalogue value in the weekly model.
        let dealt = PatternSortCoreTests.dealt(.oddOneOut, ["chance": .double(1.0 / 3)])
        expectEqual(WeeklyChance.chance(dealt: dealt), 1.0 / 3)
        print("  pattern sort: facts — item ids, slots, written chance 1/2 · 1/3 · 1/4 · 1/9 · 1/2ⁿ, 5 tags, ladder_step / methods / materials / voice / read_through")
    }

    // MARK: T10 copy

    /// Every child display string with its longest values, and every spoken unit, for the copy audits.
    static func allChildLines() -> [PatternSortLine] {
        var lines: [PatternSortLine] = [OddOneOutCopy.intro, OddOneOutCopy.generic, OddOneOutCopy.done, OddOneOutCopy.idle]
        for level in ActivityLevel.allCases {
            for step in PatternSortLadder.steps(.oddOneOut, level) {
                for target in OddOneOutGenerator.targets(step) {
                    lines += [OddOneOutCopy.named(target), OddOneOutCopy.hint(target)]
                    for item in OddOneOutGenerator.items(step, target) {
                        let q = OddOneOutQuestion(item: item, cards: item.group + [item.odd], answer: item.group.count)
                        lines.append(OddOneOutCopy.correct(q))
                        lines.append(OddOneOutCopy.wrong(q, card: 0))
                    }
                }
            }
            for step in PatternSortLadder.steps(.patternNext, level) {
                for index in 0..<20 {
                    let q = PatternGenerator.make(seed: "copy\(index)", step: step, materials: .both)
                    lines.append(PatternCopy.prompt(q))
                    for look in q.choices { lines.append(PatternCopy.wrong(look, attribute: q.attribute)) }
                }
            }
            for step in PatternSortLadder.steps(.sortGarages, level) {
                for index in 0..<20 {
                    let q = SortGaragesGenerator.make(seed: "copy\(index)", step: step, methods: SortSettings.defaultMethods)
                    lines += [SortCopy.rule(q), SortCopy.wrong(q, garage: 0), SortCopy.wrong(q, garage: 1)]
                }
            }
        }
        lines += [PatternCopy.intro, PatternCopy.nextVehicle, PatternCopy.nextShape, PatternCopy.nextSize, PatternCopy.addTwo,
                  PatternCopy.oneMore, PatternCopy.gap, PatternCopy.correct, PatternCopy.hint, PatternCopy.done,
                  PatternMakeCopy.intro, PatternMakeCopy.prompt, PatternMakeCopy.undo, PatternMakeCopy.pattern,
                  PatternMakeCopy.free, SortCopy.intro, SortCopy.prompt, SortCopy.correct, SortCopy.hint, SortCopy.done]
        return lines
    }

    /// T10: every new string HK Traditional (the repo's Simplified-only list), no empty line, no 喎 in anything
    /// spoken, every display string with its longest value inside the bubble budget.
    func testCopyIsTraditionalSpokenWithoutWoAndInsideTheBubble() throws {
        let list = try String(contentsOf: URL(fileURLWithPath: "Tests/VisaCoreTests/Fixtures/traditional-check/simplified-only.txt"),
                              encoding: .utf8)
        let simplified = Set(list.split(separator: "\n").filter { !$0.hasPrefix("#") }.joined().filter { !$0.isWhitespace })
        expectTrue(simplified.count > 2_000)
        let lines = Self.allChildLines()
        var keys: [String: String] = [:]
        for line in lines {
            expectFalse(line.zh.isEmpty || line.key.isEmpty, line.key)
            expectTrue(PatternSortLayout.fitsBubble(zh: line.zh, en: line.en), "\(line.key): \(line.zh) / \(line.en)")
            expectFalse(line.zh.contains("喎"), line.key)
            expectTrue(line.zh.allSatisfy { !simplified.contains($0) }, line.zh)
            if let earlier = keys[line.key] { expectEqual(earlier, line.zh, "one key, one line: \(line.key)") }
            keys[line.key] = line.zh
        }
        var spoken: [ReadThroughUnit] = []
        for index in 0..<30 {
            let q = OddOneOutGenerator.make(seed: "spoken\(index)", step: PatternSortStep(.l3, 0), methods: SortSettings.defaultMethods)
            spoken += OddOneOutCopy.readThrough(q, guidance: .more) + OddOneOutCopy.reveal(q)
            let p = PatternGenerator.make(seed: "spoken\(index)", step: PatternSortStep(.l2, 1), materials: .both)
            spoken += PatternCopy.readThrough(p) + PatternCopy.reveal(p)
        }
        var make = PatternMakeBoard(palette: PatternMakeGenerator.palette(seed: "s", materials: .both), deal: "s")
        for index in 0..<8 { _ = make.place(index % 2) }
        spoken += PatternMakeCopy.reveal(make)
        for unit in spoken {
            expectFalse(unit.text.isEmpty || unit.text.contains("喎"), unit.key)
            expectTrue(unit.text.allSatisfy { !simplified.contains($0) }, unit.text)
        }
        let parent = PatternSortParentCopy.allLines
        for line in parent {
            expectFalse(line.isEmpty)
            expectTrue(line.allSatisfy { !simplified.contains($0) }, line)
        }
        expectEqual(PatternSortParentCopy.helpDetail(.standard).zh, "標準（預設）：未識之前每局先讀一次；錯兩次先顯示提示。")
        expectEqual(OddOneOutCopy.named(.category(.site)).zh, "邊架唔係地盤車呀？")
        print("  pattern sort: copy — \(lines.count) display lines in the bubble budget, \(spoken.count) spoken units, \(parent.count) parent lines; Traditional only, no 喎")
    }
}
