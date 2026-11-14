import Foundation
import VisaCore

/// Hanzi H4 parent and reporting (0.40.0 / 88): design hanzi-tap v2 § Parent settings, § 教／提／熄 (two settings must
/// remain separate), the Parent rows of § Child and parent copy, the reporting paragraph of § Engineering reuse and
/// the H4 row of § H0–H5 build slices. Offline: reads the bundled pack, the Traditional-only fixture and the app
/// source (SwiftUI / AppKit are not built on this box). H4.1 (0.40.1 / 89, Carter's 2026-11-14 answers): (15)–(17)
/// the 寫字格 setting, its lines and the write board's wiring; (18) 中文字 in the weekly area suggestions.
final class HanziParentTests {
    private static let week = ["人", "上", "下", "左", "右", "木"]
    private static let findOnly = ["入", "八", "本", "未"]
    private static let packURL = URL(fileURLWithPath: "Resources/HanziTap/hanzi-pack.json")
    /// 熄 (U+7184), written as an escape so no test source carries the character either.
    private static let xi = "\u{7184}"
    private static let now = PerfCodec.parseTimestamp("2026-11-12T02:00:00.000Z")!  // 10:00 HKT
    private var seq = 0

    private func loadPack() throws -> HanziPack { try HanziPack.load(url: Self.packURL) }

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

    // MARK: (1) Persistence and the defaults (games and jyutping OFF, audio ON)

    /// (1) `VisaGames.tapHanziSettings.v1` round-trips every row; missing or invalid settings load the defaults
    /// (pack week, 廣東話語音 ON since Carter's 2026-11-13 override of D4's audio default, jyutping OFF, 標準), and both
    /// games stay OFF on every star until their own playtest.
    func testSettingsPersistAndFallBackToDefaultsWithAudioOn() throws {
        let pack = try loadPack()
        let defaults = UserDefaults(suiteName: "VisaGames.hanziParent.\(UUID().uuidString)")!
        let store = HanziTapSettingsStore(defaults: defaults)
        func expectDefaults(_ value: HanziTapSettings, _ label: String) {
            expectEqual(value, .defaults, label)
            expectEqual(value.validWeek(in: pack), Self.week, label)
            expectTrue(value.audioEnabled, label)
            expectFalse(value.jyutpingEnabled, label)
            expectEqual(value.guidance, .standard, label)
            expectEqual(value.reviewEvery, 4, label)
            expectTrue(value.confusableGuard, label)
            expectEqual(value.grid, .mizi, label)
        }
        expectDefaults(store.load(), "missing")
        expectEqual(pack.defaults.guideLevel, HanziTapSettings.defaults.guidance)
        expectTrue(pack.defaults.audioEnabled && HanziTapSettings.defaults.audioEnabled)
        expectFalse(pack.defaults.findEnabled || pack.defaults.writeEnabled || pack.defaults.jyutpingEnabled)
        // 寫字格: the pack mirrors the settings' 米字格 default (H4.1, Carter 2026-11-14 over D3's 田字格).
        expectEqual(pack.defaults.grid, HanziTapSettings.defaults.grid.rawValue)
        expectTrue(pack.defaults.miziGridEnabled)
        expectEqual(pack.defaults.strokeOrder, "inheritExisting")

        // Every row a parent can save round-trips, each away from its default (廣東話語音 OFF, 田字格), the new 描字提示
        // level included.
        for guidance in TapCountGuidanceLevel.allCases {
            let chosen = HanziTapSettings(week: ["上", "下", "木"], reviewEvery: 0, confusableGuard: false,
                                          audioEnabled: false, jyutpingEnabled: true, guidance: guidance, grid: .tianzi)
            store.save(chosen)
            expectEqual(store.load(), chosen, guidance.rawValue)
        }
        func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
        // A v1 blob from before H4 has no `guidance`: it keeps its values (廣東話語音 OFF stays OFF) and reads 標準.
        let h1: [String: Any] = ["schemaVersion": 1, "week": ["左", "右", "木"], "reviewEvery": 0, "confusableGuard": false,
                                 "audioEnabled": false, "jyutpingEnabled": true]
        defaults.set(json(h1), forKey: HanziTapSettingsStore.key)
        expectEqual(store.load(), HanziTapSettings(week: ["左", "右", "木"], reviewEvery: 0, confusableGuard: false,
                                                   audioEnabled: false, jyutpingEnabled: true, guidance: .standard))
        var withLevel = h1
        withLevel["guidance"] = "less"
        defaults.set(json(withLevel), forKey: HanziTapSettingsStore.key)
        expectEqual(store.load().guidance, .less)
        var nullLevel = h1
        nullLevel["guidance"] = NSNull()
        defaults.set(json(nullLevel), forKey: HanziTapSettingsStore.key)
        expectEqual(store.load(), HanziTapSettings(week: ["左", "右", "木"], reviewEvery: 0, confusableGuard: false,
                                                   audioEnabled: false, jyutpingEnabled: true, guidance: .standard),
                    "null reads as missing")
        // An unknown or mistyped level, like any bad H1 field, loads the defaults (never a half-read value).
        var bad: [(String, Data)] = [("corrupt", Data("{\"schemaVersion\":1,".utf8)), ("empty", Data())]
        let levels: [(String, Any)] = [("teach", "teach"), ("off", "off"), ("number", 2), ("Standard", "Standard")]
        for (label, value) in levels {
            var object = withLevel
            object["guidance"] = value
            bad.append(("guidance \(label)", json(object)))
        }
        for key in ["audioEnabled", "jyutpingEnabled", "week", "schemaVersion"] {
            var object = withLevel
            object.removeValue(forKey: key)
            bad.append(("no \(key)", json(object)))
        }
        var future = withLevel
        future["schemaVersion"] = 2
        bad.append(("schema 2", json(future)))
        for (label, data) in bad {
            defaults.set(data, forKey: HanziTapSettingsStore.key)
            expectDefaults(store.load(), label)
        }
        // The stored blob holds exactly the Hanzi rows: no stroke-order or letter / number field.
        store.save(.defaults)
        let saved = try JSONSerialization.jsonObject(with: defaults.data(forKey: HanziTapSettingsStore.key)!) as! [String: Any]
        expectEqual(saved.keys.sorted(), ["audioEnabled", "confusableGuard", "grid", "guidance", "jyutpingEnabled",
                                          "reviewEvery", "schemaVersion", "week"])
        expectEqual(saved["guidance"] as? String, "standard")
        expectEqual(saved["grid"] as? String, "mizi")

        // Both games OFF: no star on a fresh or unreadable assignment, and none before each card's own playtest.
        let assignments = UserDefaults(suiteName: "VisaGames.hanziParent.assign.\(UUID().uuidString)")!
        assignments.set(Data("not json".utf8), forKey: MissionGameAssignmentStore.key)
        for assignment in [MissionGameAssignment.defaults, MissionGameAssignmentStore(defaults: assignments).load()] {
            for kind in [ActivityKind.tapHanziAll, .tapHanziWrite] {
                expectTrue(assignment.isHiddenFromMissions(kind), kind.rawValue)
                for star in ChildDifficulty.allCases { expectFalse(assignment.pool(for: star).contains(kind), kind.rawValue) }
            }
        }
        expectFalse(ParentPlaytestLog().allowsStars(for: .tapHanziAll))
        expectFalse(ParentPlaytestLog().allowsStars(for: .tapHanziWrite))
        print("  hanzi parent: settings round-trip + H1 blob + \(bad.count) fallbacks, games / jyutping OFF, audio ON")
    }

    // MARK: (2) 今星期 editor

    /// (2) The draft edits a copy; 今星期 never drops below `HanziScheduler.minimumWeek` (3) and never takes a find-only
    /// glyph, and the saved week is what the scheduler deals.
    func testWeekEditorKeepsThreeTargetsAndNeverFindOnly() throws {
        let pack = try loadPack()
        expectEqual(HanziScheduler.minimumWeek, 3)
        var draft = HanziSettingsDraft(saved: .defaults)
        expectEqual(draft.week(in: pack), Self.week)
        expectFalse(draft.hasChanges)
        for glyph in Self.findOnly + ["大", "a", "", "人人", "hanzi:人"] {
            expectEqual(draft.toggleWeek(glyph, in: pack), .notATarget, glyph)
            expectEqual(draft.value, .defaults, glyph)
        }
        expectEqual(draft.toggleWeek("木", in: pack), .updated)
        expectEqual(draft.value.week, ["人", "上", "下", "左", "右"])
        expectTrue(draft.hasChanges)
        draft.toggleWeek("右", in: pack)
        draft.toggleWeek("左", in: pack)
        expectEqual(draft.week(in: pack), ["人", "上", "下"])
        for glyph in ["人", "上", "下"] {
            expectEqual(draft.toggleWeek(glyph, in: pack), .belowMinimum, glyph)
            expectEqual(draft.week(in: pack), ["人", "上", "下"], glyph)
        }
        draft.toggleWeek("木", in: pack)
        expectEqual(draft.value.week, ["人", "上", "下", "木"], "pack order")
        draft.toggleWeek("左", in: pack)
        draft.toggleWeek("右", in: pack)
        expectEqual(draft.value.week, [], "the saved (pack) week again is no change")
        expectFalse(draft.hasChanges)
        draft.toggleWeek("人", in: pack)
        draft.revert()
        expectEqual(draft.value, .defaults)

        // Every week of three or more targets: a toggle never leaves fewer than three, never adds a non-target.
        var weeks = 0
        for mask in 0..<64 {
            let chosen = Self.week.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            guard chosen.count >= 3 else { continue }
            weeks += 1
            for glyph in Self.week + Self.findOnly {
                var edit = HanziSettingsDraft(saved: HanziTapSettings(week: chosen))
                let result = edit.toggleWeek(glyph, in: pack)
                let after = edit.week(in: pack)
                expectTrue(after.count >= 3 && Set(after).isSubset(of: Self.week), "\(chosen) \(glyph)")
                if Self.findOnly.contains(glyph) { expectEqual(result, .notATarget) }
                else if chosen.count == 3 && chosen.contains(glyph) { expectEqual(result, .belowMinimum) }
                else { expectEqual(result, .updated) }
            }
        }
        expectEqual(weeks, 42)

        // Saved through the store, the week is what the scheduler deals.
        var edit = HanziSettingsDraft(saved: .defaults)
        for glyph in ["人", "右", "木"] { edit.toggleWeek(glyph, in: pack) }
        let defaults = UserDefaults(suiteName: "VisaGames.hanziParent.week.\(UUID().uuidString)")!
        let store = HanziTapSettingsStore(defaults: defaults)
        store.save(edit.value)
        edit.acceptSaved(store.load())
        expectFalse(edit.hasChanges)
        expectEqual(store.load().validWeek(in: pack), ["上", "下", "左"])
        var progress = HanziProgress()
        var dealt: [String] = []
        for n in 1...12 {
            let choice = HanziScheduler.next(seed: "week-\(n)", n: n, settings: store.load(), progress: progress, pack: pack,
                                             now: Self.now)
            dealt.append(choice.target)
            progress.record(choice, clean: true, round: n, at: Self.now)
        }
        expectEqual(Set(dealt), ["上", "下", "左"])
        print("  hanzi parent: week editor over \(weeks) weeks, minimum 3, no find-only, scheduler deals the saved week")
    }

    // MARK: (3) Coach vs reveal

    /// (3) 描字提示 is Hanzi's own coach level (`HanziTapSettings.guidance`, `TapCountGuidanceLevel`); 筆順動畫 is the existing
    /// `StrokeOrderSetting`, shown and never written; neither enum is migrated.
    func testCoachLevelIsHanzisOwnAndTheRevealStaysSeparate() throws {
        expectEqual(TapCountGuidanceLevel.allCases.map(\.rawValue), ["more", "standard", "less"])
        expectEqual(StrokeOrderSetting.allCases.map(\.rawValue), ["teach", "remind", "off"])
        var draft = HanziSettingsDraft(saved: .defaults)
        draft.setGuidance(.less)
        expectEqual(draft.value.guidance, .less)
        var rest = draft.value
        rest.guidance = .standard
        expectEqual(rest, .defaults, "only the coach level changed")
        draft.setReviewEvery(3)
        expectEqual(draft.value.reviewEvery, 4, "only 4 or none")
        draft.setReviewEvery(0)
        expectEqual(draft.value.reviewEvery, 0)
        // The count / letter settings keep their own level and reveal.
        expectEqual(TapCountSettings.defaults.guidance, .standard)
        expectEqual(TapCountSettings.defaults.strokeOrder, .remind)

        // Each detail line is what the coach does at that level (TapCountGuidePlan, shared with numbers and letters).
        let more = TapCountGuidePlan(level: .more, learned: true)
        expectTrue(more.demo, "次次先睇示範")
        expectEqual(more.stallSeconds, 1.0)
        let standard = TapCountGuidePlan(level: .standard, learned: false)
        let standardLearned = TapCountGuidePlan(level: .standard, learned: true)
        expectEqual(standard.stallSeconds, 2.0)
        expectTrue(standard.demo && !standardLearned.demo)
        expectTrue(standardLearned.features.count < standard.features.count, "識寫咗就收少啲提示")
        let less = TapCountGuidePlan(level: .less, learned: false)
        expectFalse(less.demo || less.headlights || less.cueSigns, "收起路牌同頭燈")
        expectNil(less.stallSeconds)
        expectEqual(less.ghostToEndSeconds, 8.0, "卡住 8 秒仲有影子車")

        // App wiring: the write round takes Hanzi's level; the plaque reveal keeps the existing stroke-order setting.
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let begin = body(of: "private func beginTapHanziWriting(", in: model)
        expectTrue(begin.contains("TapCountGuidePlan(level: hanziSettings.guidance, learned: learned)"))
        expectFalse(begin.contains("tapCountSettings"), "the Hanzi write never reads the letter / number level")
        let reveal = body(of: "private func startTapHanziStrokeReveal(", in: model)
        expectTrue(reveal.contains("StrokeOrderPlan.star1(setting: tapCountSettings.strokeOrder"))
        let save = body(of: "func saveHanziSettings(", in: model)
        expectFalse(save.isEmpty)
        expectFalse(save.contains("tapCountSettings") || save.contains("strokeOrder"))
        let view = try source("Sources/VisaGames/ParentTapHanziSettingsView.swift")
        expectTrue(view.contains("HanziParentCopy.strokeOrderNow(model.tapCountSettings.strokeOrder)"))
        for writer in ["setTapCountGuidance", "setTapCountStrokeOrder", "tapCountSettings.guidance", "TapCountSettingsStore",
                       "StrokeOrderSetting."] {
            expectFalse(view.contains(writer), writer)
        }
        expectTrue(view.contains("$0.setGuidance(label.level)"))
        print("  hanzi parent: coach level Hanzi-only, plans 1 / 2 / 8 s, reveal read from the existing setting")
    }

