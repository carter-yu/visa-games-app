import Foundation

// Weekly report W4 (weekly-report design §3, §8, §9; D2, D7, D8, D10, D13): the report as one self-contained
// HTML string — fixed 794 × 1123 px A4 page sections with inline CSS and inline SVG only; no script, web font,
// image file or URL — for the off-screen WKWebView of W5. Pure and deterministic: the same W3 text model and
// options always give the same bytes. The golden fixtures are made independently by
// `Tests/VisaCoreTests/Fixtures/weekly-ranking-5.6/reference_html.py`; keep the two in step. ADR 0024 records
// the choices made where the design left room.

private typealias P = WeeklyReportPalette

/// Render options.
public struct WeeklyReportHTMLOptions: Sendable, Equatable {
    /// When the report is made, printed in the footer (「製作於」). The renderer never reads the clock.
    public var generatedAt: Date
    /// The sample watermark 「示例數據 EXAMPLE DATA」 on every page: off for real reports, on for the design sample.
    public var sampleWatermark: Bool

    public init(generatedAt: Date, sampleWatermark: Bool = false) {
        self.generatedAt = generatedAt
        self.sampleWatermark = sampleWatermark
    }
}

public enum WeeklyReportHTML {
    /// 「VisaGames 週報 v1」 in the footer (§9.6).
    public static let reportVersion = 1
    /// Pages of a week with countable play. A week without any has page 1 only (§3), numbered 「共 1 頁」.
    public static let pageCount = 6
    /// §3 page 3: more game rows than this fold the rows with the fewest rounds into 「其他 n 個遊戲」.
    public static let matrixMaxRows = 22
    /// Rows kept when the matrix folds (the fold row makes the 22nd line).
    public static let matrixKeepRows = 21
    /// The glossary stays under the matrix while game rows plus area rows are at most this; else it moves to page 6.
    public static let matrixGlossaryLines = 24
    /// Name lists in one line: folded games (page 3) and ⚙ games (page 5).
    public static let foldNamesMax = 6
    public static let gearNamesMax = 3
    /// Page 2 day notes name the first new game and count the others.
    public static let newNamesMax = 1
    /// Page 5 panels: clear changes listed, app versions listed by name and days, setting / star / question
    /// source lines listed; the rest is counted in one line.
    public static let clearMax = 3
    public static let versionsListed = 2
    public static let changeLinesMax = 2
    /// Page 4: the 數據唔夠 list uses full rows up to this many entries, then two columns.
    public static let insufficientRowsMax = 6

    static let minimumRounds = WeeklyRanking.minimumRounds
    /// §4.10: under 20 points is 「差唔多」 (glossary).
    static let samePoints = 20
    /// §4.6: one round adds at most 10 minutes of game time (page 2 note).
    static let gameMinutesCap = WeeklyMetricsBuilder.gameMsCap / 60_000
    /// Page 5 holds 「今個星期 app 有咩改動」 (page 1 note).
    static let changesPage = 5

    /// The six pages (one for a week without countable play) for `report`, as one HTML document.
    public static func render(_ report: WeeklyReportText, options: WeeklyReportHTMLOptions) -> String {
        let c = WeeklyHTMLContext(report: report, options: options)
        let layout = matrixLayout(c)
        var pages: [(extra: String, body: String)] = [(extra: "", body: page1(c))]
        if !c.empty {
            let variant4 = page4Variant(c)
            let dense6 = page6Dense(c, glossaryHere: layout.glossaryHere)
            pages.append((extra: "", body: page2(c)))
            pages.append((extra: "", body: page3(c, layout)))
            pages.append((extra: variant4.dense ? " dense" : "", body: page4(c, variant4)))
            pages.append((extra: "", body: page5(c)))
            pages.append((extra: dense6 ? " dense" : "", body: page6(c, glossaryHere: layout.glossaryHere)))
        }
        var title = label("doc.title", ["week": same(c.stamps[0])]).zh
        if options.sampleWatermark { title += label("doc.sample").zh }
        var out = "<!DOCTYPE html>\n<html lang=\"zh-Hant-HK\">\n<head>\n<meta charset=\"utf-8\">\n<title>"
        out += esc(title)
        out += "</title>\n<meta name=\"author\" content=\"VisaGames\">\n<style>\n"
        out += WeeklyReportCSS.text
        out += "\n</style>\n</head>\n<body>\n"
        let sample = label("sample")
        for (offset, page) in pages.enumerated() {
            let number = offset + 1
            out += "<section class=\"page" + page.extra + "\" id=\"p" + String(number) + "\">\n"
            if options.sampleWatermark {
                out += "<div class=\"wm\">" + esc(sample.zh) + " " + esc(sample.en) + "</div>\n"
            }
            out += runhead(c)
            out += page.body
            out += runfoot(c, number, pages.count)
            out += "</section>\n"
        }
        out += "</body>\n</html>\n"
        return out
    }

    /// 數據指紋 (§9.6): FNV-1a 64 (`ActivityChoiceOrder.seedValue`) over the canonical W1 JSON of this week and
    /// last week (`WeeklyJSON`, keys `current` and `previous`), as 16 lowercase hex digits; the footer prints 8.
    public static func fingerprint(_ model: WeeklyModel) -> String {
        let text = WeeklyJSON.encode(.object(["current": model.current.json, "previous": model.previous.json]))
        let hex = String(ActivityChoiceOrder.seedValue(text), radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }
}

/// What every page reads: the W3 text, the W2 analysis and the W1 week inside it, and the day coverage.
struct WeeklyHTMLContext {
    let report: WeeklyReportText
    let options: WeeklyReportHTMLOptions
    let analysis: WeeklyAnalysis
    let current: WeeklyWindowMetrics
    let window: WeeklyWindow
    let stamps: [String]
    /// Days that started before the cut-off; days `firstCovered ..< started` have records (W1 `coveredDays`).
    let started: Int
    let firstCovered: Int
    /// The day the cut-off falls strictly inside (a week in progress: 「截至 HH:mm」).
    let cutDay: Int?
    /// The day of the cut-off instant; nil when the report covers the whole week.
    let untilDay: Int?
    let cutClock: String
    let name: String
    /// No countable play: page 1 only.
    let empty: Bool
    let gameAt: [WeeklyRowKey: WeeklyGame]
    let textAt: [WeeklyRowKey: WeeklyGameText]
    let asksVideo: Bool
    let fingerprint: String

    init(report: WeeklyReportText, options: WeeklyReportHTMLOptions) {
        let analysis = report.analysis
        let current = analysis.model.current
        let window = analysis.model.window
        self.report = report
        self.options = options
        self.analysis = analysis
        self.current = current
        self.window = window
        stamps = window.dayStamps
        var started = 0
        var cutDay: Int?
        var untilDay: Int?
        for index in 0..<WeeklyWindow.dayCount {
            let start = window.dayStarts[index]
            let next = window.dayStarts[index + 1]
            if start < window.cutoff { started += 1 }
            if start < window.cutoff && window.cutoff < next { cutDay = index }
            if start <= window.cutoff && window.cutoff < next { untilDay = index }
        }
        self.started = started
        firstCovered = started - current.coveredDays
        self.cutDay = cutDay
        self.untilDay = untilDay
        cutClock = WeeklyReportHTML.clock(window.cutoff, window.timeZone)
        name = report.childName
        empty = report.empty != nil
        var gameAt: [WeeklyRowKey: WeeklyGame] = [:]
        for game in analysis.games {
            gameAt[WeeklyRowKey(game)] = game
        }
        self.gameAt = gameAt
        var textAt: [WeeklyRowKey: WeeklyGameText] = [:]
        for game in report.games {
            textAt[WeeklyRowKey(kind: game.kind, type: game.type)] = game
        }
        self.textAt = textAt
        asksVideo = report.questions.contains { $0.id == "Q1" }
        fingerprint = String(WeeklyReportHTML.fingerprint(analysis.model).prefix(8))
    }

