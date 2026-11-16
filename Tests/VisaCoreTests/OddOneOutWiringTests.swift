import Foundation
import VisaCore

/// patterns-sorting P1 (0.41.0 / 91): 分類 · 邊個唔同類 in the app and the weekly report (design §5.7, §6.3 item 7, §7, §9
/// P1; §10.1 T9a, T17). The weekly ⚙ runs on real weekly analysis; the app wiring is pinned by source guards (SwiftUI /
/// AppKit are not built on this box), the 中文字 precedent (`HanziFindTests`).
final class OddOneOutWiringTests {
    private var seq = 0

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    /// `name`'s declaration in `text`, up to the next member declaration at the same indent (or the end of the type).
    private func body(of name: String, in text: String) -> String {
        guard let start = text.range(of: name) else { return "" }
        let after = text[start.upperBound...]
        let ends = ["\n    func ", "\n    private func ", "\n    var ", "\n    private var ", "\n    @discardableResult",
                    "\n}\n"]
            .compactMap { after.range(of: $0)?.lowerBound }
        return String(text[start.lowerBound..<(ends.min() ?? text.endIndex)])
    }

    private func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }

    /// `first` comes before `second` in `text` (both present).
    private func ordered(_ first: String, _ second: String, in text: String) -> Bool {
        guard let a = text.range(of: first), let b = text.range(of: second) else { return false }
        return a.lowerBound < b.lowerBound
    }

    // MARK: T9a weekly ⚙

    /// Six 邊個唔同類 rounds in one week (the Hanzi weekly fixture's shape).
    private func oddWeek(_ start: Date, firstTry: Int, step: String, readThrough: [Bool],
                         methods: String = "colour group kind shape size") -> [PerfEvent] {
        var events: [PerfEvent] = []
        for index in 0..<6 {
            seq += 1
            let id = "odd\(seq)"
            let at = start.addingTimeInterval(Double(index) * 600)
            events.append(PerfEvent(type: .gameDealt, timestamp: at, tz: "+08:00", mono: Double(seq), launch: "L1", seq: seq,
                                    app: "0.41.0", actor: .child, mode: "lock", session: "s1",
                                    fields: ["round": .string(id), "kind": .string(ActivityKind.oddOneOut.rawValue),
                                             "stars": .int(1), "gen": .string(QuestionGeneration.variants), "level": .int(1),
                                             "slots": .strings(["card-0", "card-1", "card-2"]), "chance": .double(1.0 / 3),
                                             "ladder_step": .string(step), "methods": .string(methods),
                                             "voice": .string("on"),
                                             "read_through": .string(readThrough[index % readThrough.count] ? "on" : "off")]))
            seq += 1
            let first = index < firstTry
            events.append(PerfEvent(type: .roundResult, timestamp: at.addingTimeInterval(40), tz: "+08:00",
                                    mono: Double(seq), launch: "L1", seq: seq, app: "0.41.0", actor: .child, mode: "lock",
                                    session: "s1",
                                    fields: ["round": .string(id), "kind": .string(ActivityKind.oddOneOut.rawValue),
                                             "outcome": .string("solved"), "answers": .int(first ? 1 : 2),
                                             "first_try": .bool(first), "misses": .int(first ? 0 : 1),
                                             "total_ms": .int(40_000), "active_ms": .int(9_000), "earned_min": .int(5),
                                             "guide_level": .string("standard")]))
        }
        return events
    }

    /// T9a: each `sort_*` change marks 邊個唔同類 and no other kind (分車房 is not playable yet); a same-star `ladder_step`
    /// change and a mostly-on → mostly-off `read_through` each mark the row and block its clear change; unchanged
    /// conditions still allow a clear change; `guide_level` is named 分類提示.
    func testSortSettingsAndConditionsMarkTheRowWeekly() {
        let odd = ActivityKind.oddOneOut.rawValue
        for what in ["sort_methods", "sort_guidance", "sort_audio", "sort_progress"] {
            expectEqual(WeeklyComparison.kinds(forConfig: what, kind: odd), [odd], what)
            expectFalse(WeeklyTextCatalog.configName(what) == nil, what)
        }
        expectFalse(ActivityCatalog.playableKinds.contains(.sortGarages), "分車房 joins the ⚙ rows in P4")
        expectEqual(WeeklyComparison.kinds(forConfig: "pattern_materials", kind: nil), [], "跟住排 lands in P2")
        func named(_ what: String) -> [String] {
            guard let name = WeeklyTextCatalog.configName(what) else { return [] }
            return [name.name.zh, name.name.en, name.labels]
        }
        expectEqual(named("sort_methods"), ["分類方法", "Ways to sort", "sort_methods"])
        expectEqual(named("sort_guidance"), ["分類提示", "Sorting help", "guidance"])
        expectEqual(named("sort_audio"), ["分類語音", "Sorting voice", "letter_guard"])
        expectEqual(named("sort_progress"), ["分類進度", "Sorting progress", "sort_progress"])
        expectEqual(WeeklyTextCatalog.fieldName("guide_level", kind: odd)?.name, WeeklyWords("分類提示", "Sorting help"))
        expectEqual(WeeklyTextCatalog.fieldName("methods", kind: odd)?.name, WeeklyWords("分類方法", "Ways to sort"))
        expectEqual(WeeklyTextCatalog.fieldName("voice", kind: odd)?.name, WeeklyWords("分類語音", "Sorting voice"))
        expectEqual(WeeklyTextCatalog.fieldName("ladder_step", kind: odd)?.name, WeeklyWords("題目級數（自動）", "Step (automatic)"))
        expectEqual(WeeklyTextCatalog.fieldName("read_through", kind: odd)?.name, WeeklyWords("自動讀一次", "Read-through (automatic)"))
        expectEqual(WeeklyTextCatalog.fieldName("guide_level", kind: ActivityKind.tapCountTrace.rawValue)?.name,
                    WeeklyWords("描數字提示", "Tracing help"), "numbers keep theirs")
        for field in ["ladder_step", "methods", "voice", "read_through"] {
            expectTrue(WeeklySignature.dealFields.contains(field), field)
        }

        let lastMonday = PerfCodec.parseTimestamp("2026-11-02T04:00:00.000Z")!  // 12:00 HKT
        let monday = PerfCodec.parseTimestamp("2026-11-09T04:00:00.000Z")!
        let window = WeeklyWindow(containing: monday)
        func settings(_ events: [PerfEvent]) -> (change: WeeklyChange?, marks: [WeeklySettingChange], clear: [String]) {
            let analysis = WeeklyAnalysisBuilder.build(events: events, rollup: PerfRollup(), window: window)
            let game = analysis.games.first { $0.kind == odd }
            return (game?.wow.change, game?.settings ?? [], analysis.comparison.clearChanges.map(\.kind))
        }
        // Control: the same step, settings, help and read-through both weeks → a clear ↑.
        let before = oddWeek(lastMonday, firstTry: 1, step: "L1.a", readThrough: [true])
        let control = settings(before + oddWeek(monday, firstTry: 6, step: "L1.a", readThrough: [true]))
        expectEqual(control.change, .up)
        expectEqual(control.marks, [])
        expectEqual(control.clear, [odd])
        // Same star, another step: ⚙ 「題目級數（自動）：L1.a → L1.b」, no clear change.
        let step = settings(before + oddWeek(monday, firstTry: 6, step: "L1.b", readThrough: [true]))
        expectEqual(step.marks, [.signature(field: "ladder_step", old: "L1.a", new: "L1.b")])
        expectEqual(step.clear, [])
        // Same star, step, settings and help; the read-through mostly on last week, mostly off this week (learned).
        let learned = settings(oddWeek(lastMonday, firstTry: 1, step: "L1.c", readThrough: [true, true, false])
                                + oddWeek(monday, firstTry: 6, step: "L1.c", readThrough: [false, false, true]))
        expectEqual(learned.marks, [.signature(field: "read_through", old: "on", new: "off")])
        expectEqual(learned.clear, [])
        // A 分類設定 save between the weeks marks the row too.
        seq += 1
        let save = PerfEvent(type: .configChange, timestamp: monday.addingTimeInterval(-3600), tz: "+08:00",
                             mono: Double(seq), launch: "L1", seq: seq, app: "0.41.0", actor: .parent, mode: "parent",
                             session: "p", fields: ["what": .string("sort_guidance"), "kind": .string(odd),
                                                    "value": .string("more")])
        let saved = settings(before + [save] + oddWeek(monday, firstTry: 6, step: "L1.a", readThrough: [true]))
        expectEqual(saved.marks, [.config(what: "sort_guidance", value: "more", star: nil, date: "2026-11-09")])
        expectEqual(saved.clear, [])
        print("  odd one out: weekly ⚙ — sort_* marks 邊個唔同類 only; ladder_step and read_through changes block a clear change; 分類提示")
    }

    /// Six 邊個唔同類 ★ c (形狀) rounds over two days, each with one new wrong card tagged as the app tags it (`retag`
    /// rewrites the tags: the control replays the old `same_shape`), beside six first-try 影子配對 rounds so that the
    /// week ranks (≥ 2 qualified games) and 邊個唔同類 is still learning (WeeklyTextTests' order week, in miniature).
    private func shapeWeek(_ start: Date, retag: (String) -> String) -> [PerfEvent] {
        var events: [PerfEvent] = []
        func event(_ type: PerfEventType, _ at: Date, _ fields: [String: PerfValue]) -> PerfEvent {
            seq += 1
            return PerfEvent(type: type, timestamp: at, tz: "+08:00", mono: Double(seq), launch: "L1", seq: seq, app: "0.41.0",
                             actor: .child, mode: "lock", session: "s1", fields: fields)
        }
        let odd = ActivityKind.oddOneOut.rawValue
        for index in 0..<6 {
            let q = OddOneOutGenerator.make(seed: "shape-week-\(index)", step: PatternSortStep(.l1, 2), methods: [.shape])
            let wrong = q.cards.indices.first { $0 != q.answer && $0 != 0 } ?? 0
            let id = "shape\(seq)", other = "shadow\(seq)"
            let at = start.addingTimeInterval(Double(index % 2) * 86_400 + Double(index) * 600)
            events.append(event(.gameDealt, at.addingTimeInterval(-300),
                                ["round": .string(other), "kind": .string("shadowMatch"), "stars": .int(1)]))
            events.append(event(.answerAttempt, at.addingTimeInterval(-290), ["round": .string(other), "correct": .bool(true)]))
            events.append(event(.roundResult, at.addingTimeInterval(-270),
                                ["round": .string(other), "kind": .string("shadowMatch"), "outcome": .string("solved"),
                                 "answers": .int(1), "first_try": .bool(true), "misses": .int(0), "hint_used": .bool(false),
                                 "assisted": .bool(false), "total_ms": .int(30_000), "active_ms": .int(4_000),
                                 "earned_min": .int(5)]))
            events.append(event(.gameDealt, at, ["round": .string(id), "kind": .string(odd), "stars": .int(1),
                                                 "gen": .string(QuestionGeneration.variants), "level": .int(1),
                                                 "slots": .strings(q.slots), "chance": .double(q.chance),
                                                 "ladder_step": .string("L1.c"), "methods": .string("shape"),
                                                 "voice": .string("on"), "read_through": .string("on")]))
            events.append(event(.answerAttempt, at.addingTimeInterval(10),
                                ["round": .string(id), "kind": .string(odd), "choice": .string("card-\(wrong)"),
                                 "correct": .bool(false),
                                 "tags": .strings(PatternSortFacts.oddOneOutTags(q, card: wrong).map(retag))]))
            events.append(event(.answerAttempt, at.addingTimeInterval(30),
                                ["round": .string(id), "kind": .string(odd), "choice": .string(q.correctChoice),
                                 "correct": .bool(true)]))
            events.append(event(.roundResult, at.addingTimeInterval(40),
                                ["round": .string(id), "kind": .string(odd), "outcome": .string("solved"), "answers": .int(2),
                                 "first_try": .bool(false), "misses": .int(1), "hint_used": .bool(false),
                                 "assisted": .bool(false), "total_ms": .int(40_000), "active_ms": .int(9_000),
                                 "earned_min": .int(5), "guide_level": .string("standard")]))
        }
        return events
    }

    /// Astra R1: a 邊個唔同類 形狀 week never reads as 「同款唔同色」 (the older games' `same_shape`). Its namespaced tag
    /// has no weekly words yet (P3), so no tag line is written; the control shows the old tag would have printed it.
    func testShapeWeekNeverReadsAsColour() {
        let odd = ActivityKind.oddOneOut.rawValue
        let monday = PerfCodec.parseTimestamp("2026-11-09T04:00:00.000Z")!
        func game(_ retag: @escaping (String) -> String) -> WeeklyGameText? {
            WeeklyReportTextBuilder.build(events: self.shapeWeek(monday, retag: retag), rollup: PerfRollup(),
                                          window: WeeklyWindow(containing: monday)).games.first { $0.kind == odd }
        }
        let fixed = game { $0 }
        expectTrue(fixed != nil, "the week has its 邊個唔同類 row")
        let lines = (fixed?.comment ?? []) + (fixed?.short ?? [])
        expectFalse(lines.contains { $0.zh.contains("同款唔同色") || $0.en.contains("same shape, different colour") })
        expectFalse(lines.contains { $0.id == "bot.tag" }, "no words for odd_same_shape until P3")
        let old = game { $0 == "odd_same_shape" ? "same_shape" : $0 }
        expectTrue((old?.comment ?? []).contains { $0.id == "bot.tag" && $0.zh.contains("同款唔同色") }, "control: the old tag")
        print("  odd one out: a 形狀 week never reads as 同款唔同色 (namespaced tags; the old same_shape would)")
    }

    // MARK: T17 reveal wiring

    /// T17: parent entry holds the reveal first and keeps the deal seeds; Return releases it last, once, for the open
    /// deal; a reset drops it; the playtest touches only its own reveal; every engine's events carry the deal (and the
    /// generation), a cancel reaches no end, and the end handlers read their own lane.
    func testRevealWiringOrderAndLanes() throws {
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let speech = try source("Sources/VisaGames/SystemSpeechPrompt.swift")
        let enter = body(of: "private func enterParentAfterAuthentication()", in: model)
        expectTrue(ordered("childReveal.enterParent()", "guideVoice.stop()", in: enter), "the hold before speech stops")
        expectTrue(ordered("childReveal.enterParent()", "patternSortSpeechGeneration += 1", in: enter))
        expectTrue(ordered("guideVoice.stop()", "patternSortSpeechGeneration += 1", in: enter))
        expectTrue(ordered("childReveal.enterParent()", "update { $0.enterParent(", in: enter), "before the mode change")
        expectTrue(enter.hasPrefix("private func enterParentAfterAuthentication() {\n        // patterns-sorting"),
                   "the first new step")
        expectFalse(enter.contains("choiceDealSeed ="), "parent entry never changes the deal seed")
        expectFalse(enter.contains("playtestChoiceDealSeed ="))
        expectEqual(count("childReveal.enterParent()", in: model), 1)
        // Return: last, after the playtest is dropped and parent is left; declared once, called once.
        let back = body(of: "func returnToChild(", in: model)
        expectTrue(ordered("discardPlaytestCover(reason: \"leaveParent\")", "update { $0.leaveParent(now: Date()) }", in: back))
        expectTrue(ordered("update { $0.leaveParent(now: Date()) }", "finishHeldOddOneOutReveal()", in: back))
        expectTrue(ordered("finishHeldTapHanziFind()", "finishHeldOddOneOutReveal()", in: back))
        expectTrue(back.hasSuffix("finishHeldOddOneOutReveal()\n    }\n") || back.hasSuffix("finishHeldOddOneOutReveal()\n    }"),
                   "released last")
        expectEqual(count("finishHeldOddOneOutReveal()", in: model), 2, "declared once, called once")
        let held = body(of: "private func finishHeldOddOneOutReveal()", in: model)
        expectTrue(held.contains("childReveal.returnToChild(openDeal: taskRoundOpen ? choiceDealSeed : nil, mode: session.mode)"))
        expectTrue(held.contains("finishOddOneOutRound(token: deal, playtest: false)"))
        // A reset drops the child's reveal; the playtest deal and its discard touch only the playtest's.
        expectTrue(body(of: "private func resetTaskRound()", in: model).contains("childReveal.reset()"))
        let playtestDeal = body(of: "func startPlaytest(kind: ActivityKind)", in: model)
        let discard = body(of: "private func discardPlaytestCover(reason: String)", in: model)
        for text in [playtestDeal, discard] {
            expectTrue(text.contains("playtestReveal.reset()"))
            expectFalse(text.contains("childReveal"), "never the child's reveal")
        }
        expectEqual(count("childReveal.reset()", in: model), 1, "only resetTaskRound resets the child's reveal")
        // Each engine adapter passes the deal (and for speech the generation); a cancel is never an end.
        expectTrue(speech.contains("state.onEvent(.finished(deal: state.deal, generation: state.generation))"), "didFinish")
        expectTrue(speech.contains("sequenceTimer(after: end, .finished(deal: deal, generation: generation))"), "the last clip's end")
        // Clips, all or nothing (astra R1): planned before any plays (`ReadThroughClipPlan`); a clip that does not load
        // or start sends the whole sequence to another engine: no skipped unit, no shifted index, no early end.
        expectTrue(speech.contains("if engine == .clips, let fallback = playClipSequence(units, deal: deal, generation: generation) {"))
        let clips = body(of: "private func playClipSequence(", in: speech)
        expectTrue(clips.contains("switch ReadThroughClipPlan.plan(durations: players.map { $0?.duration }, units: units, cantoneseVoice: voice != nil) {"))
        expectTrue(ordered("case .fallback(let engine):\n            return engine\n", "case .clips(let starts, let end):", in: clips))
        expectTrue(ordered("loaded.forEach { $0.stop() }", "clipPlayers = loaded", in: clips), "a failed start stops every clip")
        expectTrue(clips.contains("for (index, offset) in starts.enumerated() {"))
        expectFalse(clips.contains("continue"), "no unit is skipped")
        expectEqual(count(".finished(deal:", in: clips), 1)
        expectFalse(speech.contains("clipQueueEndsAt - now"), "the old skipping queue is gone")
        expectTrue(speech.contains("sequenceTimer(after: ReadThroughTiming.silentLength(units), .finished(deal: deal, generation: generation))"),
                   "the last beat")
        expectTrue(speech.contains("synthesizer.delegate = sequenceDelegate"))
        let events = body(of: "private func oddOneOutSpeechEvent(", in: model)
        let cancelled = events.components(separatedBy: "case .cancelled").last ?? ""
        expectTrue(cancelled.contains("oddOneOutCursor.cancelled(deal: deal, generation: generation)"))
        for end in ["oddOneOutRevealEnded", "oddOneOutRevealDeadline", "finishOddOneOutRound", "applyEntrySuccess"] {
            expectFalse(cancelled.contains(end), "a cancel reaches no end: \(end)")
        }
        let sequence = body(of: "private func startOddOneOutSequence(", in: model)
        expectTrue(sequence.contains("if reveal { self.oddOneOutRevealDeadline(deal: deal, playtest: playtest) }"),
                   "the reveal's deadline, keyed by its deal")
        expectTrue(sequence.contains("ReadThroughTiming.deadline(units)"))
        expectTrue(body(of: "private func oddOneOutRevealEnded(", in: model)
            .contains("currentGeneration: patternSortSpeechGeneration"))
        // The end handlers read their own lane's board and deal seed, and stamp only through `applyEntrySuccess`.
        let finish = body(of: "private func finishOddOneOutRound(", in: model)
        expectTrue(finish.contains("let board = playtest ? playtestOddOneOutBoard : oddOneOutBoard"))
        expectTrue(finish.contains("(playtest ? playtestChoiceDealSeed : choiceDealSeed) == token"))
        expectFalse(finish.contains("currentOddOneOutBoard"))
        expectTrue(finish.contains("guard taskRoundOpen, !activityJustCompleted, session.mode == .lock else { return }"))
        expectEqual(count("applyEntrySuccess(assisted: board.assisted)", in: finish), 1)
        expectFalse(body(of: "func oddOneOutTap(card: Int)", in: model).contains("applyEntrySuccess"), "never at the tap")
        print("  odd one out: reveal wiring — hold first at parent entry, deal seeds kept, release last on Return, lanes apart, cancel ≠ end")
    }

    // MARK: Astra R2 wiring

    /// Astra R2 source guards (the app is not built on this box; the state machines run in PatternSortRoundTests and
    /// PatternSortCoreTests): the miss wait per lane and deal through `BoardPendingMiss`, the stamp's voice inside
    /// `guideSpeakStamped()` (appearance and replay), the 邊個唔同類 row's canvas gap, the deadline stopping its own
    /// sequence first.
    func testLaneWaitStampVoiceRowGapAndDeadlineWiring() throws {
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let speech = try source("Sources/VisaGames/SystemSpeechPrompt.swift")
        let host = try source("Sources/VisaGames/CanvasActivityHost.swift")
        let views = try source("Sources/VisaGames/StampWatchTimesUpViews.swift")

        // Major: one lane + deal gate, no shared flag; a miss begins its lane's ticket; the callback settles it against
        // the lane's open deal before anything is applied; deals, resets and the discard drop only their own lane.
        expectFalse(model.contains("oddOneOutPenaltyPending"), "no shared flag")
        expectEqual(count("private var oddOneOutPendingMiss = BoardPendingMiss()", in: model), 1)
        let tap = body(of: "func oddOneOutTap(card: Int)", in: model)
        let missCase = tap.components(separatedBy: "case .miss:").dropFirst().first?.components(separatedBy: "case .knownWrongRetap:").first ?? ""
        expectTrue(missCase.contains("let ticket = oddOneOutPendingMiss.begin(lane: playtest ? .playtest : .child, deal: board.deal)"))
        expectTrue(ordered("self.oddOneOutPendingMiss.settle(ticket, openDeal: playtest ? self.playtestChoiceDealSeed : self.choiceDealSeed)",
                           "self.pendingAnswerRecord = record", in: missCase), "settled before the miss is applied")
        expectTrue(ordered("guard let self,", "self.oddOneOutPendingMiss.settle(", in: missCase))
        expectFalse(missCase.contains("== token") || missCase.contains("== ticket.deal"), "no deal check that returns before the settle")
        expectEqual(count("!oddOneOutMissPending", in: model), 3, "tap, replay and idle wait for their own lane only")
        expectTrue(body(of: "private var oddOneOutMissPending: Bool", in: model)
            .contains("oddOneOutPendingMiss.isPending(lane: oddOneOutLane, deal: board.deal)"))
        expectTrue(body(of: "private var oddOneOutLane: RoundRevealLane", in: model).contains("oddOneOutUsesPlaytest ? .playtest : .child"))
        expectTrue(ordered("oddOneOutPendingMiss.drop(lane: lane)", "clearOddOneOutDisplay()",
                           in: body(of: "private func resetOddOneOutTransient(lane: RoundRevealLane)", in: model)))
        expectEqual(count("resetOddOneOutTransient(lane: .child)", in: model), 1, "the child's deal")
        expectTrue(body(of: "func startPlaytest(kind: ActivityKind)", in: model).contains("resetOddOneOutTransient(lane: .playtest)"))
        let discard = body(of: "private func discardPlaytestCover(reason: String)", in: model)
        expectTrue(discard.contains("oddOneOutPendingMiss.drop(lane: .playtest)") && discard.contains("clearOddOneOutDisplay()"))
        expectFalse(discard.contains("drop(lane: .child)"), "the discard keeps the child's wait")
        expectTrue(body(of: "private func resetTaskRound()", in: model).contains("oddOneOutPendingMiss.drop(lane: .child)"))
        expectEqual(count("oddOneOutPendingMiss.drop(lane: .child)", in: model), 1)
        expectEqual(count("oddOneOutPendingMiss.drop(lane: .playtest)", in: model), 1)
        for text in [body(of: "private func enterParentAfterAuthentication()", in: model), body(of: "func returnToChild(", in: model)] {
            expectFalse(text.contains("oddOneOutPendingMiss"), "parent entry and Return keep a child's wait")
        }

        // Minor 1: the stamp's voice rule inside the helper that both the stamp view's appearance and its replay call.
        let stamped = body(of: "    func guideSpeakStamped() {", in: model)
        expectTrue(stamped.contains("guard PatternSortHelp.speaksStamp(activeActivityKind, sortAudio: sortSettings.audioEnabled) else { return }"))
        expectTrue(ordered("guard PatternSortHelp.speaksStamp(", "tapLetterSpeak(", in: stamped))
        expectTrue(ordered("guard PatternSortHelp.speaksStamp(", "guideVoice.speak(.stamped)", in: stamped))
        expectTrue(model.contains("if activeActivityKind?.isTapLetterFamily != true { guideSpeakStamped() }"), "the success call as before P1")
        expectTrue(model.contains("onSpeak: { model.guideSpeakStamped() },"))
        let stampView = views.components(separatedBy: "struct StampSuccessView: View {").dropFirst().first?
            .components(separatedBy: "\nstruct ").first ?? ""
        expectTrue(stampView.contains(".onAppear {\n            onSpeak()"), "its appearance")
        expectTrue(stampView.contains(".stamped, action: onSpeak)"), "its replay")
        for kind in ActivityKind.allCases {
            expectTrue(PatternSortHelp.speaksStamp(kind, sortAudio: true), kind.rawValue)
            expectEqual(PatternSortHelp.speaksStamp(kind, sortAudio: false), !kind.isSortFamily, kind.rawValue)
        }
        expectTrue(PatternSortHelp.speaksStamp(nil, sortAudio: false))

        // Minor 2: only the 邊個唔同類 row takes the canvas gap; it is read inside the stage; older rows keep 24 points.
        expectTrue(host.contains("lockedOverride: choicesAreLocked || model.oddOneOutRevealing, canvasGap: true) { id in"))
        expectEqual(count("canvasGap: true", in: host), 1)
        expectTrue(host.contains("if canvasGap {\n            CanvasGapRow { cards }\n        } else {\n            HStack(spacing: 24) { cards }\n        }"))
        let gapRow = host.components(separatedBy: "private struct CanvasGapRow<Content: View>: View {").dropFirst().first ?? ""
        expectTrue(gapRow.contains("@Environment(\\.canvasMetrics) private var metrics"))
        expectTrue(gapRow.contains("HStack(spacing: CGFloat(PatternSortLayout.rowGapPoints(scale: Double(metrics.scale)))) { content() }"))

        // Minor 3: the deadline stops its own sequence (deal + generation) before the light and the reveal end.
        let sequence = body(of: "private func startOddOneOutSequence(", in: model)
        expectTrue(ordered("self.guideVoice.stopSequence(deal: deal, generation: generation)",
                           "self.oddOneOutCursor.deadline(deal: deal, generation: generation)", in: sequence))
        expectTrue(ordered("self.guideVoice.stopSequence(deal: deal, generation: generation)",
                           "if reveal { self.oddOneOutRevealDeadline(deal: deal, playtest: playtest) }", in: sequence))
        expectEqual(count("stopSequence(", in: model), 1, "only the deadline")
        let stopSequence = body(of: "func stopSequence(deal: String, generation: Int) -> Bool {", in: speech)
        expectTrue(stopSequence.contains("guard ReadThroughDeadline.stopsSpeech(currentDeal: sequence?.deal, currentGeneration: sequence?.generation,"))
        expectTrue(ordered("guard ReadThroughDeadline.stopsSpeech(", "stop()", in: stopSequence))
        print("  odd one out: R2 wiring — the miss wait per lane and deal, the stamp's voice in its helper, the row's canvas gap, the deadline stops its own sequence")
    }

    // MARK: Board, after-pause, voice and parent wiring

    /// P1 wiring: a new wrong card reaches `handleEvaluation` / `playtestHandle` once and a known-wrong re-tap never; the
    /// board's after-pause step runs in both lanes before the generic rule; prompts use the queued path with stable keys
    /// and the 分類 voice switch; existing `speak(_:)` is unchanged; the screen, panel and card lines are wired.
    func testBoardVoiceAndParentWiring() throws {
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let speech = try source("Sources/VisaGames/SystemSpeechPrompt.swift")
        let host = try source("Sources/VisaGames/CanvasActivityHost.swift")
        let shell = try source("Sources/VisaGames/ActivityBoardView.swift")
        let settingsView = try source("Sources/VisaGames/ParentSettingsView.swift")
        let card = try source("Sources/VisaGames/ParentGameCard.swift")
        let panel = try source("Sources/VisaGames/ParentSortSettingsView.swift")
        let recorder = try source("Sources/VisaGames/PerformanceRecorder.swift")

        let tap = body(of: "func oddOneOutTap(card: Int)", in: model)
        let missCase = tap.components(separatedBy: "case .miss:").dropFirst().first?.components(separatedBy: "case .knownWrongRetap:").first ?? ""
        let knownCase = tap.components(separatedBy: "case .knownWrongRetap:").dropFirst().first?.components(separatedBy: "case .ignored").first ?? ""
        expectTrue(missCase.contains("self.handleEvaluation(.incorrect, selectionLabel: choice)"))
        expectTrue(missCase.contains("self.playtestHandle(.incorrect, selectionLabel: choice)"))
        expectTrue(missCase.contains("self.pendingAnswerRecord = record"))
        expectFalse(knownCase.contains("handleEvaluation(") || knownCase.contains("playtestHandle("), "a known-wrong card costs nothing")
        expectTrue(tap.contains("(playtest ? playtestReveal : childReveal).activeDeal == nil"), "no taps during the reveal")
        // After a Think Pause: the board's step in both lanes, before the generic two-miss rule.
        let pause = body(of: "private func finishThinkPause()", in: model)
        expectTrue(ordered("if activeActivityKind?.usesBoardAfterPause == true {", "ActivityHintPolicy.shouldAutoHint", in: pause))
        expectTrue(pause.contains("oddOneOutAfterPause(playtest: false)"))
        let playtestPause = body(of: "private func finishPlaytestThinkPause()", in: model)
        expectTrue(ordered("if playtestKind?.usesBoardAfterPause == true {", "ActivityHintPolicy.shouldAutoHint", in: playtestPause))
        expectTrue(playtestPause.contains("oddOneOutAfterPause(playtest: true)"))
        let after = body(of: "private func oddOneOutAfterPause(", in: model)
        expectTrue(after.contains("board.afterPause(miss: board.misses, currentDeal: playtest ? playtestChoiceDealSeed : choiceDealSeed)"))
        expectTrue(after.contains("let quiet = !playtest && session.mode != .lock"), "silent under parent controls")
        // Astra R1, miss → hint → a different wrong card: the hint sets its lane's flag (also under parent controls),
        // so the next new wrong card, recorded by `handleEvaluation` / `playtestHandle`, carries hint_on like the board.
        let hintCase = after.components(separatedBy: "case .hint:").dropFirst().first?.components(separatedBy: "case .tryAgain:").first ?? ""
        expectTrue(hintCase.contains("if playtest {\n                playtestHintUsed = true\n                perf.playtestHint(afterMisses: board.misses)\n            } else {\n                entryHintUsed = true\n                perf.roundHint(afterMisses: board.misses)\n            }"))
        expectTrue(ordered("entryHintUsed = true", "guard !quiet else { return }", in: hintCase), "before the quiet return")
        expectTrue(body(of: "private func handleEvaluation(", in: model)
            .contains("pendingAfter: pendingAwardMinutes, hintOn: entryHintUsed,"))
        expectTrue(body(of: "private func playtestHandle(", in: model)
            .contains("pendingAfter: playtestPendingMinutes, hintOn: playtestHintUsed,"))
        // The deal: the child's ladder step (a playtest never writes it), the read-through fixed at deal from the dealt
        // step's own run, the 分類方法 kept on the board, the facts.
        let deal = body(of: "private func makeOddOneOutBoard(", in: model)
        expectTrue(deal.contains("if !playtest, patternSortProgress.warmUp("))
        expectTrue(deal.contains("patternSortProgress.readThrough(.oddOneOut, question.step, guidance: sortSettings.guidance)"))
        expectTrue(deal.contains("OddOneOutBoard(question: question, deal: seed, guidance: sortSettings.guidance, methods: methods)"))
        expectFalse(deal.contains("patternSortProgress.record("), "a deal never records")
        expectEqual(count("patternSortProgress.record(", in: model), 1)
        // Astra R1: the round counts at the step it was dealt at, under the settings it was dealt with.
        let ladder = body(of: "private func recordOddOneOutLadder(", in: model)
        expectTrue(ladder.contains("patternSortProgress.record(.oddOneOut, board.question.step, outcome: outcome, methods: board.methods, now: Date())"))
        expectFalse(ladder.contains("sortSettings"), "never the settings at the round's end")
        expectTrue(ladder.contains("PatternSortProgressStore().save"))
        expectFalse(body(of: "private func finishOddOneOutRound(", in: model)
            .components(separatedBy: "if playtest {").dropFirst().first?.components(separatedBy: "return\n").first?
            .contains("recordOddOneOutLadder") ?? true, "a playtest never writes the ladder")
        expectTrue(body(of: "private func oddOneOutFacts()", in: model)
            .contains("readThrough: playtest ? playtestOddOneOutReadThrough : oddOneOutReadThrough"))
        expectTrue(body(of: "private func dealFacts(", in: model).contains("case .oddOneOut:\n            return oddOneOutFacts()"))
        // Voice: the queued path with stable keys, only with 分類設定's 廣東話語音 on; the sequence engine gets the switch.
        let line = body(of: "private func speakOddOneOutLine(", in: model)
        expectTrue(ordered("guard sortSettings.audioEnabled else { return }", "guideVoice.speakQueued(line.prompt, interrupt: true)", in: line))
        expectTrue(body(of: "private func startOddOneOutSequence(", in: model).contains("voiceOn: sortSettings.audioEnabled"))
        let extensionText = model.components(separatedBy: "// MARK: - 分類 · 邊個唔同類 (patterns-sorting P1, 0.41.0 / 91)").last ?? ""
        expectFalse(extensionText.contains("guideVoice.speak("), "no new caller of speak(_:)")
        let speak = body(of: "    func speak(_ prompt: SpokenPrompt) {", in: speech)
        expectTrue(speak.contains("synthesizer.stopSpeaking(at: .immediate)") && speak.contains("synthesizer.speak(utterance)"))
        expectFalse(speak.contains("sequence"), "existing games keep speak(_:) unchanged")
        // The screen: centred rows for this kind only; every older board keeps x 110.
        expectTrue(shell.contains("var choicesX: CGFloat = 110"))
        expectTrue(shell.contains(".canvasPlaced(x: choicesX, y: 430)"))
        expectTrue(host.contains("case .oddOneOut:\n                oddOneOut"))
        expectTrue(host.contains("choicesX: PatternSortLayout.rowX(count)"))
        expectTrue(host.contains("cardWidth: PatternSortLayout.cardWidth(count)"))
        expectEqual(count("choicesX:", in: host), 3, "the builder's parameter, its pass-through, the 邊個唔同類 call")
        expectTrue(host.contains("model.oddOneOutTap(card: index)"))
        // Parent: the panel, the card lines beside the Hanzi ones, the config_change.
        expectTrue(settingsView.contains("ParentSortSettingsView(model: model)"))
        expectTrue(ordered("ParentTapHanziSettingsView(model: model)", "ParentSortSettingsView(model: model)", in: settingsView))
        for needle in ["PatternSortParentCopy.defaultOffLine(kind)", "PatternSortParentCopy.suggestedStar(kind)",
                       "PatternSortParentCopy.cardDetail(kind)", "PatternSortParentCopy.starsLockedLine(kind)"] {
            expectTrue(card.contains(needle), needle)
        }
        expectTrue(panel.contains("ForEach(HanziParentCopy.coachLabels, id: \\.short)"), "the one label table")
        for literal in ["\"多啲\"", "\"標準\"", "\"少啲\""] { expectFalse(panel.contains(literal), literal) }
        expectTrue(panel.contains("model.toggleSortMethod(method)"))
        expectTrue(recorder.contains("func sortSettingChanged(what: String, value: String)"))
        let save = body(of: "private func saveSortSettings(", in: model)
        expectTrue(save.contains("PatternSortSettingChange.changes(from: before, to: sortSettings)"))
        expectTrue(save.contains("perf.sortSettingChanged(what: change.what, value: change.value)"))
        let toggle = body(of: "func toggleSortMethod(", in: model)
        expectTrue(toggle.contains("guard session.mode == .parent else { return }"))
        expectTrue(toggle.contains("case .refusedLastPerceptual:"))
        // The card copy: the 分類 cards only; the Hanzi lines stay their own.
        expectEqual(PatternSortParentCopy.defaultOffLine(.oddOneOut), "預設關閉 / Off by default")
        expectEqual(PatternSortParentCopy.suggestedStar(.oddOneOut), "建議 ★ / Suggested ★")
        expectEqual(PatternSortParentCopy.starsLockedLine(.oddOneOut), "試玩一次先開星 / Playtest once to unlock the stars")
        for kind in [ActivityKind.tapHanziAll, .tapHanziWrite, .findTheSame, .tapLetterAll] {
            expectTrue(PatternSortParentCopy.defaultOffLine(kind) == nil && PatternSortParentCopy.suggestedStar(kind) == nil
                       && PatternSortParentCopy.cardDetail(kind) == nil && PatternSortParentCopy.starsLockedLine(kind) == nil,
                       kind.rawValue)
        }
        expectEqual(PatternSortSettingChange.changes(from: .defaults, to: SortSettings(methods: [.colour], guidance: .more,
                                                                                    audioEnabled: false)).map { "\($0.what)=\($0.value)" },
                    ["sort_methods=colour", "sort_guidance=more", "sort_audio=off"])
        print("  odd one out: wiring — one miss per new wrong card, board after-pause in both lanes, queued voice behind 分類語音, centred row, 分類設定")
    }
}