    // MARK: (4) The one label table

    /// (4) D9 is Carter's open decision: the labels ship as the app's current 多啲／標準／少啲 for this enum, from one
    /// table, with D9's detail lines; no label carries 熄.
    func testCoachLabelTableIsTheOnePlaceAndShipsTodaysLabels() throws {
        let labels = HanziParentCopy.coachLabels
        expectEqual(labels.map(\.level), [.more, .standard, .less])
        expectEqual(labels.map(\.short), ["多啲", "標準", "少啲"])
        for level in TapCountGuidanceLevel.allCases {
            expectEqual(HanziParentCopy.coach(level).level, level)
            expectEqual(HanziParentCopy.coach(level).short, TapCountGuideData.copy.parent.short(level))
            expectEqual(HanziParentCopy.coach(level).short, LetterGuideData.copy.parent.short(level))
        }
        expectEqual(labels.map(\.detail), ["次次先睇示範；卡住 1 秒就幫。", "卡住 2 秒就幫；識寫咗就收少啲提示。",
                                           "收起路牌同頭燈；卡住 8 秒仲有影子車。"])
        expectEqual(TapCountGuidanceLevel.allCases.map(HanziParentCopy.coachLine), [
            "多啲：次次先睇示範；卡住 1 秒就幫。", "標準（預設）：卡住 2 秒就幫；識寫咗就收少啲提示。",
            "少啲：收起路牌同頭燈；卡住 8 秒仲有影子車。"])
        expectEqual(HanziParentCopy.coachDefault, HanziTapSettings.defaults.guidance)
        expectEqual(labels.map(\.english), ["More: a demo every time; help after 1 s",
                                            "Standard: help after 2 s; less help once learned",
                                            "Less: no signs or headlights; a ghost car still helps after 8 s"])
        for label in labels {
            for text in [label.short, label.detail, label.english, HanziParentCopy.coachLine(label.level)] {
                expectFalse(text.contains(Self.xi), text)
            }
        }
        // One place: each label is written once in Sources/VisaCore/HanziParent.swift, and the parent view
        // takes them from the table.
        let copy = try source("Sources/VisaCore/HanziParent.swift")
        for short in ["\"多啲\"", "\"標準\"", "\"少啲\""] { expectEqual(count(short, in: copy), 1, short) }
        let view = try source("Sources/VisaGames/ParentTapHanziSettingsView.swift")
        expectTrue(view.contains("ForEach(HanziParentCopy.coachLabels, id: \\.short)"))
        expectTrue(view.contains("HanziParentCopy.coachLine(draft.value.guidance)"))
        for literal in ["多啲", "標準", "少啲", "教", "提示"] { expectFalse(view.contains("\"\(literal)"), literal) }
        for file in ["Sources/VisaCore/HanziParent.swift", "Sources/VisaCore/HanziReport.swift",
                     "Sources/VisaGames/ParentTapHanziSettingsView.swift", "Sources/VisaGames/ParentGameCard.swift",
                     "Sources/VisaGames/LetterUnavailableTicketView.swift"] {
            expectFalse(try source(file).contains(Self.xi), file)
        }
        print("  hanzi parent: one coach label table 多啲／標準／少啲 with D9 detail lines, no off-word glyph")
    }

    // MARK: (5) Report fixtures

    private func ev(_ type: PerfEventType, _ fields: [String: PerfValue], daysAgo: Int = 0, actor: PerfActor = .child,
                    session: String = "s1") -> PerfEvent {
        seq += 1
        let at = Self.now.addingTimeInterval(-Double(daysAgo) * 86_400 - 3600 + Double(seq) * 0.5)
        return PerfEvent(type: type, timestamp: at, tz: "+08:00", mono: Double(seq), launch: "L1", seq: seq, app: "0.40.0",
                         actor: actor, mode: "lock", session: session, fields: fields)
    }

    /// One Hanzi round as the app records it: `game_dealt` (target), an `answer_attempt` per tap (`glyph`), then
    /// `round_result` with the find fields and, for 搵完寫, the write fields.
    private func hanziRound(_ kind: ActivityKind, target: String, taps: [String], outcome: String = "solved",
                            write: [String: PerfValue] = [:], daysAgo: Int = 0, actor: PerfActor = .child,
                            session: String = "s1") -> [PerfEvent] {
        seq += 1
        let id = "h\(seq)"
        var events = [ev(.gameDealt, ["round": .string(id), "kind": .string(kind.rawValue), "stars": .int(1),
                                      "target": .string(target), "glyph": .string("hanzi:\(target)"),
                                      "match_mode": .string("test")], daysAgo: daysAgo, actor: actor, session: session)]
        for (index, glyph) in taps.enumerated() {
            events.append(ev(.answerAttempt, ["round": .string(id), "kind": .string(kind.rawValue),
                                              "choice": .string("card-\(index)"), "correct": .bool(glyph == target),
                                              "glyph": .string(glyph), "tags": .strings([])],
                             daysAgo: daysAgo, actor: actor, session: session))
        }
        let misses = taps.filter { $0 != target }.count
        var result: [String: PerfValue] = ["round": .string(id), "kind": .string(kind.rawValue), "outcome": .string(outcome),
                                           "answers": .int(taps.count), "misses": .int(misses),
                                           "first_try": .bool(misses == 0 && outcome == "solved"),
                                           "glyph": .string("hanzi:\(target)")]
        result.merge(write) { _, new in new }
        events.append(ev(.roundResult, result, daysAgo: daysAgo, actor: actor, session: session))
        return events
    }

    private func writeFields(clean: Bool, wrongStart: Int, reverse: Int, offPath: Int, stalls: Int, ghosts: Int,
                             redemos: Int) -> [String: PerfValue] {
        ["write_clean": .bool(clean), "wrong_start": .int(wrongStart), "reverse": .int(reverse), "off_path": .int(offPath),
         "guide_stalls": .int(stalls), "guide_ghost_to_end": .int(ghosts), "guide_redemos": .int(redemos),
         "lifts": .int(9), "corner_overshoot": .int(4), "strokes_drawn": .int(5), "guide_level": .string("standard")]
    }

    /// (5) Finding errors (first-try recognition, wrong cards, confusion pairs) and writing help (trace_clean /
    /// trace_assisted / wrong_start / reverse / stall / ghost / redemo) are separate tallies of recorded events
    /// only; no events → no numbers.
    func testReportKeepsFindingErrorsApartFromWritingHelp() throws {
        let pack = try loadPack()
        // Nothing recorded: no report and one empty line, never an example number.
        expectEqual(HanziReportBuilder.build(events: [], pack: pack, now: Self.now, window: .days30), [:])
        expectEqual(PerfReportBuilder.build(events: [], rollup: PerfRollup(), videos: [], now: Self.now, window: .all,
                                            hanziPack: pack).hanzi, [:])
        for kind in [ActivityKind.tapHanziAll, .tapHanziWrite] {
            expectEqual(HanziReportText.lines(nil, kind: kind), [HanziParentCopy.reportEmpty])
            expectEqual(HanziReportText.lines(HanziKindReport(), kind: kind), [HanziParentCopy.reportEmpty])
        }
        expectEqual(HanziReportText.lines(nil, kind: .tapLetterAll), [])

        var events: [PerfEvent] = []
        events += hanziRound(.tapHanziAll, target: "上", taps: ["下", "上", "上"])
        // A 翻字卡 result never brings writing, even if a field of that name appeared.
        events += hanziRound(.tapHanziAll, target: "上", taps: ["上", "上"], write: ["write_clean": .bool(false)])
        events += hanziRound(.tapHanziAll, target: "人", taps: ["入", "木", "人", "人"])
        events += hanziRound(.tapHanziAll, target: "右", taps: ["左", "右", "右"], actor: .parentPlaytest)
        events += hanziRound(.tapHanziAll, target: "左", taps: ["左", "左"], session: "sx")
        events.append(ev(.statsExclude, ["target_session": .string("sx")]))
        events += hanziRound(.tapHanziAll, target: "下", taps: ["下", "下"], daysAgo: 40)
        // A find-only glyph is never a target row (D2).
        events += hanziRound(.tapHanziAll, target: "入", taps: ["入", "入"])
        events += hanziRound(.tapHanziWrite, target: "右", taps: ["右", "右"],
                             write: writeFields(clean: false, wrongStart: 2, reverse: 1, offPath: 1, stalls: 3, ghosts: 1,
                                                redemos: 1))
        events += hanziRound(.tapHanziWrite, target: "右", taps: ["左", "右", "右"],
                             write: writeFields(clean: true, wrongStart: 0, reverse: 0, offPath: 0, stalls: 0, ghosts: 0,
                                                redemos: 0))
        events += hanziRound(.tapHanziWrite, target: "木", taps: ["木", "木"], outcome: "abandoned")
        events += hanziRound(.tapHanziWrite, target: "左", taps: ["左", "左"],
                             write: writeFields(clean: false, wrongStart: 5, reverse: 5, offPath: 5, stalls: 5, ghosts: 5,
                                                redemos: 5), actor: .parentPlaytest)

        let reports = HanziReportBuilder.build(events: events, pack: pack, now: Self.now, window: .days30)
        expectEqual(Set(reports.keys), [.tapHanziAll, .tapHanziWrite])
        var ren = HanziFindingRow(glyph: "人")
        ren.rounds = 1
        ren.wrongCards = 2
        ren.confusions = ["入": 1]
        var shang = HanziFindingRow(glyph: "上")
        shang.rounds = 2
        shang.firstTry = 1
        shang.wrongCards = 1
        shang.confusions = ["下": 1]
        expectEqual(reports[.tapHanziAll], HanziKindReport(finding: [ren, shang], writing: []))
        var you = HanziFindingRow(glyph: "右")
        you.rounds = 2
        you.firstTry = 1
        you.wrongCards = 1
        you.confusions = ["左": 1]
        // 木: both cards flipped with no wrong card, then the write was left (round_result abandoned, first_try false):
        // a first-try find all the same (fix1), and no write.
        var mu = HanziFindingRow(glyph: "木")
        mu.rounds = 1
        mu.firstTry = 1
        var youWrite = HanziWritingRow(glyph: "右")
        youWrite.writes = 2
        youWrite.clean = 1
        youWrite.assisted = 1
        youWrite.wrongStarts = 2
        youWrite.reverses = 1
        youWrite.offPath = 1
        youWrite.stalls = 3
        youWrite.ghosts = 1
        youWrite.redemos = 1
        expectEqual(reports[.tapHanziWrite], HanziKindReport(finding: [you, mu], writing: [youWrite]))
        // Writing help is not a finding miss: 右's two wrong starts, reversal, stalls, ghost and re-demo leave its
        // finding at one wrong card (the 左 tap).
        expectEqual(reports[.tapHanziWrite]?.finding.first?.wrongCards, 1)

        // Each count line is Cantonese, then English (fix1).
        expectEqual(HanziReportText.lines(reports[.tapHanziAll], kind: .tapHanziAll), [
            HanziParentCopy.reportTitle, HanziParentCopy.reportFinding,
            "人：1 局 · 第一次就搵啱 0 局 · 搵錯 2 張（易混：入 1 張）\n人: rounds 1 · found first time 0 · wrong cards 2 (look-alikes: 入 1)",
            "上：2 局 · 第一次就搵啱 1 局 · 搵錯 1 張（易混：下 1 張）\n上: rounds 2 · found first time 1 · wrong cards 1 (look-alikes: 下 1)"])
        expectEqual(HanziReportText.lines(reports[.tapHanziWrite], kind: .tapHanziWrite), [
            HanziParentCopy.reportTitle, HanziParentCopy.reportFinding,
            "右：2 局 · 第一次就搵啱 1 局 · 搵錯 1 張（易混：左 1 張）\n右: rounds 2 · found first time 1 · wrong cards 1 (look-alikes: 左 1)",
            "木：1 局 · 第一次就搵啱 1 局 · 搵錯 0 張\n木: rounds 1 · found first time 1 · wrong cards 0",
            HanziParentCopy.reportWriting,
            "右：寫咗 2 次 · 冇提示寫完 1 · 有提示 1 · 起點錯 2 · 倒轉 1 · 出線 1 · 停咗 3 · 影子車 1 · 再示範 1\n"
                + "右: writes 2 · without help 1 · with help 1 · wrong starts 2 · reversed 1 · off path 1 · stalls 3 · "
                + "ghost car 1 · re-demos 1",
            HanziParentCopy.reportStrokeSkip])
        var pair = HanziFindingRow(glyph: "木")
        pair.rounds = 3
        pair.confusions = ["未": 2, "本": 1]
        expectEqual(HanziReportText.lines(HanziKindReport(finding: [pair]), kind: .tapHanziAll).last,
                    "木：3 局 · 第一次就搵啱 0 局 · 搵錯 0 張（易混：未 2 張、本 1 張）\n"
                        + "木: rounds 3 · found first time 0 · wrong cards 0 (look-alikes: 未 2, 本 1)")
        let noWrites = HanziKindReport(finding: [mu], writing: [])
        expectEqual(Array(HanziReportText.lines(noWrites, kind: .tapHanziWrite).suffix(3)),
                    [HanziParentCopy.reportWriting, HanziParentCopy.reportNoWrites, HanziParentCopy.reportStrokeSkip])

        // The 40-day-old 下 round counts only in 全部; a find-only glyph never has a row in either window.
        let all = HanziReportBuilder.build(events: events, pack: pack, now: Self.now, window: .all)
        expectEqual(all[.tapHanziAll]?.finding.map(\.glyph), ["人", "上", "下"])
        for report in Array(reports.values) + Array(all.values) {
            let glyphs = report.finding.map(\.glyph) + report.writing.map(\.glyph)
            expectTrue(Set(glyphs).isSubset(of: Self.week) && !glyphs.contains { Self.findOnly.contains($0) }, "\(glyphs)")
        }
        // The same report rides on the 表現 report with the same filter and window. The generic 搵完寫 row keeps the
        // tracker's round-level `first_try` (solved with no wrong card): 3 answered rounds, 1 first try, the abandoned
        // 木 round not one of them; the finding rows above count the find alone (右 1 + 木 1).
        let review = PerfReportBuilder.build(events: events, rollup: PerfRollup(), videos: [], now: Self.now,
                                             window: .days30, hanziPack: pack)
        expectEqual(review.hanzi, reports)
        let write = review.games.first { $0.kind == .tapHanziWrite }
        expectEqual(write?.answered, 3)
        expectEqual(write?.firstTry, 1)
        expectEqual(PerfReportBuilder.build(events: events, rollup: PerfRollup(), videos: [], now: Self.now,
                                            window: .days30).hanzi, [:], "no pack, no Hanzi report")
        print("  hanzi parent: report fixtures — finding 人 上 / 右 木, writing 右 only, playtest, excluded and old rounds out")
    }