    var baseline: Bool { analysis.comparison.baseline }
    var changes: WeeklyChanges { analysis.changes }

    func game(_ kind: String, _ type: WeeklyRoundType) -> WeeklyGame? {
        gameAt[WeeklyRowKey(kind: kind, type: type)]
    }

    func text(_ kind: String, _ type: WeeklyRoundType) -> WeeklyGameText? {
        textAt[WeeklyRowKey(kind: kind, type: type)]
    }

    /// A day after the cut-off, before the first record, or without play: no bars and a one-line row.
    func quiet(_ index: Int) -> Bool {
        index >= started || index < firstCovered || !current.days[index].played
    }

    func quietLabel(_ index: Int) -> String {
        if index >= started { return "day.notYet" }
        if index < firstCovered { return "day.noRecords" }
        return "day.noPlay"
    }
}

// MARK: Text and number helpers

extension WeeklyReportHTML {
    /// HTML text and attribute escaping, one rule for every interpolated string (titles and names included).
    static func esc(_ text: String) -> String {
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

    /// Tenths of a px as SVG text: 123 → "12.3", 120 → "12", -15 → "-1.5". Integers only, no locale.
    static func t(_ value: Int) -> String {
        let magnitude = value < 0 ? -value : value
        var text = String(magnitude / 10)
        if magnitude % 10 != 0 {
            text += "." + String(magnitude % 10)
        }
        return value < 0 ? "-" + text : text
    }

    /// value × num / den rounded half up, in integers (non-negative inputs, den > 0).
    static func scale(_ value: Int, _ num: Int, _ den: Int) -> Int {
        guard den > 0 else { return 0 }
        return (2 * value * num + den) / (2 * den)
    }

    static func attr(_ name: String, _ value: String) -> String {
        " " + name + "=\"" + value + "\""
    }

    static func label(_ id: String, _ values: [String: WeeklyWords] = [:]) -> WeeklyWords {
        WeeklyReportLabels.text(id, values)
    }

    static func same(_ text: String) -> WeeklyWords {
        WeeklyWords(text, text)
    }

    static func num(_ value: Int) -> WeeklyWords {
        same(String(value))
    }

    static func words(_ sentence: WeeklySentence?) -> WeeklyWords {
        guard let sentence else { return WeeklyWords("", "") }
        return WeeklyWords(sentence.zh, sentence.en)
    }

    static func minutesWords(_ minutes: Int) -> WeeklyWords {
        WeeklyWords(WeeklyFormat.minutesZH(minutes), WeeklyFormat.minutesEN(minutes))
    }

    /// The app's card titles; an unknown kind is shown as recorded.
    static func gameName(_ kind: String) -> WeeklyWords {
        guard let known = ActivityKind(rawValue: kind) else { return same(kind) }
        return WeeklyWords(known.parentCardTitle, known.parentCardEnglish)
    }

    /// Chinese, then the English line (a block span), inside the caller's element.
    static func bi(_ zh: String, _ en: String) -> String {
        var out = esc(zh)
        out += "<span class=\"en\">"
        out += esc(en)
        out += "</span>"
        return out
    }

    static func bi(_ words: WeeklyWords) -> String {
        bi(words.zh, words.en)
    }

    static func bi(_ sentence: WeeklySentence) -> String {
        bi(sentence.zh, sentence.en)
    }

    static func heading(_ tag: String, _ id: String) -> String {
        "<" + tag + ">" + bi(label(id)) + "</" + tag + ">\n"
    }

    static func pair(_ zh: String, _ en: String, _ cls: String = "pair") -> String {
        var out = "<p class=\"" + cls + "\"><span class=\"zh\">"
        out += esc(zh)
        out += "</span><span class=\"en\">"
        out += esc(en)
        out += "</span></p>\n"
        return out
    }

    static func li(_ words: WeeklyWords) -> String {
        "<li>" + bi(words) + "</li>\n"
    }

    static func joined(_ parts: [WeeklyWords]) -> WeeklyWords {
        WeeklyWords(parts.map(\.zh).joined(separator: " · "), parts.map(\.en).joined(separator: " · "))
    }

    // MARK: Dates (window time zone, Gregorian, no locale)

    static func ymd(_ stamp: String) -> (year: Int, month: Int, day: Int) {
        let parts = stamp.split(separator: "-").map { Int($0) ?? 0 }
        guard parts.count == 3 else { return (year: 0, month: 1, day: 1) }
        return (year: parts[0], month: parts[1], day: parts[2])
    }

    static func monthEN(_ month: Int) -> String {
        let names = WeeklyReportLabels.monthsEN
        return month >= 1 && month <= names.count ? names[month - 1] : String(month)
    }

    /// 「10月21日」 / "21 Oct".
    static func dateMD(_ stamp: String) -> WeeklyWords {
        let date = ymd(stamp)
        return label("date.md", ["m": num(date.month), "d": num(date.day), "mon": same(monthEN(date.month))])
    }

    /// 「10月21日（三）」 / "Wed 21 Oct".
    static func dateMDW(_ stamp: String, _ weekday: Int) -> WeeklyWords {
        let date = ymd(stamp)
        let day = WeeklyReportLabels.weekdays[min(max(weekday, 0), WeeklyWindow.dayCount - 1)]
        var values: [String: WeeklyWords] = [:]
        values["m"] = num(date.month)
        values["d"] = num(date.day)
        values["w"] = same(day.zh)
        values["wd"] = same(day.en)
        values["mon"] = same(monthEN(date.month))
        return label("date.mdw", values)
    }

    /// A day of this week with its weekday; another date without.
    static func dateFor(_ c: WeeklyHTMLContext, _ stamp: String) -> WeeklyWords {
        guard let index = c.stamps.firstIndex(of: stamp) else { return dateMD(stamp) }
        return dateMDW(stamp, index)
    }

    /// 「2026年10月19–25日」 / "19–25 Oct 2026" (other months and years spelt out).
    static func dateRange(_ first: String, _ last: String) -> WeeklyWords {
        let a = ymd(first)
        let b = ymd(last)
        var values: [String: WeeklyWords] = [:]
        if a.year != b.year {
            values["y0"] = num(a.year)
            values["m0"] = num(a.month)
            values["d0"] = num(a.day)
            values["y1"] = num(b.year)
            values["m1"] = num(b.month)
            values["d1"] = num(b.day)
            values["mon0"] = same(monthEN(a.month))
            values["mon1"] = same(monthEN(b.month))
            return label("range.other", values)
        }
        if a.month != b.month {
            values["y"] = num(a.year)
            values["m0"] = num(a.month)
            values["d0"] = num(a.day)
            values["m1"] = num(b.month)
            values["d1"] = num(b.day)
            values["mon0"] = same(monthEN(a.month))
            values["mon1"] = same(monthEN(b.month))
            return label("range.year", values)
        }
        values["y"] = num(a.year)
        values["m"] = num(a.month)
        values["d0"] = num(a.day)
        values["d1"] = num(b.day)
        values["mon"] = same(monthEN(a.month))
        return label("range.month", values)
    }

    /// 「10月19–21日」 / "19–21 Oct" for days `first ... last` of the week.
    static func daySpan(_ c: WeeklyHTMLContext, _ first: Int, _ last: Int) -> WeeklyWords {
        let from = c.stamps[min(max(first, 0), WeeklyWindow.dayCount - 1)]
        let to = c.stamps[min(max(last, 0), WeeklyWindow.dayCount - 1)]
        if from == to { return dateMD(from) }
        let a = ymd(from)
        let b = ymd(to)
        if a.month == b.month {
            return label("date.span", ["m": num(a.month), "d0": num(a.day), "d1": num(b.day), "mon": same(monthEN(a.month))])
        }
        let start = dateMD(from)
        let end = dateMD(to)
        return WeeklyWords(start.zh + "–" + end.zh, start.en + " – " + end.en)
    }

    /// C3 / C4 x-axis: "10/12–18", "10/26–11/1", or "10/12" when there are more than 4 weeks.
    static func weekLabel(_ stamp: String, short: Bool, timeZone: TimeZone) -> String {
        let a = ymd(stamp)
        var text = String(a.month) + "/" + String(a.day)
        if short { return text }
        let end = WeeklyWindow(weekStart: stamp, timeZone: timeZone)?.weekEndStamp ?? stamp
        let b = ymd(end)
        if a.month == b.month {
            text += "–" + String(b.day)
        } else {
            text += "–" + String(b.month) + "/" + String(b.day)
        }
        return text
    }

    /// "21:00" in `timeZone`.
    static func clock(_ date: Date, _ timeZone: TimeZone) -> String {
        String(PerfClock.timeStamp(date, timeZone: timeZone).prefix(5))
    }

    /// "2026-10-25 21:00 HKT".
    static func stampClock(_ date: Date, _ timeZone: TimeZone) -> String {
        PerfClock.dayStamp(date, timeZone: timeZone) + " " + clock(date, timeZone) + " HKT"
    }
}

// MARK: Running head and foot

extension WeeklyReportHTML {
    static func runhead(_ c: WeeklyHTMLContext) -> String {
        let title = label("head.title")
        let family = label("head.family")
        let week = dateRange(c.stamps[0], c.stamps[WeeklyWindow.dayCount - 1]).zh
        var out = "<div class=\"runhead\"><div class=\"rh-left\"><b>" + esc(title.zh) + "</b> "
        out += esc(title.en) + " · " + esc(week)
        out += " · " + esc(family.zh) + " " + esc(family.en)
        out += "</div>"
        if c.options.sampleWatermark {
            let sample = label("sample")
            out += "<div class=\"rh-tag\">" + esc(sample.zh) + " " + esc(sample.en) + "</div>"
        }
        out += "</div>\n"
        return out
    }

