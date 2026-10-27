import Foundation
import VisaCore

/// Weekly report W4 (weekly-report design §3, §8, §9, §12 W4): `WeeklyReportHTML.render`, the report as one
/// self-contained HTML string. Golden fixtures: `Fixtures/weekly-ranking-5.6/expected-report.html` (sample
/// watermark on) and `Fixtures/weekly-2026-10-19/expected-report.html`, made by
/// `weekly-ranking-5.6/reference_html.py` from each folder's W1–W3 goldens (see the READMEs). The synthetic
/// weeks below were mirrored in Python when the expectations were written (ADR 0024).
final class WeeklyReportHTMLTests {
    private var seq = 0

    private static let fixtureNames = ["weekly-ranking-5.6", "weekly-2026-10-19"]
    /// Monday 2026-10-19, 00:00 HKT.
    private static let monday = PerfCodec.parseTimestamp("2026-10-18T16:00:00.000Z")!
    /// Sunday 2026-10-25, 21:00 HKT: when the fixtures and the synthetic weeks are made.
    private static let madeAt = PerfCodec.parseTimestamp("2026-10-25T13:00:00.000Z")!
    /// The series colours `validate_palette.js` passed (light, surface #ffffff, adjacent pairs; ADR 0024).
    private static let validatedSeries = ["#2a78d6", "#eb6834", "#1baf7a"]

    /// §6.3 banned phrases and English whole words (as in `WeeklyTextTests`).
    private static let bannedPhrases = ["最差", "好差", "差勁", "做得差", "太慢", "好慢", "蠢", "懶", "失敗", "唔叻", "輸咗", "弱"]
    private static let bannedWords: Set<String> = ["worst", "bad", "fail", "failure", "poor", "slow", "lazy", "weak",
                                                   "behind"]

    /// One rendered week.
    private struct Rendered {
        let name: String
        let report: WeeklyReportText
        let html: String
    }

    // MARK: Records

    private func ev(_ type: PerfEventType, _ fields: [String: PerfValue], at date: Date, actor: PerfActor = .child,
                    session: String = "s1", app: String = "0.34.0") -> PerfEvent {
        seq += 1
        return PerfEvent(type: type, timestamp: date, tz: "+08:00", mono: Double(seq), launch: "L1", seq: seq,
                         app: app, actor: actor, mode: "lock", session: session, fields: fields)
    }

    /// `game_dealt` (★), then a solved `round_result` `seconds` later: right first time, or right after one miss.
    private func quiz(_ kind: String, at date: Date, right: Bool = true, ms: Int = 30_000, seconds: Double = 30,
                      actor: PerfActor = .child, session: String = "s1", app: String = "0.34.0") -> [PerfEvent] {
        seq += 1
        let id = "r\(seq)"
        let dealt: [String: PerfValue] = ["round": .string(id), "kind": .string(kind), "stars": .int(1)]
        let result: [String: PerfValue] = [
            "round": .string(id), "kind": .string(kind), "outcome": .string("solved"), "answers": .int(right ? 1 : 2),
            "first_try": .bool(right), "misses": .int(right ? 0 : 1), "hint_used": .bool(false),
            "assisted": .bool(false), "total_ms": .int(ms), "active_ms": .int(4_000), "earned_min": .int(5)
        ]
        return [ev(.gameDealt, dealt, at: date, actor: actor, session: session, app: app),
                ev(.roundResult, result, at: date.addingTimeInterval(seconds), actor: actor, session: session, app: app)]
    }

    /// A 一架一架數 · 點一點 practice round, done smoothly (no recount).
    private func tapRound(at date: Date, ms: Int = 30_000) -> [PerfEvent] {
        seq += 1
        let id = "r\(seq)"
        let dealt: [String: PerfValue] = ["round": .string(id), "kind": .string("tapCountAll"), "stars": .int(1)]
        let result: [String: PerfValue] = [
            "round": .string(id), "kind": .string("tapCountAll"), "outcome": .string("solved"), "answers": .int(0),
            "first_try": .null, "misses": .int(0), "hint_used": .bool(false), "assisted": .bool(false),
            "total_ms": .int(ms), "active_ms": .int(4_000), "earned_min": .int(5), "recount_attempts": .int(0)
        ]
        return [ev(.gameDealt, dealt, at: date), ev(.roundResult, result, at: date.addingTimeInterval(30))]
    }

    /// A picker play of video `v1`, watched for `seconds`.
    private func video(at date: Date, seconds: Int) -> [PerfEvent] {
        seq += 1
        let play = "p\(seq)"
        let start: [String: PerfValue] = ["play": .string(play), "video": .string("v1"), "source": .string("picker")]
        let end: [String: PerfValue] = ["play": .string(play), "video": .string("v1"),
                                        "watched_s": .double(Double(seconds))]
        return [ev(.videoStart, start, at: date), ev(.videoEnd, end, at: date.addingTimeInterval(Double(seconds)))]
    }

    /// A parent `config_change`.
    private func config(_ what: String, _ value: PerfValue, at date: Date, kind: String? = nil, star: Int? = nil,
                        app: String = "0.34.0") -> PerfEvent {
        var fields: [String: PerfValue] = ["what": .string(what), "value": value]
        if let kind { fields["kind"] = .string(kind) }
        if let star { fields["star"] = .int(star) }
        return ev(.configChange, fields, at: date, actor: .parent, session: "p", app: app)
    }

