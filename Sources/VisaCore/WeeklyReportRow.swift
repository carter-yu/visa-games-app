import Foundation

// Weekly report W5 (weekly-report design §9.3, §9.4, §11): what the parent 表現 screen's 每週報告 row shows — the
// weeks it offers, the Sunday 21:00 ready line, the state of each row and every row string (one table, Hong Kong
// Traditional Chinese and English). Pure value code: the week maths reuse `WeeklyWindow` (Asia/Hong_Kong, Gregorian,
// POSIX locale) and the W1 round index; nothing here reads the clock, the host zone or the host locale. ADR 0025.

/// One week the row offers.
public struct WeeklyReportWeek: Sendable, Equatable, Identifiable {
    /// "2026-10-19" (Monday) and "2026-10-25" (Sunday), Hong Kong days.
    public let weekStart: String
    public let weekEnd: String
    /// The week that held `now` when the list was made.
    public let isCurrent: Bool
    /// The week was over when the list was made. Otherwise its report is a draft with data up to the making time.
    public let isComplete: Bool

    public init(window: WeeklyWindow, now: Date) {
        weekStart = window.weekStartStamp
        weekEnd = window.weekEndStamp
        isCurrent = window.start <= now && now < window.end
        isComplete = now >= window.end
    }

    public var id: String { weekStart }

    /// 「星期未完（資料截至而家）」.
    public var isDraft: Bool { !isComplete }

    /// 「10月19日至10月25日」 / "Oct 19 – Oct 25".
    public var label: WeeklyWords {
        WeeklyReportUILabels.weekLabel(weekStart: weekStart, weekEnd: weekEnd)
    }
}

/// The weeks and the ready line, read from the records at one moment.
public struct WeeklyReportWeekList: Sendable, Equatable {
    /// Newest first: this week, then earlier weeks with countable play.
    public var weeks: [WeeklyReportWeek]
    /// §9.3: from Sunday 21:00 HKT the current week's report is ready.
    public var ready: Bool

    public init(weeks: [WeeklyReportWeek] = [], ready: Bool = false) {
        self.weeks = weeks
        self.ready = ready
    }
}

/// §9.3 schedule (D1) and the row's week list.
public enum WeeklyReportSchedule {
    /// Rows at most: this week and up to 7 earlier weeks with countable play. 8 weeks (56 days) stay inside the
    /// 90-day raw retention together with each week's previous week.
    public static let maximumWeeks = 8
    /// The current week's report is ready from Sunday at this hour (HKT).
    public static let readyHour = 21
    /// Earlier weeks looked at, at most (90 raw days are about 13 weeks).
    static let lookBackWeeks = 26

    /// Sunday 21:00 of `window`, on its own (Hong Kong) calendar.
    public static func readyTime(of window: WeeklyWindow) -> Date {
        let sunday = window.dayStarts[WeeklyWindow.dayCount - 1]
        let calendar = WeeklyWindow.calendar(window.timeZone)
        var parts = calendar.dateComponents([.year, .month, .day], from: sunday)
        parts.hour = readyHour
        parts.minute = 0
        parts.second = 0
        return calendar.date(from: parts) ?? sunday.addingTimeInterval(Double(readyHour * 3600))
    }

    /// 「今個星期嘅報告可以製作喇」 shows from Sunday 21:00:00 to the end of Sunday. Last week's report can be made
    /// any time, so Monday shows no line.
    public static func isReady(now: Date, timeZone: TimeZone = WeeklyWindow.hongKong) -> Bool {
        now >= readyTime(of: WeeklyWindow(containing: now, timeZone: timeZone))
    }

    public static func list(events: [PerfEvent], now: Date, timeZone: TimeZone = WeeklyWindow.hongKong,
                            maximum: Int = maximumWeeks) -> WeeklyReportWeekList {
        WeeklyReportWeekList(weeks: weeks(events: events, now: now, timeZone: timeZone, maximum: maximum),
                             ready: isReady(now: now, timeZone: timeZone))
    }

    /// This week (always, with data up to `now`), then each earlier week with countable play, newest first, at most
    /// `maximum` in all. "Countable play" is the W1 rule for 「有玩嘅日子」: a counted round or a counted play in
    /// the week, seen to its end, so a listed week never renders as the one-page 「今個星期未有紀錄」 report.
    public static func weeks(events: [PerfEvent], now: Date, timeZone: TimeZone = WeeklyWindow.hongKong,
                             maximum: Int = maximumWeeks) -> [WeeklyReportWeek] {
        guard maximum > 0 else { return [] }
        let current = WeeklyWindow(containing: now, dataUntil: now, timeZone: timeZone)
        var out = [WeeklyReportWeek(window: current, now: now)]
        let ordered = PerfCodec.ordered(WeeklyReportBuild.reportEvents(events))
        let index = WeeklyMetricsBuilder.Index(ordered: ordered, excluded: PerfFilter.excludedSessions(in: ordered),
                                               rollup: PerfRollup())
        guard let first = index.firstEvent else { return out }
        var week = current.shifted(weeks: -1)
        var looked = 0
        while out.count < maximum, week.end > first, looked < lookBackWeeks {
            if WeeklyMetricsBuilder.metrics(index, window: week).daysPlayed > 0 {
                out.append(WeeklyReportWeek(window: week, now: now))
            }
            week = week.shifted(weeks: -1)
            looked += 1
        }
        return out
    }
}