    static func appVersions(_ c: WeeklyHTMLContext) -> String {
        let versions = c.changes.versions
        guard let first = versions.first, let last = versions.last else { return "—" }
        if versions.count == 1 { return "v" + first.app }
        return "v" + first.app + "–v" + last.app
    }

    /// §9.6 provenance line, the counted-only line with the child's name (D7), the page number.
    static func runfoot(_ c: WeeklyHTMLContext, _ page: Int, _ total: Int) -> String {
        let zone = c.window.timeZone
        var values: [String: WeeklyWords] = [:]
        values["report"] = num(reportVersion)
        values["builder"] = num(WeeklyModel.builderVersion)
        values["until"] = same(stampClock(c.window.cutoff, zone))
        values["made"] = same(stampClock(c.options.generatedAt, zone))
        values["apps"] = same(appVersions(c))
        values["fp"] = same(c.fingerprint)
        let provenance = label("foot.provenance", values).zh
        let counted = label("foot.counted", ["name": same(c.name)])
        var second = counted.zh + " · " + counted.en
        if c.options.sampleWatermark {
            let sample = label("sample")
            second += " · " + sample.zh + " " + sample.en
        }
        let number = label("foot.page", ["n": num(page), "total": num(total)])
        var out = "<div class=\"runfoot\"><div class=\"prov\">" + esc(provenance) + "<br>" + esc(second)
        out += "</div><div class=\"pageno\">" + esc(number.zh) + " · " + esc(number.en) + "</div></div>\n"
        return out
    }
}

// MARK: Page 1 — 一頁睇晒 / This week at a glance

extension WeeklyReportHTML {
    enum ChangeKind {
        case rate, count, minutes
    }

    /// §4.10 words: rates keep their four words; counts and minutes only 「明顯」 up or down.
    static func changeWords(_ change: WeeklyChange?, _ kind: ChangeKind) -> WeeklyWords? {
        guard let change else { return nil }
        switch kind {
        case .rate:
            return label("change." + change.rawValue)
        case .count:
            return label(change == .up ? "change.more" : "change.fewer")
        case .minutes:
            return label(change == .up ? "change.more" : "change.less")
        }
    }

    /// 「上星期 …」 and the change word of a count or minutes tile; nothing in the first week.
    static func countParts(_ c: WeeklyHTMLContext, _ comparison: WeeklyCountComparison, _ lastID: String,
                           _ kind: ChangeKind) -> [WeeklyWords] {
        guard !c.baseline else { return [] }
        var parts: [WeeklyWords] = []
        if kind == .minutes {
            parts.append(label(lastID, ["t": minutesWords(WeeklyFormat.minutes(ms: comparison.previous))]))
        } else {
            // "Last week: 1 day"
            let one = comparison.previous == 1 ? "One" : ""
            parts.append(label(lastID + one, ["n": num(comparison.previous)]))
        }
        if let change = changeWords(comparison.change, kind) {
            parts.append(change)
        }
        return parts
    }

    static func minutesValue(_ minutes: Int, approx: Bool) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        var out = ""
        if approx {
            out += "<small>" + esc(label("unit.approx").zh) + "</small>"
        }
        if hours > 0 {
            out += String(hours) + "<small>" + esc(label("unit.hours").zh) + "</small>"
            out += String(rest) + "<small>" + esc(label("unit.minutes").zh) + "</small>"
        } else {
            out += String(rest) + "<small>" + esc(label("unit.minutesOnly").zh) + "</small>"
        }
        return out
    }

    static func tile(_ swatch: String, _ id: String, _ value: String, _ parts: [WeeklyWords], na: Bool = false) -> String {
        var out = "<div class=\"tile\"><div class=\"lbl\">"
        if !swatch.isEmpty {
            out += "<span class=\"sw " + swatch + "\"></span>"
        }
        out += bi(label(id)) + "</div><div class=\"val"
        if na { out += " na" }
        out += "\">" + value + "</div>"
        out += "<div class=\"cmp\">" + bi(joined(parts)) + "</div></div>\n"
        return out
    }

