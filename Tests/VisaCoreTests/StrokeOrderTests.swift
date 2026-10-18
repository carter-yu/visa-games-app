import Foundation
import VisaCore

/// v0.31.0 筆順動畫 (stroke-order design D1–D15, digits only): the D7 pacing table, Reduce Motion,
/// the glyph adapter, who gets which dose, the glance budget and 7-day refresh, the ★ plate taps,
/// and that the ★★ glance never plays with the car and a touch ends it (no paint, no miss).
final class StrokeOrderTests {
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func countedBoard(_ n: Int, kind: ActivityKind) -> TapCountBoard? {
        for i in 0..<4000 {
            let q = TapCountGenerator.make(seed: "stroke.\(n).\(i)", kind: kind)
            guard q.target == n else { continue }
            var board = TapCountBoard(question: q)
            for (k, bay) in q.occupiedBays.enumerated() { _ = board.tap(bay: bay, now: Double(k)) }
            return board.stage == .counted ? board : nil
        }
        return nil
    }

    // MARK: D7 pacing

    func testTimelineTotalsMatchTheDesignTable() {
        // design.md D7 expected totals (teach / remind / glance).
        let expected: [Int: (Double, Double, Double)] = [8: (5.3, 2.3, 1.2), 1: (2.3, 1.1, 0.4), 4: (4.9, 2.4, 1.1),
                                                         5: (5.4, 2.5, 1.1), 10: (5.5, 2.9, 1.5)]
        for (n, totals) in expected {
            guard let teach = StrokeOrderTimeline.digit(n, dosage: .teach),
                  let remind = StrokeOrderTimeline.digit(n, dosage: .remind),
                  let glance = StrokeOrderTimeline.digit(n, dosage: .glance) else {
                expectTrue(false, "timeline for \(n)")
                continue
            }
            // 教 follows the v0.30 rhyme seconds exactly (D7 "有口訣就跟口訣秒數"); the table's 8 (5.3) is an
            // estimate — the rhyme gives 4.7 — so 教 allows 0.65 s, 提 / 一閃 0.1 s.
            expectTrue(abs(teach.duration - totals.0) <= 0.65, "teach \(n): \(teach.duration) vs \(totals.0)")
            if let spec = TapCountGuideData.numeral(n) {
                let pace = StrokeOrderPacing.of(.teach)
                let beats = spec.beats.reduce(0) { $0 + $1.seconds }
                let pauses = teach.steps.filter { if case .pause = $0.kind { return true }; return false }.count
                let lifts = Double(teach.glyph.strokes.count - 1) * pace.lift
                expectEqual(teach.duration, pace.leadIn + beats + Double(pauses) * pace.turnPause + lifts + pace.endHold,
                            accuracy: 1e-6)
            }
            expectTrue(abs(remind.duration - totals.1) <= 0.1, "remind \(n): \(remind.duration) vs \(totals.1)")
            expectTrue(abs(glance.duration - totals.2) <= 0.1, "glance \(n): \(glance.duration) vs \(totals.2)")
            expectTrue(glance.duration < remind.duration && remind.duration < teach.duration, "doses shrink for \(n)")
        }
        for n in 1...10 {
            for dose in StrokeOrderDosage.allCases {
                guard let t = StrokeOrderTimeline.digit(n, dosage: dose) else { expectTrue(false, "\(n)"); continue }
                // Steps are contiguous and every stroke is drawn in order, start to end.
                var clock = 0.0
                var drawn: [Int: Double] = [:]
                for step in t.steps {
                    expectEqual(step.start, clock, accuracy: 1e-9)
                    expectTrue(step.end >= step.start)
                    clock = step.end
                    if case .draw(let s, let from, let to) = step.kind {
                        expectEqual(from, drawn[s] ?? 0, accuracy: 1e-9)
                        expectTrue(drawn.keys.allSatisfy { $0 <= s }, "strokes in order for \(n)")
                        drawn[s] = to
                    }
                }
                expectEqual(clock, t.duration, accuracy: 1e-9)
                for (i, stroke) in t.glyph.strokes.enumerated() {
                    expectEqual(drawn[i] ?? -1, stroke.path.length, accuracy: 1e-6)
                }
                expectEqual(t.inked(at: t.duration), t.glyph.strokes.map { $0.path.length })
                expectTrue(t.inked(at: 0).allSatisfy { $0 == 0 })
                expectTrue(t.written(at: t.duration))
                // Pauses only at turns (glance has none).
                let pauses = t.steps.filter { if case .pause = $0.kind { return true }; return false }
                if dose == .glance { expectTrue(pauses.isEmpty, "glance never pauses") }
            }
        }
    }

