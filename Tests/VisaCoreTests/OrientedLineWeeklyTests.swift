import Foundation
import VisaCore

/// 畫直線・四方 R2 (four-direction design §9, T13 (a)–(i); C5): its own row in 手眼・畫線, ⚙ from its own settings on that
/// row only, and the two existing weekly suggestions (A8 / A9) still read 畫直線 · 熱身 (and the shape cards) only. The
/// weeks run through the real weekly text builder; deals use the real deal facts of both cards.
final class OrientedLineWeeklyTests {
    private var seq = 0
    private static let lastMonday = PerfCodec.parseTimestamp("2026-11-02T04:00:00.000Z")!  // 12:00 HKT
    private static let monday = PerfCodec.parseTimestamp("2026-11-09T04:00:00.000Z")!
    private static let newCard = ActivityKind.traceOrientedLines.rawValue
    private static let original = ActivityKind.traceLines.rawValue
    private static let dotted = ActivityKind.traceShapesDotted.rawValue

    private func ev(_ type: PerfEventType, _ fields: [String: PerfValue], at date: Date,
                    actor: PerfActor = .child) -> PerfEvent {
        seq += 1
        return PerfEvent(type: type, timestamp: date, tz: "+08:00", mono: Double(seq), launch: "L1", seq: seq, app: "0.42.0",
                         actor: actor, mode: actor == .child ? "lock" : "parent", session: "s1", fields: fields)
    }

    /// One solved practice round (deal + result). `wrongStart` red-end touches (each also a reversal).
    private func round(_ kind: String, at date: Date, dealt: [String: PerfValue], wrongStart: Int = 0,
                       actor: PerfActor = .child) -> [PerfEvent] {
        seq += 1
        let id = "w\(seq)"
        var fields = dealt
        fields["round"] = .string(id)
        fields["kind"] = .string(kind)
        fields["stars"] = .int(1)
        let result: [String: PerfValue] = [
            "round": .string(id), "kind": .string(kind), "outcome": .string("solved"), "answers": .int(0),
            "first_try": .null, "misses": .int(0), "hint_used": .bool(false), "assisted": .bool(false),
            "total_ms": .int(40_000), "active_ms": .int(20_000), "earned_min": .int(5), "practice": .string("shape_trace"),
            "shapes_done": .int(3), "shapes_total": .int(3), "wrong_start": .int(wrongStart),
            "reverse_direction": .int(wrongStart), "off_path_count": .int(0), "guide_level": .string("standard")
        ]
        return [ev(.gameDealt, fields, at: date, actor: actor), ev(.roundResult, result, at: date.addingTimeInterval(40), actor: actor)]
    }

    /// The new card's real deal facts, plus any forced field.
    private func newDeal(_ direction: OrientedLineDirectionSetting = .both, seed: String,
                         forced: [String: PerfValue] = [:]) -> [String: PerfValue] {
        let question = OrientedLineGenerator.make(seed: seed, settings: OrientedLineSettings(lineDirection: direction))
        return PerfChoiceCatalog.facts(orientedLines: question).dealtFields.merging(forced) { _, new in new }
    }

    /// 畫直線 · 熱身's (or a shape card's) real deal facts with 方向提示 and 畫直線加斜線 as given.
    private func originalDeal(_ kind: ActivityKind = .traceLines, coaching: Bool, slant: Bool = false) -> [String: PerfValue] {
        var settings = ShapeTraceSettings.defaults
        settings.directionHint = coaching
        settings.slantLines = slant
        return PerfChoiceCatalog.facts(shapeTrace: ShapeTraceGenerator.make(seed: "o\(seq)", kind: kind, settings: settings),
                                       settings: settings, tolerance: .standard).dealtFields
    }

    private static func at(_ week: Date, _ day: Int, _ minute: Int) -> Date {
        week.addingTimeInterval(Double(day) * 86_400 + Double(minute) * 60)
    }

    private static func build(_ events: [PerfEvent]) -> WeeklyReportText {
        let text = WeeklyReportTextBuilder.build(events: events, rollup: PerfRollup(), window: WeeklyWindow(containing: monday))
        let problems = text.allSentences.flatMap(\.problems)
        expectTrue(problems.isEmpty, "rendering problems: \(problems)")
        return text
    }

    private static func ids(_ text: WeeklyReportText) -> [String] { text.app.map(\.id) }

    private static func row(_ text: WeeklyReportText, _ kind: String) -> WeeklyGame? {
        text.analysis.games.first { $0.kind == kind && $0.type == .practice }
    }