    // MARK: (6) Weekly and catalogue areas

    /// (6) Both kinds report under 「中文字」 / "Chinese characters" (no longer 其他); the catalogue keeps ten cards.
    func testWeeklyAndCatalogueRegisterBothHanziKinds() throws {
        expectEqual(WeeklyArea.allCases, [.numbers, .matching, .comparing, .pen, .letters, .hanzi, .other])
        expectEqual(WeeklyArea.hanzi.rawValue, "hanzi")
        expectEqual([WeeklyArea.hanzi.zh, WeeklyArea.hanzi.en], ["中文字", "Chinese characters"])
        expectEqual(WeeklyArea.of(kind: ActivityKind.tapHanziAll.rawValue), .hanzi)
        expectEqual(WeeklyArea.of(kind: ActivityKind.tapHanziWrite.rawValue), .hanzi)
        expectEqual(WeeklyArea.of(kind: ActivityKind.tapLetterAll.rawValue), .letters)
        expectEqual(WeeklyArea.of(kind: "mysteryQuiz"), .other)
        for kind in ActivityKind.allCases { expectTrue(WeeklyArea.of(kind: kind.rawValue) != .other, kind.rawValue) }
        for kind in [ActivityKind.tapHanziAll, .tapHanziWrite] {
            expectEqual(PerfChoiceCatalog.chance(for: kind), 1.0 / 45.0)
            expectEqual(PerfChoiceCatalog.slots(kind: kind, seed: "x"), (0..<10).map { "card-\($0)" })
            expectEqual(PerfChoiceCatalog.allChoices(for: kind), (0..<10).map { "card-\($0)" })
            expectNil(PerfChoiceCatalog.correctChoice(for: kind))
        }
        // A week with one round of each card: both rows and the 中文字 area count them; nothing lands in 其他.
        let monday = PerfCodec.parseTimestamp("2026-11-09T04:00:00.000Z")!
        var events: [PerfEvent] = []
        for (offset, kind) in [ActivityKind.tapHanziAll, .tapHanziWrite].enumerated() {
            seq += 1
            let id = "wk\(seq)"
            let at = monday.addingTimeInterval(Double(offset) * 600)
            events.append(PerfEvent(type: .gameDealt, timestamp: at, tz: "+08:00", mono: Double(seq), launch: "L1", seq: seq,
                                    app: "0.40.0", actor: .child, mode: "lock", session: "s1",
                                    fields: ["round": .string(id), "kind": .string(kind.rawValue), "stars": .int(1),
                                             "match_mode": .string("test"), "target": .string("上")]))
            seq += 1
            events.append(PerfEvent(type: .roundResult, timestamp: at.addingTimeInterval(40), tz: "+08:00",
                                    mono: Double(seq), launch: "L1", seq: seq, app: "0.40.0", actor: .child, mode: "lock",
                                    session: "s1",
                                    fields: ["round": .string(id), "kind": .string(kind.rawValue), "outcome": .string("solved"),
                                             "answers": .int(2), "first_try": .bool(offset == 0), "misses": .int(offset),
                                             "total_ms": .int(40_000), "active_ms": .int(9_000), "earned_min": .int(5)]))
        }
        let week = WeeklyMetricsBuilder.build(events: events, rollup: PerfRollup(),
                                              window: WeeklyWindow(containing: monday)).current
        expectEqual(week.kinds.filter { $0.kind.hasPrefix("tapHanzi") }.map(\.area), [.hanzi, .hanzi])
        expectEqual(week.areas[.hanzi]?.rounds, 2)
        expectEqual(week.areas[.hanzi]?.answered, 2)
        expectEqual(week.areas[.hanzi]?.firstTry, 1)
        expectEqual(week.areas[.other]?.rounds ?? 0, 0)
        print("  hanzi parent: weekly area 中文字 for both kinds, catalogue 10 cards at 1/45")
    }

    // MARK: (7) Copy audit