    func testReduceMotionNeverGlides() {
        guard let t = StrokeOrderTimeline.digit(8, dosage: .remind) else { expectTrue(false, "8"); return }
        for step in t.steps {
            guard case .draw(let s, let from, let to) = step.kind else { continue }
            let mid = (step.start + step.end) / 2
            let pose = t.pose(at: mid, reduceMotion: true)
            expectEqual(pose.stroke, s)
            expectEqual(pose.distance, to, accuracy: 1e-9)   // the whole chunk, not a glide
            expectEqual(pose.newestFrom, from, accuracy: 1e-9)
            let early = t.pose(at: step.start + 0.05, reduceMotion: true)
            expectTrue(early.newestOpacity < 1, "the chunk fades in")
            let moving = t.pose(at: mid, reduceMotion: false)
            expectTrue(moving.distance < to, "without Reduce Motion the pen glides")
        }
        // A lone stroke with no turns still appears in steps (1 = quarters).
        if let one = StrokeOrderTimeline.digit(1, dosage: .remind) {
            let draws = one.steps.filter { if case .draw = $0.kind { return true }; return false }
            expectTrue(draws.count >= 4, "1 is split for Reduce Motion")
        }
        expectEqual(StrokeOrderPacing.reduceMotionFadeSeconds, 0.2, accuracy: 1e-9)
        expectEqual(StrokeOrderPacing.inkFadeSeconds, 1.5, accuracy: 1e-9)
    }

    func testGlyphAdapterIsTheTracedNumeral() {
        for n in 1...10 {
            guard let glyph = StrokeGlyph.digit(n) else { expectTrue(false, "\(n)"); continue }
            let paths = NumeralGlyphs.paths(n, offset: LineMatchPoint(x: 0, y: 0), scale: 1)
            expectEqual(glyph.strokes.map { $0.path }, paths, "same strokes, same order for \(n)")
            expectEqual(glyph.script, .digit)
            expectEqual(glyph.progressKey, "\(n)")
        }
        expectNil(StrokeGlyph.digit(0))
        expectNil(StrokeGlyph.digit(11))
        expectNil(StrokeOrderTimeline.digit(11, dosage: .remind))
    }

    // MARK: Who gets what (D3, D4)

