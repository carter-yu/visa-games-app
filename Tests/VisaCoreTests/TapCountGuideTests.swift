import Foundation
import VisaCore

/// v0.30.0 描數字提示 / tracing guidance for 1–10 (★★ / ★★★, Cantonese and English cards): the Opus
/// spec data for every numeral in both languages, the demo timeline, 識咗 (2 clean in a row), the
/// parent level, help timers, headlights, and that the demo never takes input away (a touch ends it).
final class TapCountGuideTests {
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Simplified forms that must never appear (HK Traditional only); each differs from its HK form.
    private static let simplified = ["数", "车", "点", "个", "写", "对", "错", "齐", "随", "机", "闪", "颜", "号", "两", "开",
                                     "关", "设", "笔", "划", "顺", "边", "张", "双", "样", "读", "声", "试", "为", "们", "时",
                                     "从", "发", "后", "会", "动", "还", "进", "过", "头", "画", "线", "圆", "这", "這", "么",
                                     "吗", "里", "转", "弯", "灯", "该", "让", "条", "处", "见", "飞", "竖", "绕", "继", "续",
                                     "备", "终", "绿", "红", "黄", "门", "长", "认", "识", "练", "习", "跟着"]

    private func hasCJK(_ s: String) -> Bool { s.unicodeScalars.contains { $0.value >= 0x2E80 } }

    /// A ★★ board (counted, ready to trace) whose target is `n`.
    private func countedBoard(_ n: Int, english: Bool) -> TapCountBoard? {
        let kind: ActivityKind = english ? .tapCountTraceEnglish : .tapCountTrace
        for i in 0..<4000 {
            let q = TapCountGenerator.make(seed: "guide.\(n).\(i)", kind: kind)
            guard q.target == n else { continue }
            var board = TapCountBoard(question: q)
            for (k, bay) in q.occupiedBays.enumerated() { _ = board.tap(bay: bay, now: Double(k)) }
            return board.stage == .counted ? board : nil
        }
        return nil
    }

    @discardableResult
    private func drive(_ board: inout ShapeTraceBoard, clock: inout Double) -> ShapeTraceMove {
        var last = ShapeTraceMove.ignored
        var steps = 0
        while !board.isComplete, steps < 10 {
            steps += 1
            guard let path = board.currentPath else { break }
            clock += 0.1
            _ = board.penDown(at: path.start, now: clock)
            var d = 0.0
            while d <= path.length + 16 {
                clock += 0.02
                last = board.penMove(to: path.point(at: min(d, path.length)), now: clock)
                if case .strokeDone = last { break }
                if case .shapeDone = last { break }
                if case .allDone = last { break }
                d += 6
            }
            board.penUp()
        }
        return last
    }

    // MARK: Data (every numeral, both languages)