    /// A rate tile: 「—」 and 「數據唔夠」 under 5 rounds (§3); last week and the §4.10 word; the lucky-guess level.
    static func rateTile(_ c: WeeklyHTMLContext, _ swatch: String, _ id: String, _ comparison: WeeklyRateComparison,
                         _ noLastID: String, guess: Double?) -> String {
        guard comparison.n1 >= minimumRounds else {
            let notEnough = label(comparison.n1 == 1 ? "cmp.notEnoughOne" : "cmp.notEnough", ["n": num(comparison.n1)])
            return tile(swatch, id, "—", [notEnough], na: true)
        }
        var parts: [WeeklyWords] = []
        if !c.baseline {
            if comparison.n0 > 0 {
                parts.append(label("cmp.rate", ["p": num(WeeklyFormat.percent(comparison.k0, of: comparison.n0))]))
                if let change = changeWords(comparison.change, .rate) {
                    parts.append(change)
                }
            } else {
                parts.append(label(noLastID))
            }
        }
        if let guess {
            parts.append(label("cmp.guess", ["c": num(WeeklyFormat.percent(guess))]))
        }
        return tile(swatch, id, String(WeeklyFormat.percent(comparison.k1, of: comparison.n1)) + "%", parts)
    }

    static func tiles(_ c: WeeklyHTMLContext) -> String {
        let comparison = c.analysis.comparison
        let current = c.current
        var out = "<div class=\"tiles\">\n"
        let days = comparison.daysPlayed
        var value = String(days.current) + "<small>"
        value += esc(label("unit.ofDays", ["n": num(current.coveredDays)]).zh) + "</small>"
        out += tile("", "tile.days", value, countParts(c, days, "cmp.days", .count))
        let rounds = comparison.rounds
        out += tile("", "tile.rounds", String(rounds.current), countParts(c, rounds, "cmp.rounds", .count))
        out += rateTile(c, "q", "tile.quiz", comparison.quiz, "cmp.noQuiz", guess: current.totals.chanceMean)
        out += rateTile(c, "p", "tile.practice", comparison.practice, "cmp.noPractice", guess: nil)
        let gameMs = current.quizMs + current.practiceMs
        var parts = countParts(c, comparison.gameMs, "cmp.time", .minutes)
        if current.totals.rounds > 0 {
            let tenths = WeeklyFormat.tenths(gameMs, current.totals.rounds * 60_000)
            parts.append(label("cmp.perRound", ["x": same(WeeklyFormat.decimal(tenths: tenths))]))
        }
        out += tile("", "tile.game", minutesValue(WeeklyFormat.minutes(ms: gameMs), approx: false), parts)
        parts = countParts(c, comparison.videoMs, "cmp.time", .minutes)
        parts.append(label("cmp.visa", ["t": minutesWords(current.visaMinutes)]))
        let video = minutesValue(WeeklyFormat.minutes(ms: current.videoMs), approx: current.videoEstimated)
        out += tile("v", "tile.video", video, parts)
        out += "</div>\n"
        return out
    }

    static func page1(_ c: WeeklyHTMLContext) -> String {
        let report = c.report
        let cover = dateRange(c.stamps[0], c.stamps[WeeklyWindow.dayCount - 1])
        let until: WeeklyWords
        if let day = c.untilDay {
            let date = dateMD(c.stamps[day])
            let dated = WeeklyWords(date.zh, WeeklyFormat.dayNamesEN[day] + " " + date.en)
            until = label("p1.until", ["date": dated, "time": same(c.cutClock)])
        } else {
            until = label("p1.whole")
        }
        let metaZH = cover.zh + " · " + until.zh + " · " + c.name
        let metaEN = cover.en + " · " + until.en + " · " + c.name
        let title = label("p1.title")
        var out = "<div class=\"cover\"><h1>" + esc(title.zh) + "<span class=\"en\">" + esc(title.en)
        out += "</span></h1><div class=\"meta\">" + bi(metaZH, metaEN) + "</div></div>\n"
        out += "<div class=\"highlights\">\n" + heading("h3", "p1.highlights")
        if let empty = report.empty {
            out += pair(empty.zh, empty.en)
        }
        for sentence in report.highlights {
            out += pair(sentence.zh, sentence.en)
        }
        if let videos = report.videos {
            out += pair(videos.zh, videos.en)
        }
        out += "</div>\n"
        if !c.empty {
            out += tiles(c)
            let previousDays = c.analysis.comparison.previousCoveredDays
            if c.baseline {
                let note = label("wr.baseline")
                out += pair(note.zh, note.en, "pair tilenote")
            } else if previousDays < 4 {
                let note = label(previousDays == 1 ? "wr.partialPrevOne" : "wr.partialPrev", ["n": num(previousDays)])
                out += pair(note.zh, note.en, "pair tilenote")
            }
            let wins = report.wins
            var next: [WeeklySentence] = []
            for item in report.family.prefix(2) {
                next.append(item.text)
            }
            if next.isEmpty, let none = report.familyNone {
                next.append(none)
            }
            out += "<div class=\"" + (wins.isEmpty ? "onecol" : "twocol") + "\">\n"
            if !wins.isEmpty {
                out += "<div class=\"box wins\">" + heading("h3", "p1.wins") + "<ul class=\"items\">\n"
                for sentence in wins {
                    out += "<li>" + bi(sentence) + "</li>\n"
                }
                out += "</ul></div>\n"
            }
            out += "<div class=\"box next\">" + heading("h3", "p1.next") + "<ul class=\"items dots\">\n"
            for sentence in next {
                out += "<li>" + bi(sentence) + "</li>\n"
            }
            out += "</ul></div>\n</div>\n"
        }
        out += countedNote(c)
        if c.empty {
            out += "<p class=\"privacy\">" + bi(label("wr.privacy")) + "</p>\n"
        }
        return out
    }

    /// 「只計 Cedric 自己玩…」, rounds not counted, app updates and setting changes (page 5).
    static func countedNote(_ c: WeeklyHTMLContext) -> String {
        let counted = label("p1.counted", ["name": same(c.name)])
        var zh = counted.zh
        var en = counted.en
        let excluded = c.current.excludedTotal
        if excluded > 0 {
            let words = label(excluded == 1 ? "p1.excludedOne" : "p1.excluded", ["n": num(excluded)])
            zh += words.zh
            en += " " + words.en
        }
        if !c.empty {
            let updates = max(0, c.changes.versions.count - 1)
            let settings = c.changes.settings.count + c.changes.assignments.count
            var words: WeeklyWords?
            if updates > 0 && settings > 0 {
                words = label("p1.changes", ["u": num(updates), "s": num(settings), "page": num(changesPage)])
            } else if updates > 0 {
                words = label("p1.updates", ["u": num(updates), "page": num(changesPage)])
            } else if settings > 0 {
                words = label("p1.settings", ["s": num(settings), "page": num(changesPage)])
            }
            if let words {
                zh += words.zh
                en += " " + words.en
            }
        }
        return "<p class=\"note\">" + bi(zh, en) + "</p>\n"
    }
}

// MARK: Page 2 — 每日明細 / Day by day

extension WeeklyReportHTML {
    /// The first new game of the day, the count of the others, and 「截至 HH:mm」 on the cut-off day.
    static func dayNote(_ c: WeeklyHTMLContext, _ index: Int) -> WeeklyWords {
        var zh: [String] = []
        var en: [String] = []
        let newKinds = c.current.days[index].newKinds
        for kind in newKinds.prefix(newNamesMax) {
            let words = label("note.newGame", ["game": gameName(kind)])
            zh.append(words.zh)
            en.append(words.en)
        }
        if newKinds.count > newNamesMax {
            let words = label("note.moreNew", ["n": num(newKinds.count - newNamesMax)])
            zh.append(words.zh)
            en.append(words.en)
        }
        if c.cutDay == index {
            let words = label("day.upTo", ["time": same(c.cutClock)])
            zh.append(words.zh)
            en.append(words.en)
        }
        return WeeklyWords(zh.joined(separator: "；"), en.joined(separator: "; "))
    }

