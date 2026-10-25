import Foundation
import VisaCore

/// Weekly report W3 (weekly-report design §6, §7, §12 W3): the report text built from the W1 metrics and
/// the W2 analysis. Golden fixtures: `Fixtures/weekly-ranking-5.6/expected-text.json` and
/// `Fixtures/weekly-2026-10-19/expected-text.json` (made by `weekly-ranking-5.6/reference_text.py`, video
/// titles from each folder's `video-titles.json`), and the OpenCC-derived
/// `Fixtures/traditional-check/simplified-only.txt` (see the READMEs).
final class WeeklyTextTests {
    private var seq = 0

    private static let fixtureNames = ["weekly-ranking-5.6", "weekly-2026-10-19"]
    /// Monday 2026-10-19, 17:00 HKT: the synthetic weeks below.
    private static let monday = PerfCodec.parseTimestamp("2026-10-19T09:00:00.000Z")!

    /// §6.3 banned phrases (matched as phrases: 「差唔多」 and 「慢慢嚟」 are approved wording).
    private static let bannedPhrases = ["最差", "好差", "差勁", "做得差", "太慢", "好慢", "蠢", "懶", "失敗", "唔叻", "輸咗", "弱"]
    /// §6.3 banned English whole words.
    private static let bannedWords: Set<String> = ["worst", "bad", "fail", "failure", "poor", "slow", "lazy", "weak",
                                                   "behind"]

    private func ev(_ type: PerfEventType, _ fields: [String: PerfValue], at date: Date, actor: PerfActor = .child,
                    session: String = "s1", launch: String = "L1") -> PerfEvent {
        seq += 1
        return PerfEvent(type: type, timestamp: date, tz: "+08:00", mono: Double(seq), launch: launch, seq: seq,
                         app: "0.34.0", actor: actor, mode: "lock", session: session, fields: fields)
    }

    /// `game_dealt`, one wrong `answer_attempt` per entry of `wrong` (its tags), then a solved `round_result`
    /// 30 s later (fields overridable). Right first time when `wrong` is empty.
    private func round(_ kind: String, at date: Date, stars: Int = 1, dealt: [String: PerfValue] = [:],
                       result: [String: PerfValue] = [:], wrong: [[String]] = [], fast: Bool = false,
                       actor: PerfActor = .child, session: String = "s1") -> [PerfEvent] {
        seq += 1
        let id = "t\(seq)"
        var dealtFields: [String: PerfValue] = ["round": .string(id), "kind": .string(kind), "stars": .int(stars)]
        dealtFields.merge(dealt) { _, new in new }
        var events = [ev(.gameDealt, dealtFields, at: date, actor: actor, session: session)]
        for (offset, tags) in wrong.enumerated() {
            let fields: [String: PerfValue] = ["round": .string(id), "correct": .bool(false), "tags": .strings(tags),
                                               "fast": .bool(fast)]
            events.append(ev(.answerAttempt, fields, at: date.addingTimeInterval(Double(offset + 1)), actor: actor,
                             session: session))
        }
        var resultFields: [String: PerfValue] = [
            "round": .string(id), "kind": .string(kind), "outcome": .string("solved"), "answers": .int(1 + wrong.count),
            "first_try": .bool(wrong.isEmpty), "misses": .int(wrong.count), "hint_used": .bool(false),
            "assisted": .bool(false), "total_ms": .int(30_000), "active_ms": .int(4_000), "earned_min": .int(stars * 5)
        ]
        resultFields.merge(result) { _, new in new }
        events.append(ev(.roundResult, resultFields, at: date.addingTimeInterval(30), actor: actor, session: session))
        return events
    }

    private static func at(_ day: Int, _ minute: Int) -> Date {
        monday.addingTimeInterval(Double(day) * 86_400 + Double(minute) * 60)
    }

    private static func build(_ events: [PerfEvent], name: String = WeeklyReportText.defaultChildName) -> WeeklyReportText {
        WeeklyReportTextBuilder.build(events: events, rollup: PerfRollup(), window: WeeklyWindow(containing: monday),
                                      childName: name)
    }