    func testGuideDataCoversEveryNumeralInBothLanguages() {
        for n in 1...10 {
            guard let spec = TapCountGuideData.numeral(n), let guide = NumeralGuide(n) else {
                expectTrue(false, "guide data for \(n)")
                continue
            }
            let strokes = NumeralGlyphs.strokes(n)
            expectEqual(guide.paths.count, strokes.count, "paths of \(n)")
            expectFalse(spec.beats.isEmpty, "beats of \(n)")
            expectTrue(spec.beats.count <= 6, "at most 6 beats for \(n)")
            // Every stroke is demonstrated, in order, and each stroke's beats end at its end.
            expectEqual(Set(spec.beats.map(\.stroke)), Set(strokes.indices), "beats cover every stroke of \(n)")
            expectEqual(spec.beats.map(\.stroke), spec.beats.map(\.stroke).sorted(), "stroke order of \(n)")
            for (index, path) in guide.paths.enumerated() {
                let ends = guide.beats.filter { $0.stroke == index }.map(\.end)
                expectEqual(ends, ends.sorted(), "beat ends rise on stroke \(index) of \(n)")
                expectEqual(ends.last ?? 0, path.length, accuracy: 1)
            }
            for beat in spec.beats {
                expectTrue(beat.seconds >= 0.4 && beat.seconds <= 4, "beat seconds of \(n)")
                if let until = beat.until {
                    let off = NumeralGuide.glyphOffset(of: until, on: strokes[beat.stroke])
                    expectTrue((off ?? 99) <= NumeralGuide.pointTolerance, "beat point on stroke for \(n): \(String(describing: off))")
                }
            }
            for cue in spec.cues {
                let off = NumeralGuide.glyphOffset(of: cue.point, on: strokes[cue.stroke])
                expectTrue((off ?? 99) <= NumeralGuide.pointTolerance, "cue point on stroke for \(n): \(String(describing: off))")
            }
            for cue in guide.cues {
                // A cue may sit at a stroke's very start (10: the sign at the top of the 0, shown as that stroke begins).
                expectTrue(cue.distance >= 0 && cue.distance < guide.paths[cue.stroke].length, "cue inside stroke of \(n)")
                let sign = cue.signPoint
                let board = NumeralGlyphs.traceBoard(n)
                expectTrue(sign.x >= board.x && sign.x <= board.x + board.width && sign.y >= board.y
                           && sign.y <= board.y + board.height, "cue sign on the board for \(n)")
            }
            // Two-stroke numerals hop and say the last-stroke line; one-stroke numerals do not.
            let multi = strokes.count > 1
            expectEqual(spec.hop != nil, multi, "hop line of \(n)")
            expectEqual(spec.hopSide != nil, multi, "hop side of \(n)")
            expectEqual(spec.lastStroke != nil, multi, "last-stroke line of \(n)")
            for english in [false, true] {
                let lines = TapCountLines(english ? .english : .cantonese)
                expectEqual(lines.guideBeats(n).count, spec.beats.count)
                expectEqual(lines.guideCues(n).count, spec.cues.count)
                expectTrue(lines.guideMerge(n) != nil)
                let prompts = lines.allGuidePrompts(n)
                for prompt in prompts {
                    expectFalse(prompt.mainText.trimmingCharacters(in: .whitespaces).isEmpty, "empty line for \(n)")
                    expectFalse(prompt.mainText.contains("{"), "unfilled placeholder: \(prompt.mainText)")
                    if english {
                        expectTrue(prompt.key.hasPrefix("en."), "English key \(prompt.key)")
                        expectFalse(hasCJK(prompt.mainText), "Chinese in English line: \(prompt.mainText)")
                        expectFalse(hasCJK(prompt.subText ?? ""), "Chinese in English sub: \(prompt.subText ?? "")")
                    } else {
                        expectTrue(prompt.key.hasPrefix("tapCount.guide."), "Cantonese key \(prompt.key)")
                        expectTrue(hasCJK(prompt.mainText), "Cantonese line: \(prompt.mainText)")
                        for ch in Self.simplified { expectFalse(prompt.mainText.contains(ch), "simplified \(ch) in \(prompt.mainText)") }
                        expectFalse(hasCJK(prompt.subText ?? ""), "English sub has no Chinese: \(prompt.subText ?? "")")
                    }
                }
                expectEqual(Set(prompts.map(\.key)).count, prompts.count, "unique keys for \(n)")
            }
        }
        for english in [false, true] {
            let lines = TapCountLines(english ? .english : .cantonese)
            for pair in lines.allGuidePairs {
                expectFalse(pair.0.isEmpty)
                expectFalse(pair.0.contains("{") || pair.1.contains("{"))
                if english {
                    expectFalse(hasCJK(pair.0) || hasCJK(pair.1), "Chinese in English pair: \(pair)")
                } else {
                    for ch in Self.simplified { expectFalse(pair.0.contains(ch), "simplified \(ch) in \(pair.0)") }
                }
            }
            expectFalse(lines.guideStopWord.isEmpty)
            expectEqual(hasCJK(lines.guideStopWord), !english)
        }
        let parent = TapCountGuideData.copy.parent
        for text in [parent.title, parent.more, parent.standard, parent.less, parent.learnedNote, parent.moreShort,
                     parent.standardShort, parent.lessShort] {
            expectFalse(text.isEmpty)
            for ch in Self.simplified { expectFalse(text.contains(ch), "simplified \(ch) in parent copy \(text)") }
        }
        expectEqual(parent.moreShort, "多啲")
        expectEqual(parent.standardShort, "標準")
        expectEqual(parent.lessShort, "少啲")
        // Every guidance line is in the child-facing lists the copy checks walk.
        let zhAll = Set(TapCountLines(.cantonese).allSpokenPrompts.map(\.key))
        let enAll = Set(TapCountLines(.english).allSpokenPrompts.map(\.key))
        for n in 1...10 {
            for p in TapCountLines(.cantonese).allGuidePrompts(n) { expectTrue(zhAll.contains(p.key), "listed \(p.key)") }
            for p in TapCountLines(.english).allGuidePrompts(n) { expectTrue(enAll.contains(p.key), "listed \(p.key)") }
        }
    }