    static func ratioCell(_ k: Int, _ n: Int) -> String {
        guard n > 0 else { return "<td class=\"muted\">—</td>" }
        var out = "<td>" + String(k) + "/" + String(n)
        out += "<span class=\"en\">" + String(WeeklyFormat.percent(k, of: n)) + "%</span></td>"
        return out
    }

    static func noteCell(_ note: WeeklyWords, _ cls: String) -> String {
        if note.zh.isEmpty { return "<td class=\"" + cls + "\"></td>" }
        return "<td class=\"" + cls + "\">" + bi(note) + "</td>"
    }

    /// Video minutes; 「約」 when a play had no `video_end` (§3, §4.6).
    static func videoCell(_ ms: Int, approx: Bool) -> String {
        let minutes = String(WeeklyFormat.minutes(ms: ms))
        if approx { return "<td>" + esc(label("unit.approx").zh) + minutes + "</td>" }
        return "<td>" + minutes + "</td>"
    }

    static func page2(_ c: WeeklyHTMLContext) -> String {
        let current = c.current
        var out = heading("h2", "p2.title")
        out += "<div class=\"charttitle\">" + bi(label("p2.chart")) + "</div>\n"
        if let svg = chartC1(c) {
            out += "<div class=\"chart\">\n" + svg + "</div>\n"
        } else {
            out += "<p class=\"chartnote\">" + bi(label("c1.empty")) + "</p>\n"
        }
        out += "<table class=\"daily\">\n<colgroup><col style=\"width:96px\"><col style=\"width:52px\">"
        out += "<col style=\"width:64px\"><col style=\"width:76px\"><col style=\"width:68px\"><col style=\"width:54px\">"
        out += "<col style=\"width:54px\"><col style=\"width:62px\"><col></colgroup>\n<tr>"
        let heads = ["th.date", "th.sessions", "th.rounds", "th.quiz", "th.practice", "th.games", "th.videos", "th.visa",
                     "th.note"]
        for id in heads {
            out += (id == "th.date" || id == "th.note") ? "<th class=\"l\">" : "<th>"
            out += bi(label(id)) + "</th>"
        }
        out += "</tr>\n"
        for index in 0..<WeeklyWindow.dayCount {
            let day = current.days[index]
            let first = "<td class=\"l\">" + bi(dateMDW(c.stamps[index], index)) + "</td>"
            let note = dayNote(c, index)
            if c.quiet(index) {
                let words = label(c.quietLabel(index))
                out += "<tr>" + first + "<td class=\"muted l\" colspan=\"7\">"
                out += esc(words.zh) + " · " + esc(words.en) + "</td>"
                out += noteCell(note, "l note-cell") + "</tr>\n"
                continue
            }
            out += "<tr>" + first + "<td>" + String(day.sessions.count) + "</td>"
            out += "<td>" + String(day.rounds) + "<span class=\"en\">" + String(day.quizRounds) + " / "
            out += String(day.practiceRounds) + "</span></td>"
            out += ratioCell(day.counts.firstTry, day.counts.answered)
            out += ratioCell(day.counts.smooth, day.counts.smoothDefined)
            out += "<td>" + String(WeeklyFormat.minutes(ms: day.gameMs)) + "</td>"
            out += videoCell(day.videoMs, approx: day.videoEstimated)
            out += "<td>" + String(day.visaMinutes) + "</td>"
            out += noteCell(note, "l note-cell") + "</tr>\n"
        }
        let totals = current.totals
        out += "<tr class=\"total\"><td class=\"l\">" + bi(label("row.total")) + "</td>"
        out += "<td>" + String(current.sessionCount) + "</td>"
        out += "<td>" + String(totals.rounds) + "<span class=\"en\">" + String(totals.quizRounds) + " / "
        out += String(totals.practiceRounds) + "</span></td>"
        out += ratioCell(totals.firstTry, totals.answered)
        out += ratioCell(totals.smooth, totals.smoothDefined)
        out += "<td>" + String(WeeklyFormat.minutes(ms: current.quizMs + current.practiceMs)) + "</td>"
        out += videoCell(current.videoMs, approx: current.videoEstimated)
        out += "<td>" + String(current.visaMinutes) + "</td><td class=\"l\"></td></tr>\n</table>\n"
        let stars = current.stars
        var starValues: [String: WeeklyWords] = [:]
        starValues["a"] = num(stars.count > 0 ? stars[0] : 0)
        starValues["b"] = num(stars.count > 1 ? stars[1] : 0)
        starValues["c"] = num(stars.count > 2 ? stars[2] : 0)
        out += "<p class=\"note\">" + bi(label("p2.tickets", starValues)) + "</p>\n"
        let time = label("p2.time", ["cap": num(gameMinutesCap)])
        var zh = time.zh
        var en = time.en
        if let day = c.cutDay {
            let dayName = WeeklyWords(WeeklyFormat.dayNamesZH[day], WeeklyFormat.dayNamesEN[day])
            let words = label("p2.cutoff", ["day": dayName, "time": same(c.cutClock)])
            zh += words.zh
            en += " " + words.en
        }
        if current.videoEstimated {
            let words = label("p2.approx")
            zh += words.zh
            en += " " + words.en
        }
        if c.asksVideo {
            let words = label("p2.pointer", ["page": num(WeeklyReportText.questionsPage)])
            zh += words.zh
            en += " " + words.en
        }
        out += "<p class=\"note\">" + bi(zh, en) + "</p>\n"
        return out
    }
}

// MARK: Page 3 — 玩咗乜、做成點 / Which games, and how they went (M1)

extension WeeklyReportHTML {
    struct MatrixLayout {
        let rows: [WeeklyKindMetrics]
        let folded: [WeeklyKindMetrics]
        let glossaryHere: Bool
    }

    /// W1 rows grouped by area (design order), quiz before practice, catalog order inside; past 22 rows the rows
    /// with the fewest rounds fold (ties: the later row folds).
    static func matrixLayout(_ c: WeeklyHTMLContext) -> MatrixLayout {
        var ordered: [WeeklyKindMetrics] = []
        for area in WeeklyArea.allCases {
            for type in [WeeklyRoundType.quiz, WeeklyRoundType.practice] {
                for row in c.current.kinds where row.area == area && row.type == type {
                    ordered.append(row)
                }
            }
        }
        var folded: [WeeklyKindMetrics] = []
        if ordered.count > matrixMaxRows {
            let rows = ordered
            let rank = rows.indices.sorted { lhs, rhs in
                rows[lhs].rounds != rows[rhs].rounds ? rows[lhs].rounds > rows[rhs].rounds : lhs < rhs
            }
            let keep = Set(rank.prefix(matrixKeepRows))
            var kept: [WeeklyKindMetrics] = []
            for (index, row) in rows.enumerated() {
                if keep.contains(index) {
                    kept.append(row)
                } else {
                    folded.append(row)
                }
            }
            ordered = kept
        }
        var areas: [WeeklyArea] = []
        for row in ordered where !areas.contains(row.area) {
            areas.append(row.area)
        }
        let here = folded.isEmpty && ordered.count + areas.count <= matrixGlossaryLines
        return MatrixLayout(rows: ordered, folded: folded, glossaryHere: here)
    }