    private static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        monday.addingTimeInterval(Double(((day * 24 + hour) * 60 + minute) * 60))
    }

    // MARK: Synthetic weeks (mirrored in Python when the expectations were written; ADR 0024)

    /// Mon: 6 邊個影子 (5 right first time); Tue: 3 數車仔 and `tapRounds` 點數; Wed: a 10-minute video.
    private func currentPlay(tapRounds: Int = 2) -> [PerfEvent] {
        var events: [PerfEvent] = []
        for index in 0..<6 { events += quiz("shadowMatch", at: Self.at(0, 10, index), right: index != 5) }
        for index in 0..<3 { events += quiz("countVehicles", at: Self.at(1, 10, index)) }
        for index in 0..<tapRounds { events += tapRound(at: Self.at(1, 11, index)) }
        events += video(at: Self.at(2, 19), seconds: 600)
        return events
    }

    /// No earlier records: the first week (no history, no C3 / C4).
    private func baselineWeek() -> [PerfEvent] {
        seq = 0
        return currentPlay()
    }

    /// One earlier week: 6 邊個影子 (4 right) and 5 點數.
    private func oneEarlierWeek() -> [PerfEvent] {
        seq = 0
        var events: [PerfEvent] = []
        for index in 0..<6 { events += quiz("shadowMatch", at: Self.at(-7, 10, index), right: index < 4) }
        for index in 0..<5 { events += tapRound(at: Self.at(-6, 11, index)) }
        return events + currentPlay()
    }

    /// Two earlier weeks: the week of 10-05 starts on Wednesday (partial); 10-12 has 3 quiz rounds (a C4 gap).
    private func twoEarlierWeeks() -> [PerfEvent] {
        seq = 0
        var events: [PerfEvent] = []
        for index in 0..<6 { events += quiz("shadowMatch", at: Self.at(-12, 10, index)) }
        for index in 0..<5 { events += tapRound(at: Self.at(-12, 11, index)) }
        for index in 0..<3 { events += quiz("shadowMatch", at: Self.at(-7, 10, index)) }
        for index in 0..<5 { events += tapRound(at: Self.at(-6, 11, index)) }
        return events + currentPlay(tapRounds: 5)
    }

    /// Last week has records from Friday only; this week's few rounds took no time and nothing was watched.
    private func lowDataWeek() -> [PerfEvent] {
        seq = 0
        var events: [PerfEvent] = []
        for index in 0..<2 { events += quiz("shadowMatch", at: Self.at(-3, 10, index)) }
        for index in 0..<3 { events += quiz("countVehicles", at: Self.at(0, 10, index), ms: 0) }
        for index in 0..<2 { events += tapRound(at: Self.at(1, 11, index), ms: 0) }
        return events
    }

    /// Made on Wednesday at 18:30 (`inProgressUntil`): records from Tuesday, one round still open at the
    /// cut-off, one after it.
    private func inProgressWeek() -> [PerfEvent] {
        seq = 0
        var events: [PerfEvent] = []
        for index in 0..<5 { events += quiz("shadowMatch", at: Self.at(1, 9, index)) }
        for index in 0..<3 { events += quiz("findTheSame", at: Self.at(2, 10, index)) }
        events += video(at: Self.at(2, 12), seconds: 300)
        events += quiz("shadowMatch", at: Self.at(2, 18, 29), seconds: 90)
        events += quiz("shadowMatch", at: Self.at(2, 19))
        return events
    }

    private static let inProgressUntil = WeeklyReportHTMLTests.at(2, 18, 30)

    /// 28 games of unknown kinds (area 其他): 21 with 2 rounds and 7 with 1, so the matrix folds 7 rows.
    private func foldWeek() -> [PerfEvent] {
        seq = 0
        var events: [PerfEvent] = []
        for number in 1...28 {
            let kind = number < 10 ? "game0\(number)" : "game\(number)"
            for turn in 0..<(number <= 21 ? 2 : 1) {
                events += quiz(kind, at: Self.at(number % 7, 9 + turn, number))
            }
        }
        return events
    }

    /// Parent playtest rounds only: no countable play.
    private func emptyWeek() -> [PerfEvent] {
        seq = 0
        var events: [PerfEvent] = []
        for index in 0..<2 {
            events += quiz("shadowMatch", at: Self.at(0, 10, index), actor: .parentPlaytest, session: "pt")
        }
        return events
    }

    /// Videos only: countable play without a game.
    private func videoOnlyWeek() -> [PerfEvent] {
        seq = 0
        return video(at: Self.at(0, 18), seconds: 900) + video(at: Self.at(1, 18), seconds: 1_200)
    }

    /// Two quiz games right first time once in 8 rounds each over two days: ranked, but nothing goes well.
    private func allLearningWeek() -> [PerfEvent] {
        seq = 0
        var events: [PerfEvent] = []
        for kind in ["shadowMatch", "findTheSame"] {
            for index in 0..<8 { events += quiz(kind, at: Self.at(index % 2, 10, index), right: index == 0) }
        }
        return events
    }

    /// Four games clearly up, four ⚙ games, three app versions, 3 setting changes and 4 star assignments.
    private func capsWeek() -> [PerfEvent] {
        seq = 0
        let clear = ["shadowMatch", "findTheSame", "halfMatch", "countVehicles"]
        let gear: [(kind: String, star: Int, on: Bool)] = [("moreFewer", 3, true), ("capacityCompare", 3, true),
                                                           ("emptyBay", 2, false), ("sequenceShortToLong", 3, true)]
        var events = [config("lineMatch_tolerance", .string("standard"), at: Self.at(-2, 8), kind: "lineMatch",
                             app: "0.32.0")]
        for kind in clear {
            for index in 0..<8 {
                events += quiz(kind, at: Self.at(-7 + index / 4, 10, index), right: index == 0, app: "0.32.0")
            }
        }
        events.append(config("lineMatch_tolerance", .string("wide"), at: Self.at(0, 8), kind: "lineMatch",
                             app: "0.33.0"))
        events.append(config("shapeTrace_direction_hint", .string("on"), at: Self.at(1, 8), app: "0.33.1"))
        events.append(config("tapCount_range", .string("1-10"), at: Self.at(2, 8)))
        for (day, app) in [(0, "0.33.0"), (1, "0.33.1")] {
            for kind in clear {
                for index in 0..<4 { events += quiz(kind, at: Self.at(day, 10, index), app: app) }
            }
        }
        for item in gear {
            events.append(config("assignment", .bool(item.on), at: Self.at(3, 8), kind: item.kind, star: item.star))
        }
        for item in gear {
            for index in 0..<2 { events += quiz(item.kind, at: Self.at(2, 10, index)) }
        }
        return events
    }

    // MARK: Rendering

    private static func render(_ events: [PerfEvent], until: Date = WeeklyReportHTMLTests.madeAt,
                               childName: String = WeeklyReportText.defaultChildName,
                               titles: [String: String] = [:]) -> (report: WeeklyReportText, html: String) {
        guard let window = WeeklyWindow(weekStart: "2026-10-19", dataUntil: until) else {
            preconditionFailure("week stamp did not parse")
        }
        let report = WeeklyReportTextBuilder.build(events: events, rollup: PerfRollup(), window: window,
                                                   childName: childName, videoTitles: titles)
        let html = WeeklyReportHTML.render(report, options: WeeklyReportHTMLOptions(generatedAt: madeAt))
        return (report, html)
    }

    private func syntheticWeeks() -> [Rendered] {
        var out: [Rendered] = []
        func add(_ name: String, _ events: [PerfEvent], until: Date = WeeklyReportHTMLTests.madeAt) {
            let built = Self.render(events, until: until)
            out.append(Rendered(name: name, report: built.report, html: built.html))
        }
        add("baseline", baselineWeek())
        add("oneEarlier", oneEarlierWeek())
        add("twoEarlier", twoEarlierWeeks())
        add("lowData", lowDataWeek())
        add("inProgress", inProgressWeek(), until: Self.inProgressUntil)
        add("fold", foldWeek())
        add("empty", emptyWeek())
        add("videoOnly", videoOnlyWeek())
        add("allLearning", allLearningWeek())
        add("caps", capsWeek())
        return out
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

    /// A fixture week made as in W3 (`WeeklyTextTests`): Sunday 21:00, with the folder's video titles; the §5.6
    /// sample carries the sample watermark (the design's sample report), the W1 fixture does not.
    private static func fixtureReport(_ name: String) throws -> (events: [PerfEvent], rollup: PerfRollup,
                                                                 window: WeeklyWindow, titles: [String: String],
                                                                 report: WeeklyReportText, html: String) {
        let folder = fixtureFolder(name)
        let store = PerfEventStore(directory: folder)
        let read = store.read()
        let rollup = store.loadRollup()
        let data = try Data(contentsOf: folder.appendingPathComponent("video-titles.json"))
        let titles = try JSONDecoder().decode([String: String].self, from: data)
        guard let window = WeeklyWindow(weekStart: "2026-10-19", dataUntil: madeAt), !read.events.isEmpty else {
            preconditionFailure("weekly fixture \(name) not found or week stamp did not parse")
        }
        let report = WeeklyReportTextBuilder.build(events: read.events, rollup: rollup, window: window,
                                                   videoTitles: titles)
        let html = WeeklyReportHTML.render(report, options: fixtureOptions(name))
        return (read.events, rollup, window, titles, report, html)
    }

    private static func fixtureOptions(_ name: String) -> WeeklyReportHTMLOptions {
        WeeklyReportHTMLOptions(generatedAt: madeAt, sampleWatermark: name == "weekly-ranking-5.6")
    }

    private func allReports() throws -> [Rendered] {
        var out: [Rendered] = []
        for name in Self.fixtureNames {
            let built = try Self.fixtureReport(name)
            out.append(Rendered(name: name, report: built.report, html: built.html))
        }
        return out + syntheticWeeks()
    }

    // MARK: Scanners

    private static func count(_ text: String, _ needle: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// The text between each `open` and the next `close`.
    private static func spans(_ text: String, _ open: String, _ close: String) -> [String] {
        var out: [String] = []
        for part in text.components(separatedBy: open).dropFirst() {
            out.append(part.components(separatedBy: close).first ?? "")
        }
        return out
    }

    /// The page sections, in order (from just after `<section class="page`).
    private static func pages(_ html: String) -> [String] {
        spans(html, "<section class=\"page", "</section>")
    }

    /// Every `<svg …>…</svg>` of `text`, in order.
    private static func svgs(_ text: String) -> [String] {
        spans(text, "<svg ", "</svg>").map { "<svg " + $0 }
    }

    /// The renderer's escaping, for expected strings.
    private static func esc(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Text without tags, entities decoded (text never holds a raw `<` or `>`: both are escaped).
    private static func plain(_ fragment: String) -> String {
        var out = ""
        var inTag = false
        for character in fragment {
            if character == "<" {
                inTag = true
            } else if character == ">" {
                inTag = false
            } else if !inTag {
                out.append(character)
            }
        }
        return unescape(out)
    }

    /// The document text a reader sees: the stylesheet dropped, tags removed, one space between elements.
    private static func visibleText(_ html: String) -> String {
        var text = html
        if let open = text.range(of: "<style>"), let close = text.range(of: "</style>"),
           open.upperBound <= close.lowerBound {
            text.removeSubrange(open.upperBound..<close.lowerBound)
        }
        return plain(text.replacingOccurrences(of: "<", with: " <"))
    }

    /// `name="value"` in a start tag (`name` preceded by a space).
    private static func attribute(_ tag: String, _ name: String) -> String? {
        let parts = tag.components(separatedBy: " " + name + "=\"")
        guard parts.count > 1 else { return nil }
        return parts[1].components(separatedBy: "\"").first
    }

    /// "12.3" → 123, "-1.5" → -15, "190" → 1900: SVG numbers in tenths (the renderer prints one decimal at most).
    private static func tenths(_ text: String) -> Int? {
        var body = Substring(text)
        var sign = 1
        if body.hasPrefix("-") {
            sign = -1
            body = body.dropFirst()
        }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2, let whole = Int(parts[0]) else { return nil }
        var value = whole * 10
        if parts.count == 2 {
            guard parts[1].count == 1, let digit = Int(parts[1]) else { return nil }
            value += digit
        }
        return sign * value
    }

    /// Width in tenths of a px at font size `size` (tenths of a px): `emWidth` is in thousandths of an em.
    private static func width(_ text: String, _ size: Int) -> Int {
        (WeeklyReportHTML.emWidth(text) * size + 999) / 1000
    }

    /// Lines of `text` in a box `box` tenths of a px wide, 92 % of it usable (the layout estimate's rule).
    private static func lines(_ text: String, _ size: Int, _ box: Int) -> Int {
        guard !text.isEmpty else { return 0 }
        let usable = box * 92 / 100
        return max(1, (width(text, size) + usable - 1) / usable)
    }

    /// Chinese and English halves of a `bi()` fragment ("zh<span class="en">en</span>").
    private static func halves(_ fragment: String) -> (zh: String, en: String) {
        let parts = fragment.components(separatedBy: "<span class=\"en\">")
        return (plain(parts[0]), parts.count > 1 ? plain(parts[1]) : "")
    }

    /// Every `#rrggbb` in `text` (`&#39;` skipped); anything else after a `#` comes back short and fails.
    private static func hexColours(_ text: String) -> [String] {
        let scalars = Array(text.unicodeScalars)
        var out: [String] = []
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "#", index == 0 || scalars[index - 1] != "&" else {
                index += 1
                continue
            }
            var hex = "#"
            var next = index + 1
            while next < scalars.count, next - index <= 6, isHex(scalars[next]) {
                hex.unicodeScalars.append(scalars[next])
                next += 1
            }
            out.append(hex)
            index = next
        }
        return out
    }

    /// Lowercase hex digits only (the palette writes lowercase).
    private static func isHex(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 97 && scalar.value <= 102)
    }

    /// Tag nesting problems (void and self-closed elements skipped, the stylesheet skipped).
    private static func nestingProblems(_ html: String) -> [String] {
        var text = html
        if let open = text.range(of: "<style>"), let close = text.range(of: "</style>"),
           open.upperBound <= close.lowerBound {
            text.removeSubrange(open.upperBound..<close.lowerBound)
        }
        let voids: Set<String> = ["meta", "br", "col"]
        var stack: [String] = []
        var problems: [String] = []
        var index = text.startIndex
        while let open = text[index...].firstIndex(of: "<") {
            guard let close = text[open...].firstIndex(of: ">") else {
                problems.append("a < without >")
                break
            }
            let tag = String(text[text.index(after: open)..<close])
            index = text.index(after: close)
            if tag.hasPrefix("!") || tag.hasSuffix("/") { continue }
            if tag.hasPrefix("/") {
                let name = String(tag.dropFirst())
                if stack.last == name {
                    stack.removeLast()
                } else {
                    problems.append("</\(name)> closes <\(stack.last ?? "nothing")>")
                }
                continue
            }
            let name = String(tag.prefix(while: { $0 != " " }))
            if !voids.contains(name) { stack.append(name) }
        }
        if !stack.isEmpty { problems.append("not closed: \(stack)") }
        return problems
    }

    /// Fails with the first differing line and byte offset; the actual text is written to the temporary folder.
    private static func expectSameText(_ actual: String, _ expected: String, _ label: String, file: String) {
        guard actual != expected else { return }
        let got = Array(actual.utf8)
        let want = Array(expected.utf8)
        var offset = 0
        while offset < got.count, offset < want.count, got[offset] == want[offset] { offset += 1 }
        var line = 1
        for byte in want.prefix(offset) where byte == 10 { line += 1 }
        let gotLines = actual.components(separatedBy: "\n")
        let wantLines = expected.components(separatedBy: "\n")
        let wantLine = line - 1 < wantLines.count ? wantLines[line - 1] : "<end>"
        let gotLine = line - 1 < gotLines.count ? gotLines[line - 1] : "<end>"
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(file)
        try? Data(actual.utf8).write(to: out)
        preconditionFailure("\(label) golden mismatch at line \(line), byte offset \(offset) (expected \(want.count) "
                            + "bytes, got \(got.count)): expected [\(wantLine)] got [\(gotLine)]; actual written to "
                            + out.path)
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

    private static func label(_ id: String, _ values: [String: WeeklyWords] = [:]) -> WeeklyWords {
        WeeklyReportLabels.text(id, values)
    }

    // MARK: Golden fixtures (byte for byte)

    func testHTMLGolden() throws {
        for name in Self.fixtureNames {
            let folder = Self.fixtureFolder(name)
            let expectedURL = folder.appendingPathComponent("expected-report.html")
            guard FileManager.default.fileExists(atPath: expectedURL.path) else {
                preconditionFailure("weekly report fixture not found at \(expectedURL.path)")
            }
            let built = try Self.fixtureReport(name)
            // Upstream first, so a W1–W3 difference is reported as such rather than as an HTML diff.
            let metrics = try String(contentsOf: folder.appendingPathComponent("expected-metrics.json"), encoding: .utf8)
            Self.expectSameText(built.report.analysis.model.canonicalJSON(), metrics, "\(name) metrics",
                                file: "\(name)-metrics-actual.json")
            let analysis = try String(contentsOf: folder.appendingPathComponent("expected-analysis.json"),
                                      encoding: .utf8)
            Self.expectSameText(built.report.analysis.canonicalJSON(), analysis, "\(name) analysis",
                                file: "\(name)-analysis-actual.json")
            let text = try String(contentsOf: folder.appendingPathComponent("expected-text.json"), encoding: .utf8)
            Self.expectSameText(built.report.canonicalJSON(), text, "\(name) text", file: "\(name)-text-actual.json")
            let expected = try String(contentsOf: expectedURL, encoding: .utf8)
            Self.expectSameText(built.html, expected, "\(name) report HTML", file: "\(name)-report-actual.html")
            print("  weekly report golden \(name): \(expected.utf8.count) bytes match")

            // Pure: the same records in any order give the same bytes; the options only add the watermark.
            let reversed = WeeklyReportTextBuilder.build(events: Array(built.events.reversed()), rollup: built.rollup,
                                                         window: built.window, videoTitles: built.titles)
            expectEqual(WeeklyReportHTML.render(reversed, options: Self.fixtureOptions(name)), built.html, name)
            let sample = name == "weekly-ranking-5.6"
            expectEqual(built.html.contains("示例數據 EXAMPLE DATA"), sample, name)
            let plainOptions = WeeklyReportHTMLOptions(generatedAt: Self.madeAt)
            expectFalse(plainOptions.sampleWatermark, "the watermark is off by default")
            let unmarked = WeeklyReportHTML.render(built.report, options: plainOptions)
            expectFalse(unmarked.contains("示例數據") || unmarked.contains("EXAMPLE DATA"), name)
            if sample {
                // One watermark, one header tag and one footer note per page.
                expectEqual(Self.count(built.html, "<div class=\"wm\">示例數據 EXAMPLE DATA</div>"), 6)
                expectEqual(Self.count(built.html, "<div class=\"rh-tag\">示例數據 EXAMPLE DATA</div>"), 6)
                expectTrue(built.html.contains("<title>VisaGames 每週學習報告 2026-10-19（示例數據）</title>"))
            } else {
                expectEqual(unmarked, built.html, name)
            }

            // §9.6: 數據指紋 is the first 8 of 16 lowercase hex digits; 「製作於」 is the option, never the clock.
            let fingerprint = WeeklyReportHTML.fingerprint(built.report.analysis.model)
            expectEqual(fingerprint.count, 16)
            expectTrue(fingerprint.unicodeScalars.allSatisfy { Self.isHex($0) }, fingerprint)
            expectEqual(Self.count(built.html, "數據指紋 " + String(fingerprint.prefix(8))), 6)
            expectEqual(Self.count(built.html, "製作於 2026-10-25 21:00 HKT"), 6)
            let later = WeeklyReportHTMLOptions(generatedAt: Self.madeAt.addingTimeInterval(86_400),
                                                sampleWatermark: sample)
            let made = WeeklyReportHTML.render(built.report, options: later)
            expectEqual(Self.count(made, "製作於 2026-10-26 21:00 HKT"), 6)
            expectEqual(made.replacingOccurrences(of: "製作於 2026-10-26", with: "製作於 2026-10-25"), built.html)
        }
        // The fingerprint follows the counted records.
        let first = Self.render(baselineWeek()).report.analysis.model
        let second = Self.render(oneEarlierWeek()).report.analysis.model
        let again = Self.render(baselineWeek()).report.analysis.model
        expectFalse(WeeklyReportHTML.fingerprint(first) == WeeklyReportHTML.fingerprint(second))
        expectEqual(WeeklyReportHTML.fingerprint(first), WeeklyReportHTML.fingerprint(again))
    }

    // MARK: §3 six pages (page 1 only without countable play)

    func testPageCountSix() throws {
        expectEqual(WeeklyReportHTML.pageCount, 6)
        var checked = 0
        for item in try allReports() where item.report.empty == nil {
            let html = item.html
            expectEqual(Self.count(html, "<section class=\"page"), WeeklyReportHTML.pageCount, item.name)
            expectEqual(Self.count(html, "</section>"), WeeklyReportHTML.pageCount, item.name)
            var last = html.startIndex
            for page in 1...WeeklyReportHTML.pageCount {
                guard let found = html.range(of: "\" id=\"p\(page)\">\n", range: last..<html.endIndex) else {
                    preconditionFailure("\(item.name): page \(page) missing or out of order")
                }
                last = found.upperBound
                let number = "第 \(page) 頁，共 6 頁 · Page \(page) of 6"
                expectEqual(Self.count(html, number), 1, "\(item.name): \(number)")
            }
            for page in Self.pages(html) {
                expectEqual(Self.count(page, "<div class=\"runhead\">"), 1, item.name)
                expectEqual(Self.count(page, "<div class=\"runfoot\">"), 1, item.name)
                expectTrue(page.contains("家長版，只供家人參考 For parents, family use only"), item.name)
            }
            checked += 1
        }
        expectEqual(checked, 11)

        // No countable play (only parent playtest rounds): page 1 says so, numbered 「共 1 頁」 (§3).
        let blank = Self.render(emptyWeek())
        expectTrue(blank.report.empty != nil)
        expectEqual(Self.count(blank.html, "<section class=\"page"), 1)
        expectTrue(blank.html.contains("第 1 頁，共 1 頁 · Page 1 of 1"))
        expectTrue(blank.html.contains("今個星期未有紀錄。"))
        expectTrue(blank.html.contains("今個星期有 2 局唔計。"))
        expectTrue(blank.html.contains(Self.esc(Self.label("wr.privacy").zh)))
        expectFalse(blank.html.contains("<svg") || blank.html.contains("<table") || blank.html.contains("class=\"tile\""))
        // A week with no records at all is the same single page.
        let nothing = Self.render([])
        expectEqual(Self.count(nothing.html, "<section class=\"page"), 1)
        expectTrue(nothing.html.contains("第 1 頁，共 1 頁 · Page 1 of 1"))
        // Videos alone are countable play: six pages.
        let videos = Self.render(videoOnlyWeek())
        expectNil(videos.report.empty)
        expectEqual(Self.count(videos.html, "<section class=\"page"), 6)
        print("  weekly report: \(checked) weeks with play on 6 pages, weeks without on 1")
    }

    // MARK: §3 / §8 chart fallbacks and low-data states

    func testChartFallbacks() throws {
        let quizBar = "fill=\"" + WeeklyReportPalette.quiz + "\""
        let hollowQuiz = "fill=\"#ffffff\" stroke=\"" + WeeklyReportPalette.quiz + "\""
        let diamond = " l5 5 l-5 5 l-5 -5 Z\""

        // 0 weeks of history: no C3 / C4 (page 5 says why), C2 without ◇, the first-week note on page 1 and 5.
        let baseline = Self.render(baselineWeek())
        var pages = Self.pages(baseline.html)
        expectEqual(baseline.report.analysis.model.weeks.count, 1)
        let firstWeek = Self.esc(Self.label("wr.baseline").zh)
        expectTrue(pages[0].contains("<p class=\"pair tilenote\"><span class=\"zh\">" + firstWeek))
        expectTrue(pages[4].contains("<p class=\"chartnote\">" + firstWeek))
        expectEqual(Self.svgs(pages[4]).count, 2, "C2a and C2b only")
        expectFalse(pages[4].contains(Self.esc(Self.label("c3.title").zh)))
        var c2a = Self.svgs(pages[4])[0]
        expectEqual(Self.count(c2a, diamond), 1, "the legend's ◇ only: nothing last week")
        expectTrue(c2a.contains(">數據唔夠（3 局） Not enough data (3 rounds)</text>"), "數車仔: n < 5, no bar")
        expectTrue(c2a.contains(">83%（6 局）</text>"))
        expectEqual(Self.count(c2a, "<path"), 2, "one bar and the legend ◇")
        expectTrue(Self.svgs(pages[4])[1].contains(">數據唔夠（2 局） Not enough data (2 rounds)</text>"))
        // A rate tile with fewer than 5 rounds: 「—」 and 「數據唔夠」 (§3).
        expectTrue(pages[0].contains("<div class=\"val na\">—</div><div class=\"cmp\">數據唔夠（2 局）"
                                     + "<span class=\"en\">Not enough data (2 rounds)</span></div>"))
        expectTrue(pages[0].contains(">89%</div>"))
        // Fewer than 2 qualified games: page 4 prints W3's status instead of the two lists.
        expectFalse(baseline.report.analysis.ranking.ranked)
        let status = baseline.report.ranking.status
        expectTrue(status != nil && pages[3].contains("<p class=\"status\">" + Self.esc(status?.zh ?? "")))
        expectFalse(pages[3].contains(Self.esc(Self.label("p4.top").zh)))
        // No settings changes and no recommendations: W3's sentences stand in (§3).
        expectTrue(pages[4].contains("今個星期冇改設定"))
        expectTrue(baseline.report.familyNone != nil && baseline.report.appNone != nil)
        expectTrue(pages[5].contains(Self.esc(baseline.report.familyNone?.zh ?? "-")))
        expectTrue(pages[5].contains(Self.esc(baseline.report.appNone?.zh ?? "-")))

        // 1 week of history: C3 and C4 with two weeks; ◇ last week where it had ≥ 5 rounds.
        let one = Self.render(oneEarlierWeek())
        pages = Self.pages(one.html)
        expectEqual(one.report.analysis.model.weeks.count, 2)
        var charts = Self.svgs(pages[4])
        expectEqual(charts.count, 4)
        expectTrue(charts[0].contains(">10/12–18</text>") && charts[0].contains(">10/19–25</text>"))
        expectEqual(Self.count(charts[1], "<polyline"), 1, "quiz in both weeks, practice < 5 this week")
        expectTrue(charts[1].contains("stroke=\"" + WeeklyReportPalette.quiz + "\" stroke-width=\"2\""))
        c2a = charts[2]
        expectEqual(Self.count(c2a, diamond), 2, "the legend and 觀察・配對 last week")
        expectTrue(c2a.contains(">83%（6 局） · 上星期 67%</text>"))
        expectFalse(pages[0].contains("tilenote"), "a whole previous week: no note")

        // 2 weeks of history: the partial week hollow with 「部分」; 3 quiz rounds in 10-12 leave a C4 gap.
        let two = Self.render(twoEarlierWeeks())
        pages = Self.pages(two.html)
        expectEqual(two.report.analysis.model.weeks.map(\.partial), [true, false, false])
        charts = Self.svgs(pages[4])
        expectEqual(charts.count, 4)
        expectTrue(charts[0].contains(hollowQuiz), "C3: the partial week is outlined")
        expectTrue(charts[0].contains(">部分</text>") && charts[0].contains(">partial</text>"))
        expectTrue(charts[0].contains(">10/5–11</text>") && charts[0].contains(">今個星期</text>"))
        expectEqual(Self.count(charts[1], "<polyline"), 1, "practice joined; quiz has a gap at 10-12")
        expectTrue(charts[1].contains("<polyline") && charts[1].contains("stroke=\"" + WeeklyReportPalette.practice
                                                                         + "\" stroke-width=\"2\" stroke-linejoin"))
        expectTrue(charts[1].contains("r=\"4\" " + hollowQuiz), "C4: a partial week's dot is hollow")
        expectTrue(charts[1].contains("r=\"4\" " + quizBar), "C4: this week's quiz dot")
        expectTrue(charts[1].contains(">答題 89%</text>") && charts[1].contains(">練習 100%</text>"), "end labels")
        expectTrue(charts[1].contains(">少過 5 局嘅星期唔畫點 · weeks with &lt; 5 rounds of a type are not plotted</text>"))

        // A partial previous week, all-zero minutes, every tile base < 5, nothing ranked.
        let low = Self.render(lowDataWeek())
        pages = Self.pages(low.html)
        expectTrue(pages[0].contains("上星期只有 3 日有紀錄，比較只可以做參考。"))
        expectTrue(pages[0].contains("上星期 1 日<span class=\"en\">Last week: 1 day</span>"), "singular")
        expectEqual(Self.count(pages[0], "<div class=\"val na\">—</div>"), 2)
        expectTrue(pages[0].contains("數據唔夠（3 局）"))
        expectFalse(pages[1].contains("<svg"), "C1 has no bars to draw")
        expectTrue(pages[1].contains("<p class=\"chartnote\">今個星期未有遊戲或睇片紀錄。"))
        expectFalse(low.report.analysis.ranking.ranked)
        expectTrue(Self.svgs(pages[4])[2].contains(">數據唔夠（0 局） Not enough data (0 rounds)</text>"))

        // A week in progress: days before the first record, after the cut-off, and 「截至 18:30」.
        let progress = Self.render(inProgressWeek(), until: Self.inProgressUntil)
        pages = Self.pages(progress.html)
        expectTrue(pages[0].contains("資料截至 10月21日 18:30"))
        expectTrue(pages[0].contains("data up to Wed 21 Oct, 18:30 HKT"))
        expectEqual(Self.count(pages[1], "<td class=\"muted l\" colspan=\"7\">未有紀錄 · No records</td>"), 1)
        expectEqual(Self.count(pages[1], "<td class=\"muted l\" colspan=\"7\">未到 · Not yet</td>"), 4)
        expectTrue(pages[1].contains("；截至 18:30<span class=\"en\">first time: Find the same; to 18:30</span>"))
        let c1 = Self.svgs(pages[1])[0]
        expectEqual(Self.count(c1, ">未有紀錄 No records</text>"), 1)
        expectEqual(Self.count(c1, ">未到 Not yet</text>"), 4)
        expectTrue(c1.contains(">截至 18:30 / to 18:30</text>"))
        expectTrue(pages[1].contains("星期三只計到 18:30。"))
        expectTrue(pages[4].contains("冇計：製作報告時仲玩緊 1 局。"))
        expectTrue(progress.html.contains("資料截至 2026-10-21 18:30 HKT · 製作於 2026-10-25 21:00 HKT"))
        expectEqual(progress.report.analysis.model.current.coveredDays, 2)

        // More than 22 game rows: the 7 with the fewest rounds fold into one line; the glossary moves to page 6.
        let fold = Self.render(foldWeek())
        pages = Self.pages(fold.html)
        expectEqual(Self.count(pages[2], "<tr><td class=\"name\">"), WeeklyReportHTML.matrixKeepRows)
        expectTrue(pages[2].contains("<tr class=\"fold\"><td colspan=\"10\">其他 7 個遊戲（共 7 局）：game22、game23、"
                                     + "game24、game25、game26、game27同另外 1 個遊戲<span class=\"en\">7 other games "
                                     + "(7 rounds): game22, game23, game24, game25, game26, game27 and 1 more</span>"))
        let glossary = Self.esc(Self.label("gloss.title").zh)
        expectFalse(pages[2].contains(glossary))
        expectTrue(pages[5].contains(glossary))
        expectFalse(pages[2].contains(">game28<"), "folded rows are named in the fold line only")

        // Videos only: the game parts say there were no games; C1 draws two video bars.
        let videos = Self.render(videoOnlyWeek())
        pages = Self.pages(videos.html)
        let noGames = "<p class=\"status\">今個星期冇玩遊戲。"
        expectTrue(pages[2].contains(noGames) && pages[3].contains(noGames))
        expectTrue(pages[4].contains("今個星期同上星期都冇答題遊戲。") && pages[4].contains("今個星期同上星期都冇練習遊戲。"))
        let videoChart = Self.svgs(pages[1])[0]
        expectEqual(Self.count(videoChart, "<path"), 2)
        expectEqual(Self.count(videoChart, "fill=\"" + WeeklyReportPalette.video + "\"/>"), 2)

        // Ranked, but no game going well: W3's status under the going-well head, then the still-learning rows.
        let learning = Self.render(allLearningWeek())
        pages = Self.pages(learning.html)
        expectTrue(learning.report.analysis.ranking.ranked && learning.report.analysis.ranking.top.count == 0)
        expectEqual(learning.report.ranking.status?.id, "rank.allLearning")
        expectTrue(pages[3].contains("</div>\n<p class=\"status\">今個星期每個遊戲都仲學緊，慢慢嚟。"))
        expectEqual(Self.count(pages[3], "<div class=\"row\">"), 2)
        expectFalse(pages[3].contains(Self.esc(Self.label("wr.bottom.none").zh)))

        // Caps: 3 clear changes + a count, 3 ⚙ names + a count, versions as a range, 2 change lines + a count.
        let caps = Self.render(capsWeek())
        pages = Self.pages(caps.html)
        expectEqual(caps.report.analysis.comparison.clearChanges.count, 4)
        expectEqual(Self.count(pages[4], "（明顯進步）"), WeeklyReportHTML.clearMax)
        expectTrue(pages[4].contains("仲有 1 個遊戲都有明顯變化。<span class=\"en\">1 more game changed clearly.</span>"))
        expectTrue(pages[4].contains("同另外 1 個遊戲今個星期改咗設定，所以唔同上星期比。"))
        expectTrue(pages[4].contains("and 1 more: settings changed this week, so not compared."))
        expectTrue(pages[4].contains("用過 3 個 app 版本，由 v0.33.0 到 v0.34.0。"))
        expectTrue(pages[4].contains("10月19日（一）連一連寬容度：標準 → 闊（影響 3 個遊戲）。"))
        expectTrue(pages[4].contains("仲有 5 項改動冇列出。<span class=\"en\">5 more changes not listed.</span>"))
        expectEqual(caps.report.analysis.changes.settings.count + caps.report.analysis.changes.assignments.count, 7)
        expectTrue(pages[0].contains("今個星期 app 更新咗 2 次、改咗 7 個設定，詳情喺第 5 頁。"))
        expectTrue(caps.html.contains("App v0.33.0–v0.34.0"))
        // Every qualified game goes well: the still-learning list says it is empty (§3).
        expectTrue(pages[3].contains("<p class=\"status\">" + Self.esc(Self.label("wr.bottom.none").zh)))
        print("  weekly report: chart fallbacks for 0, 1 and 2 weeks of history, n < 5, zero minutes, folds and caps")
    }

    // MARK: §9.2 / §13 items 10–11 text budgets

    func testNoTextOverflowBudget() throws {
        var problems: [String] = []
        var checked = 0
        func need(_ used: Int, _ limit: Int, _ what: String) {
            checked += 1
            if used > limit { problems.append("\(what): \(used) > \(limit)") }
        }
        for item in try allReports() {
            let html = item.html
            let name = item.name
            // SVG text never wraps: every label stays inside its chart's viewBox.
            for svg in Self.svgs(html) {
                let box = (Self.attribute(svg, "viewBox") ?? "").split(separator: " ").compactMap { Int($0) }
                guard box.count == 4 else {
                    problems.append("\(name): a chart without a viewBox")
                    continue
                }
                for element in Self.spans(svg, "<text ", "</text>") {
                    let parts = element.components(separatedBy: ">")
                    let tag = " " + parts[0]
                    guard parts.count == 2, let x = Self.attribute(tag, "x").flatMap(Self.tenths),
                          let y = Self.attribute(tag, "y").flatMap(Self.tenths),
                          let size = Self.attribute(tag, "font-size").flatMap(Self.tenths) else {
                        problems.append("\(name): unreadable <text \(element)")
                        continue
                    }
                    let content = Self.unescape(parts[1])
                    let used = Self.width(content, size)
                    let left: Int
                    switch Self.attribute(tag, "text-anchor") ?? "start" {
                    case "middle": left = x - used / 2
                    case "end": left = x - used
                    default: left = x
                    }
                    need(-left, 0, "\(name) chart text left of 0: \(content)")
                    need(left + used, box[2] * 10, "\(name) chart text right edge: \(content)")
                    need(y, box[3] * 10, "\(name) chart text baseline: \(content)")
                    need(size * 8 / 10, y, "\(name) chart text top: \(content)")
                }
            }
            // One-line (nowrap) parts: running head, page number, tile values, badges, list-head splits.
            for head in Self.spans(html, "<div class=\"runhead\">", "</div>\n") {
                var used = Self.width(Self.plain(Self.spans(head, "<div class=\"rh-left\">", "</div>").first ?? ""), 96)
                if let tag = Self.spans(head, "<div class=\"rh-tag\">", "</div>").first {
                    used += Self.width(Self.plain(tag), 93) + 160
                }
                need(used, 6_880, "\(name) running head")
            }
            for foot in Self.spans(html, "<div class=\"runfoot\"><div class=\"prov\">", "</div></div>\n") {
                let parts = foot.components(separatedBy: "</div><div class=\"pageno\">")
                guard parts.count == 2 else {
                    problems.append("\(name): footer without a page number")
                    continue
                }
                need(Self.width(Self.plain(parts[1]), 88), 1_600, "\(name) page number")
                var footLines = 0
                for row in parts[0].components(separatedBy: "<br>") {
                    footLines += Self.lines(Self.plain(row), 83, 6_880 - 1_600 - 120)
                }
                need(footLines, 4, "\(name) footer lines (50 px at 8.3 px × 1.35)")
            }
            for value in Self.spans(html, "<div class=\"val", "</div>") {
                let body = String(value.drop(while: { $0 != ">" }).dropFirst())
                let pieces = body.components(separatedBy: "<small>")
                var big = pieces[0]
                var small = ""
                for piece in pieces.dropFirst() {
                    let halves = piece.components(separatedBy: "</small>")
                    small += halves[0]
                    if halves.count > 1 { big += halves[1] }
                }
                need(Self.width(Self.unescape(big), 227) + Self.width(Self.unescape(small), 120), 1_990,
                     "\(name) tile value \(body)")
            }
            for badge in Self.spans(html, "<span class=\"badge ", "</span>") {
                need(Self.width(Self.plain(String(badge.drop(while: { $0 != ">" }))), 80), 1_200, "\(name) badge")
            }
            for split in Self.spans(html, "<span class=\"split\">", "</span>") {
                need(Self.width(Self.unescape(split), 99), 6_880 - 2_600, "\(name) list head split \(split)")
            }
            // M1: day cells, totals and tickets on one line; names in two lines at most, English in one.
            if let matrix = Self.spans(html, "<table class=\"matrix\">", "</table>").first {
                for cls in ["q", "p", "na"] {
                    for cell in Self.spans(matrix, "<td class=\"\(cls)\">", "</td>") {
                        need(Self.width(Self.unescape(cell), 101), 420 - 40, "\(name) matrix cell \(cell)")
                    }
                }
                for cell in Self.spans(matrix, "<td class=\"tot", "</td>") {
                    need(Self.width(Self.plain(String(cell.drop(while: { $0 != ">" }))), 101), 460 - 40,
                         "\(name) matrix total \(cell)")
                }
                for cell in Self.spans(matrix, "<td class=\"stars\">", "</td>") {
                    need(Self.width(Self.unescape(cell), 90), 600 - 40, "\(name) matrix tickets \(cell)")
                }
                for cell in Self.spans(matrix, "<td class=\"name\">", "</td>") {
                    let split = Self.halves(cell)
                    var badges = 0
                    for badge in Self.spans(cell, "<span class=\"badge ", "</span>") {
                        badges += Self.width(Self.plain(String(badge.drop(while: { $0 != ">" }))), 80) + 123
                    }
                    let head = cell.components(separatedBy: "<span class=\"en\">")[0]
                    let zh = Self.plain(head.components(separatedBy: "</span>").last ?? "")
                    let usable = 2_850 * 92 / 100
                    need((badges + Self.width(zh, 101) + usable - 1) / usable, 2, "\(name) matrix name \(zh)")
                    need(Self.lines(split.en, 81, 2_850), 1, "\(name) matrix English name \(split.en)")
                }
                for cell in Self.spans(matrix, "<tr class=\"fold\"><td colspan=\"10\">", "</td>") {
                    let split = Self.halves(cell)
                    need(Self.lines(split.zh, 93, 6_820) + Self.lines(split.en, 81, 6_820), 4, "\(name) fold line")
                }
            }
            // Page 2: dates on one line, notes in 4 lines at most.
            if let daily = Self.spans(html, "<table class=\"daily\">", "</table>").first {
                for cell in Self.spans(daily, "<tr><td class=\"l\">", "</td>") {
                    need(Self.width(Self.halves(cell).zh, 107), 960 - 80, "\(name) date \(cell)")
                }
                for cell in Self.spans(daily, "<td class=\"l note-cell\">", "</td>") {
                    let split = Self.halves(cell)
                    need(Self.lines(split.zh, 96, 1_540) + Self.lines(split.en, 85, 1_540), 4, "\(name) day note")
                }
            }
        }

        // Template budgets, whatever the data (chart geometry of `WeeklyReportCharts`, column widths of the CSS).
        // C1: the day labels fit the day's slot, (683 − 46) / 7 px, with 2 px either side.
        let slot = (6_830 - 460) / 7
        for id in ["day.noPlay", "day.notYet", "day.noRecords"] {
            let words = Self.label(id)
            need(Self.width(words.zh + " " + words.en, 90), slot - 40, "C1 \(id)")
        }
        let cut = Self.label("day.upTo", ["time": WeeklyReportLabels.same("21:00")])
        need(Self.width(cut.zh + " / " + cut.en, 80), slot - 40, "C1 cut-off")
        for index in 0..<WeeklyWindow.dayCount {
            need(Self.width(WeeklyFormat.dayNamesZH[index], 95), slot - 40, "C1 day name")
            need(Self.width(WeeklyFormat.dayNamesEN[index] + " 28", 85), slot - 40, "C1 day")
        }
        // C3 / C4: week labels for 1–7 weeks ("10/26–11/1" up to 4 weeks, "12/28" past that).
        for (chart, plot) in [("C3", 3_220 - 340), ("C4", 2_900 - 340)] {
            for weeks in 1...(WeeklyMetricsBuilder.trendWeeks + 1) {
                let weekSlot = plot / weeks
                need(Self.width(weeks > 4 ? "12/28" : "10/26–11/1", 90), weekSlot - 40, "\(chart) \(weeks) weeks")
                for id in ["week.this", "week.partial"] {
                    let words = Self.label(id)
                    need(max(Self.width(words.zh, 80), Self.width(words.en, 80)), weekSlot, "\(chart) \(id)")
                }
            }
        }
        // C2a / C2b: row names end before the bars (x = 186 px); the widest value label ends inside the chart.
        for area in WeeklyArea.allCases where area != .pen {
            need(max(Self.width(area.zh, 100), Self.width(area.en, 85)), 1_860 - 60, "C2a \(area.rawValue)")
        }
        for family in WeeklyPracticeFamily.allCases {
            let words = Self.label("family." + family.rawValue)
            need(max(Self.width(words.zh, 100), Self.width(words.en, 85)), 1_860 - 60, "C2b \(family.rawValue)")
        }
        let valueX = 1_860 + 3_300 + 50 + 100
        let value = Self.label("c2.value", ["p": WeeklyReportLabels.number(100), "n": WeeklyReportLabels.number(999)]).zh
            + Self.label("c2.last", ["p": WeeklyReportLabels.number(100)]).zh
        need(valueX + Self.width(value, 95), 6_880, "C2 value label")
        let guess = Self.label("c2.guess", ["c": WeeklyReportLabels.number(99)])
        need(valueX + Self.width(guess.zh + " · " + guess.en, 80), 6_880, "C2 lucky-guess label")
        // M1: every game title with every badge in two lines of the 288 px name column, English in one.
        var allBadges = 0
        for id in ["badge.quiz", "badge.fixed", "badge.settings"] {
            allBadges += Self.width(Self.label(id).zh, 80) + 123
        }
        let newBadge = Self.label("badge.new")
        allBadges += Self.width(newBadge.zh + " " + newBadge.en, 80) + 123
        let nameUsable = 2_850 * 92 / 100
        for kind in ActivityKind.allCases {
            need((allBadges + Self.width(kind.parentCardTitle, 101) + nameUsable - 1) / nameUsable, 2,
                 "M1 \(kind.rawValue)")
            need(Self.width(kind.parentCardEnglish, 81), nameUsable, "M1 English \(kind.rawValue)")
        }
        // The caps that keep lists short are the published constants.
        expectEqual([WeeklyReportHTML.matrixMaxRows, WeeklyReportHTML.matrixKeepRows, WeeklyReportHTML.foldNamesMax,
                     WeeklyReportHTML.gearNamesMax, WeeklyReportHTML.newNamesMax, WeeklyReportHTML.clearMax,
                     WeeklyReportHTML.versionsListed, WeeklyReportHTML.changeLinesMax], [22, 21, 6, 3, 1, 3, 2, 2])

        expectTrue(problems.isEmpty, problems.joined(separator: "\n"))
        expectTrue(checked > 3_000, "budgets checked: \(checked)")
        print("  weekly report: \(checked) text budgets within their boxes")
    }

    // MARK: §8 palette

    func testHTMLPaletteTokens() throws {
        // The Swift palette is the validated one (validate_palette.js; the JS itself never runs in the app).
        expectEqual(WeeklyReportPalette.validatedSeries, Self.validatedSeries)
        expectEqual([WeeklyReportPalette.quiz, WeeklyReportPalette.video, WeeklyReportPalette.practice],
                    Self.validatedSeries)
        let tokens = Set(WeeklyReportPalette.all)
        for token in WeeklyReportPalette.all {
            expectEqual(Self.hexColours(token), [token], "palette token \(token)")
        }
        for series in Self.validatedSeries {
            expectTrue(tokens.contains(series), series)
        }
        // The page chrome wears the app's own tokens (`DesignTokens.Palette`); the matrix tints are the series
        // colours at 12 % on white, 255 − round(0.12 × (255 − c)) per channel.
        func hex(_ value: UInt32) -> String {
            let digits = String(value, radix: 16)
            return "#" + String(repeating: "0", count: max(0, 6 - digits.count)) + digits
        }
        expectEqual(WeeklyReportPalette.brand, hex(DesignTokens.Palette.passportBlue))
        expectEqual(WeeklyReportPalette.paper, hex(DesignTokens.Palette.paper))
        expectEqual(WeeklyReportPalette.ticket, hex(DesignTokens.Palette.taxiTicket))
        expectEqual(WeeklyReportPalette.metro, hex(DesignTokens.Palette.metroTicket))
        func tint(_ colour: String) -> String {
            let digits = Array(colour.dropFirst())
            var out = "#"
            for index in stride(from: 0, to: 6, by: 2) {
                let channel = Int(String(digits[index...index + 1]), radix: 16) ?? 0
                let text = String(255 - (12 * (255 - channel) + 50) / 100, radix: 16)
                out += (text.count < 2 ? "0" : "") + text
            }
            return out
        }
        expectEqual(tint(WeeklyReportPalette.quiz), WeeklyReportPalette.quizTint)
        expectEqual(tint(WeeklyReportPalette.practice), WeeklyReportPalette.practiceTint)
        let inks = Set([WeeklyReportPalette.ink, WeeklyReportPalette.ink2, WeeklyReportPalette.muted])
        let marks = Set(Self.validatedSeries + [WeeklyReportPalette.surface, WeeklyReportPalette.grid,
                                                WeeklyReportPalette.baseline, WeeklyReportPalette.guessBand])
        var colours = 0
        for item in try allReports() {
            for colour in Self.hexColours(item.html) {
                expectTrue(tokens.contains(colour), "\(item.name): \(colour) is not a palette token")
                colours += 1
            }
            for svg in Self.svgs(item.html) {
                // Chart text wears the ink tokens; marks the series colours, the surface and the rules.
                for element in Self.spans(svg, "<text ", ">") {
                    expectTrue(inks.contains(Self.attribute(" " + element, "fill") ?? ""), "\(item.name) text fill")
                }
                for shape in ["<path ", "<rect ", "<circle ", "<line ", "<polyline "] {
                    for element in Self.spans(svg, shape, "/>") {
                        let tag = " " + element
                        for key in ["fill", "stroke"] {
                            guard let colour = Self.attribute(tag, key), colour != "none" else { continue }
                            expectTrue(marks.contains(colour) || colour == WeeklyReportPalette.ink2,
                                       "\(item.name): \(shape)\(key)=\(colour)")
                        }
                    }
                }
            }
        }
        expectTrue(colours > 1_000, "colours checked: \(colours)")
        print("  weekly report: \(colours) colours, all \(tokens.count) palette tokens (series \(Self.validatedSeries))")
    }

    // MARK: D2 self-contained

    func testHTMLSelfContained() throws {
        let banned = ["http", "src=", "<script", "url(", "@import", "@font-face", "<link", "<img", "<iframe", "<object",
                      "<embed", "href=", "javascript:", "xmlns"]
        for item in try allReports() {
            for needle in banned {
                expectFalse(item.html.contains(needle), "\(item.name) contains \(needle)")
            }
            // §9.5: Hong Kong Chinese, UTF-8, the sans fonts named in the design; inline CSS once.
            expectTrue(item.html.hasPrefix("<!DOCTYPE html>\n<html lang=\"zh-Hant-HK\">\n<head>\n<meta charset=\"utf-8\">\n"))
            expectTrue(item.html.contains("font-family: \"PingFang HK\", \"Noto Sans CJK HK\", sans-serif;"))
            expectEqual(Self.count(item.html, "<style>"), 1, item.name)
            expectTrue(item.html.contains("section.page { position: relative; box-sizing: border-box; width: 794px; "
                                          + "height: 1123px; overflow: hidden;"))
        }
        // Every interpolated string is escaped, names and video titles included (D7, D8).
        seq = 0
        let title = "<script>alert(1)</script> & 'Bus' \"1\""
        let built = Self.render(currentPlay(), childName: "Mei <b>&</b>", titles: ["v1": title])
        expectFalse(built.html.contains("<script") || built.html.contains("<b>&"), "raw markup from data")
        expectTrue(built.html.contains("&lt;script&gt;alert(1)&lt;/script&gt; &amp; &#39;Bus&#39; &quot;1&quot;"),
                   "the title is escaped and otherwise unchanged")
        expectTrue(built.html.contains("Mei &lt;b&gt;&amp;&lt;/b&gt;"))
        expectEqual(Self.count(built.html, "只計 Mei &lt;b&gt;&amp;&lt;/b&gt; 自己玩 · Counts Mei &lt;b&gt;&amp;&lt;/b&gt;"
                               + "&#39;s own play only"), 6)
        expectTrue(Self.nestingProblems(built.html).isEmpty, "\(Self.nestingProblems(built.html))")

        // The renderer reads no clock, host zone, calendar or locale, and runs no script.
        let root = Self.repoRoot()
        for name in ["WeeklyReportHTML.swift", "WeeklyReportCharts.swift", "WeeklyReportLayout.swift",
                     "WeeklyReportLabels.swift", "WeeklyReportCSS.swift", "WeeklyReportPalette.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/VisaCore/\(name)"), encoding: .utf8)
            for needle in ["Date()", "TimeZone.current", "autoupdatingCurrent", "Locale.current", "Calendar.current",
                           "NSTimeZone", "String(format:", "import WebKit", "import AppKit", "import SwiftUI",
                           "http"] {
                expectFalse(source.contains(needle), "\(name) must not use \(needle)")
            }
        }
        print("  weekly report: self-contained (no URL, script, font file or image), escaped names and titles")
    }

    // MARK: Well-formed

    func testHTMLWellFormed() throws {
        var elements = 0
        for item in try allReports() {
            let html = item.html
            expectTrue(html.hasSuffix("</section>\n</body>\n</html>\n"), item.name)
            let problems = Self.nestingProblems(html)
            expectTrue(problems.isEmpty, "\(item.name): \(problems.prefix(5))")
            for (open, close) in [("<section ", "</section>"), ("<svg ", "</svg>"), ("<table", "</table>"),
                                  ("<tr", "</tr>"), ("<ul ", "</ul>"), ("<li>", "</li>"), ("<text ", "</text>")] {
                expectEqual(Self.count(html, open), Self.count(html, close), "\(item.name) \(open)")
                elements += Self.count(html, open)
            }
            // Every chart is inside a page, a `div.chart`, with a viewBox and no fixed pixel size.
            for svg in Self.svgs(html) {
                expectTrue(svg.hasPrefix("<svg viewBox=\"0 0 "), item.name)
                expectNil(Self.attribute(svg.components(separatedBy: ">")[0], "width"))
            }
            expectEqual(Self.count(html, "<div class=\"chart\">\n<svg "), Self.count(html, "<svg "), item.name)
            // Numbers are POSIX: no thousands separators, no comma decimals, no NaN.
            for svg in Self.svgs(html) {
                expectFalse(svg.contains("NaN") || svg.contains("inf") || svg.contains("e+"), item.name)
                for element in Self.spans(svg, "<text ", ">") {
                    for key in ["x", "y", "font-size"] {
                        expectTrue(Self.attribute(" " + element, key).flatMap(Self.tenths) != nil, "\(item.name) \(key)")
                    }
                }
            }
        }
        expectTrue(elements > 1_000, "elements checked: \(elements)")
        print("  weekly report: \(elements) elements balanced and nested")
    }

    // MARK: Every W3 sentence on its page

    func testW3StringsPresent() throws {
        var shownCount = 0
        var hiddenCount = 0
        for item in try allReports() {
            let report = item.report
            let html = item.html
            let ranking = report.analysis.ranking
            var shown: [WeeklySentence] = []
            var hidden: [WeeklySentence] = []
            if let empty = report.empty { shown.append(empty) }
            shown += report.highlights
            if let videos = report.videos { shown.append(videos) }
            if report.empty == nil {
                shown += report.wins
                hidden += report.winCandidates.dropFirst(report.wins.count)
                shown += report.changes
                for family in report.family {
                    shown += [family.text, family.because]
                }
                for sentence in [report.praise, report.familyNone, report.appNone] {
                    if let sentence { shown.append(sentence) }
                }
                for app in report.app {
                    shown += [app.text, app.because, app.check]
                }
                for question in report.questions {
                    shown.append(question.question)
                    if let note = question.note { shown.append(note) }
                }
                // Page 4: the ranked rows print fact and short form, the 數據唔夠 list the short form.
                var rows: Set<String> = []
                if ranking.ranked && !report.analysis.model.current.kinds.isEmpty {
                    for line in [report.ranking.status, report.ranking.topSplit, report.ranking.stillLearningSplit,
                                 report.ranking.alsoWell, report.ranking.alsoLearning] {
                        if let line { shown.append(line) }
                    }
                    for lists in [ranking.top, ranking.stillLearning] {
                        for kind in lists.quiz { rows.insert(kind + "|quiz") }
                        for kind in lists.practice { rows.insert(kind + "|practice") }
                    }
                } else if !report.analysis.model.current.kinds.isEmpty, let status = report.ranking.status {
                    shown.append(status)
                }
                var insufficient: Set<String> = []
                for entry in ranking.insufficient {
                    insufficient.insert(entry.kind + "|" + entry.type.rawValue)
                }
                for game in report.games {
                    let key = game.kind + "|" + game.type.rawValue
                    // The long forms are not on a page (page 4 prints the short forms; ADR 0024).
                    hidden += game.comment
                    if rows.contains(key) {
                        if let fact = game.fact { shown.append(fact) }
                        shown += game.short
                    } else if insufficient.contains(key) {
                        shown += game.short
                        if let fact = game.fact { hidden.append(fact) }
                    } else {
                        hidden += game.short
                        if let fact = game.fact { hidden.append(fact) }
                    }
                }
            }
            for sentence in shown {
                expectTrue(html.contains(Self.esc(sentence.zh)), "\(item.name) \(sentence.id): \(sentence.zh)")
                expectTrue(html.contains(Self.esc(sentence.en)), "\(item.name) \(sentence.id): \(sentence.en)")
            }
            // App settings are code lines, the same in both languages; each is printed once.
            for app in report.app where report.empty == nil {
                for setting in app.settings {
                    expectEqual(setting.zh, setting.en, setting.id)
                    expectTrue(html.contains("<div class=\"param\">" + Self.esc(setting.en) + "</div>"), setting.en)
                    shownCount += 1
                }
            }
            // Anything else in the model is one of the forms above that the pages leave out.
            for sentence in report.allSentences {
                let printed = html.contains(Self.esc(sentence.zh)) && html.contains(Self.esc(sentence.en))
                let accounted = printed || hidden.contains(sentence) || report.empty != nil
                    || report.app.contains { $0.settings.contains(sentence) }
                expectTrue(accounted, "\(item.name) \(sentence.id) is neither on a page nor a known hidden form")
            }
            // The child's name (D7) and the provenance line on every page.
            expectTrue(html.contains("只計 " + Self.esc(report.childName) + " 自己玩"), item.name)
            shownCount += shown.count
            hiddenCount += hidden.count
        }
        expectTrue(shownCount > 200, "sentences on pages: \(shownCount)")
        print("  weekly report: \(shownCount) W3 sentences on their pages (\(hiddenCount) long or spare forms kept off)")
    }

    // MARK: §6.3 Traditional Chinese only, no banned words

    func testHTMLTraditionalOnlyAndNoBannedWords() throws {
        let simplified = try Self.simplifiedOnly()
        expectTrue(simplified.count > 2_000, "OpenCC list size \(simplified.count)")
        func check(_ text: String, _ label: String) {
            let found = text.filter { simplified.contains($0) }
            expectTrue(found.isEmpty, "\(label): Simplified \(found)")
            expectTrue(isTraditionalChineseOnly(text) && perfTraditionalOnly(text), "\(label) is Traditional only")
            expectTrue(Self.bannedHits(text).isEmpty, "\(label): banned \(Self.bannedHits(text))")
        }
        // Every W4 label, weekday, month and glossary entry.
        expectEqual(WeeklyReportLabels.table.count, 177)
        for (id, words) in WeeklyReportLabels.table {
            check(words.zh, id)
            check(words.en, id)
            expectFalse(words.zh.isEmpty || words.en.isEmpty, id)
        }
        for words in WeeklyReportLabels.weekdays {
            check(words.zh + " " + words.en, "weekday")
        }
        check(WeeklyReportLabels.monthsEN.joined(separator: " "), "months")
        for entry in WeeklyReportLabels.glossaryEntries() {
            check(entry.term + entry.zh + " " + entry.en, entry.term)
            expectFalse(entry.zh.contains("{") || entry.en.contains("{"), "glossary numbers filled")
        }
        // The full rendered text of every week, without the verbatim spans (video titles, the child's name, ids).
        var characters = 0
        for item in try allReports() {
            // The fingerprint is hex: "…bad…" would read as a word.
            let fingerprint = String(WeeklyReportHTML.fingerprint(item.report.analysis.model).prefix(8))
            var verbatim: [String] = [item.report.childName, fingerprint]
            for sentence in item.report.allSentences { verbatim += sentence.verbatim }
            for game in item.report.analysis.games where ActivityKind(rawValue: game.kind) == nil {
                verbatim.append(game.kind)
            }
            var text = Self.visibleText(item.html)
            for span in verbatim.sorted(by: { $0.count > $1.count }) where !span.isEmpty {
                text = text.replacingOccurrences(of: span, with: " ")
            }
            check(text, item.name)
            characters += text.count
        }
        // The stylesheet and the W4 sources are Traditional only too.
        let root = Self.repoRoot()
        for name in ["WeeklyReportHTML.swift", "WeeklyReportCharts.swift", "WeeklyReportLayout.swift",
                     "WeeklyReportLabels.swift", "WeeklyReportCSS.swift", "WeeklyReportPalette.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/VisaCore/\(name)"), encoding: .utf8)
            let found = source.filter { simplified.contains($0) }
            expectTrue(found.isEmpty, "\(name): Simplified \(found)")
        }
        print("  weekly report: \(WeeklyReportLabels.table.count) labels and \(characters) characters of report text "
              + "Traditional only, no banned words")
    }
}