    func testOwnRowAndSettingsWords() {
        // The row, area, family and smooth rule; the row label is the locked title.
        expectEqual(WeeklyArea.of(kind: Self.newCard), .pen)
        expectEqual(WeeklyPracticeFamily.of(kind: Self.newCard), .lines)
        expectEqual(ActivityKind.traceOrientedLines.parentCardTitle, "畫直線・四方")
        let solved = ev(.roundResult, ["outcome": .string("solved"), "shapes_done": .int(3), "shapes_total": .int(3),
                                       "wrong_start": .int(0), "reverse_direction": .int(0), "off_path_count": .int(3)],
                        at: Self.monday)
        expectEqual(WeeklySmooth.evaluate(kind: Self.newCard, result: solved), true)
        let refused = ev(.roundResult, ["outcome": .string("solved"), "shapes_done": .int(3), "shapes_total": .int(3),
                                        "wrong_start": .int(1), "reverse_direction": .int(1), "off_path_count": .int(0)],
                         at: Self.monday)
        expectEqual(WeeklySmooth.evaluate(kind: Self.newCard, result: refused), false)
        // Exact keys → the new row only; the 畫形狀設定 keys never mark it; its own words.
        for what in OrientedLineWeekly.configKeys {
            expectEqual(WeeklyComparison.kinds(forConfig: what, kind: nil), [Self.newCard], what)
            expectFalse(WeeklyTextCatalog.configName(what) == nil, what)
        }
        expectEqual(OrientedLineWeekly.configKeys, ["orientedLine_line_shape", "orientedLine_line_direction",
                                                    "orientedLine_line_help", "orientedLine_tolerance"])
        for what in ["shapeTrace_tolerance", "shapeTrace_direction_hint", "shapeTrace_slant_lines", "shapeTrace_dot_style",
                     "lineMatch_tolerance"] {
            expectFalse(WeeklyComparison.kinds(forConfig: what, kind: nil).contains(Self.newCard), what)
        }
        expectTrue(WeeklyComparison.kinds(forConfig: "shapeTrace_tolerance", kind: nil).contains(Self.original))
        expectEqual(WeeklyTextCatalog.fieldName("line_direction", kind: Self.newCard)?.name, WeeklyWords("方向", "Direction"))
        expectEqual(WeeklyTextCatalog.fieldName("line_shape", kind: Self.newCard)?.name, WeeklyWords("線形", "Line shape"))
        expectEqual(WeeklyTextCatalog.fieldName("guide_level", kind: Self.newCard)?.name, WeeklyWords("畫線提示", "Line help"))
        expectEqual(WeeklyTextCatalog.fieldName("tolerance", kind: Self.newCard)?.name,
                    WeeklyWords("畫直線・四方寬容度", "Four ways tolerance"))
        expectEqual(WeeklyTextCatalog.fieldName("tolerance", kind: Self.original)?.name,
                    WeeklyWords("畫形狀寬容度", "Shapes tolerance"), "畫直線 · 熱身 keeps its words")
        expectEqual(WeeklyTextCatalog.fieldName("guide_level", kind: ActivityKind.tapCountTrace.rawValue)?.name,
                    WeeklyWords("描數字提示", "Tracing help"))
        for field in ["line_shape", "line_direction"] { expectTrue(WeeklySignature.dealFields.contains(field)) }
        expectEqual(WeeklyTextCatalog.configName("orientedLine_line_help")?.labels, "guidance")
        print("  畫直線・四方 T13: own row in 手眼・畫線 (lines family, the lines smooth rule); orientedLine_* marks it alone; 線形 / 方向 / 畫線提示 / 寬容度 words")
    }