    func testDosageTruthTableAndSettings() throws {
        expectEqual(TapCountSettings.defaults.strokeOrder, .remind, "digits default to 提")
        expectEqual(StrokeOrderPlan.star1(setting: .off, learned: false), nil)
        expectEqual(StrokeOrderPlan.star1(setting: .teach, learned: true), .teach)
        expectEqual(StrokeOrderPlan.star1(setting: .remind, learned: false), .remind)
        expectEqual(StrokeOrderPlan.star1(setting: .remind, learned: true), .glance)
        var progress = StrokeOrderProgress()
        let key = "8"
        func glance(_ s: StrokeOrderSetting, _ g: TapCountGuidanceLevel, learned: Bool, today: Int = 100)
            -> StrokeOrderProgress.GlanceReason? {
            let plan = TapCountGuidePlan(level: g, learned: learned)
            return StrokeOrderPlan.star2Glance(setting: s, guidance: g, learned: learned, carDemo: plan.demo,
                                               progress: progress, key: key, today: today)
        }
        // Learning: the car, never the pen. 多啲 = the car every time; 少啲 / 熄 = nothing.
        expectNil(glance(.remind, .standard, learned: false))
        expectNil(glance(.remind, .more, learned: true))
        expectNil(glance(.remind, .less, learned: true))
        expectNil(glance(.off, .standard, learned: true))
        // 識咗 at 標準: 3 glances, then none, then one refresh after 7 days away.
        for left in (1...3).reversed() {
            expectEqual(progress.remaining(key), left)
            expectEqual(glance(.remind, .standard, learned: true), .budget)
            progress.consume(key, reason: .budget)
            progress.noteTraced(key, today: 100)
        }
        expectEqual(progress.remaining(key), 0)
        expectNil(glance(.remind, .standard, learned: true, today: 106))
        expectEqual(glance(.remind, .standard, learned: true, today: 107), .refresh)
        progress.consume(key, reason: .refresh)
        progress.noteTraced(key, today: 107)
        expectNil(glance(.remind, .standard, learned: true, today: 108))
        // A stall puts it back to learning: the budget comes back.
        progress.reset(key)
        expectEqual(progress.remaining(key), 3)
        // Store: round trip, corrupt → empty, never throws.
        let suite = "strokeOrder.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = StrokeOrderProgressStore(defaults: defaults)
        progress.consume(key, reason: .budget)
        store.save(progress)
        expectEqual(store.load(), progress)
        defaults.set(Data("nope".utf8), forKey: StrokeOrderProgressStore.key)
        expectEqual(store.load(), StrokeOrderProgress())
        expectEqual(StrokeOrderProgressStore.key, "VisaGames.strokeOrderProgress.v1")
        // Settings: saved, and v0.30 data (no strokeOrder key) loads as 提.
        let settingsStore = TapCountSettingsStore(defaults: defaults)
        var settings = TapCountSettings.defaults
        settings.strokeOrder = .off
        settingsStore.save(settings)
        expectEqual(settingsStore.load().strokeOrder, .off)
        let old = #"{"range":5,"countVoice":false,"english":true,"badgeStyle":"ticks","traceScaffold":"outline","guidance":"more"}"#
        defaults.set(Data(old.utf8), forKey: TapCountSettingsStore.key)
        expectEqual(settingsStore.load().strokeOrder, .remind)
        expectEqual(settingsStore.load().guidance, .more)
        // Day numbers: local calendar days.
        let hk = TimeZone(identifier: "Asia/Hong_Kong")!
        let a = StrokeOrderProgress.day(clock: 0, timeZone: hk)
        expectEqual(StrokeOrderProgress.day(clock: 86_400 * 7, timeZone: hk) - a, 7)
    }

    // MARK: ★ plate (finish now, replay ≤ 2; never a miss)

    func testStarPlateTapFinishesAndReplays() {
        for kind in [ActivityKind.tapCountAll, .tapCountAllEnglish] {
            guard var board = countedBoard(8, kind: kind), let t = StrokeOrderTimeline.digit(8, dosage: .remind) else {
                expectTrue(false, "★ board"); continue
            }
            expectEqual(board.tapStrokeReveal(now: 10), .ignored, "no pen, nothing to tap")
            board.startStrokeReveal(dosage: .remind, duration: t.duration, startAt: 10.2)
            expectTrue(board.strokeReveal?.writing(now: 10.5) == true)
            expectEqual(board.tapStrokeReveal(now: 11), .finished)
            expectFalse(board.strokeReveal?.writing(now: 11.01) == true)
            expectEqual(board.strokeReveal?.endsAt(now: 11.01) ?? 0, 11, accuracy: 1e-9)
            expectEqual(board.tapStrokeReveal(now: 12), .replayed)
            expectEqual(board.strokeReveal?.endsAt(now: 12) ?? 0, 12 + t.duration, accuracy: 1e-9)
            expectEqual(board.tapStrokeReveal(now: 20), .replayed)
            expectEqual(board.tapStrokeReveal(now: 30), .ignored, "at most 2 replays")
            expectEqual(board.misses, 0)
            expectEqual(board.resultFields["stroke_reveal"], .string("remind"))
            expectEqual(board.resultFields["stroke_replays"], .int(2))
            expectEqual(board.resultFields["stroke_skips"], .int(1))
            board.finishWithoutTrace(now: 31)
            expectEqual(board.tapStrokeReveal(now: 31.5), .ignored, "no replay after the stamp starts")
        }
        // ★★ boards never get the plate pen (they trace).
        if var traced = countedBoard(8, kind: .tapCountTrace) {
            traced.startStrokeReveal(dosage: .remind, duration: 2, startAt: 0)
            expectNil(traced.strokeReveal)
        }
    }

    // MARK: ★★ glance (never with the car; a touch ends it)