    /// The fixtures sit beside this file; `#filePath` finds them from any working directory.
    private static func fixtureFolder(_ name: String) -> URL {
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: beside.path) { return beside }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/VisaCoreTests/Fixtures/\(name)", isDirectory: true)
    }

    private static func repoRoot() -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) { return root }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    /// Both fixtures are made on Sunday 2026-10-25 at 21:00 HKT for the week of 2026-10-19, with the
    /// folder's synthetic video titles.
    private static func fixtureText(_ name: String) throws -> (text: WeeklyReportText, events: [PerfEvent],
                                                               rollup: PerfRollup, window: WeeklyWindow,
                                                               titles: [String: String]) {
        let folder = fixtureFolder(name)
        let store = PerfEventStore(directory: folder)
        let read = store.read()
        let rollup = store.loadRollup()
        let data = try Data(contentsOf: folder.appendingPathComponent("video-titles.json"))
        let titles = try JSONDecoder().decode([String: String].self, from: data)
        let madeAt = PerfCodec.parseTimestamp("2026-10-25T13:00:00.000Z")!
        guard let window = WeeklyWindow(weekStart: "2026-10-19", dataUntil: madeAt), !read.events.isEmpty else {
            preconditionFailure("weekly fixture \(name) not found or week stamp did not parse")
        }
        let text = WeeklyReportTextBuilder.build(events: read.events, rollup: rollup, window: window, videoTitles: titles)
        return (text, read.events, rollup, window, titles)
    }

    // MARK: Synthetic weeks (mirrored in Python when the expectations were written; see ADR 0023)

    /// Comment extras in order (tag before fuel; the ★★★ rule), F6 before F1, A10 claiming its games.
    private func orderWeek() -> WeeklyReportText {
        seq = 0
        var events: [PerfEvent] = []
        for index in 0..<6 { events += round("shadowMatch", at: Self.at(index % 2, index)) }
        let zeroed: [String: PerfValue] = ["outcome": .string("zeroed"), "answers": .int(3), "first_try": .bool(false),
                                           "misses": .int(3), "earned_min": .int(0)]
        for index in 0..<6 {
            if index < 2 {
                events += round("countVehicles", at: Self.at(index % 2, 20 + index), result: zeroed,
                                wrong: [["over_by_1"], ["over_by_1"], ["over_by_1"]])
            } else {
                events += round("countVehicles", at: Self.at(index % 2, 20 + index), wrong: [["over_by_1"]])
            }
        }
        for index in 0..<6 {
            if index < 3 {
                events += round("moreFewer", at: Self.at(index % 2, 40 + index), stars: 1)
            } else {
                events += round("moreFewer", at: Self.at(index % 2, 40 + index), stars: 3, wrong: [[]])
            }
        }
        return Self.build(events)
    }

    /// Family and app limits, claims, and suggestions equal to this week's settings.
    private func rulesWeek() -> WeeklyReportText {
        seq = 0
        var events: [PerfEvent] = []
        for index in 0..<10 { events += round("shadowMatch", at: Self.at(index % 2, index)) }
        for index in 0..<10 { events += round("findTheSame", at: Self.at(index % 2, 20 + index)) }
        for (kind, tag, base) in [("moreFewer", "fewer", 40), ("capacityCompare", "smaller", 60),
                                  ("emptyBay", "vehicle_attraction", 80)] {
            for index in 0..<6 {
                if index == 0 {
                    events += round(kind, at: Self.at(index % 2, base + index))
                } else {
                    events += round(kind, at: Self.at(index % 2, base + index), wrong: [[tag]], fast: true)
                }
            }
        }
        let practice: [String: PerfValue] = ["answers": .int(0), "first_try": .null]
        let traced = practice.merging(["recount_attempts": .int(0), "guide_clean": .int(0), "guide_helps": .int(3),
                                       "guide_level": .string("more")]) { _, new in new }
        for index in 0..<6 {
            events += round("tapCountTrace", at: Self.at(index % 2, 100 + index),
                            dealt: ["trace_scaffold": .string("dots")], result: traced)
        }
        let road = practice.merging(["roads": .int(3), "roads_total": .int(3), "wrong_start": .int(0),
                                     "off_path_count": .int(7)]) { _, new in new }
        for index in 0..<6 {
            events += round("lineMatchGuidedBridge", at: Self.at(index % 2, 120 + index),
                            dealt: ["match_mode": .string("guided"), "tolerance": .string("wide")], result: road)
        }
        for index in 0..<6 {
            let shape = practice.merging(["shapes_done": .int(3), "shapes_total": .int(3),
                                          "wrong_start": .int(index < 3 ? 1 : 0), "reverse_direction": .int(0),
                                          "off_path_count": .int(0)]) { _, new in new }
            events += round("traceShapesDotted", at: Self.at(index % 2, 140 + index),
                            dealt: ["match_mode": .string("guided"), "direction_coaching": .bool(false)], result: shape)
        }
        return Self.build(events)
    }

    /// Three counted rounds and two in 家長測試中: Q2, with the child's name.
    private func uatWeek(name: String) -> WeeklyReportText {
        seq = 0
        var events: [PerfEvent] = []
        for index in 0..<3 { events += round("shadowMatch", at: Self.at(0, index)) }
        for index in 0..<2 {
            events += round("shadowMatch", at: Self.at(0, 10 + index), actor: .parentUAT, session: "u1")
        }
        return Self.build(events, name: name)
    }

    private func syntheticWeeks() -> [WeeklyReportText] {
        [orderWeek(), rulesWeek(), uatWeek(name: "Mei"), Self.build([])]
    }

    private func allTexts() throws -> [WeeklyReportText] {
        var texts: [WeeklyReportText] = []
        for name in Self.fixtureNames { texts.append(try Self.fixtureText(name).text) }
        return texts + syntheticWeeks()
    }

    // MARK: Scanners

    /// Every ASCII number in `text`: digits, with an optional ".digits" part.
    private static func numbers(in text: String) -> [String] {
        let scalars = Array(text.unicodeScalars)
        var out: [String] = []
        var index = 0
        while index < scalars.count {
            guard isDigit(scalars[index]) else {
                index += 1
                continue
            }
            var run = ""
            while index < scalars.count, isDigit(scalars[index]) {
                run.unicodeScalars.append(scalars[index])
                index += 1
            }
            if index + 1 < scalars.count, scalars[index] == ".", isDigit(scalars[index + 1]) {
                run.unicodeScalars.append(scalars[index])
                index += 1
                while index < scalars.count, isDigit(scalars[index]) {
                    run.unicodeScalars.append(scalars[index])
                    index += 1
                }
            }
            out.append(run)
        }
        return out
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
    }

    /// "07" → "7", "0.4" → "0.4": a number as the traceable list writes it.
    private static func normalized(_ number: String) -> String {
        let parts = number.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        var whole = String(parts.first ?? "")
        while whole.count > 1 && whole.hasPrefix("0") { whole.removeFirst() }
        return parts.count == 2 ? whole + "." + String(parts[1]) : whole
    }

    /// The text without its verbatim spans (titles, the child's name, unknown ids): our copy only.
    private static func ourText(_ text: String, _ verbatim: [String]) -> String {
        var out = text
        for span in verbatim.sorted(by: { $0.count > $1.count }) where !span.isEmpty {
            out = out.replacingOccurrences(of: span, with: " ")
        }
        return out
    }

    private static func bannedHits(_ text: String) -> [String] {
        var hits = bannedPhrases.filter { text.contains($0) }
        var word = ""
        for scalar in (text + " ").unicodeScalars {
            let letter = (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
            if letter {
                word.unicodeScalars.append(scalar)
            } else {
                if bannedWords.contains(word.lowercased()) { hits.append(word) }
                word = ""
            }
        }
        return hits
    }

    /// `Fixtures/traditional-check/simplified-only.txt`: one character per entry, `#` lines are comments.
    private static func simplifiedOnly() throws -> Set<Character> {
        let url = fixtureFolder("traditional-check").appendingPathComponent("simplified-only.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        var characters: Set<Character> = []
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            for character in line where !character.isWhitespace { characters.insert(character) }
        }
        return characters
    }

    // MARK: §6.2 the one formatter

    func testWeeklyTextFormatter() {
        expectEqual(WeeklyFormat.percent(72, of: 97), 74)
        expectEqual(WeeklyFormat.percent(59, of: 86), 69)
        expectEqual(WeeklyFormat.percent(1, of: 8), 13)  // 12.5 % → 13, half up
        expectEqual(WeeklyFormat.percent(0, of: 0), 0)
        expectEqual(WeeklyFormat.percent(1.0 / 3.0), 33)
        expectEqual(WeeklyFormat.percent(0.125), 13)
        expectEqual(WeeklyFormat.percent(1.0 / 24.0), 4)
        expectEqual(WeeklyFormat.tenths(11, 7), 16)
        expectEqual(WeeklyFormat.tenths(36, 15), 24)
        expectEqual(WeeklyFormat.tenths(1, 4), 3)  // 0.25 → 0.3, half up
        expectEqual(WeeklyFormat.decimal(tenths: 16), "1.6")
        expectEqual(WeeklyFormat.decimal(tenths: 4), "0.4")
        expectEqual(WeeklyFormat.minutes(ms: 7_636_685), 127)
        expectEqual(WeeklyFormat.minutes(ms: 29_999), 0)
        expectEqual(WeeklyFormat.minutes(ms: 30_000), 1)
        expectEqual(WeeklyFormat.minutes(ms: 53_100_000, per: 6), 148)  // 147.5 → 148
        expectEqual(WeeklyFormat.minutes(ms: 53_100_000, per: 70), 13)
        expectEqual(WeeklyFormat.minutes(ms: 10, per: 0), 0)
        expectEqual(WeeklyFormat.minutesZH(127), "2 小時 7 分")
        expectEqual(WeeklyFormat.minutesEN(127), "2 h 07 min")
        expectEqual(WeeklyFormat.minutesZH(45), "45 分鐘")
        expectEqual(WeeklyFormat.minutesEN(45), "45 min")
        expectEqual(WeeklyFormat.minutesEN(885), "14 h 45 min")
        expectEqual(WeeklyFormat.seconds(4.25), "4.3")
        expectEqual(WeeklyFormat.seconds(9.94), "9.9")
        expectEqual(WeeklyFormat.seconds(9.96), "10")
        expectEqual(WeeklyFormat.seconds(12.5), "13")
        expectEqual(WeeklyFormat.dayNamesZH, ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"])
        expectEqual(WeeklyFormat.dayNamesEN, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        expectEqual(WeeklyFormat.starMix([7, 2, 1]), "★7 ★★2 ★★★1")
        expectEqual(WeeklyFormat.starMix([3, 0, 2]), "★3 ★★★2")
        expectEqual(WeeklyFormat.rangeLabel(5), TapCountRange.upTo5.label)

        // Every slot renders through the formatter; numbers are traced, words and titles are not.
        let video = WeeklyTemplates.render("video.item", ["title": .verbatim("Bus 1"), "time": .minutes(127, path: "p")])
        expectEqual(video.zh, "「Bus 1」（2 小時 7 分）")
        expectEqual(video.en, "\"Bus 1\" (2 h 07 min)")
        expectEqual(video.traceable, [WeeklyTraceable(path: "p#h", value: "2"), WeeklyTraceable(path: "p#m", value: "7")])
        expectEqual(video.verbatim, ["Bus 1"])
        let clean = WeeklyTemplates.render("win.cleanDay", ["day": .day(1), "n": .int(6, path: "q")])
        expectEqual(clean.zh, "星期二答題全部一次答啱（6 局）。")
        expectEqual(clean.en, "Tue: every quiz round right first time (6).")
        expectTrue(video.problems.isEmpty && clean.problems.isEmpty)
        let range = WeeklyTemplates.render("A3", ["from": .range(5, path: "r"), "to": .range(7, path: "s")])
        expectEqual(range.en, "Bigger numbers: set Numbers from 1–5 to 1–7.")
        expectEqual(range.traceable.map(\.value), ["1", "5", "1", "7"])
        // A value's own braces are text, never a placeholder.
        let braces = WeeklyTemplates.render("video.item", ["title": .verbatim("{time}"), "time": .minutes(5, path: "t")])
        expectEqual(braces.zh, "「{time}」（5 分鐘）")
    }

    // MARK: §6.2 every number traceable

    func testEveryNumberTraceable() throws {
        var checked = 0
        for text in try allTexts() {
            expectTrue(text.problems.isEmpty, "rendering problems: \(text.problems)")
            for sentence in text.allSentences {
                let allowed = Set(sentence.traceable.map { Self.normalized($0.value) })
                for language in [sentence.zh, sentence.en] {
                    let ours = Self.ourText(language, sentence.verbatim)
                    for number in Self.numbers(in: ours) {
                        expectTrue(allowed.contains(Self.normalized(number)), "\(sentence.id): \(number) is not traced in \(language)")
                        checked += 1
                    }
                    for fullWidth in "０１２３４５６７８９" {
                        expectFalse(ours.contains(fullWidth), "\(sentence.id): full-width digit in \(language)")
                    }
                }
                let printed = Set((Self.numbers(in: sentence.zh) + Self.numbers(in: sentence.en)).map { Self.normalized($0) })
                for entry in sentence.traceable {
                    expectFalse(entry.path.isEmpty, "\(sentence.id): a traced number without a path")
                    expectTrue(printed.contains(Self.normalized(entry.value)), "\(sentence.id): \(entry.path) = \(entry.value) is not printed")
                    if entry.path.hasPrefix("copy.") || entry.path.hasPrefix("rule.") {
                        expectTrue(WeeklyTextCatalog.constants[entry.path]?.contains(entry.value) == true,
                                   "\(sentence.id): constant \(entry.path) = \(entry.value)")
                    } else {
                        expectTrue(entry.path.hasPrefix("metrics.") || entry.path.hasPrefix("analysis.")
                                   || entry.path.hasPrefix("facts."), "\(sentence.id): path \(entry.path)")
                    }
                }
            }
        }
        expectTrue(checked > 300, "numbers checked: \(checked)")
        // The scanner: every digit run is found; verbatim spans (titles) are skipped.
        expectEqual(Self.numbers(in: "Played 4×, 2.4 times; 07 and 10/11."), ["4", "2.4", "07", "10", "11"])
        expectEqual(Self.normalized("07"), "7")
        expectEqual(Self.normalized("0.4"), "0.4")
        expectEqual(Self.numbers(in: Self.ourText("「數字歌 1 to 10」（21 分鐘）", ["數字歌 1 to 10"])), ["21"])
        print("  weekly text: \(checked) printed numbers traced")
    }

    // MARK: §6.3 banned words

    func testNoBannedWords() throws {
        expectTrue(Self.bannedHits("差唔多，慢慢嚟，做得好").isEmpty, "approved wording is not banned")
        expectEqual(Self.bannedHits("好慢"), ["好慢"])
        expectTrue(Self.bannedHits("draw slowly, behindhand").isEmpty, "whole words only")
        expectEqual(Self.bannedHits("a slow game"), ["slow"])
        for template in WeeklyTemplates.all {
            expectTrue(Self.bannedHits(template.zh + " " + template.en).isEmpty, "template \(template.id)")
        }
        for words in WeeklyTextCatalog.allWords {
            expectTrue(Self.bannedHits(words.zh + " " + words.en).isEmpty, "catalogue \(words.en)")
        }
        var checked = 0
        for text in try allTexts() {
            for sentence in text.allSentences {
                let ours = Self.ourText(sentence.zh + " " + sentence.en, sentence.verbatim)
                expectTrue(Self.bannedHits(ours).isEmpty, "\(sentence.id): \(Self.bannedHits(ours))")
                checked += 1
            }
        }
        print("  weekly text: \(WeeklyTemplates.all.count) templates and \(checked) sentences free of banned words")
    }

    // MARK: §6.3 Traditional Chinese only

    func testReportStringsTraditionalOnly() throws {
        let simplified = try Self.simplifiedOnly()
        expectTrue(simplified.count > 2_000, "OpenCC list size \(simplified.count)")
        expectFalse(simplified.contains("吓"), "吓 is allowed (§6.3)")
        expectFalse(simplified.contains("晒"), "晒 is allowed (§6.3)")
        expectFalse(simplified.contains("搵"), "game titles keep 搵 (§6.3)")
        // The Simplified forms of 這, 車 and 說, written as escapes so this file stays Traditional only.
        expectTrue(simplified.contains("\u{8FD9}") && simplified.contains("\u{8F66}") && simplified.contains("\u{8BF4}"),
                   "the list has common Simplified forms")

        func check(_ text: String, _ label: String) {
            let found = text.filter { simplified.contains($0) }
            expectTrue(found.isEmpty, "\(label): Simplified \(found)")
            expectTrue(isTraditionalChineseOnly(text) && perfTraditionalOnly(text), "\(label) is Traditional only")
        }
        for template in WeeklyTemplates.all {
            check(template.zh, template.id)
            check(template.en, template.id)
        }
        for words in WeeklyTextCatalog.allWords {
            check(words.zh, words.en)
        }
        for kind in ActivityKind.allCases {
            check(kind.parentCardTitle, kind.rawValue)
        }
        var checked = 0
        for text in try allTexts() {
            for sentence in text.allSentences {
                check(Self.ourText(sentence.zh, sentence.verbatim), sentence.id)
                check(Self.ourText(sentence.en, sentence.verbatim), sentence.id)
                checked += 1
            }
        }
        // Video titles are shown as recorded (§11): the scan skips them, and only them.
        let title = "\u{513F}歌"  // 兒歌 in Simplified form, as a provider might send a title
        let sentence = WeeklyTemplates.render("video.item", ["title": .verbatim(title), "time": .minutes(3, path: "t")])
        expectFalse(sentence.zh.filter { simplified.contains($0) }.isEmpty, "the title itself is Simplified")
        expectTrue(Self.ourText(sentence.zh, sentence.verbatim).filter { simplified.contains($0) }.isEmpty,
                   "our copy around the title is Traditional")

        // Never the host's zone, calendar or locale; Traditional Chinese only in the sources.
        let root = Self.repoRoot()
        for name in ["WeeklyTextFormat.swift", "WeeklyTextTemplates.swift", "WeeklyTextFacts.swift", "WeeklyReportText.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/VisaCore/\(name)"), encoding: .utf8)
            for banned in ["TimeZone.current", "autoupdatingCurrent", "Locale.current", "Calendar.current", "NSTimeZone"] {
                expectFalse(source.contains(banned), "\(name) must not use \(banned)")
            }
            check(source, name)
        }
        print("  weekly text: \(checked) sentences Traditional only (\(simplified.count) OpenCC Simplified-only characters)")
    }

    // MARK: §6.2 first match wins, deterministic

    func testTemplateSelectionDeterministic() throws {
        var ids: Set<String> = []
        for template in WeeklyTemplates.all {
            expectFalse(ids.contains(template.id), "duplicate template \(template.id)")
            ids.insert(template.id)
            let used = Set(WeeklyFormat.placeholders(template.zh) + WeeklyFormat.placeholders(template.en))
            expectEqual(used, Set(template.slots.map(\.name)), template.id)
            expectFalse(template.zh.isEmpty || template.en.isEmpty || template.when.isEmpty, template.id)
        }
        expectEqual(WeeklyTemplates.byID.count, WeeklyTemplates.all.count)

        // The same records give the same text, in any record order.
        for name in Self.fixtureNames {
            let built = try Self.fixtureText(name)
            let again = WeeklyReportTextBuilder.build(events: built.events, rollup: built.rollup, window: built.window,
                                                      videoTitles: built.titles)
            let reversed = WeeklyReportTextBuilder.build(events: Array(built.events.reversed()), rollup: built.rollup,
                                                         window: built.window, videoTitles: built.titles)
            expectEqual(again.canonicalJSON(), built.text.canonicalJSON(), name)
            expectEqual(reversed.canonicalJSON(), built.text.canonicalJSON(), name)
        }
        expectEqual(orderWeek().canonicalJSON(), orderWeek().canonicalJSON())

        // §6.6: first matching template wins, at most 1 main + 1 extra.
        let order = orderWeek()
        func game(_ kind: String) -> WeeklyGameText? { order.games.first { $0.kind == kind } }
        // 數車仔: an approved tag and 2 fuel-outs → bot.tag (listed first); the page-4 main is dropped.
        expectEqual(game("countVehicles")?.comment.map(\.id), ["bot.ft", "bot.tag"])
        expectEqual(game("countVehicles")?.short.map(\.id), ["bot.tag"])
        // 邊邊車多啲: the ★★★ rule without a tag, ⚙ or fuel extra → bot.ft.short + bot.stars.
        expectEqual(game("moreFewer")?.comment.map(\.id), ["bot.ft", "bot.stars"])
        expectEqual(game("moreFewer")?.short.map(\.id), ["bot.ft.short", "bot.stars"])
        // 邊個影子 6/6: top.all (k == n) before top.ft; page 4 uses top.ft.short.
        expectEqual(game("shadowMatch")?.comment.map(\.id), ["top.all"])
        expectEqual(game("shadowMatch")?.short.map(\.id), ["top.ft.short"])
        expectEqual(order.highlights.map(\.id), ["hl.volume", "hl.rates.quiz", "hl.games", "hl.time"])
        for text in try allTexts() {
            for item in text.games {
                expectTrue(item.comment.count <= 2 && item.short.count <= 2, "\(item.kind): 1 main + 1 extra at most")
            }
        }

        // Bad input is reported, never a crash.
        let bad = WeeklyTemplates.render("bot.tag", ["tag": .int(1, path: "x"), "w": .int(2, path: "y")])
        expectFalse(bad.problems.isEmpty, "a mistyped and a missing slot are reported")
        expectFalse(WeeklyTemplates.render("no.such.template").problems.isEmpty)
        expectTrue(WeeklyTemplates.render("vs.same").problems.isEmpty)
    }

    // MARK: §6.7 sample sentences

    func testSampleSentences67ReproducedExactly() throws {
        let text = try Self.fixtureText("weekly-ranking-5.6").text
        func game(_ kind: String) -> WeeklyGameText? { text.games.first { $0.kind == kind } }
        let rise = text.winCandidates.first { $0.id == "win.rise" && $0.en.hasPrefix("\"Shapes · Follow the arrows\"") }
        let samples: [(String, WeeklySentence?, String, String)] = [
            ("1 hl.volume", text.highlights.first,
             "今個星期有 6 日玩（星期三冇玩），總共 154 局：答題 97 局、練習 57 局，比上星期多 24 局。",
             "Played on 6 days (none on Wed): 154 rounds in all, 97 quiz and 57 practice, 24 more than last week."),
            ("2 hl.rates", text.highlights.count > 1 ? text.highlights[1] : nil,
             "答題遊戲第一次答啱 74%（上星期 69%，差唔多）；練習遊戲做得順 74%（上星期 66%，差唔多）。",
             "Quiz games right first time 74% (last week 69%, about the same); practice games done smoothly 74% (last week 66%, about the same)."),
            ("3 top.ft.short (邊個影子)", game("shadowMatch")?.short.first,
             "亂估都有大約 33%，佢明顯高好多，好穩陣。",
             "Guessing alone gives about 33% — well above that, very steady."),
            ("4 bot.tag (數車仔)", game("countVehicles")?.short.first,
             "錯嘅時候多數係「多數咗一架」（8/14 次）。",
             "When wrong, usually \"counted one too many\" (8 of 14)."),
            ("5 bot.helps (一架一架數 · 數完畫)", game("tapCountTrace")?.comment.first,
             "描數字平均每次要提示 1.6 次。",
             "Needed about 1.6 hints per numeral."),
            ("6 bot.offPath (連一連 · 沿路過橋)", game("lineMatchGuidedBridge")?.short.first,
             "平均每條路出界 2.4 次。",
             "Off the road 2.4 times per road on average."),
            ("7 top.memorised (搵另一半)", game("halfMatch")?.short.last,
             "次次都係同一條題目，可能已經記住咗，可以加新題目。",
             "Same question every time — it may be memorised; new versions would help."),
            ("8 win.rise", rise,
             "「畫形狀 · 跟箭嘴」比上星期順咗：3/6 → 7/9。",
             "\"Shapes · Follow the arrows\" went better than last week: 3/6 → 7/9."),
            ("9 insuff.n (圓圓嘅)", game("shapeCousin")?.short.first,
             "玩咗 4 次，全部一次答啱，再玩 1 局就排名。",
             "Played 4×, all right first time; 1 more to rank."),
            ("10 any.settings (連一連 · 自己配)", game("lineMatch")?.short.first,
             "今個星期改咗設定（連一連寬容度：標準 → 闊），同上星期比要小心。",
             "Settings changed this week (Line Match tolerance: Standard → Wide); compare with last week carefully.")
        ]
        for (label, sentence, zh, en) in samples {
            expectEqual(sentence?.zh, zh, "§6.7 sample " + label)
            expectEqual(sentence?.en, en, "§6.7 sample " + label)
        }
        // Where the samples sit: page-4 forms, a win candidate beyond the 3 shown, the ⚙ extra alone.
        expectEqual(game("halfMatch")?.short.map(\.id), ["top.ft.short", "top.memorised"])
        expectEqual(game("lineMatch")?.short.map(\.id), ["any.settings"])
        expectEqual(game("lineMatchGuidedBridge")?.short.map(\.id), ["bot.offPath", "any.settings"])
        expectEqual(text.wins.map(\.id), ["win.newGame", "win.numeral", "win.streak"])
        expectEqual(text.highlights.map(\.id), ["hl.volume", "hl.rates", "hl.games", "hl.time"])
        print("  weekly text: all 10 §6.7 sample sentences rendered (Chinese and English)")
    }

    // MARK: Golden fixtures

    func testWeeklyTextGoldenFixtures() throws {
        for name in Self.fixtureNames {
            let folder = Self.fixtureFolder(name)
            let expectedURL = folder.appendingPathComponent("expected-text.json")
            guard FileManager.default.fileExists(atPath: expectedURL.path) else {
                preconditionFailure("weekly text fixture not found at \(expectedURL.path)")
            }
            let built = try Self.fixtureText(name)
            let actual = built.text.canonicalJSON()
            let expected = try String(contentsOf: expectedURL, encoding: .utf8)
            if actual != expected {
                let got = actual.components(separatedBy: "\n")
                let want = expected.components(separatedBy: "\n")
                var line = min(got.count, want.count)
                for index in 0..<min(got.count, want.count) where got[index] != want[index] {
                    line = index
                    break
                }
                let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-text-actual.json")
                try? Data(actual.utf8).write(to: out)
                let wantLine = line < want.count ? want[line] : "<end>"
                let gotLine = line < got.count ? got[line] : "<end>"
                preconditionFailure("\(name) text golden mismatch at line \(line + 1): expected [\(wantLine)] "
                                    + "got [\(gotLine)]; actual written to \(out.path)")
            }
            print("  weekly text golden \(name): \(expected.utf8.count) bytes match")
            expectTrue(built.text.problems.isEmpty, "\(name): \(built.text.problems)")
            // W3 changes nothing upstream: the analysis inside is the W2 golden.
            let analysis = try String(contentsOf: folder.appendingPathComponent("expected-analysis.json"), encoding: .utf8)
            expectEqual(built.text.analysis.canonicalJSON(), analysis, name)
        }
    }

    // MARK: §7 recommendations

    func testRecommendationRulesAndClaims() {
        // F6 runs before F1 and claims 數車仔; A10 claims both 數字・數量 games, so A1 does not repeat them.
        let order = orderWeek()
        expectEqual(order.family.map(\.id), ["F6", "F1"])
        expectEqual(order.family.map(\.kinds), [["countVehicles"], ["moreFewer"]])
        expectEqual(order.app.map(\.id), ["A10"])
        expectEqual(order.app.first?.text.id, "A10.numbers")
        expectEqual(order.app.first?.kinds, ["countVehicles", "moreFewer"])
        expectTrue(order.praise != nil, "F8 closes the list when there is a win")

        // At most 3 family items (F3 and F7 also apply) and 4 app items (A12 also applies).
        let rules = rulesWeek()
        expectEqual(rules.family.map(\.id), ["F1", "F5", "F4"])
        expectEqual(rules.app.map(\.id), ["A5", "A10", "A1", "A8"])
        // A5: 搵同一個 is already generated in this version; 邊個影子 alone is suggested.
        expectEqual(rules.app.first?.text.id, "A5.one")
        expectEqual(rules.app.first?.kinds, ["shadowMatch"])
        expectEqual(rules.app.last?.settings.map(\.en), ["ShapeTraceSettings.directionHint: off → on"])
        // A4 (guidance already 多啲, trace guide dots) and A6 (bridge only at ★, tolerance already 闊) apply,
        // but their suggestions equal this week's settings, so they are skipped.
        expectFalse(rules.app.contains { $0.id == "A4" || $0.id == "A6" }, "suggestions equal to the current value")
        for items in [order.family.map(\.kinds), order.app.map(\.kinds), rules.family.map(\.kinds), rules.app.map(\.kinds)] {
            let kinds = items.flatMap { $0 }
            expectEqual(kinds.count, Set(kinds).count, "a game feeds at most one item per section")
        }

        // Q2 names the child (D7): the parent's name, Cedric by default.
        let uat = uatWeek(name: "Mei")
        expectEqual(uat.childName, "Mei")
        expectEqual(uat.questions.map(\.id), ["Q2"])
        expectEqual(uat.questions.first?.question.zh,
                    "今個星期有 2 局冇計（家長試玩／測試）。如果有啲其實係 Mei 玩嘅，可以喺「表現 › 最近玩過」撳「計返」。")
        expectEqual(uat.questions.first?.question.en,
                    "2 rounds were not counted (parent testing). If some were actually Mei's, use 表現 › 最近玩過 › 計返.")
        expectEqual(uat.questions.first?.question.verbatim, ["Mei"])
        expectEqual(uat.highlights.map(\.id), ["hl.volume.oneDay", "hl.games.none", "hl.time"])

        // No countable play: page 1 says so; nothing else is suggested (§3).
        let blank = Self.build([], name: "  ")
        expectEqual(blank.childName, WeeklyReportText.defaultChildName)
        expectEqual(blank.empty?.zh, "今個星期未有紀錄。")
        expectTrue(blank.highlights.isEmpty && blank.family.isEmpty && blank.app.isEmpty && blank.questions.isEmpty)
        expectNil(blank.familyNone)
        expectNil(blank.appNone)
        expectNil(blank.praise)
    }
}