    // MARK: Demo timeline

    func testDemoTimelineIsAPureFunctionOfTimeAndRespectsReduceMotion() {
        for n in 1...10 {
            guard let guide = NumeralGuide(n) else { continue }
            let timeline = TapCountDemoTimeline(guide: guide)
            expectTrue(timeline.duration > 1.5 && timeline.duration < 15, "demo of \(n) lasts \(timeline.duration)")
            expectEqual(timeline.beatStarts.count, guide.beats.count)
            expectEqual(timeline.beatStarts, timeline.beatStarts.sorted())
            expectNil(timeline.pose(at: -0.01))
            expectNil(timeline.pose(at: timeline.duration + 0.01))
            let first = timeline.pose(at: 0)!
            expectTrue(first.point.distance(to: guide.paths[guide.beats[0].stroke].start) < 1, "demo starts at the start of \(n)")
            let lastBeat = guide.beats.last!
            let atEnd = timeline.pose(at: timeline.mergeStart - 0.001)!
            expectTrue(atEnd.point.distance(to: guide.paths[lastBeat.stroke].point(at: lastBeat.end)) < 3, "demo ends at the end of \(n)")
            // Reduce Motion: no gliding — mid-step poses sit at the step's end, and nothing leaves the ground.
            for timed in timeline.steps {
                let mid = (timed.start + timed.end) / 2
                guard let still = timeline.pose(at: mid, reduceMotion: true) else { continue }
                expectEqual(still.lift, 0, accuracy: 1e-9)
                if case let .drive(stroke, _, to, _) = timed.step {
                    expectTrue(still.point.distance(to: guide.paths[stroke].point(at: to)) < 0.01, "RM snaps for \(n)")
                }
                if case .hop = timed.step {
                    expectTrue((timeline.pose(at: mid)?.lift ?? 0) > 0.5, "the car is in the air mid-hop for \(n)")
                }
                if case let .pause(_, _, cue, _) = timed.step {
                    expectEqual(timeline.pausedCue(at: mid), cue)
                }
            }
            let hops = timeline.steps.filter { if case .hop = $0.step { return true } else { return false } }
            expectEqual(hops.count, guide.paths.count - 1, "one hop per extra stroke of \(n)")
            // The route ends up covering every stroke; the beat line follows the car.
            let route = timeline.route(at: timeline.mergeStart)
            for (index, path) in guide.paths.enumerated() {
                let covered = route.filter { $0.stroke == index }.reduce(0) { $0 + ($1.to - $1.from) }
                expectEqual(covered, path.length, accuracy: 2)
            }
            for (i, start) in timeline.beatStarts.enumerated() {
                expectEqual(timeline.beat(at: start + 0.001), i)
            }
            expectNil(timeline.beat(at: timeline.mergeStart + 0.01))
        }
    }

    // MARK: 識咗

    func testLearnedNeedsTwoCleanTracesInARowAndAStallResetsIt() {
        expectEqual(TapCountGuideProgress.cleanInARow, 2)
        var progress = TapCountGuideProgress()
        expectFalse(progress.isLearned(8, language: .cantonese))
        progress.recordClean(8, language: .cantonese)
        expectFalse(progress.isLearned(8, language: .cantonese), "one clean is not 識咗")
        progress.recordStall(8, language: .cantonese)
        progress.recordClean(8, language: .cantonese)
        expectFalse(progress.isLearned(8, language: .cantonese), "clean, stall, clean is not in a row")
        progress.recordClean(8, language: .cantonese)
        expectTrue(progress.isLearned(8, language: .cantonese), "two clean in a row = 識咗")
        expectFalse(progress.isLearned(5, language: .cantonese), "per numeral")
        // Writing an 8 is the same skill on the English card.
        expectEqual(progress.isLearned(8, language: .english), TapCountGuideData.sharedAcrossLanguages)
        expectEqual(progress.learnedNumerals(language: .cantonese), [8])
        progress.recordStall(8, language: .english)
        expectEqual(progress.isLearned(8, language: .cantonese), !TapCountGuideData.sharedAcrossLanguages)
        // Store: round trip; junk or missing data = nothing learned (never blocks the child).
        let suite = "tapCountGuide.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TapCountGuideProgressStore(defaults: defaults)
        expectEqual(store.load(), TapCountGuideProgress())
        var saved = TapCountGuideProgress()
        saved.recordClean(3, language: .english)
        saved.recordClean(3, language: .english)
        store.save(saved)
        expectEqual(store.load(), saved)
        expectTrue(store.load().isLearned(3, language: .english))
        defaults.set(Data("junk".utf8), forKey: TapCountGuideProgressStore.key)
        expectEqual(store.load(), TapCountGuideProgress())
    }