    func testWeeklySuggestionsReadTheOriginalCardOnly() throws {
        // (a) A week with both cards: A9 reads 畫直線 · 熱身's rounds only.
        seq = 0
        var both: [PerfEvent] = []
        for i in 0..<10 {
            both += round(Self.original, at: Self.at(Self.monday, i % 2, i), dealt: originalDeal(coaching: true))
            both += round(Self.newCard, at: Self.at(Self.monday, i % 2, 30 + i), dealt: newDeal(seed: "a\(i)"))
        }
        let a = Self.build(both)
        expectEqual(Self.ids(a).filter { $0 == "A9" }.count, 1)
        expectEqual(a.app.first { $0.id == "A9" }?.kinds, [Self.original])
        expectEqual(Self.row(a, Self.newCard)?.rounds, 10)
        expectEqual(Self.row(a, Self.original)?.rounds, 10)
        // Six 畫直線 · 熱身 rounds are too few for A9 even beside ten smooth new-card rounds.
        seq = 0
        var few: [PerfEvent] = []
        for i in 0..<6 { few += round(Self.original, at: Self.at(Self.monday, i % 2, i), dealt: originalDeal(coaching: true)) }
        for i in 0..<10 { few += round(Self.newCard, at: Self.at(Self.monday, i % 2, 30 + i), dealt: newDeal(seed: "f\(i)")) }
        expectFalse(Self.ids(Self.build(few)).contains("A9"))
        // A parent's 試玩 of the new card is no row.
        seq = 0
        var playtest: [PerfEvent] = []
        for i in 0..<6 {
            playtest += round(Self.newCard, at: Self.at(Self.monday, 0, i), dealt: newDeal(seed: "p\(i)"), actor: .parentPlaytest)
        }
        expectNil(Self.row(Self.build(playtest), Self.newCard))

        // (b) New-card rounds with many red-end touches, and a dotted deal with 方向提示 off: no A8 for 畫直線.
        seq = 0
        var red: [PerfEvent] = []
        for i in 0..<6 {
            red += round(Self.newCard, at: Self.at(Self.monday, i % 2, i), dealt: newDeal(seed: "b\(i)"), wrongStart: 2)
            red += round(Self.original, at: Self.at(Self.monday, i % 2, 20 + i), dealt: originalDeal(coaching: true))
        }
        red += round(Self.dotted, at: Self.at(Self.monday, 1, 50), dealt: originalDeal(.traceShapesDotted, coaching: false))
        let b = Self.build(red)
        expectFalse(Self.ids(b).contains("A8"))

        // (c) A new-card-only week, even with forced shared fields: no A8 and no A9.
        seq = 0
        var only: [PerfEvent] = []
        for i in 0..<12 {
            only += round(Self.newCard, at: Self.at(Self.monday, i % 2, i),
                          dealt: newDeal(seed: "c\(i)", forced: ["direction_coaching": .bool(false), "slant_enabled": .bool(false)]),
                          wrongStart: i < 6 ? 1 : 0)
        }
        let c = Self.build(only)
        expectFalse(Self.ids(c).contains("A8") || Self.ids(c).contains("A9"))
        expectFalse(c.app.contains { $0.kinds.contains(Self.newCard) && ($0.id == "A8" || $0.id == "A9") })

        // (f) Legacy, unchanged: 畫直線 with 方向提示 off and red-end starts, then a dotted deal with it on → no A8.
        seq = 0
        var legacy: [PerfEvent] = []
        for i in 0..<6 {
            legacy += round(Self.original, at: Self.at(Self.monday, 0, i), dealt: originalDeal(coaching: false),
                            wrongStart: i < 3 ? 1 : 0)
        }
        let control = Self.build(legacy)
        expectEqual(control.app.first { $0.id == "A8" }?.kinds, [Self.original], "control: A8 fires on 畫直線")
        legacy += round(Self.dotted, at: Self.at(Self.monday, 1, 10), dealt: originalDeal(.traceShapesDotted, coaching: true))
        expectFalse(Self.ids(Self.build(legacy)).contains("A8"))

        // (g) Forced new-card values never reach the shared lookup: A8 still fires on 畫直線.
        seq = 0
        var forced: [PerfEvent] = []
        for i in 0..<6 {
            forced += round(Self.original, at: Self.at(Self.monday, 0, i), dealt: originalDeal(coaching: false),
                            wrongStart: i < 3 ? 1 : 0)
        }
        for i in 0..<3 {
            forced += round(Self.newCard, at: Self.at(Self.monday, 1, i),
                            dealt: newDeal(seed: "g\(i)", forced: ["direction_coaching": .bool(true)]))
        }
        expectEqual(Self.build(forced).app.first { $0.id == "A8" }?.kinds, [Self.original])

        // (h) 畫直線加斜線 is still read from the existing shape-trace deals only: A9 still fires.
        seq = 0
        var slant: [PerfEvent] = []
        for i in 0..<10 {
            slant += round(Self.original, at: Self.at(Self.monday, i % 2, i), dealt: originalDeal(coaching: true))
        }
        for i in 0..<3 {
            slant += round(Self.newCard, at: Self.at(Self.monday, 1, 40 + i),
                           dealt: newDeal(seed: "h\(i)", forced: ["slant_enabled": .bool(true)]))
        }
        expectEqual(Self.build(slant).app.first { $0.id == "A9" }?.kinds, [Self.original])

        // (e) Old records behave as today: the golden fixtures hold no new-card event (their goldens are checked
        // byte for byte by the weekly suites, and 畫直線 · 熱身 by T17).
        for name in ["weekly-ranking-5.6", "weekly-2026-10-19"] {
            let folder = URL(fileURLWithPath: "Tests/VisaCoreTests/Fixtures/\(name)", isDirectory: true)
            let events = PerfEventStore(directory: folder).read().events
            expectFalse(events.isEmpty)
            expectFalse(events.contains { $0.string("kind") == Self.newCard }, name)
        }
        print("  畫直線・四方 T13 (a)–(c), (e)–(h): A8 / A9 read 畫直線 · 熱身 only — mixed weeks, red-end-heavy and new-card-only weeks, forced shared fields ignored, legacy unchanged, goldens hold no new-card event")
    }