    /// Quiz: right first time / answered; practice: smooth / smooth-defined. Blank without rounds, 「—」 when
    /// rounds have nothing to score (§3, §8 M1).
    static func matrixCell(_ row: WeeklyKindMetrics, _ day: Int) -> String {
        let counts = row.cells[day]
        guard counts.rounds > 0 else { return "<td></td>" }
        let quiz = row.type == .quiz
        let k = quiz ? counts.firstTry : counts.smooth
        let n = quiz ? counts.answered : counts.smoothDefined
        guard n > 0 else { return "<td class=\"na\">—</td>" }
        return "<td class=\"" + (quiz ? "q" : "p") + "\">" + String(k) + "/" + String(n) + "</td>"
    }

    /// Badge texts: type, 「新 New」, 「同一題」 (quiz rows only) and ⚙.
    static func badgeTexts(_ game: WeeklyGame) -> [(cls: String, text: String)] {
        var out: [(cls: String, text: String)] = []
        if game.type == .quiz {
            out.append((cls: "q", text: label("badge.quiz").zh))
        } else {
            out.append((cls: "p", text: label("badge.practice").zh))
        }
        if game.isNew {
            let words = label("badge.new")
            out.append((cls: "new", text: words.zh + " " + words.en))
        }
        if game.type == .quiz && game.fixedQuestion {
            out.append((cls: "fixed", text: label("badge.fixed").zh))
        }
        if !game.settings.isEmpty {
            out.append((cls: "cfg", text: label("badge.settings").zh))
        }
        return out
    }

    static func badges(_ game: WeeklyGame) -> String {
        var out = ""
        for badge in badgeTexts(game) {
            out += "<span class=\"badge " + badge.cls + "\">" + esc(badge.text) + "</span>"
        }
        return out
    }

    /// Names joined by 「、」 / ", ", at most `limit`, then 「同另外 n 個遊戲」 / "and n more".
    static func namesList(_ kinds: [String], limit: Int) -> WeeklyWords {
        var names: [WeeklyWords] = []
        for kind in kinds.prefix(limit) {
            names.append(gameName(kind))
        }
        var zh = names.map(\.zh).joined(separator: "、")
        var en = names.map(\.en).joined(separator: ", ")
        if kinds.count > limit {
            let more = label("list.more", ["n": num(kinds.count - limit)])
            zh += more.zh
            en += " " + more.en
        }
        return WeeklyWords(zh, en)
    }

    static func glossary() -> String {
        var out = "<div class=\"howto\">\n" + heading("h3", "gloss.title") + "<div class=\"gloss\">\n"
        for entry in WeeklyReportLabels.glossaryEntries() {
            out += "<div><b>" + esc(entry.term) + "</b>：" + bi(entry.zh, entry.en) + "</div>\n"
        }
        out += "</div></div>\n"
        return out
    }

    static func page3(_ c: WeeklyHTMLContext, _ layout: MatrixLayout) -> String {
        var out = heading("h2", "p3.title")
        let cells = label("p3.cells")
        let key = label("p3.badges")
        out += pair(cells.zh, cells.en, "pair key")
        out += pair(key.zh, key.en, "pair key")
        if c.current.kinds.isEmpty {
            out += "<p class=\"status\">" + bi(label("none.games")) + "</p>\n"
        } else {
            out += "<table class=\"matrix\">\n<colgroup><col style=\"width:288px\">"
            for _ in 0..<WeeklyWindow.dayCount {
                out += "<col style=\"width:42px\">"
            }
            out += "<col style=\"width:46px\"><col style=\"width:60px\"></colgroup>\n<tr>"
            out += "<th class=\"name\">" + bi(label("th.game")) + "</th>"
            for index in 0..<WeeklyWindow.dayCount {
                let weekday = WeeklyReportLabels.weekdays[index]
                out += "<th>" + bi(weekday.zh, weekday.en + " " + String(ymd(c.stamps[index]).day)) + "</th>"
            }
            out += "<th>" + bi(label("th.week")) + "</th><th>" + bi(label("th.tickets")) + "</th></tr>\n"
            var area: WeeklyArea?
            for row in layout.rows {
                if row.area != area {
                    area = row.area
                    out += "<tr class=\"area\"><td colspan=\"10\">" + bi(row.area.zh, row.area.en) + "</td></tr>\n"
                }
                guard let game = c.game(row.kind, row.type) else { continue }
                out += "<tr><td class=\"name\">" + badges(game) + bi(gameName(row.kind)) + "</td>"
                for day in 0..<WeeklyWindow.dayCount {
                    out += matrixCell(row, day)
                }
                if game.n > 0 {
                    out += "<td class=\"tot\">" + String(game.k) + "/" + String(game.n) + "</td>"
                } else {
                    out += "<td class=\"tot na\">—</td>"
                }
                let stars = row.stars.map(\.rounds)
                out += "<td class=\"stars\">" + String(stars[0]) + " · " + String(stars[1])
                out += " · " + String(stars[2]) + "</td></tr>\n"
            }
            if !layout.folded.isEmpty {
                var rounds = 0
                for row in layout.folded {
                    rounds += row.rounds
                }
                let names = namesList(layout.folded.map(\.kind), limit: foldNamesMax)
                let fold = label("m1.fold", ["n": num(layout.folded.count), "m": num(rounds), "names": names])
                out += "<tr class=\"fold\"><td colspan=\"10\">" + bi(fold) + "</td></tr>\n"
            }
            out += "</table>\n"
        }
        if layout.glossaryHere {
            out += glossary()
        }
        return out
    }
}

// MARK: Page 4 — 做得好嘅同仲學緊嘅 / Going well, and still learning

extension WeeklyReportHTML {
    /// Stars and days played under a row's fact: "★6 ★★2 ★★★1 · 6 日 days".
    static func factTail(_ game: WeeklyGame) -> String {
        let days = label(game.daysPlayed == 1 ? "p4.daysOne" : "p4.days", ["n": num(game.daysPlayed)])
        let tail = days.zh + " " + days.en
        let mix = WeeklyFormat.starMix(game.stars)
        return mix.isEmpty ? tail : mix + " · " + tail
    }

    static func factBlock(_ game: WeeklyGame, _ text: WeeklyGameText) -> String {
        let tail = "<span class=\"stars\">" + esc(factTail(game)) + "</span>"
        guard let fact = text.fact else { return "<div class=\"fact\">" + tail + "</div>" }
        return "<div class=\"fact\">" + bi(fact) + tail + "</div>"
    }

    static func commentBlock(_ sentences: [WeeklySentence]) -> String {
        var out = "<div class=\"cm\">"
        for sentence in sentences {
            out += bi(sentence)
        }
        out += "</div>"
        return out
    }