    // MARK: Level setting

    func testLevelDefaultsToStandardOldDataDecodesAndPlansFollowTheLevel() throws {
        expectEqual(TapCountSettings.defaults.guidance, .standard)
        let suite = "tapCountGuideLevel.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TapCountSettingsStore(defaults: defaults)
        var settings = TapCountSettings.defaults
        settings.guidance = .more
        store.save(settings)
        expectEqual(store.load().guidance, .more)
        // v0.28–v0.29 data has no guidance key → 標準, everything else kept.
        let old = #"{"range":5,"countVoice":false,"english":true,"badgeStyle":"ticks","traceScaffold":"outline"}"#
        defaults.set(Data(old.utf8), forKey: TapCountSettingsStore.key)
        let loaded = store.load()
        expectEqual(loaded.guidance, .standard)
        expectEqual(loaded.range, .upTo5)
        expectEqual(loaded.traceScaffold, .outline)
        // Carter's choice: 標準 = demo (until 識咗) + headlights + rhyme + just-in-time cue, re-shown after a 2 s stall.
        let standard = TapCountGuidePlan(level: .standard, learned: false)
        expectTrue(standard.demo)
        expectTrue(standard.headlights && standard.cueSigns && standard.cueWords)
        expectTrue(standard.fadesLaterStrokes && standard.hops, "two-stroke numerals fade and hop")
        expectEqual(standard.stallSeconds ?? 0, 2, accuracy: 1e-9)
        expectEqual(TapCountGuideData.timing.headlightDots, 3)
        for level in TapCountGuidanceLevel.allCases {
            let spec = TapCountGuideData.level(level)
            for learned in [false, true] {
                let plan = TapCountGuidePlan(level: level, learned: learned)
                let demo = spec.demo == .always || (spec.demo == .untilLearned && !learned)
                expectEqual(plan.demo, demo, "demo of \(level) learned=\(learned)")
                if learned, spec.demo != .always {
                    expectTrue(plan.features.isSubset(of: spec.learnedKeeps), "識咗 trims \(level)")
                } else {
                    expectEqual(plan.features, spec.features)
                }
            }
        }
        // 多啲 ⊇ 標準 ⊇ 少啲; once learned, 標準 drops the demo.
        expectTrue(TapCountGuideData.level(.standard).features.isSubset(of: TapCountGuideData.level(.more).features))
        expectTrue(TapCountGuideData.level(.less).features.isSubset(of: TapCountGuideData.level(.standard).features))
        expectFalse(TapCountGuidePlan(level: .standard, learned: true).demo)
        expectTrue(TapCountGuidePlan(level: .more, learned: true).demo)
        expectFalse(TapCountGuidePlan(level: .less, learned: false).demo)
    }

    // MARK: The demo never blocks input