    /// (7) Every new parent, report and ticket line is HK Traditional (both lists and the OpenCC fixture), with no
    /// unfilled placeholder; the new sources carry no Simplified-only character at all.
    func testNewCopyIsHongKongTraditional() throws {
        let fixture = URL(fileURLWithPath: "Tests/VisaCoreTests/Fixtures/traditional-check/simplified-only.txt")
        let simplified = Set(try String(contentsOf: fixture, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") }.joined().filter { !$0.isWhitespace })
        expectTrue(simplified.count > 100)
        typealias Copy = HanziParentCopy
        var lines = [Copy.coachTitle, Copy.coachEnglish, Copy.coachScope, Copy.coachScopeEnglish, Copy.defaultMark,
                     Copy.settingsTitle, Copy.settingsSubtitle, Copy.defaultOff, Copy.defaultOffEnglish, Copy.weekTitle,
                     Copy.weekEnglish, Copy.weekDetail, Copy.weekDetailEnglish, Copy.weekMinimum, Copy.weekMinimumEnglish,
                     Copy.findOnlyTitle, Copy.findOnlyEnglish, Copy.findOnlyDetail, Copy.findOnlyDetailEnglish,
                     Copy.reviewTitle, Copy.reviewEnglish, Copy.reviewOn, Copy.reviewOnEnglish, Copy.reviewOffEnglish,
                     Copy.guardTitle, Copy.guardEnglish, Copy.guardDetail, Copy.gridTitle, Copy.gridEnglish, Copy.gridTianzi,
                     Copy.gridTianziEnglish, Copy.gridMizi, Copy.gridMiziEnglish, Copy.strokeOrderTitle,
                     Copy.strokeOrderEnglish, Copy.strokeOrderNowEnglish, Copy.strokeOrderWhere, Copy.strokeOrderWhereEnglish,
                     Copy.jyutpingTitle, Copy.jyutpingEnglish, Copy.jyutpingDetail, Copy.audioTitle, Copy.audioEnglish,
                     Copy.audioDetail, Copy.saveNote, Copy.saveNoteEnglish, Copy.packUnavailable, Copy.cardDefaultOff,
                     Copy.starsLocked, Copy.reportTitle, Copy.reportFinding, Copy.reportWriting, Copy.reportEmpty,
                     Copy.reportNoWrites, Copy.reportStrokeSkip]
        lines += [true, false].flatMap { [Copy.status(hasChanges: $0), Copy.statusEnglish(hasChanges: $0)] }
        lines += StrokeOrderSetting.allCases.map(Copy.strokeOrderNow)
        lines += Copy.coachLabels.flatMap { [$0.short, $0.detail, $0.english, Copy.coachLine($0.level)] }
        // H4.1: the 寫字格 detail lines (the 「米字格：呢個版本未有。」 note and its English are gone).
        lines += HanziWritingGrid.allCases.flatMap { [Copy.gridLine($0), Copy.gridLineEnglish($0)] }
        for kind in [ActivityKind.tapHanziAll, .tapHanziWrite] {
            lines += [Copy.suggestedStar(kind) ?? "missing", Copy.cardDetail(kind) ?? "missing"]
        }
        expectNil(Copy.suggestedStar(.tapLetterAll))
        expectNil(Copy.cardDetail(.findTheSame))
        for kinds in [[], [ActivityKind.tapLetterAll], [.tapHanziAll], [.tapHanziWrite, .tapLetterWrite]] {
            let ticket = TicketUnavailableCopy.lines(for: kinds)
            lines += [ticket.advice, ticket.adviceEnglish] + ticket.cards
        }
        // Report lines as built from records (numbers filled).
        var row = HanziFindingRow(glyph: "木")
        row.rounds = 3
        row.confusions = ["本": 1, "未": 2]
        var write = HanziWritingRow(glyph: "木")
        write.writes = 1
        lines += HanziReportText.lines(HanziKindReport(finding: [row], writing: [write]), kind: .tapHanziWrite)
        // Fix1: rolled-up history (no retained detail) and the scope line beside retained detail.
        lines += [Copy.reportDetailNotKept(5), Copy.reportRolledUp(5)]
        expectEqual(lines.count, 100)
        for line in lines {
            expectFalse(line.isEmpty, "empty line")
            expectTrue(isTraditionalChineseOnly(line) && perfTraditionalOnly(line), line)
            expectFalse(line.contains { simplified.contains($0) }, "Simplified character in \(line)")
            expectFalse(line.contains("{") || line.contains("}") || line.contains(Self.xi), line)
        }
        // The design's exact Parent-row copy.
        expectEqual(Copy.reviewOn, "每 4 輪 1 輪")
        expectEqual(Copy.jyutpingDetail.components(separatedBy: "\n").first, "開咗先喺字卡下面顯示。")
        expectTrue(Copy.audioDetail.hasPrefix("開咗先出聲，文字提示照常顯示。"))
        expectTrue(Copy.defaultOff.contains("預設關閉") && Copy.defaultOff.contains("試玩一次先開星"))
        expectTrue(Copy.cardDefaultOff.hasPrefix("預設關閉") && Copy.starsLocked.hasPrefix("試玩一次先開星"))
        for file in ["Sources/VisaCore/HanziParent.swift", "Sources/VisaCore/HanziReport.swift",
                     "Sources/VisaGames/ParentTapHanziSettingsView.swift"] {
            let text = try source(file)
            expectFalse(text.contains { simplified.contains($0) }, "Simplified character in \(file)")
            expectTrue(isTraditionalChineseOnly(text) && perfTraditionalOnly(text), file)
        }
        print("  hanzi parent: \(lines.count) new lines HK Traditional (two lists + OpenCC fixture)")
    }

    // MARK: (8) Unavailable ticket

    /// (8) A Hanzi ticket that cannot be dealt says so and names 中文字設定, not the letter settings.
    func testUnavailableTicketNamesTheHanziSettings() throws {
        var desk = LetterTicketDesk()
        expectEqual(desk.unavailableKinds, [])
        func select(_ pool: [ActivityKind], filtered: [ActivityKind] = [], board: String?) {
            let _: LetterTicketDesk.Outcome<String> = desk.prepare(pool: pool, filtered: filtered, seed: "ticket") { _ in board }
        }
        select([.tapHanziAll], board: nil)
        expectTrue(desk.unavailable)
        expectEqual(desk.unavailableKinds, [.tapHanziAll])
        let hanzi = TicketUnavailableCopy.lines(for: desk.unavailableKinds)
        expectEqual(hanzi, TicketUnavailableCopy.Lines(advice: "叫大人長按右下角，睇吓中文字設定。",
            adviceEnglish: "Ask a grown-up to hold the bottom-right corner and check the Chinese character settings.",
            cards: ["中文字 · 翻字卡"]))
        expectTrue(desk.recover(.parentEntered))
        expectEqual(desk.unavailableKinds, [])
        // Letters keep their build-79 lines; an emptied pool names what the filters took out.
        select([.tapLetterWrite], board: nil)
        let letters = TicketUnavailableCopy.lines(for: desk.unavailableKinds)
        expectEqual(letters.advice, "叫大人長按右下角，睇吓字母設定。")
        expectEqual(letters.adviceEnglish, "Ask a grown-up to hold the bottom-right corner and check the letter settings.")
        expectEqual(letters.cards, [])
        expectEqual(TicketUnavailableCopy.lines(for: []), letters)
        select([], filtered: [.tapHanziWrite, .tapLetterAll], board: nil)
        expectEqual(desk.unavailableKinds, [.tapHanziWrite, .tapLetterAll])
        let both = TicketUnavailableCopy.lines(for: desk.unavailableKinds)
        expectEqual(both.advice, "叫大人長按右下角，睇吓字母同中文字設定。")
        expectEqual(both.cards, ["中文字 · 搵完寫"])
        select([], filtered: [.tapHanziWrite, .tapHanziAll], board: nil)
        expectEqual(TicketUnavailableCopy.lines(for: desk.unavailableKinds).cards, ["中文字 · 翻字卡", "中文字 · 搵完寫"])
        select([.tapHanziAll], board: "board")
        expectFalse(desk.unavailable)
        expectEqual(desk.unavailableKinds, [], "a dealt ticket clears it")

        // The screen reads the desk through the model; the copy moved into VisaCore.
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        expectTrue(model.contains("var unavailableTicketKinds: [ActivityKind] { letterTicketDesk.unavailableKinds }"))
        expectTrue(model.contains("LetterUnavailableTicketView(kinds: model.unavailableTicketKinds)"))
        let select = body(of: "func selectDifficulty(stars: Int)", in: model)
        expectTrue(select.contains("let assigned = gameAssignment.pool(for: difficulty)"))
        expectTrue(select.contains("desk.prepare(pool: pool, filtered: assigned.filter { !pool.contains($0) }, seed: ticketSeed)"))
        let view = try source("Sources/VisaGames/LetterUnavailableTicketView.swift")
        expectTrue(view.contains("TicketUnavailableCopy.lines(for: kinds)"))
        expectTrue(view.contains("var kinds: [ActivityKind] = []"))
        expectFalse(view.contains("字母設定") || view.contains("letter settings"), "the advice comes from the copy")
        print("  hanzi parent: unavailable ticket names 中文字設定 and the card; letters unchanged")
    }

    // MARK: (9) App wiring source guards

    /// (9) SwiftUI / AppKit wiring (not compiled on this box): two independent cards with their own playtest gates,
    /// the settings draft and its one save path, jyutping only when on, voice only when on, the review lines.
    func testParentWiringSourceGuards() throws {
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let settingsView = try source("Sources/VisaGames/ParentSettingsView.swift")
        let card = try source("Sources/VisaGames/ParentGameCard.swift")
        let hanziView = try source("Sources/VisaGames/ParentTapHanziSettingsView.swift")
        let host = try source("Sources/VisaGames/CanvasActivityHost.swift")
        let find = try source("Sources/VisaGames/TapHanziBoardView.swift")
        let write = try source("Sources/VisaGames/TapHanziWriteBoardView.swift")
        let review = try source("Sources/VisaGames/ParentReviewView.swift")
        let recorder = try source("Sources/VisaGames/PerformanceRecorder.swift")

        // Two cards, one per kind: each card reads its own playtest date and starts its own 試玩.
        expectTrue(settingsView.contains("items: ActivityCatalog.playableKinds"))
        expectTrue(settingsView.contains("playtestedOn: model.parentPlaytestLog.playtestedOn(kind)"))
        expectTrue(settingsView.contains("onPlaytest: { model.startPlaytest(kind: kind) }"))
        expectTrue(card.contains("private var starsLocked: Bool { kind.requiresPlaytestBeforeStars && playtestedOn == nil }"))
        expectTrue(card.contains("if let suggested = HanziParentCopy.suggestedStar(kind)"))
        expectTrue(card.contains("if kind.isTapHanziFamily && starsLocked"))
        expectTrue(card.contains("Text(HanziParentCopy.starsLocked)"))
        expectTrue(card.contains("if let detail = HanziParentCopy.cardDetail(kind)"))
        expectTrue(card.contains("kind.isTapHanziFamily ? HanziParentCopy.cardDefaultOff : \"唔會出現 / Hidden from missions\""))
        expectTrue(card.contains("VectorArtView(artwork: HanziCueArt.robot)"), "the play board's robot, no new icon")
        // Stars wait for that card's own playtest; a finished playtest records only the kind that was played.
        let toggle = body(of: "func toggleMissionStar(kind: ActivityKind, star: ChildDifficulty)", in: model)
        expectTrue(toggle.contains("if !gameAssignment.isEnabled(kind, star: star), !parentPlaytestLog.allowsStars(for: kind) {"))
        let finish = body(of: "private func finishTapHanziRound(token: String, playtest: Bool)", in: model)
        expectTrue(finish.contains("if let kind = currentTapHanziKind, parentPlaytestLog.playtestedOn(kind) == nil {"))
        expectEqual(count("parentPlaytestLog.recording(", in: finish), 1)
        expectTrue(finish.contains("parentPlaytestLog = parentPlaytestLog.recording(kind, on: Date())"))
        expectFalse(finish.contains("recording(.tapHanzi"), "never the other card")

        // The settings draft and its one save path.
        expectTrue(settingsView.contains("ParentTapHanziSettingsView(model: model)"))
        expectTrue(model.contains("@Published private(set) var hanziSettings = HanziTapSettingsStore().load()"))
        let save = body(of: "func saveHanziSettings(", in: model)
        for needle in ["guard session.mode == .parent else { return hanziSettings }", "let store = HanziTapSettingsStore()",
                       "store.save(value)", "hanziSettings = store.load()"] {
            expectTrue(save.contains(needle), needle)
        }
        expectEqual(count("HanziTapSettingsStore().save(", in: model) + count("store.save(value)", in: model), 1)
        expectTrue(hanziView.contains("@State private var draft: HanziSettingsDraft?"))
        expectTrue(hanziView.contains("draft = HanziSettingsDraft(saved: model.tapHanziSettings)"))
        expectEqual(count("model.saveHanziSettings(", in: hanziView), 1)
        expectTrue(body(of: "private func save()", in: hanziView).contains("model.saveHanziSettings(next.value)"))
        expectFalse(hanziView.contains("HanziTapSettingsStore"), "the view saves only through the model")
        expectTrue(hanziView.contains("next.toggleWeek(glyph, in: pack)"))
        expectTrue(hanziView.contains("ForEach(pack.board.targetWeek, id: \\.self)"), "only targets are tiles")
        expectTrue(hanziView.contains("ForEach(pack.dealableFindOnly, id: \\.self)"), "find-only shown, not selectable")
        for row in ["$0.setConfusableGuard(value)", "$0.setJyutping(value)", "$0.setAudio(value)", "$0.setReviewEvery(0)",
                    "$0.setReviewEvery(4)", "$0.revert()"] {
            expectTrue(hanziView.contains(row), row)
        }
        expectFalse(hanziView.contains("Slider"), "no percentage sliders")

        // 粵拼 only when on: the model hands the views a line or nil, and each view draws it only when it has one.
        let jyutping = body(of: "var tapHanziJyutping: String?", in: model)
        expectTrue(jyutping.contains("HanziJyutping.line(board.target, pack: pack, settings: hanziSettings)"))
        expectEqual(count("jyutping: model.tapHanziJyutping", in: host), 2)
        for view in [find, write] {
            expectTrue(view.contains("var jyutping: String? = nil"))
            expectTrue(view.contains("if let jyutping {"))
            expectEqual(count("CanvasText(jyutping,", in: view), 1)
        }
        // 廣東話語音: the one Hanzi voice path still returns at once while it is off.
        expectTrue(body(of: "private func tapHanziSpeak(", in: model).contains("guard hanziSettings.audioEnabled else { return }"))

        // 表現: the report carries the Hanzi tallies, and each Hanzi row's detail shows its lines.
        expectTrue(model.contains("hanziPack: hanziPack"))
        expectTrue(recorder.contains("now: Date(), window: window, timeZone: store.timeZone, hanziPack: hanziPack"))
        expectTrue(review.contains("GameReviewDetail(row: row, hanziLines: HanziReportText.lines(report.hanzi[row.kind], kind: row.kind))"))
        expectTrue(review.contains("ForEach(Array(hanziLines.enumerated()), id: \\.offset)"))
        print("  hanzi parent: wiring guards — cards, own playtest gates, draft save, jyutping gate, voice gate, review")
    }

    // MARK: (10) Finding success comes from the find (astra fix1)

    /// (10) Fix1, Major 2: a round's finding success is its own recorded taps (both target cards flipped: the pack's
    /// `board.targetCards` distinct `choice`s, with no wrong card), never `round_result.first_try`, which needs the
    /// whole round solved. Two correct flips and then an abandoned write: a first-try find, and no write counted.
    func testFindingSuccessComesFromTheFindNotTheWrite() throws {
        let pack = try loadPack()
        expectEqual(pack.board.targetCards, 2)
        let abandoned = hanziRound(.tapHanziWrite, target: "上", taps: ["上", "上"], outcome: "abandoned")
        expectEqual(abandoned.last?.bool("first_try"), false, "the round itself is no first try")
        expectEqual(abandoned.last?.bool("write_clean"), nil, "no write recorded")
        var found = HanziFindingRow(glyph: "上")
        found.rounds = 1
        found.firstTry = 1
        let report = HanziReportBuilder.build(events: abandoned, pack: pack, now: Self.now, window: .days30)
        expectEqual(report, [.tapHanziWrite: HanziKindReport(finding: [found], writing: [])])
        expectEqual(HanziReportText.lines(report[.tapHanziWrite], kind: .tapHanziWrite), [
            HanziParentCopy.reportTitle, HanziParentCopy.reportFinding,
            "上：1 局 · 第一次就搵啱 1 局 · 搵錯 0 張\n上: rounds 1 · found first time 1 · wrong cards 0",
            HanziParentCopy.reportWriting, HanziParentCopy.reportNoWrites, HanziParentCopy.reportStrokeSkip])

        // No first-try find: one card only (left mid-find), a wrong card on the way, or one card's flip recorded twice.
        var events = hanziRound(.tapHanziWrite, target: "下", taps: ["下"], outcome: "abandoned")
        events += hanziRound(.tapHanziAll, target: "左", taps: ["右", "左", "左"])
        var twice = hanziRound(.tapHanziAll, target: "木", taps: ["木"], outcome: "abandoned")
        twice.insert(ev(.answerAttempt, ["round": .string(twice[0].string("round") ?? ""),
                                         "kind": .string(ActivityKind.tapHanziAll.rawValue), "choice": .string("card-0"),
                                         "correct": .bool(true), "glyph": .string("木"), "tags": .strings([])]), at: 2)
        events += twice
        let misses = HanziReportBuilder.build(events: events, pack: pack, now: Self.now, window: .days30)
        var xia = HanziFindingRow(glyph: "下")
        xia.rounds = 1
        var zuo = HanziFindingRow(glyph: "左")
        zuo.rounds = 1
        zuo.wrongCards = 1
        zuo.confusions = ["右": 1]
        var mu = HanziFindingRow(glyph: "木")
        mu.rounds = 1
        expectEqual(misses[.tapHanziWrite], HanziKindReport(finding: [xia]))
        expectEqual(misses[.tapHanziAll], HanziKindReport(finding: [zuo, mu]))

        // The rule reads what H3 records: a correct attempt only for the first flip of a target card, a wrong one only
        // for the first tap on a wrong card (a re-tap of either records nothing).
        let tap = body(of: "func tapHanziTap(card: Int)", in: try source("Sources/VisaGames/AppDelegate.swift"))
        for needle in ["let attempt = (tags: [String](), fields: [\"card\": PerfValue.int(card), \"glyph\": .string(glyph)])",
                       "if outcome == .found || outcome == .allFound {", "if outcome == .miss {",
                       "self.pendingAnswerRecord = attempt"] {
            expectTrue(tap.contains(needle), needle)
        }
        print("  hanzi parent: finding success from the find's own taps; an abandoned write is a first-try find, no write")
    }

    // MARK: (11) Rolled-up history (astra fix1)

    /// (11) Fix1, Minor 1: raw events are kept `PerfRetention.rawDays` (90) days, then only the rollup's daily counts.
    /// A card whose rounds in the window are all rolled up says its detail is gone (the 表現 row still counts them),
    /// never 「未有中文字紀錄」; beside retained rounds one line says how many the detail leaves out. No history at all
    /// still reads 「未有中文字紀錄」.
    func testRolledUpHistoryIsNotNoHistory() throws {
        let pack = try loadPack()
        expectEqual(PerfRetention.rawDays, 90)
        func stamp(_ daysAgo: Int) -> String {
            PerfClock.dayStamp(Self.now.addingTimeInterval(-Double(daysAgo) * 86_400), timeZone: PerfClock.hongKong)
        }
        func stats(_ deals: Int) -> PerfGameDayStats {
            var day = PerfGameDayStats()
            day.deals = deals
            day.answered = deals
            day.firstTry = 1
            day.solved = deals
            return day
        }
        var rollup = PerfRollup()
        rollup.days[stamp(120)] = PerfDaySummary(games: ["tapHanziAll|1": stats(3), "tapHanziWrite|2": stats(4),
                                                         "tapLetterAll|1": stats(6)])
        rollup.days[stamp(200)] = PerfDaySummary(games: ["tapHanziAll|1": stats(2)])

        // Rollup only: 全部 has Hanzi history but no retained event, so each card says its detail is gone.
        let rolled = HanziReportBuilder.build(events: [], pack: pack, now: Self.now, window: .all, rollup: rollup)
        expectEqual(rolled, [.tapHanziAll: HanziKindReport(rolledUpRounds: 5),
                             .tapHanziWrite: HanziKindReport(rolledUpRounds: 4)])
        expectEqual(HanziReportText.lines(rolled[.tapHanziAll], kind: .tapHanziAll), [
            "呢段時間有 5 局中文字，但逐局紀錄只留 90 日，而家只剩每日總數，冇細項。\n"
                + "Rounds in this period: 5. Round records are kept for 90 days only, so just daily totals remain and "
                + "there is no detail."])
        expectEqual(HanziReportText.lines(rolled[.tapHanziWrite], kind: .tapHanziWrite),
                    [HanziParentCopy.reportDetailNotKept(4)])
        // The 表現 rows count the same rounds (their rollup rule), and the report carries the Hanzi scope.
        let review = PerfReportBuilder.build(events: [], rollup: rollup, videos: [], now: Self.now, window: .all,
                                             hanziPack: pack)
        expectEqual(review.games.first { $0.kind == .tapHanziAll }?.deals, 5)
        expectEqual(review.games.first { $0.kind == .tapHanziWrite }?.deals, 4)
        expectEqual(review.hanzi, rolled)
        // 近 30 日 holds none of those days: no Hanzi history there, so no report and 「未有中文字紀錄」.
        expectEqual(HanziReportBuilder.build(events: [], pack: pack, now: Self.now, window: .days30, rollup: rollup), [:])
        expectEqual(HanziReportText.lines(nil, kind: .tapHanziAll), [HanziParentCopy.reportEmpty])

        // Retained rounds beside rolled-up ones: the lines count the retained round and say how many they leave out.
        let events = hanziRound(.tapHanziAll, target: "上", taps: ["上", "上"])
        let mixed = HanziReportBuilder.build(events: events, pack: pack, now: Self.now, window: .all, rollup: rollup)
        var shang = HanziFindingRow(glyph: "上")
        shang.rounds = 1
        shang.firstTry = 1
        expectEqual(mixed[.tapHanziAll], HanziKindReport(finding: [shang], rolledUpRounds: 5))
        expectEqual(HanziReportText.lines(mixed[.tapHanziAll], kind: .tapHanziAll), [
            HanziParentCopy.reportTitle,
            "另外 5 局只剩每日總數（逐局紀錄只留 90 日），下面冇計。\n"
                + "Rounds with daily totals only: 5 (round records are kept for 90 days); the lines below leave them out.",
            HanziParentCopy.reportFinding,
            "上：1 局 · 第一次就搵啱 1 局 · 搵錯 0 張\n上: rounds 1 · found first time 1 · wrong cards 0"])
        // A rollup day whose raw events still exist is not counted twice (today's rounds are the raw ones).
        rollup.days[stamp(0)] = PerfDaySummary(games: ["tapHanziAll|1": stats(7)])
        expectEqual(HanziReportBuilder.build(events: events, pack: pack, now: Self.now, window: .all,
                                             rollup: rollup)[.tapHanziAll]?.rolledUpRounds, 5)
        print("  hanzi parent: rolled-up history says its detail is gone (5 / 4 rounds), not 「未有中文字紀錄」")
    }

    // MARK: (12) 粵拼 line (astra fix1)

    /// (12) Fix1, Minor 3: `HanziJyutping.line` itself. OFF → nil for every glyph; ON → the pack's reading for a week
    /// target (人 jan4, 木 muk6); a find-only glyph (its reading sits under the pack's `findOnly`, never shown) or an
    /// unknown glyph → nil whatever the toggle. Only 粵拼 turns it on.
    func testJyutpingLineFollowsTheToggle() throws {
        let pack = try loadPack()
        var on = HanziTapSettings.defaults
        on.jyutpingEnabled = true
        let off = HanziTapSettings(week: ["左", "右", "木"], reviewEvery: 0, confusableGuard: false, audioEnabled: false,
                                   jyutpingEnabled: false, guidance: .less)
        let unknown = ["大", "a", "", "人人", "hanzi:人"]
        for settings in [HanziTapSettings.defaults, off] {
            expectFalse(settings.jyutpingEnabled)
            for glyph in Self.week + Self.findOnly + unknown {
                expectEqual(HanziJyutping.line(glyph, pack: pack, settings: settings), nil, "OFF \(glyph)")
            }
        }
        expectEqual(HanziJyutping.line("人", pack: pack, settings: on), "jan4")
        expectEqual(HanziJyutping.line("木", pack: pack, settings: on), "muk6")
        expectEqual(Self.week.map { HanziJyutping.line($0, pack: pack, settings: on) },
                    ["jan4", "soeng6", "haa6", "zo2", "jau6", "muk6"])
        for glyph in Self.findOnly {
            expectFalse(pack.findOnly[glyph]?.jyutping.isEmpty ?? true, "the pack has a reading for \(glyph)")
            expectEqual(HanziJyutping.line(glyph, pack: pack, settings: on), nil, "find-only \(glyph)")
        }
        for glyph in unknown { expectEqual(HanziJyutping.line(glyph, pack: pack, settings: on), nil, "unknown \(glyph)") }
        print("  hanzi parent: jyutping OFF → nil, ON → 人 jan4 / 木 muk6, find-only and unknown → nil")
    }

    // MARK: (13) Weekly ⚙ for 中文字設定 (astra fix1)

    /// (13) Fix1, Major 1 (weekly-report design §4.10): a 中文字設定 save records each field its read-back value
    /// changed as a `tapHanzi_` `config_change` (the 數字設定 / 字母設定 style). The family marks both 中文字 cards ⚙,
    /// so does a week or guard change seen in their deals (the week as a Hanzi set, not the ASCII letter filter), and
    /// each name is the settings screen's own, bilingual (描字提示, never 描數字提示). A ⚙ card keeps its numbers but gets
    /// no clear change and no 「比上星期順咗」 win; page 5 lists the save instead of 「今個星期冇改設定」.
    func testHanziSettingChangesMarkBothCardsWeekly() throws {
        let pack = try loadPack()
        let cards = [ActivityKind.tapHanziAll.rawValue, ActivityKind.tapHanziWrite.rawValue]

        // What a save records: the fields whose read-back value changed, valued as the report prints them.
        var saved = HanziTapSettings.defaults
        saved.week = ["人", "上", "下"]
        saved.reviewEvery = 0
        saved.confusableGuard = false
        let changes = HanziSettingChange.changes(from: .defaults, to: saved, pack: pack)
        expectEqual(changes, [HanziSettingChange(what: "week", value: "人 上 下"),
                              HanziSettingChange(what: "review_every", value: "0"),
                              HanziSettingChange(what: "guard", value: "off")])
        expectEqual(HanziSettingChange.changes(from: saved, to: saved, pack: pack), [])
        expectEqual(HanziSettingChange.changes(from: .defaults, to: HanziTapSettings(week: Self.week), pack: pack), [],
                    "the pack's own week again is no change")
        let every = HanziTapSettings(week: ["左", "右", "木"], reviewEvery: 0, confusableGuard: false, audioEnabled: false,
                                     jyutpingEnabled: true, guidance: .less, grid: .tianzi)
        expectEqual(HanziSettingChange.changes(from: .defaults, to: every, pack: pack).map { "\($0.what)=\($0.value)" },
                    ["week=左 右 木", "review_every=0", "guard=off", "guidance=less", "grid=tianzi", "audio=off",
                     "jyutping=on"])

        // One family for both cards; every name is the settings screen's own, Cantonese and English.
        func named(_ what: String) -> [String] {
            guard let name = WeeklyTextCatalog.configName(what) else { return [] }
            return [name.name.zh, name.name.en, name.labels]
        }
        for change in HanziSettingChange.changes(from: .defaults, to: every, pack: pack) {
            expectEqual(WeeklyComparison.kinds(forConfig: "tapHanzi_\(change.what)", kind: ActivityKind.tapHanziAll.rawValue),
                        cards, change.what)
            expectFalse(named("tapHanzi_\(change.what)").isEmpty, change.what)
        }
        expectEqual(named("tapHanzi_week"), ["今星期中文字", "Characters this week", "letter_set"])
        expectEqual(named("tapHanzi_review_every"), ["中文字溫習", "Character review", "hanzi_review"])
        expectEqual(named("tapHanzi_guard"), ["易混字護欄", "Look-alike guard", "letter_guard"])
        expectEqual(named("tapHanzi_guidance"), ["描字提示", "Writing help", "guidance"])
        expectEqual(named("tapHanzi_grid"), ["寫字格", "Writing grid", "hanzi_grid"])
        expectEqual(named("tapHanzi_audio"), ["廣東話語音", "Cantonese voice", "letter_guard"])
        expectEqual(named("tapHanzi_jyutping"), ["粵拼", "Jyutping", "letter_guard"])
        for kind in cards {
            expectEqual(WeeklyTextCatalog.fieldName("this_week", kind: kind)?.name,
                        WeeklyWords("今星期中文字", "Characters this week"))
            expectEqual(WeeklyTextCatalog.fieldName("guard", kind: kind)?.name, WeeklyWords("易混字護欄", "Look-alike guard"))
            expectEqual(WeeklyTextCatalog.fieldName("guide_level", kind: kind)?.name, WeeklyWords("描字提示", "Writing help"))
        }
        // The number and letter names stay theirs.
        expectEqual(WeeklyTextCatalog.fieldName("guide_level", kind: ActivityKind.tapCountTrace.rawValue)?.name,
                    WeeklyWords("描數字提示", "Tracing help"))
        expectEqual(WeeklyTextCatalog.fieldName("guard", kind: ActivityKind.tapLetterAll.rawValue)?.name,
                    WeeklyWords("新字母護欄", "Letter guard"))
        expectEqual(WeeklyTextCatalog.fieldName("this_week", kind: ActivityKind.tapLetterAll.rawValue)?.name, nil)
        // A week is a set of Hanzi, never read through the ASCII letter filter.
        expectEqual(WeeklySignature.letterSet(["人", "上", "下"]), "", "the letter rule reads a Hanzi week as empty")
        expectEqual(WeeklySignature.hanziSet(.strings(["人", "上", "下", "上"])), "上 下 人")
        expectEqual(WeeklySignature.hanziSet(.string("人 上 下")), nil)

        // Two weeks of both cards: last week 1 of 6 right first time each, this week 6 of 6 (a clear ↑ by §4.10).
        let lastMonday = PerfCodec.parseTimestamp("2026-11-02T04:00:00.000Z")!  // 12:00 HKT
        let monday = PerfCodec.parseTimestamp("2026-11-09T04:00:00.000Z")!
        let window = WeeklyWindow(containing: monday)
        func week(_ start: Date, firstTry: Int, glyphs: [String], guardOn: Bool) -> [PerfEvent] {
            var events: [PerfEvent] = []
            for index in 0..<6 {
                for (offset, kind) in [ActivityKind.tapHanziAll, .tapHanziWrite].enumerated() {
                    seq += 1
                    let id = "wk\(seq)"
                    let at = start.addingTimeInterval(Double(index) * 600 + Double(offset) * 300)
                    events.append(PerfEvent(type: .gameDealt, timestamp: at, tz: "+08:00", mono: Double(seq), launch: "L1",
                                            seq: seq, app: "0.40.0", actor: .child, mode: "lock", session: "s1",
                                            fields: ["round": .string(id), "kind": .string(kind.rawValue), "stars": .int(1),
                                                     "match_mode": .string("test"), "gen": .string("hanzi_v1"),
                                                     "target": .string(glyphs[index % glyphs.count]),
                                                     "this_week": .strings(glyphs), "guard": .string(guardOn ? "on" : "off")]))
                    seq += 1
                    let first = index < firstTry
                    events.append(PerfEvent(type: .roundResult, timestamp: at.addingTimeInterval(40), tz: "+08:00",
                                            mono: Double(seq), launch: "L1", seq: seq, app: "0.40.0", actor: .child,
                                            mode: "lock", session: "s1",
                                            fields: ["round": .string(id), "kind": .string(kind.rawValue),
                                                     "outcome": .string("solved"), "answers": .int(first ? 2 : 3),
                                                     "first_try": .bool(first), "misses": .int(first ? 0 : 1),
                                                     "total_ms": .int(40_000), "active_ms": .int(9_000),
                                                     "earned_min": .int(5)]))
                }
            }
            return events
        }
        let before = week(lastMonday, firstTry: 1, glyphs: Self.week, guardOn: true)
        // The save as the recorder writes it (parent, after read-back), an hour before this week's play.
        var save: [PerfEvent] = []
        for change in changes {
            seq += 1
            save.append(PerfEvent(type: .configChange, timestamp: monday.addingTimeInterval(-3600), tz: "+08:00",
                                  mono: Double(seq), launch: "L1", seq: seq, app: "0.40.0", actor: .parent, mode: "parent",
                                  session: "p", fields: ["what": .string("tapHanzi_\(change.what)"),
                                                         "kind": .string(ActivityKind.tapHanziAll.rawValue),
                                                         "value": .string(change.value)]))
        }
        let after = week(monday, firstTry: 6, glyphs: ["人", "上", "下"], guardOn: false)
        let unchanged = week(monday, firstTry: 6, glyphs: Self.week, guardOn: true)
        func settings(_ analysis: WeeklyAnalysis, _ kind: String) -> [WeeklySettingChange] {
            analysis.games.first { $0.kind == kind }?.settings ?? []
        }

        // Control: the same play with nothing changed → both cards are a clear ↑ and a 「比上星期順咗」 win.
        let control = WeeklyAnalysisBuilder.build(events: before + unchanged, rollup: PerfRollup(), window: window)
        for kind in cards {
            expectEqual(control.games.first { $0.kind == kind }?.wow.change, WeeklyChange.up, kind)
            expectEqual(settings(control, kind), [], kind)
        }
        expectEqual(control.comparison.clearChanges.map(\.kind), cards)
        expectEqual(control.winCandidates.filter { $0.id == "win.rise" }.count, 2)
        let controlText = WeeklyReportTextBuilder.build(events: before + unchanged, rollup: PerfRollup(), window: window)
        expectEqual(controlText.changes.map(\.id), ["changes.none"])

        // The save and the changed deals: both cards ⚙ for the config lines and the deal signature; numbers kept.
        let events = before + save + after
        let analysis = WeeklyAnalysisBuilder.build(events: events, rollup: PerfRollup(), window: window)
        let marked: [WeeklySettingChange] = [
            .config(what: "tapHanzi_week", value: "人 上 下", star: nil, date: "2026-11-09"),
            .config(what: "tapHanzi_review_every", value: "0", star: nil, date: "2026-11-09"),
            .config(what: "tapHanzi_guard", value: "off", star: nil, date: "2026-11-09"),
            .signature(field: "guard", old: "on", new: "off"),
            .signature(field: "this_week", old: "上 下 人 右 左 木", new: "上 下 人")]
        for kind in cards {
            expectEqual(analysis.games.first { $0.kind == kind }?.wow.change, WeeklyChange.up, kind)
            expectEqual(settings(analysis, kind), marked, kind)
        }
        expectEqual(analysis.comparison.clearChanges, [])
        expectEqual(analysis.winCandidates.filter { $0.id == "win.rise" }, [])
        expectEqual(analysis.changes.settings.map(\.what), ["tapHanzi_week", "tapHanzi_review_every", "tapHanzi_guard"])
        for setting in analysis.changes.settings { expectEqual(setting.kinds, cards, setting.what) }

        // The deals alone (no config line) still mark both cards: the week as a Hanzi set, and the guard.
        let deals = WeeklyAnalysisBuilder.build(events: before + after, rollup: PerfRollup(), window: window)
        for kind in cards { expectEqual(settings(deals, kind), Array(marked.suffix(2)), kind) }
        expectEqual(deals.comparison.clearChanges, [])
        expectEqual(deals.winCandidates.filter { $0.id == "win.rise" }, [])

        // Text and HTML: each card's comment qualifies the comparison; page 5 lists the save, not 「今個星期冇改設定」.
        let text = WeeklyReportTextBuilder.build(events: events, rollup: PerfRollup(), window: window)
        expectEqual(text.changes, [])
        for kind in cards {
            let comment = text.games.first { $0.kind == kind }?.comment ?? []
            expectEqual(comment.filter { $0.id == "any.settings" }.map { [$0.zh, $0.en] }, [[
                "今個星期改咗設定（今星期中文字：人 上 下），同上星期比要小心。",
                "Settings changed this week (Characters this week: 人 上 下); compare with last week carefully."]], kind)
        }
        // Page 5 lists `changeLinesMax` (2) change lines, then a count of the rest (the existing W4 rule).
        expectEqual(WeeklyReportHTML.changeLinesMax, 2)
        let html = WeeklyReportHTML.render(text, options: WeeklyReportHTMLOptions(generatedAt: monday.addingTimeInterval(86_400)))
        for line in ["今星期中文字改做 人 上 下（影響 2 個遊戲）。", "Characters this week set to 人 上 下 (affects 2 games).",
                     "中文字溫習改做 關（影響 2 個遊戲）。", "Character review set to Off (affects 2 games).",
                     "仲有 1 項改動冇列出。", "1 more change not listed."] {
            expectTrue(html.contains(line), line)
        }
        expectFalse(html.contains("今個星期冇改設定"))
        let guardOnly = WeeklyReportTextBuilder.build(events: before + Array(save.suffix(1)) + after, rollup: PerfRollup(),
                                                      window: window)
        let guardHTML = WeeklyReportHTML.render(guardOnly,
                                                options: WeeklyReportHTMLOptions(generatedAt: monday.addingTimeInterval(86_400)))
        expectTrue(guardHTML.contains("易混字護欄改做 關（影響 2 個遊戲）。") && guardHTML.contains("Look-alike guard set to Off (affects 2 games)."))

        // App wiring: the save records after its read-back, through the recorder's `tapHanzi_` family.
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let saveBody = body(of: "func saveHanziSettings(", in: model)
        expectTrue(saveBody.contains("let before = hanziSettings"))
        let readBack = saveBody.range(of: "hanziSettings = store.load()")
        let record = saveBody.range(of: "for change in HanziSettingChange.changes(from: before, to: hanziSettings, pack: hanziPack) {")
        expectTrue(readBack != nil && record != nil && readBack!.upperBound <= record!.lowerBound, "recorded after read-back")
        expectTrue(saveBody.contains("perf.tapHanziSettingChanged(what: change.what, value: change.value)"))
        let recorder = try source("Sources/VisaGames/PerformanceRecorder.swift")
        let emit = body(of: "func tapHanziSettingChanged(what: String, value: String)", in: recorder)
        for needle in ["emit(.configChange, [", "\"what\": .string(\"tapHanzi_\\(what)\")",
                       "\"kind\": .string(ActivityKind.tapHanziAll.rawValue)", "\"value\": .string(value)",
                       "actorOverride: .parent"] {
            expectTrue(emit.contains(needle), needle)
        }
        print("  hanzi parent: 中文字設定 save → tapHanzi_ config_change; both cards ⚙, no clear ↑ or rise; page 5 lists it")
    }

    // MARK: (14) Speaker mark truth (audio default ON, Carter 2026-11-13)

    /// (14) Carter 2026-11-13 00:14 HKT (「改做預設開，推翻 D4，放入 H4」): 廣東話語音 defaults ON, so the boards' speaker
    /// mark shows ON only while the setting is on and a zh-HK / yue-HK voice is installed (`SystemSpeechPrompt.isAvailable`);
    /// a Mac with no Hong Kong Cantonese voice shows it crossed out. The voice path is unchanged ((9)). A recorded clip
    /// could speak without a system voice, but no Hanzi clip exists.
    func testSpeakerMarkShowsOnOnlyWithAnInstalledVoice() throws {
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let speech = try source("Sources/VisaGames/SystemSpeechPrompt.swift")
        let host = try source("Sources/VisaGames/CanvasActivityHost.swift")
        let find = try source("Sources/VisaGames/TapHanziBoardView.swift")
        let write = try source("Sources/VisaGames/TapHanziWriteBoardView.swift")

        // The mark's one flag: the setting and an installed Hong Kong Cantonese voice.
        expectTrue(model.contains("var tapHanziAudioOn: Bool { hanziSettings.audioEnabled && guideVoice.isAvailable }"))
        expectEqual(count("var tapHanziAudioOn", in: model), 1)
        expectTrue(model.contains("private let guideVoice = SystemSpeechPrompt()"))
        // `isAvailable` is the zh-HK / yue-HK voice the picker resolved at launch (never Mandarin).
        for needle in ["var isAvailable: Bool { voice != nil }", "var picked = CantoneseVoicePicker.pick(from: candidates)",
                       "CantoneseVoicePicker.isHongKongCantonese(byLang.language)", "voice = resolved"] {
            expectTrue(speech.contains(needle), needle)
        }
        // Both boards draw the mark from that flag, crossed out while it is false.
        expectEqual(count("audioOn: model.tapHanziAudioOn", in: host), 2)
        expectEqual(count("audioOn:", in: host), 2)
        expectTrue(write.contains("HanziSpeakerMark(audioOn: audioOn)"))
        for view in [find, write] {
            expectTrue(view.contains("VectorArtView(artwork: CanvasArt.speaker)"))
            expectEqual(count("if !audioOn {", in: view), 1)
        }
        // `speakQueued` plays a bundled `Voice/<key>.m4a` before the system voice; no Hanzi key (`hanzi.…`) has one.
        let clips = try FileManager.default.contentsOfDirectory(atPath: "Resources/Voice")
        expectFalse(clips.contains { $0.hasPrefix("hanzi.") }, "a Hanzi clip would speak while the mark is crossed out")
        print("  hanzi parent: speaker mark ON only with 廣東話語音 on and a zh-HK / yue-HK voice; both boards; no Hanzi clip")
    }

    // MARK: H4.1 helpers

    /// One 中文字 or letter round as the weekly report reads it (the fields both boards record): `game_dealt` with the
    /// card's `gen` and chance, then a solved `round_result` 40 s later, right first time or after one wrong card.
    private func weeklyRound(_ kind: ActivityKind, at date: Date, firstTry: Bool) -> [PerfEvent] {
        seq += 1
        let id = "wa\(seq)"
        let gen = kind.isTapHanziFamily ? "hanzi_v1" : "letters_v2"
        let dealt = PerfEvent(type: .gameDealt, timestamp: date, tz: "+08:00", mono: Double(seq), launch: "L1", seq: seq,
                              app: "0.40.1", actor: .child, mode: "lock", session: "s1",
                              fields: ["round": .string(id), "kind": .string(kind.rawValue), "stars": .int(1),
                                       "match_mode": .string("test"), "gen": .string(gen), "chance": .double(1.0 / 45)])
        seq += 1
        let result = PerfEvent(type: .roundResult, timestamp: date.addingTimeInterval(40), tz: "+08:00", mono: Double(seq),
                               launch: "L1", seq: seq, app: "0.40.1", actor: .child, mode: "lock", session: "s1",
                               fields: ["round": .string(id), "kind": .string(kind.rawValue), "outcome": .string("solved"),
                                        "answers": .int(firstTry ? 2 : 3), "first_try": .bool(firstTry),
                                        "misses": .int(firstTry ? 0 : 1), "total_ms": .int(40_000),
                                        "active_ms": .int(9_000), "earned_min": .int(5)])
        return [dealt, result]
    }

    /// `rounds` rounds of `kind` from `start` on two days, the first `firstTry` of them right first time.
    private func weeklyRounds(_ kind: ActivityKind, from start: Date, rounds: Int, firstTry: Int) -> [PerfEvent] {
        (0..<rounds).flatMap { index in
            weeklyRound(kind, at: start.addingTimeInterval(Double(index % 2) * 86_400 + Double(index) * 120),
                        firstTry: index < firstTry)
        }
    }

    // MARK: (15) 寫字格 setting (H4.1)

    /// (15) Carter 2026-11-14 03:37 HKT (「加米字格」): 寫字格 is a 中文字設定 row, 田字格 or 米字格, 米字格 by default (D3
    /// gave 田字格; pending his confirmation), stored as its raw value in `VisaGames.tapHanziSettings.v1`. A blob without
    /// it (saved before H4.1), or with null, a wrong type or an unknown grid, keeps every other value and reads 米字格; a
    /// broken H1 field or an unknown 描字提示 level still loads the defaults. The draft edits it like any row, and a save
    /// records `tapHanzi_grid`, which the weekly report names 寫字格 with the screen's own words.
    func testWritingGridSettingDefaultsToMiziAndKeepsOldBlobs() throws {
        let pack = try loadPack()
        expectEqual(HanziWritingGrid.allCases.map(\.rawValue), ["tianzi", "mizi"])
        expectEqual(HanziTapSettings.defaults.grid, .mizi)
        expectEqual(HanziTapSettings(week: ["上", "下", "木"]).grid, .mizi)
        let defaults = UserDefaults(suiteName: "VisaGames.hanziGrid.\(UUID().uuidString)")!
        let store = HanziTapSettingsStore(defaults: defaults)
        expectEqual(store.load().grid, .mizi, "nothing saved")
        for grid in HanziWritingGrid.allCases {
            var chosen = HanziTapSettings.defaults
            chosen.grid = grid
            store.save(chosen)
            expectEqual(store.load(), chosen, grid.rawValue)
            let blob = try JSONSerialization.jsonObject(with: defaults.data(forKey: HanziTapSettingsStore.key)!) as! [String: Any]
            expectEqual(blob["grid"] as? String, grid.rawValue)
        }
        func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
        // A blob saved before H4.1 (every H4 row, each away from its default, and no grid): all kept, 米字格.
        let h4: [String: Any] = ["schemaVersion": 1, "week": ["左", "右", "木"], "reviewEvery": 0, "confusableGuard": false,
                                 "audioEnabled": false, "jyutpingEnabled": true, "guidance": "less"]
        let kept = HanziTapSettings(week: ["左", "右", "木"], reviewEvery: 0, confusableGuard: false, audioEnabled: false,
                                    jyutpingEnabled: true, guidance: .less, grid: .mizi)
        defaults.set(json(h4), forKey: HanziTapSettingsStore.key)
        expectEqual(store.load(), kept, "no grid key")
        var square = h4
        square["grid"] = "tianzi"
        var keptSquare = kept
        keptSquare.grid = .tianzi
        defaults.set(json(square), forKey: HanziTapSettingsStore.key)
        expectEqual(store.load(), keptSquare, "grid tianzi")
        // Null, a wrong type or an unknown grid: the other values stay and the grid reads 米字格.
        let odd: [(String, Any)] = [("null", NSNull()), ("unknown", "jiugong"), ("capitalised", "Mizi"), ("empty", ""),
                                    ("Chinese", "田字格"), ("number", 1), ("bool", false), ("array", ["tianzi"])]
        for (label, value) in odd {
            var object = h4
            object["grid"] = value
            defaults.set(json(object), forKey: HanziTapSettingsStore.key)
            expectEqual(store.load(), kept, "grid \(label)")
        }
        // The grid never rescues a broken blob: a missing H1 field or an unknown 描字提示 level still loads the defaults.
        var broken: [(String, [String: Any])] = []
        for key in ["audioEnabled", "week", "schemaVersion"] {
            var object = square
            object.removeValue(forKey: key)
            broken.append(("no \(key)", object))
        }
        var badLevel = square
        badLevel["guidance"] = "teach"
        broken.append(("unknown level", badLevel))
        for (label, object) in broken {
            defaults.set(json(object), forKey: HanziTapSettingsStore.key)
            expectEqual(store.load(), .defaults, label)
        }

        // The draft: edits stay in the draft until Save, 還原 restores, choosing the saved grid again is no change.
        var draft = HanziSettingsDraft(saved: .defaults)
        draft.setGrid(.tianzi)
        expectTrue(draft.hasChanges)
        expectEqual([draft.value.grid, draft.saved.grid], [.tianzi, .mizi])
        draft.revert()
        expectFalse(draft.hasChanges)
        draft.setGrid(.tianzi)
        draft.setGrid(.mizi)
        expectFalse(draft.hasChanges, "back to the saved grid")
        draft.setGrid(.tianzi)
        draft.acceptSaved(keptSquare)
        expectEqual([draft.value.grid, draft.saved.grid], [.tianzi, .tianzi])

        // A save records the grid like every row (`tapHanzi_grid`, its raw value), for both cards.
        expectEqual(HanziSettingChange.changes(from: .defaults, to: keptSquare, pack: pack).map(\.what),
                    ["week", "review_every", "guard", "guidance", "grid", "audio", "jyutping"])
        var squareOnly = HanziTapSettings.defaults
        squareOnly.grid = .tianzi
        expectEqual(HanziSettingChange.changes(from: .defaults, to: squareOnly, pack: pack),
                    [HanziSettingChange(what: "grid", value: "tianzi")])
        expectEqual(HanziSettingChange.changes(from: squareOnly, to: .defaults, pack: pack),
                    [HanziSettingChange(what: "grid", value: "mizi")])
        let cards = [ActivityKind.tapHanziAll.rawValue, ActivityKind.tapHanziWrite.rawValue]
        expectEqual(WeeklyComparison.kinds(forConfig: "tapHanzi_grid", kind: cards[0]), cards)
        // The weekly report names it with the settings screen's words: each card's comment and page 5's change line.
        let lastMonday = PerfCodec.parseTimestamp("2026-11-02T04:00:00.000Z")!  // 12:00 HKT
        let monday = PerfCodec.parseTimestamp("2026-11-09T04:00:00.000Z")!
        seq = 0
        var events: [PerfEvent] = []
        for start in [lastMonday, monday] {
            events += weeklyRounds(.tapHanziAll, from: start, rounds: 6, firstTry: 3)
            events += weeklyRounds(.tapHanziWrite, from: start.addingTimeInterval(3_600), rounds: 6, firstTry: 3)
        }
        seq += 1
        events.append(PerfEvent(type: .configChange, timestamp: monday.addingTimeInterval(-3_600), tz: "+08:00",
                                mono: Double(seq), launch: "L1", seq: seq, app: "0.40.1", actor: .parent, mode: "parent",
                                session: "p", fields: ["what": .string("tapHanzi_grid"),
                                                       "kind": .string(ActivityKind.tapHanziAll.rawValue),
                                                       "value": .string("tianzi")]))
        let text = WeeklyReportTextBuilder.build(events: events, rollup: PerfRollup(), window: WeeklyWindow(containing: monday))
        for kind in cards {
            let comment = text.games.first { $0.kind == kind }?.comment ?? []
            expectEqual(comment.filter { $0.id == "any.settings" }.map { [$0.zh, $0.en] }, [[
                "今個星期改咗設定（寫字格：田字格），同上星期比要小心。",
                "Settings changed this week (Writing grid: Square grid); compare with last week carefully."]], kind)
        }
        let html = WeeklyReportHTML.render(text, options: WeeklyReportHTMLOptions(generatedAt: monday.addingTimeInterval(86_400)))
        for line in ["寫字格改做 田字格（影響 2 個遊戲）。", "Writing grid set to Square grid (affects 2 games)."] {
            expectTrue(html.contains(line), line)
        }
        print("  hanzi parent: 寫字格 米字格 by default; round-trip, H4 blob + \(odd.count) odd values keep the rest, "
              + "\(broken.count) broken blobs → defaults; draft; tapHanzi_grid named on the report")
    }

    // MARK: (16) 寫字格 geometry (H4.1)

    /// (16) `HanziWritingGridGeometry.lines`: 田字格 is the square's four sides and its centre vertical and horizontal,
    /// with no diagonal; 米字格 is the same six lines plus exactly the two corner-to-corner diagonals, crossing at the
    /// centre. Every point lies on the square; the border is solid, the cross and the diagonals share one dash. The
    /// lines follow the square alone (the board's 350 × 350, the strokes' uniform 7/6 scale), never a glyph.
    func testWritingGridGeometryIsTheSquaresOwnLines() throws {
        let square = HanziWriteBoard.square
        expectEqual(square, LineMatchRect(x: 465, y: 166, width: 350, height: 350))
        expectEqual(HanziWriteBoard.scale, 350.0 / 300.0, accuracy: 1e-12)
        func p(_ x: Double, _ y: Double) -> LineMatchPoint { LineMatchPoint(x: x, y: y) }
        let tianzi = HanziWritingGridGeometry.lines(for: .tianzi, in: square)
        expectEqual(tianzi, [HanziGridLine(role: .border, from: p(465, 166), to: p(815, 166)),
                             HanziGridLine(role: .border, from: p(815, 166), to: p(815, 516)),
                             HanziGridLine(role: .border, from: p(815, 516), to: p(465, 516)),
                             HanziGridLine(role: .border, from: p(465, 516), to: p(465, 166)),
                             HanziGridLine(role: .centre, from: p(640, 166), to: p(640, 516)),
                             HanziGridLine(role: .centre, from: p(465, 341), to: p(815, 341))])
        expectEqual(tianzi.filter { $0.role == .diagonal }, [], "田字格 has no diagonal")
        let mizi = HanziWritingGridGeometry.lines(for: .mizi, in: square)
        expectEqual(mizi.count, 8)
        expectEqual(Array(mizi.prefix(6)), tianzi, "米字格 keeps every 田字格 line")
        expectEqual(Array(mizi.dropFirst(6)), [HanziGridLine(role: .diagonal, from: p(465, 166), to: p(815, 516)),
                                               HanziGridLine(role: .diagonal, from: p(815, 166), to: p(465, 516))])
        expectEqual(["border", "centre", "diagonal"].map { role in mizi.filter { $0.role.rawValue == role }.count }, [4, 2, 2])
        // Corner to corner, through the centre where the cross meets.
        let corners = [p(465, 166), p(815, 166), p(815, 516), p(465, 516)]
        for line in mizi where line.role == .diagonal {
            expectTrue(corners.contains(line.from) && corners.contains(line.to), "\(line)")
            expectEqual([abs(line.to.x - line.from.x), abs(line.to.y - line.from.y)], [square.width, square.height])
            expectEqual([(line.from.x + line.to.x) / 2, (line.from.y + line.to.y) / 2], [square.midX, square.midY])
        }
        // Every point on the square; only the border is solid.
        for grid in HanziWritingGrid.allCases {
            for line in HanziWritingGridGeometry.lines(for: grid, in: square) {
                expectTrue(square.contains(line.from) && square.contains(line.to), "\(grid) \(line)")
                expectEqual(line.dashed, line.role != .border, "\(grid) \(line.role)")
            }
        }
        // The lines follow the square alone: another square moves and scales them, nothing else does.
        let other = LineMatchRect(x: 10, y: 20, width: 300, height: 300)
        let moved = HanziWritingGridGeometry.lines(for: .mizi, in: other)
        expectEqual(moved.map(\.role), mizi.map(\.role))
        for (line, base) in zip(moved, mizi) {
            for (point, origin) in [(line.from, base.from), (line.to, base.to)] {
                expectEqual(point.x, other.x + (origin.x - square.x) * other.width / square.width, accuracy: 1e-9)
                expectEqual(point.y, other.y + (origin.y - square.y) * other.height / square.height, accuracy: 1e-9)
            }
        }
        expectEqual(HanziWritingGridGeometry.lines(for: .mizi, in: square), mizi, "a pure function")
        print("  hanzi parent: 寫字格 lines — 田字格 4 sides + cross, 米字格 + 2 corner diagonals, on the square, dashed guides")
    }

    // MARK: (17) 寫字格 wiring (H4.1; SwiftUI / AppKit are not compiled on this box)

    /// (17) The write board draws the saved grid: the host hands it `model.tapHanziSettings.grid`, and `drawGrid` strokes
    /// `HanziWritingGridGeometry.lines(for: grid, in: HanziWriteBoard.square)` first on the canvas that draws the strokes
    /// (no touches), under the guidance layer (cars, headlights, signs) and the numbered starts. One solid style for the
    /// border, the cross's one dashed style for the cross and the diagonals. The strokes, starts, coach and write core
    /// never read the grid. 中文字設定 offers 田字格 / 米字格 through the draft; the find board has no grid.
    func testWriteBoardDrawsTheSavedGridUnderEverything() throws {
        let host = try source("Sources/VisaGames/CanvasActivityHost.swift")
        let write = try source("Sources/VisaGames/TapHanziWriteBoardView.swift")
        let find = try source("Sources/VisaGames/TapHanziBoardView.swift")
        let panel = try source("Sources/VisaGames/ParentTapHanziSettingsView.swift")
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let core = try source("Sources/VisaCore/HanziWrite.swift")

        // From the saved settings, through the board to its stage.
        expectEqual(count("grid: model.tapHanziSettings.grid", in: host), 1)
        expectEqual(count("grid:", in: host), 1)
        expectEqual(count("    let grid: HanziWritingGrid\n", in: write), 2)
        expectTrue(write.contains("TapHanziWriteStage(round: round, pack: pack, copy: copy, audioOn: audioOn, grid: grid,"))
        // The grid's lines on the board's square: a solid border, and the cross's one dash for every dashed line.
        let draw = body(of: "private func drawGrid(in g: inout GraphicsContext)", in: write)
        expectTrue(draw.contains("for line in HanziWritingGridGeometry.lines(for: grid, in: HanziWriteBoard.square) {"))
        expectTrue(draw.contains("if line.dashed {"))
        expectEqual(count("g.stroke(", in: draw), 2)
        expectTrue(draw.contains("g.stroke(border, with: .color(Color(hex: 0xADBFCE)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))"))
        expectTrue(draw.contains("g.stroke(guides, with: .color(Color(hex: 0xB4C8D8)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 7]))"))
        // First on the strokes' canvas, which takes no touches; then the guidance layer, then the numbers.
        let card = body(of: "private var writingCard", in: write)
        expectEqual(count("drawGrid(in: &g)", in: write), 1)
        expectTrue(card.contains("""
                    Canvas { canvas, _ in
                        var g = canvas
                        g.scaleBy(x: metrics.scale, y: metrics.scale)
                        drawGrid(in: &g)
                        drawStrokes(in: &g)
                    }
                    .frame(width: metrics.u(1280), height: metrics.u(720))
                    .allowsHitTesting(false)
        """), "the grid first, under the strokes, on a canvas without hit-testing")
        let grid = card.range(of: "drawGrid(in: &g)"), cars = card.range(of: "            guidanceLayer\n")
        let starts = card.range(of: "drawStarts(in: &g)")
        expectTrue(grid != nil && cars != nil && starts != nil
                   && grid!.upperBound < cars!.lowerBound && cars!.upperBound < starts!.lowerBound,
                   "grid, then cars / headlights / signs, then the numbers")
        // Only drawGrid reads the grid: the strokes, the numbered starts, the coach layer and the write core never do.
        for name in ["private func drawStrokes(in g: inout GraphicsContext)", "private func drawStarts(in g: inout GraphicsContext)",
                     "@ViewBuilder private var guidanceLayer"] {
            let part = body(of: name, in: write)
            expectFalse(part.isEmpty, name)
            expectFalse(part.contains("grid"), name)
        }
        let sections = core.components(separatedBy: "// MARK: - 寫字格")
        let tail = sections.count == 2 ? sections[1].components(separatedBy: "// MARK: - Copy") : []
        expectEqual([sections.count, tail.count], [2, 2])
        if sections.count == 2, tail.count == 2 {
            for part in [sections[0], tail[1]] { expectFalse(part.contains(".grid") || part.contains("grid:")) }
        }
        expectFalse(body(of: "private func beginTapHanziWriting(", in: model).contains("grid"))
        // The find board has no writing box and no grid.
        expectFalse(find.contains("HanziWritingGrid") || find.contains("drawGrid"))
        // 中文字設定: two choices through the draft, the chosen grid's detail lines; 「呢個版本未有」 is gone.
        let row = body(of: "private func gridRow(_ draft: HanziSettingsDraft)", in: panel)
        for needle in ["edit { $0.setGrid(.tianzi) }", "edit { $0.setGrid(.mizi) }", "selected: draft.value.grid == .tianzi",
                       "selected: draft.value.grid == .mizi", "HanziParentCopy.gridLine(draft.value.grid)",
                       "HanziParentCopy.gridLineEnglish(draft.value.grid)"] {
            expectTrue(row.contains(needle), needle)
        }
        expectTrue(panel.contains("                gridRow(draft)\n"))
        expectFalse(panel.contains("gridNote") || panel.contains("呢個版本未有"))
        // The parent copy: the default carries 預設; both lines say what the grid shows.
        expectEqual(HanziParentCopy.gridLine(.mizi), "米字格（預設）：田字格再加兩條斜線，幫手對準字嘅位置同平衡。")
        expectEqual(HanziParentCopy.gridLine(.tianzi), "田字格：方框加中間十字；冇斜線，唔會同撇、捺同頭燈爭位。")
        expectEqual([HanziParentCopy.gridName(.tianzi), HanziParentCopy.gridNameEnglish(.tianzi),
                     HanziParentCopy.gridName(.mizi), HanziParentCopy.gridNameEnglish(.mizi)],
                    ["田字格", "Square grid", "米字格", "Diagonal grid"])
        // The save keeps its one path; its log line names the grid.
        expectTrue(body(of: "func saveHanziSettings(", in: model).contains("grid=\\(hanziSettings.grid.rawValue)"))
        print("  hanzi parent: 寫字格 wiring — saved grid to the write board, drawn first, no hit-testing; 2 parent choices")
    }

    // MARK: (18) 中文字 in the weekly area suggestions (H4.1)

    /// (18) Carter 2026-11-14 03:37 HKT (「計埋」): 中文字 is a weekly quiz area for the area-level app items, exactly like
    /// 字母 and after it in the area order (`WeeklyArea.allCases`): A10 「多做一款「中文字」遊戲。」 when ≥ 2 of its cards
    /// are still learning, or when it is the lowest quiz area two weeks running (≥ 10 answered rounds, beside another area
    /// with ≥ 10); A11 when every ranked card goes well two weeks running. Not suggested without Hanzi play or when
    /// neither rule holds; on an equal rate 字母, earlier in the order, stays the lowest. Weeks without Hanzi do not change
    /// (the two golden fixtures hold no Hanzi round and their goldens are unchanged).
    func testWeeklyAreaSuggestionsCountHanzi() throws {
        let fixture = URL(fileURLWithPath: "Tests/VisaCoreTests/Fixtures/traditional-check/simplified-only.txt")
        let simplified = Set(try String(contentsOf: fixture, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") }.joined().filter { !$0.isWhitespace })
        let lastMonday = PerfCodec.parseTimestamp("2026-11-02T04:00:00.000Z")!  // 12:00 HKT
        let monday = PerfCodec.parseTimestamp("2026-11-09T04:00:00.000Z")!
        func text(_ events: [PerfEvent]) -> WeeklyReportText {
            WeeklyReportTextBuilder.build(events: events, rollup: PerfRollup(), window: WeeklyWindow(containing: monday))
        }
        let all = ActivityKind.tapHanziAll.rawValue, write = ActivityKind.tapHanziWrite.rawValue
        let letters = ActivityKind.tapLetterAll.rawValue
        var sentences: [WeeklySentence] = []

        // (a) Both 中文字 cards still learning (0 of 6 right first time each, two days) beside 字母 going well (6 of 6):
        // A10 for 中文字 by the still-learning rule, and nothing else.
        seq = 0
        let learning = text(weeklyRounds(.tapHanziAll, from: monday, rounds: 6, firstTry: 0)
                            + weeklyRounds(.tapHanziWrite, from: monday.addingTimeInterval(3_600), rounds: 6, firstTry: 0)
                            + weeklyRounds(.tapLetterAll, from: monday.addingTimeInterval(7_200), rounds: 6, firstTry: 6))
        expectEqual(learning.analysis.ranking.stillLearning.quiz, [all, write])
        expectEqual(learning.app.map(\.id), ["A10"])
        if let build = learning.app.first {
            expectEqual([build.text.id, build.because.id], ["A10", "A10.because.learning"])
            expectEqual([build.text.zh, build.text.en], ["多做一款「中文字」遊戲。", "Add another \"Chinese characters\" game."])
            expectEqual([build.because.zh, build.because.en], [
                "「中文字」有 2 個答題遊戲仲學緊：「中文字 · 翻字卡」、「中文字 · 搵完寫」。",
                "2 \"Chinese characters\" quiz games are still learning: \"Chinese characters · Find & flip\" and "
                    + "\"Chinese characters · Find & write\"."])
            expectEqual([build.check.zh, build.check.en],
                        ["「中文字」嘅第一次答啱率（兩個星期）", "right first time in \"Chinese characters\" over two weeks"])
            expectEqual(build.kinds, [all, write])
            expectEqual(build.settings, [])
            sentences += [build.text, build.because, build.check]
        }
        expectNil(learning.appNone)

        // (b) 中文字 the lowest quiz area two weeks running (2 of 10 right first time, beside 字母's 10 of 10): A10 by the
        // lowest rule with the recorded rates; 字母, going well both weeks, still gets its A11.
        seq = 0
        var lowestWeeks: [PerfEvent] = []
        for start in [lastMonday, monday] {
            lowestWeeks += weeklyRounds(.tapHanziAll, from: start, rounds: 10, firstTry: 2)
            lowestWeeks += weeklyRounds(.tapLetterAll, from: start.addingTimeInterval(3_600), rounds: 10, firstTry: 10)
        }
        let lowest = text(lowestWeeks)
        expectEqual(lowest.app.map(\.id), ["A10", "A11"])
        expectEqual(lowest.app.map(\.kinds), [[all], [letters]])
        if lowest.app.count == 2 {
            expectEqual([lowest.app[0].text.zh, lowest.app[0].because.id], ["多做一款「中文字」遊戲。", "A10.because.lowest"])
            expectEqual([lowest.app[0].because.zh, lowest.app[0].because.en], [
                "「中文字」連續兩個星期係最低嘅答題類別：今個星期 20%（亂估都有大約 2%），上星期 20%。",
                "\"Chinese characters\" was the lowest quiz area two weeks running: 20% this week (guessing gives about 2%), "
                    + "20% last week."])
            expectEqual(lowest.app[1].text.zh, "「字母」可以加難度：★★★ 題目／4 個選擇。")
            sentences += [lowest.app[0].text, lowest.app[0].because]
        }

        // (c) Every ranked 中文字 card going well two weeks running (10 of 10) while 字母 is the lowest (2 of 10): 字母
        // gets its A10 (two areas with 10 rounds now make a lowest one) and 中文字 its A11.
        seq = 0
        var harderWeeks: [PerfEvent] = []
        for start in [lastMonday, monday] {
            harderWeeks += weeklyRounds(.tapHanziAll, from: start, rounds: 10, firstTry: 10)
            harderWeeks += weeklyRounds(.tapLetterAll, from: start.addingTimeInterval(3_600), rounds: 10, firstTry: 2)
        }
        let harder = text(harderWeeks)
        expectEqual(harder.app.map(\.id), ["A10", "A11"])
        expectEqual(harder.app.map(\.kinds), [[letters], [all]])
        if harder.app.count == 2 {
            expectEqual(harder.app[0].text.zh, "多做一款「字母」遊戲。")
            expectEqual([harder.app[1].text.zh, harder.app[1].text.en],
                        ["「中文字」可以加難度：★★★ 題目／4 個選擇。", "\"Chinese characters\" can get harder: ★★★ questions or 4 choices."])
            expectEqual([harder.app[1].because.zh, harder.app[1].because.en],
                        ["「中文字」嘅遊戲連續兩個星期都做得好：「中文字 · 翻字卡」。",
                         "Every ranked \"Chinese characters\" game went well two weeks running: \"Chinese characters · Find & flip\"."])
            sentences += [harder.app[1].text, harder.app[1].because]
        }

        // (d) Not suggested: no Hanzi play; one card still learning (neither area at 10 rounds); 中文字 lowest this week
        // only (last week both areas 10 of 10: on that equal rate 字母, earlier in the order, was the lowest).
        func naming(_ report: WeeklyReportText) -> [String] {
            report.app.filter { $0.kinds.contains(all) || $0.kinds.contains(write) || $0.text.zh.contains("中文字") }.map(\.id)
        }
        seq = 0
        let noHanzi = text(weeklyRounds(.tapLetterAll, from: monday, rounds: 6, firstTry: 0))
        expectEqual(naming(noHanzi), [])
        seq = 0
        let one = text(weeklyRounds(.tapHanziAll, from: monday, rounds: 6, firstTry: 0)
                       + weeklyRounds(.tapLetterAll, from: monday.addingTimeInterval(3_600), rounds: 6, firstTry: 6))
        expectEqual(one.analysis.ranking.stillLearning.quiz, [all])
        expectEqual(one.app.map(\.id), [])
        expectEqual(one.appNone?.zh, "今個星期冇需要改嘅設定。")
        seq = 0
        var once = weeklyRounds(.tapHanziAll, from: lastMonday, rounds: 10, firstTry: 10)
            + weeklyRounds(.tapLetterAll, from: lastMonday.addingTimeInterval(3_600), rounds: 10, firstTry: 10)
        once += weeklyRounds(.tapHanziAll, from: monday, rounds: 10, firstTry: 2)
            + weeklyRounds(.tapLetterAll, from: monday.addingTimeInterval(3_600), rounds: 10, firstTry: 10)
        let onceText = text(once)
        expectEqual(naming(onceText), [], "lowest this week only, and the tie last week went to 字母")
        expectEqual(onceText.app.map(\.id), ["A11"])
        expectEqual(onceText.app.first?.kinds, [letters])

        // The golden fixtures (letters, counts, matching, pen; no Hanzi round) are the unchanged weeks: their text goldens
        // pass as before (weekly-text group).
        for name in ["weekly-ranking-5.6", "weekly-2026-10-19"] {
            let events = PerfEventStore(directory: URL(fileURLWithPath: "Tests/VisaCoreTests/Fixtures/\(name)")).read().events
            expectTrue(events.count > 100, name)
            expectFalse(events.contains { $0.string("kind")?.hasPrefix("tapHanzi") == true }, name)
        }
        // Every new 中文字 sentence: HK Traditional (both lists and the OpenCC fixture), no unfilled slot.
        expectEqual(sentences.count, 7)
        for sentence in sentences {
            expectTrue(sentence.problems.isEmpty, sentence.zh)
            expectTrue(isTraditionalChineseOnly(sentence.zh) && perfTraditionalOnly(sentence.zh), sentence.zh)
            expectFalse(sentence.zh.contains { simplified.contains($0) }, sentence.zh)
            expectFalse(sentence.zh.contains("{") || sentence.en.contains("{"), sentence.zh)
        }
        print("  hanzi parent: weekly 中文字 suggestions — A10 still learning / lowest, A11 harder; none without the rule; "
              + "ties stay 字母")
    }
}