    static func rankRows(_ c: WeeklyHTMLContext, _ lists: WeeklyKindLists) -> String {
        var out = ""
        let groups: [(kinds: [String], type: WeeklyRoundType)] = [(kinds: lists.quiz, type: .quiz),
                                                                  (kinds: lists.practice, type: .practice)]
        for group in groups {
            for kind in group.kinds {
                guard let game = c.game(kind, group.type), let text = c.text(kind, group.type) else { continue }
                out += "<div class=\"row\"><div class=\"nm\">" + badges(game) + bi(gameName(kind)) + "</div>"
                out += factBlock(game, text) + commentBlock(text.short) + "</div>\n"
            }
        }
        return out
    }

    static func rankHead(_ id: String, _ split: WeeklySentence?) -> String {
        let words = label(id)
        var out = "<div class=\"head\"><h3>" + esc(words.zh) + "<span class=\"en\">" + esc(words.en) + "</span></h3>"
        if let split {
            out += "<span class=\"split\">" + esc(split.zh) + " · " + esc(split.en) + "</span>"
        }
        out += "</div>\n"
        return out
    }

    static func statusLine(_ words: WeeklyWords) -> String {
        "<p class=\"status\">" + bi(words) + "</p>\n"
    }

    static func page4(_ c: WeeklyHTMLContext, _ variant: Page4Variant) -> String {
        let ranking = c.analysis.ranking
        let text = c.report.ranking
        var out = heading("h2", "p4.title")
        if c.current.kinds.isEmpty {
            out += statusLine(label("none.games"))
        } else if !ranking.ranked {
            out += statusLine(words(text.status))
        } else {
            out += "<div class=\"rank\">\n" + rankHead("p4.top", text.topSplit)
            if let status = text.status {
                out += statusLine(words(status))
            }
            out += rankRows(c, ranking.top)
            if let also = text.alsoWell {
                out += "<p class=\"also\">" + bi(also) + "</p>\n"
            }
            out += "</div>\n"
            out += "<div class=\"rank\">\n" + rankHead("p4.bottom", text.stillLearningSplit)
            if ranking.stillLearning.count == 0 {
                out += statusLine(label("wr.bottom.none"))
            }
            out += rankRows(c, ranking.stillLearning)
            if let also = text.alsoLearning {
                out += "<p class=\"also\">" + bi(also) + "</p>\n"
            }
            out += "</div>\n"
        }
        let entries = ranking.insufficient
        if !entries.isEmpty {
            out += "<div class=\"rank insuff\">\n" + rankHead("p4.insufficient", nil)
            if variant.columns {
                out += "<div class=\"cols\">\n"
            }
            for entry in entries {
                guard let game = c.game(entry.kind, entry.type), let text = c.text(entry.kind, entry.type) else { continue }
                out += "<div class=\"" + (variant.columns ? "item" : "row") + "\"><div class=\"nm\">"
                out += badges(game) + bi(gameName(entry.kind)) + "</div>" + commentBlock(text.short) + "</div>\n"
            }
            if variant.columns {
                out += "</div>\n"
            }
            out += "</div>\n"
        }
        if variant.method && !c.current.kinds.isEmpty {
            let method = label("p4.method", ["min": num(minimumRounds), "days": num(WeeklyRanking.minimumDays)])
            out += "<div class=\"method\">" + bi(method) + "</div>\n"
        }
        return out
    }
}

// MARK: Page 5 — 同上星期比較 / Compared with last week

extension WeeklyReportHTML {
    /// 「「a」、「b」同另外 n 個遊戲」 / "\"a\", \"b\" and n more" (or "\"a\" and \"b\"").
    static func quotedNames(_ kinds: [String], limit: Int) -> WeeklyWords {
        var zhItems: [String] = []
        var enItems: [String] = []
        for kind in kinds.prefix(limit) {
            let name = gameName(kind)
            zhItems.append("「" + name.zh + "」")
            enItems.append("\"" + name.en + "\"")
        }
        let zh = zhItems.joined(separator: "、")
        if kinds.count > limit {
            let more = label("list.more", ["n": num(kinds.count - limit)])
            return WeeklyWords(zh + more.zh, enItems.joined(separator: ", ") + " " + more.en)
        }
        if enItems.count > 1 {
            return WeeklyWords(zh, enItems.dropLast().joined(separator: ", ") + " and " + (enItems.last ?? ""))
        }
        return WeeklyWords(zh, enItems.first ?? "")
    }

    /// A value with its setting's labels (W3 catalogue), else as recorded.
    static func settingValue(_ labels: String, _ value: String) -> WeeklyWords {
        WeeklyTextCatalog.label(labels, value) ?? same(value)
    }

    static func settingLine(_ c: WeeklyHTMLContext, _ setting: WeeklyChanges.Setting) -> WeeklyWords {
        let named = WeeklyTextCatalog.configName(setting.what)
        let labels = named?.labels ?? ""
        var values: [String: WeeklyWords] = [:]
        values["date"] = dateFor(c, setting.date)
        values["name"] = named?.name ?? same(setting.what)
        values["affects"] = setting.kinds.isEmpty ? WeeklyWords("", "") : label("set.affects", ["n": num(setting.kinds.count)])
        if let new = setting.new {
            values["new"] = settingValue(labels, new)
            if let old = setting.old {
                values["old"] = settingValue(labels, old)
                return label("set.change", values)
            }
            return label("set.new", values)
        }
        return label("set.plain", values)
    }

    /// 「冇計：家長試玩 6 局、測試模式 5 局。」 with rounds still open at the cut-off; nil when nothing.
    static func excludedLine(_ c: WeeklyHTMLContext) -> WeeklyWords? {
        let changes = c.changes
        let reasons = ["parent_playtest", "parent_uat", "parent_test_visa", "excluded_session"]
        let others = changes.excludedRounds.keys.filter { !reasons.contains($0) }
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        var zh: [String] = []
        var en: [String] = []
        for reason in reasons + others {
            let count = changes.excludedRounds[reason] ?? 0
            guard count > 0 else { continue }
            let words: WeeklyWords
            if reasons.contains(reason) {
                words = label("excl." + reason, ["n": num(count)])
            } else {
                words = label("excl.other", ["reason": same(reason), "n": num(count)])
            }
            zh.append(words.zh)
            en.append(words.en)
        }
        if changes.openAtCutoff > 0 {
            let words = label("excl.open", ["n": num(changes.openAtCutoff)])
            zh.append(words.zh)
            en.append(words.en)
        }
        guard !zh.isEmpty else { return nil }
        return label("excl.list", ["items": WeeklyWords(zh.joined(separator: "、"), en.joined(separator: ", "))])
    }