    func testDemoNeverBlocksInputAndATouchEndsIt() {
        for english in [false, true] {
            for n in 1...10 {
                guard var board = countedBoard(n, english: english) else {
                    expectTrue(false, "board for \(n)")
                    continue
                }
                board.startTracing(tolerance: .standard, guidance: TapCountGuidePlan(level: .standard, learned: false),
                                   now: 100, demoLead: 1.4)
                expectEqual(board.stage, .tracing)
                expectTrue(board.guideDemoPending(now: 100), "the demo is on for \(n)")
                expectTrue(board.guideDemoPending(now: 102), "the demo plays for \(n)")
                // The trace takes a pen at once, demo or not (nothing is locked).
                var trace = board.trace!
                let grab = trace.penDown(at: trace.currentPath!.start, now: 102)
                if case .grabbed = grab {} else { expectTrue(false, "the pen is taken during the demo for \(n): \(grab)") }
                // The touch ends the demo.
                expectTrue(board.skipGuideDemo(now: 102))
                expectFalse(board.guideDemoPending(now: 102.1))
                expectFalse(board.skipGuideDemo(now: 102.2), "only once")
                expectEqual(board.guide?.readyAt ?? 0, 102, accuracy: 1e-9)
                expectEqual(board.guide?.demoCode, "skipped")
                trace.penUp()
                var clock = 102.5
                drive(&trace, clock: &clock)
                board.updateTrace(trace, now: clock)
                expectEqual(board.stage, .done, "finishes after a skipped demo for \(n)")
                expectEqual(board.misses, 0)
                expectEqual(board.resultFields["guide_demo"], .string("skipped"))
                expectEqual(board.resultFields["guide_clean"], .int(1))
            }
        }
        // A learned numeral at 標準 (and 少啲) has no demo at all.
        if var board = countedBoard(8, english: false) {
            board.startTracing(tolerance: .standard, guidance: TapCountGuidePlan(level: .standard, learned: true),
                               now: 10, demoLead: 1.4)
            expectFalse(board.guideDemoPending(now: 10))
            expectEqual(board.guide?.readyAt ?? 0, 10, accuracy: 1e-9)
        }
        // Played out: the child's turn begins when the demo ends.
        if var board = countedBoard(5, english: true), let guide = NumeralGuide(5) {
            board.startTracing(tolerance: .standard, guidance: TapCountGuidePlan(level: .more, learned: true),
                               now: 0, demoLead: 1.4)
            let duration = TapCountDemoTimeline(guide: guide).duration
            expectTrue(board.guideDemoPending(now: 1.4 + duration - 0.01))
            expectFalse(board.guideDemoPending(now: 1.4 + duration + 0.01))
            expectEqual(board.guide?.readyAt ?? 0, 1.4 + duration, accuracy: 1e-9)
            expectEqual(board.guide?.demoCode, "played")
        }
    }

    // MARK: Help timers (never a miss)

    func testHelpTimersShowHelpButNeverMarkWrong() {
        guard var board = countedBoard(8, english: false), let guide = NumeralGuide(8) else {
            expectTrue(false, "board for 8")
            return
        }
        let plan = TapCountGuidePlan(level: .standard, learned: true)
        board.startTracing(tolerance: .standard, guidance: plan, now: 50)
        var trace = board.trace!
        // Pen down on the car, then nothing: 2 s → stall (ring + ghost of the next bit).
        _ = trace.penDown(at: trace.currentPath!.start, now: 50.5)
        expectEqual(TapCountGuideCoach.help(plan: plan, guide: guide, trace: trace, readyAt: 50, now: 52), .none)
        let stall = TapCountGuideCoach.help(plan: plan, guide: guide, trace: trace, readyAt: 50, now: 52.6)
        guard case let .stall(_, from, to, _) = stall else {
            expectTrue(false, "stall after 2 s: \(stall)")
            return
        }
        expectTrue(to > from, "the ghost runs ahead")
        expectTrue(TapCountGuideCoach.ghostPose(stall, guide: guide, now: 52.7) != nil)
        // The key is stable for the episode (noted once).
        expectEqual(TapCountGuideCoach.help(plan: plan, guide: guide, trace: trace, readyAt: 50, now: 53).key, stall.key)
        // 8 s idle → the ghost drives to the end; 20 s idle with the pen up → the demo again.
        expectEqual(TapCountGuideCoach.help(plan: plan, guide: guide, trace: trace, readyAt: 50, now: 58.7).kind, "ghost_to_end")
        trace.penUp()
        expectEqual(TapCountGuideCoach.help(plan: plan, guide: guide, trace: trace, readyAt: 50, now: 70.7).kind, "redemo")
        // 少啲: no stall ring.
        let less = TapCountGuidePlan(level: .less, learned: false)
        var held = board.trace!
        _ = held.penDown(at: held.currentPath!.start, now: 50.5)
        expectEqual(TapCountGuideCoach.help(plan: less, guide: guide, trace: held, readyAt: 50, now: 53), .none)
        // Help is noted, the trace is no longer clean, and nothing else changes.
        expectTrue(board.noteGuideHelp(key: stall.key!, kind: stall.kind))
        expectFalse(board.noteGuideHelp(key: stall.key!, kind: stall.kind), "once per episode")
        expectFalse(board.guide!.clean)
        expectEqual(board.misses, 0)
        var clock = 60.0
        var t = board.trace!
        drive(&t, clock: &clock)
        board.updateTrace(t, now: clock)
        expectEqual(board.stage, .done, "tracing is never wrong")
        expectEqual(board.resultFields["guide_clean"], .int(0))
        expectEqual(board.resultFields["guide_stalls"], .int(1))
    }