    func testDirectionChangeMarksOnlyTheNewRow() {
        // (d) Both cards both weeks; the new card switches 左→右 → 右→左: ⚙ on its row only.
        seq = 0
        var events: [PerfEvent] = []
        for (week, direction) in [(Self.lastMonday, OrientedLineDirectionSetting.rightward), (Self.monday, .leftward)] {
            for i in 0..<6 {
                events += round(Self.newCard, at: Self.at(week, i % 2, i), dealt: newDeal(direction, seed: "d\(week)\(i)"))
                events += round(Self.original, at: Self.at(week, i % 2, 20 + i), dealt: originalDeal(coaching: true))
            }
        }
        let d = Self.build(events)
        expectEqual(Self.row(d, Self.newCard)?.settings, [.signature(field: "line_direction", old: "rightward", new: "leftward")])
        expectEqual(Self.row(d, Self.original)?.settings, [])
        expectFalse(d.analysis.comparison.clearChanges.contains { $0.kind == Self.newCard })
        // The 方向 change is written in the row's words.
        expectTrue(d.allSentences.contains { $0.zh.contains("左→右") && $0.zh.contains("右→左") }, "⚙ names 方向 in its own words")
        // A save of the new card's settings marks its row only; a 畫形狀設定 save marks 畫直線 · 熱身 and not the new row.
        seq = 1_000
        let save = ev(.configChange, ["what": .string("orientedLine_line_direction"), "value": .string("leftward")],
                      at: Self.monday.addingTimeInterval(-3600), actor: .parent)
        let shared = ev(.configChange, ["what": .string("shapeTrace_tolerance"), "value": .string("wide")],
                        at: Self.monday.addingTimeInterval(-1800), actor: .parent)
        let saved = Self.build(events + [save, shared])
        let newMarks = Self.row(saved, Self.newCard)?.settings ?? []
        let originalMarks = Self.row(saved, Self.original)?.settings ?? []
        expectTrue(newMarks.contains(.config(what: "orientedLine_line_direction", value: "leftward", star: nil, date: "2026-11-09")))
        expectFalse(newMarks.contains { if case .config(let what, _, _, _) = $0 { return what.hasPrefix("shapeTrace_") }; return false })
        expectTrue(originalMarks.contains { if case .config(let what, _, _, _) = $0 { return what == "shapeTrace_tolerance" }; return false })
        expectFalse(originalMarks.contains { if case .config(let what, _, _, _) = $0 { return what.hasPrefix("orientedLine_") }; return false })

        // (i) A new-card-only fortnight switching 左→右 → 右→左: ⚙ on the new row, still no A8 / A9.
        seq = 0
        var only: [PerfEvent] = []
        for i in 0..<6 {
            only += round(Self.newCard, at: Self.at(Self.lastMonday, i % 2, i), dealt: newDeal(.rightward, seed: "i\(i)"))
        }
        for i in 0..<12 {
            only += round(Self.newCard, at: Self.at(Self.monday, i % 2, i), dealt: newDeal(.leftward, seed: "j\(i)"),
                          wrongStart: i < 6 ? 1 : 0)
        }
        let i = Self.build(only)
        expectEqual(Self.row(i, Self.newCard)?.settings, [.signature(field: "line_direction", old: "rightward", new: "leftward")])
        expectFalse(Self.ids(i).contains("A8") || Self.ids(i).contains("A9"))
        print("  畫直線・四方 T13 (d), (i): a 左→右 → 右→左 switch and an orientedLine_ save mark only the new row; a 畫形狀設定 save never marks it; no A8 / A9")
    }
}