/// Every string of the 每週報告 row and the clear dialog's new sentence. `review.weekly.*` keys with design §9.4
/// copy hold it verbatim; the others were written for W5 (ADR 0025). The Traditional-only and banned-word checks
/// scan every entry.
public enum WeeklyReportUILabels {
    public static let table: [String: WeeklyWords] = [
        "review.weekly.title": WeeklyWords("每週報告",
                                           "Weekly report"),
        "review.weekly.ready": WeeklyWords("今個星期嘅報告可以製作喇",
                                           "This week's report is ready to make"),
        "review.weekly.week": WeeklyWords("{m}月{d}日至{m2}月{d2}日",
                                          "{mon} {d} – {mon2} {d2}"),
        "review.weekly.draft": WeeklyWords("星期未完（資料截至而家）",
                                           "Week in progress (data up to now)"),
        "review.weekly.make": WeeklyWords("製作 PDF",
                                          "Make PDF"),
        "review.weekly.making": WeeklyWords("製作緊…",
                                            "Making…"),
        "review.weekly.done": WeeklyWords("已製作，資料夾已開啟。",
                                          "Made. The folder is open."),
        "review.weekly.show": WeeklyWords("喺 Finder 顯示",
                                          "Show in Finder"),
        "review.weekly.failed": WeeklyWords("製作唔到報告，請再試。（唔影響小朋友玩）",
                                            "Couldn't make the report. Please try again. (Play is not affected.)"),
        "review.weekly.shareNote": WeeklyWords("入面有 {name} 嘅紀錄，只分享俾屋企人。",
                                               "Contains {name}'s records — share with family only."),
        "review.weekly.loading": WeeklyWords("計緊…",
                                             "Loading…"),
        "review.weekly.finderHint": WeeklyWords("見唔到 Finder？佢喺 Visa Games 後面打開，撳「離開程式」就見到。",
                                                "No Finder window? It opens underneath Visa Games; use Quit to see it."),
        "clear.sharedReports": WeeklyWords("已經分享出去嘅週報唔會被刪除。",
                                           "Reports you have already shared are not deleted.")
    ]

    /// Words of label `id` with `{slots}` filled in one pass (the W4 rule); an unknown id gives empty words.
    public static func text(_ id: String, _ values: [String: WeeklyWords] = [:]) -> WeeklyWords {
        guard let words = table[id] else { return WeeklyWords("", "") }
        var zhValues: [String: String] = [:]
        var enValues: [String: String] = [:]
        for (key, value) in values {
            zhValues[key] = value.zh
            enValues[key] = value.en
        }
        var missing: [String] = []
        let zh = WeeklyFormat.fill(words.zh, zhValues, missing: &missing)
        let en = WeeklyFormat.fill(words.en, enValues, missing: &missing)
        return WeeklyWords(zh, en)
    }

    /// 「中文 / English」 on one line, like the other parent status lines (「已匯出，資料夾已開啟。 / Exported.」).
    public static func line(_ id: String, _ values: [String: WeeklyWords] = [:]) -> String {
        let words = text(id, values)
        return words.zh + " / " + words.en
    }

    /// 「10月19日至10月25日」 / "Oct 19 – Oct 25" for two day stamps.
    public static func weekLabel(weekStart: String, weekEnd: String) -> WeeklyWords {
        let first = monthDay(weekStart)
        let last = monthDay(weekEnd)
        var values: [String: WeeklyWords] = [:]
        values["m"] = WeeklyReportLabels.number(first.month)
        values["d"] = WeeklyReportLabels.number(first.day)
        values["m2"] = WeeklyReportLabels.number(last.month)
        values["d2"] = WeeklyReportLabels.number(last.day)
        values["mon"] = WeeklyReportLabels.same(monthEN(first.month))
        values["mon2"] = WeeklyReportLabels.same(monthEN(last.month))
        return text("review.weekly.week", values)
    }

    /// 「入面有 Cedric 嘅紀錄，只分享俾屋企人。」 with the report's child name (D7; W5b makes it editable).
    public static func shareNote(childName: String) -> WeeklyWords {
        text("review.weekly.shareNote", ["name": WeeklyReportLabels.same(childName)])
    }