    static func page5(_ c: WeeklyHTMLContext) -> String {
        var out = heading("h2", "p5.title")
        let weeks = c.analysis.model.weeks
        let zone = c.window.timeZone
        if weeks.count < 2 {
            out += "<p class=\"chartnote\">" + bi(label("wr.baseline")) + "</p>\n"
        } else {
            out += "<div class=\"grid2\"><div><div class=\"charttitle\">" + bi(label("c3.title")) + "</div>\n"
            out += "<div class=\"chart\">\n" + chartC3(weeks, zone) + "</div></div>"
            out += "<div><div class=\"charttitle\">" + bi(label("c4.title")) + "</div>\n"
            out += "<div class=\"chart\">\n" + chartC4(weeks, zone) + "</div></div></div>\n"
        }
        out += "<div class=\"charttitle\">" + bi(label("c2a.title")) + "</div>\n"
        let areas = areaRows(c)
        if areas.isEmpty {
            out += "<p class=\"chartnote\">" + bi(label("c2.noQuiz")) + "</p>\n"
        } else {
            out += "<div class=\"chart\">\n" + chartBars(areas, color: P.quiz, guess: true) + "</div>\n"
        }
        out += "<div class=\"charttitle\">" + bi(label("c2b.title")) + "</div>\n"
        let families = familyRows(c)
        if families.isEmpty {
            out += "<p class=\"chartnote\">" + bi(label("c2.noPractice")) + "</p>\n"
        } else {
            out += "<div class=\"chart\">\n" + chartBars(families, color: P.practice, guess: false) + "</div>\n"
        }
        out += "<div class=\"grid2\"><div class=\"panel\">" + heading("h3", "p5.clear") + "<ul class=\"items dots\">\n"
        if c.baseline {
            out += li(label("wr.baseline"))
        } else {
            let clear = c.analysis.comparison.clearChanges
            for change in clear.prefix(clearMax) {
                guard let game = c.game(change.kind, change.type) else { continue }
                let wow = game.wow
                var values: [String: WeeklyWords] = [:]
                values["game"] = gameName(change.kind)
                values["metric"] = label(change.type == .quiz ? "metric.quiz" : "metric.practice")
                values["k0"] = num(wow.k0)
                values["n0"] = num(wow.n0)
                values["k1"] = num(wow.k1)
                values["n1"] = num(wow.n1)
                out += li(label(change.change == .up ? "clear.up" : "clear.down", values))
            }
            if clear.count > clearMax {
                let more = clear.count - clearMax
                out += li(label(more == 1 ? "clear.moreOne" : "clear.more", ["n": num(more)]))
            }
            out += li(label(clear.isEmpty ? "clear.none" : "clear.others"))
            var gear: [String] = []
            for game in c.analysis.games where !game.settings.isEmpty {
                gear.append(game.kind)
            }
            if !gear.isEmpty {
                out += li(label("clear.gear", ["games": quotedNames(gear, limit: gearNamesMax)]))
            }
        }
        out += "</ul></div>\n<div class=\"panel\">" + heading("h3", "p5.app") + "<ul class=\"items dots\">\n"
        let changes = c.changes
        let versions = changes.versions
        if versions.count == 1 {
            out += li(label("ver.one", ["v": same("v" + versions[0].app)]))
        } else if versions.count > 1 && versions.count <= versionsListed {
            var zh: [String] = []
            var en: [String] = []
            for version in versions {
                let days = daySpan(c, version.firstDay, version.lastDay)
                let words = label("ver.item", ["v": same("v" + version.app), "days": days])
                zh.append(words.zh)
                en.append(words.en)
            }
            let list = WeeklyWords(zh.joined(separator: "、"), en.dropLast().joined(separator: ", ") + " and " + (en.last ?? ""))
            out += li(label("ver.list", ["n": num(versions.count), "list": list]))
        } else if versions.count > versionsListed {
            var values: [String: WeeklyWords] = [:]
            values["n"] = num(versions.count)
            values["first"] = same("v" + versions[0].app)
            values["last"] = same("v" + versions[versions.count - 1].app)
            out += li(label("ver.many", values))
        }
        for sentence in c.report.changes {
            out += li(words(sentence))
        }
        var lines: [WeeklyWords] = []
        for setting in changes.settings {
            lines.append(settingLine(c, setting))
        }
        for assignment in changes.assignments {
            var values: [String: WeeklyWords] = [:]
            values["date"] = dateFor(c, assignment.date)
            values["game"] = gameName(assignment.kind)
            values["stars"] = same(WeeklyFormat.stars(assignment.star))
            lines.append(label(assignment.on ? "assign.on" : "assign.off", values))
        }
        for generation in changes.generations {
            var values: [String: WeeklyWords] = [:]
            values["game"] = gameName(generation.kind)
            values["old"] = WeeklyTextCatalog.generation(generation.old) ?? same(generation.old)
            values["new"] = WeeklyTextCatalog.generation(generation.new) ?? same(generation.new)
            lines.append(label("gen.change", values))
        }
        for line in lines.prefix(changeLinesMax) {
            out += li(line)
        }
        if lines.count > changeLinesMax {
            let more = lines.count - changeLinesMax
            out += li(label(more == 1 ? "changes.moreOne" : "changes.more", ["n": num(more)]))
        }
        let now = changes.quizRounds.current + changes.practiceRounds.current
        let before = changes.quizRounds.previous + changes.practiceRounds.previous
        if now > 0 {
            let share = num(WeeklyFormat.percent(changes.practiceRounds.current, of: now))
            if !c.baseline && before > 0 {
                let previous = num(WeeklyFormat.percent(changes.practiceRounds.previous, of: before))
                out += li(label("mix.both", ["p": share, "p0": previous]))
            } else {
                out += li(label("mix.now", ["p": share]))
            }
        }
        if let excluded = excludedLine(c) {
            out += li(excluded)
        }
        out += "</ul></div></div>\n"
        return out
    }
}

// MARK: Page 6 — 結論同下一步 / Conclusion and next steps

extension WeeklyReportHTML {
    static func recBlock(_ zh: String, _ en: String, why: WeeklyWords? = nil, params: [String] = [],
                         decide: Bool = false) -> String {
        var out = "<div class=\"rec\"><div class=\"t\">" + esc(zh)
        if decide {
            out += "<span class=\"decide\">" + esc(label("p6.decide").zh) + "</span>"
        }
        out += "<span class=\"en\">" + esc(en) + "</span></div>"
        if let why {
            out += "<div class=\"why\">" + bi(why) + "</div>"
        }
        for param in params {
            out += "<div class=\"param\">" + esc(param) + "</div>"
        }
        out += "</div>\n"
        return out
    }

    static func page6(_ c: WeeklyHTMLContext, glossaryHere: Bool) -> String {
        let report = c.report
        var out = heading("h2", "p6.title") + heading("h3", "p6.family")
        for item in report.family {
            let why = label("p6.because", ["because": words(item.because)])
            out += recBlock(item.text.zh, item.text.en, why: why)
        }
        for sentence in [report.praise, report.familyNone] {
            if let sentence {
                out += recBlock(sentence.zh, sentence.en)
            }
        }
        out += "<div class=\"sec\">\n" + heading("h3", "p6.app")
        for item in report.app {
            let why = label("p6.why", ["because": words(item.because), "check": words(item.check)])
            out += recBlock(item.text.zh, item.text.en, why: why, params: item.settings.map(\.en), decide: true)
        }
        if let none = report.appNone {
            out += recBlock(none.zh, none.en)
        }
        out += "</div>\n"
        if !report.questions.isEmpty {
            out += "<div class=\"sec\">\n" + heading("h3", "p6.questions")
            for question in report.questions {
                let note = question.note.map { words($0) }
                out += recBlock(question.question.zh, question.question.en, why: note)
            }
            out += "</div>\n"
        }
        if !glossaryHere {
            out += glossary()
        }
        out += "<p class=\"privacy\">" + bi(label("wr.privacy")) + "</p>\n"
        return out
    }
}