    // MARK: Headlights

    func testHeadlightsShowOnlyTheNextThreeDotsAheadOfTheCar() {
        let plan = TapCountGuidePlan(level: .standard, learned: false)
        for n in 1...10 {
            guard var board = countedBoard(n, english: n % 2 == 0), let guide = NumeralGuide(n) else { continue }
            board.startTracing(tolerance: .standard)
            var trace = board.trace!
            let path = trace.currentPath!
            var lights = TapCountGuideCoach.headlights(plan: plan, guide: guide, trace: trace)
            expectEqual(lights.count, 3, "three dots for \(n)")
            expectTrue(lights.allSatisfy { $0 > trace.progress + TapCountGuideCoach.noseUnits && $0 <= path.length }, "ahead of the car for \(n)")
            for i in 1..<lights.count { expectEqual(lights[i] - lights[i - 1], guide.dotSpacing, accuracy: 1e-6) }
            // Drive most of the stroke: fewer dots near the end, never past it.
            var clock = 1.0
            _ = trace.penDown(at: path.start, now: clock)
            var d = 0.0
            while d < path.length - 60 {
                clock += 0.02
                _ = trace.penMove(to: path.point(at: d), now: clock)
                d += 6
            }
            lights = TapCountGuideCoach.headlights(plan: plan, guide: guide, trace: trace)
            expectTrue(lights.count <= 3)
            expectTrue(lights.allSatisfy { $0 <= path.length }, "never past the end for \(n)")
            expectTrue(TapCountGuideCoach.headlights(plan: TapCountGuidePlan(level: .less, learned: false), guide: guide,
                                                     trace: trace).isEmpty, "少啲 has no headlights")
        }
    }

    // MARK: Wiring

    func testGuidanceWiringSourceGuards() throws {
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let host = try source("Sources/VisaGames/CanvasActivityHost.swift")
        let view = try source("Sources/VisaGames/TapCountBoardView.swift")
        let drawing = try source("Sources/VisaGames/TapCountGuideDrawing.swift")
        let parent = try source("Sources/VisaGames/ParentTapCountSettingsView.swift")
        let data = try source("Sources/VisaCore/TapCountGuideData.swift")
        let engine = try source("Sources/VisaCore/TapCountGuidance.swift")
        // The demo is never part of `locked` (a touch ends it).
        let lockedLine = host.components(separatedBy: "\n").first { $0.contains("locked: justCompleted") && $0.contains("tapCountInputOpen") } ?? ""
        expectFalse(lockedLine.isEmpty)
        expectFalse(lockedLine.contains("guide") || lockedLine.contains("demo"), "demo is not a lock: \(lockedLine)")
        expectTrue(view.contains("view.onGuideSkip()"))
        expectTrue(view.contains("accessibilityReduceMotion"))
        expectTrue(model.contains("TapCountGuidePlan(level: tapCountSettings.guidance"))
        expectTrue(model.contains("tapCountGuideProgressStore.save"))
        expectTrue(model.contains("!tapCountUsesPlaytest"), "playtests never change 識咗")
        expectTrue(parent.contains("onGuidance"))
        // Generated from the committed Opus spec, never hand-written.
        expectTrue(data.hasPrefix("// GENERATED by scripts/guidance_spec_to_swift.py from docs/tap-count-guidance-spec.json"))
        expectTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("docs/tap-count-guidance-spec.json").path))
        expectFalse(data.contains("\"dev\""), "the DEV placeholder spec is never shipped")
        // ADR 0010 / 0011: no isolation hops, no window or presentation changes in the guidance code
        // (".level = ." is a window level; the plan's own `self.level = level` is the 多啲/標準/少啲 setting).
        for text in [drawing, engine, data] {
            for banned in ["assumeIsolated", "unowned", "addObserver", "NSWindow", "presentationOptions", "styleMask",
                           ".level = .", "NSMenu", "toggleFullScreen", "setFrame"] {
                expectFalse(text.contains(banned), "banned \(banned) in guidance code")
            }
        }
    }
}