    func testGlanceNeverPlaysWithTheCarAndATouchEndsIt() {
        for kind in [ActivityKind.tapCountTrace, .tapCountTraceEnglish] {
            guard var board = countedBoard(5, kind: kind), let glance = StrokeOrderTimeline.digit(5, dosage: .glance) else {
                expectTrue(false, "★★ board"); continue
            }
            board.startTracing(tolerance: .standard, guidance: TapCountGuidePlan(level: .standard, learned: true),
                               now: 100, demoLead: 1.4, glanceDuration: glance.duration)
            expectTrue(board.guide?.isGlance == true)
            expectTrue(board.guideDemoPending(now: 101))
            expectEqual(board.guide?.demosPlayed, 0, "no car")
            expectEqual(board.guide?.readyAt ?? 0, 101.4 + glance.duration, accuracy: 1e-9)
            expectTrue(board.skipGuideDemo(now: 101.5))
            expectFalse(board.guideDemoPending(now: 101.6))
            expectEqual(board.guide?.demoCode, "glance_skipped")
            expectNil(board.guide?.glanceEndedFor(now: 110))  // skipped → no ink fade
            expectTrue(board.guide?.clean == true, "a glance is not help")
            expectEqual(board.resultFields["stroke_glance"], .int(1))
            expectEqual(board.misses, 0)
        }
        // While learning (car demo), a glance duration is ignored: never both.
        if var board = countedBoard(5, kind: .tapCountTrace), let guide = NumeralGuide(5) {
            board.startTracing(tolerance: .standard, guidance: TapCountGuidePlan(level: .standard, learned: false),
                               now: 0, demoLead: 1.4, glanceDuration: 1.1)
            expectFalse(board.guide?.isGlance == true)
            expectEqual(board.guide?.demoDuration ?? 0, TapCountDemoTimeline(guide: guide).duration, accuracy: 1e-9)
        }
        // Played out: the child's turn starts when the pen is done; the 20 s re-demo is the car.
        if var board = countedBoard(4, kind: .tapCountTrace), let guide = NumeralGuide(4) {
            board.startTracing(tolerance: .standard, guidance: TapCountGuidePlan(level: .standard, learned: true),
                               now: 0, demoLead: 1.4, glanceDuration: 1.1)
            expectEqual(board.guide?.demoCode, "glance")
            expectEqual(board.guide?.glanceEndedFor(now: 3.0) ?? -1, 0.5, accuracy: 1e-9)
            var run = board.guide!
            run.restartDemo(now: 30, lead: 1.4)
            expectFalse(run.isGlance)
            expectEqual(run.demoDuration, TapCountDemoTimeline(guide: guide).duration, accuracy: 1e-9)
        }
    }

    // MARK: Source guards

    func testStrokeOrderSourceGuards() throws {
        let core = try source("Sources/VisaCore/StrokeOrder.swift")
        let drawing = try source("Sources/VisaGames/StrokeOrderDrawing.swift")
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let parent = try source("Sources/VisaGames/ParentTapCountSettingsView.swift")
        for text in [core, drawing] {
            for banned in ["assumeIsolated", "unowned", "addObserver", "NSWindow", "presentationOptions", "styleMask",
                           ".level = .", "NSMenu", "toggleFullScreen", "setFrame", "AVSpeech", "speak("] {
                expectFalse(text.contains(banned), "banned \(banned) in stroke-order code")
            }
        }
        // No Simplified Chinese in the parent copy.
        let copy = [StrokeOrderCopy.title] + StrokeOrderSetting.allCases.flatMap { [StrokeOrderCopy.short($0), StrokeOrderCopy.detail($0)] }
        for simplified in ["笔", "顺", "画", "动", "数", "认", "识", "练", "习", "边", "时", "这", "们", "写", "关", "开"] {
            expectFalse(copy.joined().contains(simplified), "simplified \(simplified)")
        }
        expectEqual(StrokeOrderCopy.short(.teach) + StrokeOrderCopy.short(.remind) + StrokeOrderCopy.short(.off), "教提熄")
        expectTrue(model.contains("strokeOrderProgressStore.save"))
        expectTrue(model.contains("setTapCountStrokeOrder"))
        expectTrue(model.contains("guard !tapCountUsesPlaytest else { return }"), "playtests never use up glances")
        expectTrue(parent.contains("onStrokeOrder"))
        expectTrue(drawing.contains("reduceMotion"))
    }
}