    /// §11: the sentence the 「清除表現紀錄」 confirmation gains.
    public static var clearNote: WeeklyWords {
        text("clear.sharedReports")
    }

    static func monthDay(_ stamp: String) -> (month: Int, day: Int) {
        let parts = stamp.split(separator: "-").map { Int($0) ?? 0 }
        guard parts.count == 3 else { return (month: 1, day: 1) }
        return (month: parts[1], day: parts[2])
    }

    static func monthEN(_ month: Int) -> String {
        let names = WeeklyReportLabels.monthsEN
        return month >= 1 && month <= names.count ? names[month - 1] : String(month)
    }
}

/// What the row is doing. A parent visit has at most one make at a time.
public enum WeeklyReportJob: Sendable, Equatable {
    case idle
    case making(weekStart: String)
    case made(weekStart: String)
    case failed(weekStart: String)

    public var isMaking: Bool {
        if case .making = self { return true }
        return false
    }
}

/// One week as the row draws it: finished strings, nothing to compute in a view body.
public struct WeeklyReportRow: Sendable, Equatable, Identifiable {
    public let weekStart: String
    /// 「10月19日至10月25日」 / "Oct 19 – Oct 25".
    public let label: WeeklyWords
    /// 「星期未完（資料截至而家） / Week in progress (data up to now)」 for a week that is not over.
    public let draft: String?
    /// 「製作 PDF / Make PDF」, or 「製作緊… / Making…」 on the week being made.
    public let makeTitle: String
    /// False while any week is being made.
    public let canMake: Bool
    public let isMaking: Bool
    /// 「喺 Finder 顯示 / Show in Finder」 once this week's PDF was made in this parent visit.
    public let finderTitle: String?
    /// The done line with the Finder hint, or the failure line.
    public let status: [String]

    public var id: String { weekStart }
}

/// The whole 每週報告 block: an `Equatable` value, so the 表現 screen's `.equatable()` skips the 0.5 s tick.
public struct WeeklyReportPanel: Sendable, Equatable {
    public var list: WeeklyReportWeekList
    /// False until the first list arrives from the recorder queue.
    public var loaded: Bool
    public var job: WeeklyReportJob
    /// D7: Cedric (`WeeklyReportText.defaultChildName`) until W5b adds the parent-set nickname.
    public var childName: String

    public init(list: WeeklyReportWeekList = WeeklyReportWeekList(), loaded: Bool = false,
                job: WeeklyReportJob = .idle, childName: String = WeeklyReportText.defaultChildName) {
        self.list = list
        self.loaded = loaded
        self.job = job
        self.childName = childName
    }

    /// 「每週報告」 / "Weekly report".
    public var title: WeeklyWords {
        WeeklyReportUILabels.text("review.weekly.title")
    }

    /// 「計緊… / Loading…」 until the weeks are read.
    public var loadingLine: String? {
        loaded ? nil : WeeklyReportUILabels.line("review.weekly.loading")
    }

    /// 「今個星期嘅報告可以製作喇 / This week's report is ready to make」 from Sunday 21:00 (as of the last read).
    public var banner: String? {
        loaded && list.ready ? WeeklyReportUILabels.line("review.weekly.ready") : nil
    }

    /// 「入面有 Cedric 嘅紀錄，只分享俾屋企人。 / Contains Cedric's records — share with family only.」
    public var shareNote: String {
        let words = WeeklyReportUILabels.shareNote(childName: childName)
        return words.zh + " / " + words.en
    }

    public var rows: [WeeklyReportRow] {
        loaded ? list.weeks.map { row($0) } : []
    }

    public func row(_ week: WeeklyReportWeek) -> WeeklyReportRow {
        let here = week.weekStart
        let makingHere = job == .making(weekStart: here)
        let madeHere = job == .made(weekStart: here)
        var status: [String] = []
        if madeHere {
            status.append(WeeklyReportUILabels.line("review.weekly.done"))
            status.append(WeeklyReportUILabels.line("review.weekly.finderHint"))
        } else if job == .failed(weekStart: here) {
            status.append(WeeklyReportUILabels.line("review.weekly.failed"))
        }
        return WeeklyReportRow(
            weekStart: here,
            label: week.label,
            draft: week.isDraft ? WeeklyReportUILabels.line("review.weekly.draft") : nil,
            makeTitle: WeeklyReportUILabels.line(makingHere ? "review.weekly.making" : "review.weekly.make"),
            canMake: !job.isMaking,
            isMaking: makingHere,
            finderTitle: madeHere ? WeeklyReportUILabels.line("review.weekly.show") : nil,
            status: status
        )
    }
}
