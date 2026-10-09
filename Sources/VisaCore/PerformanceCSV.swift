import Foundation

/// Parent-only CSV export (design §5.10). UTF-8 with BOM, RFC 4180 quoting, CRLF rows,
/// HKT date/time columns plus a UTC column. Every row is exported, with `counted`
/// saying whether it belongs to the child's own play.
public enum PerfCSVExport {
    public static let bom = "\u{FEFF}"

    public static let roundsHeader = [
        "date_hkt", "time_hkt", "ts_utc", "round_id", "session_id", "actor", "counted", "stars",
        "kind", "kind_zh", "item_id", "deal_mode", "outcome", "abandon_reason", "first_try", "misses",
        "answers", "hint_used", "assisted", "pending_start_min", "earned_min", "active_s", "total_s",
        "first_tap_s", "wrong_choices", "wrong_tags", "wrong_slots", "repeat_wrong", "fast_wrong",
        "mash_taps", "steps_before_first_miss", "app_version"
    ]

    public static let videosHeader = [
        "date_hkt", "time_hkt", "ts_utc", "play_id", "session_id", "actor", "counted", "visa_source",
        "video_id", "title", "source", "visit_id", "page", "slot", "deck_size", "ms_on_page",
        "start_s", "stop_reason", "completed", "resume_saved", "resumed_later", "watched_s", "wall_s",
        "max_pos_s", "duration_s", "completion_pct", "telemetry", "app_version"
    ]

    public static let impressionsHeader = [
        "date_hkt", "time_hkt", "ts_utc", "visit_id", "session_id", "actor", "counted", "page",
        "slot", "video_id", "title", "via", "picked"
    ]

    public static let dailyGamesHeader = [
        "date_hkt", "kind", "kind_zh", "stars", "deals", "answered", "first_try", "misses",
        "solved", "zeroed", "abandoned", "hinted", "active_s"
    ]

    public static let dailyVideosHeader = [
        "date_hkt", "video_id", "title", "impressions", "picks", "plays", "completions",
        "time_up_cuts", "resumed_plays", "watched_min"
    ]

    /// RFC 4180: quote when a field has a comma, quote, CR or LF; double inner quotes.
    public static func escape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    public static func document(header: [String], rows: [[String]]) -> String {
        let lines = [header] + rows
        return bom + lines.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// All export files: name → contents.
    public static func files(events: [PerfEvent], rollup: PerfRollup, titles: [String: String],
                             timeZone: TimeZone = PerfClock.hongKong) -> [String: String] {
        let ordered = PerfCodec.ordered(events)
        let excluded = PerfFilter.excludedSessions(in: ordered)
        return [
            "rounds.csv": document(header: roundsHeader,
                                   rows: roundRows(ordered, excluded: excluded, timeZone: timeZone)),
            "videos.csv": document(header: videosHeader,
                                   rows: videoRows(ordered, excluded: excluded, titles: titles, timeZone: timeZone)),
            "video_impressions.csv": document(header: impressionsHeader,
                                              rows: impressionRows(ordered, excluded: excluded, titles: titles,
                                                                   timeZone: timeZone)),
            "daily_games.csv": document(header: dailyGamesHeader, rows: dailyGameRows(rollup)),
            "daily_videos.csv": document(header: dailyVideosHeader, rows: dailyVideoRows(rollup, titles: titles)),
            "README.txt": readme
        ]
    }

    // MARK: Rows

    static func timeColumns(_ date: Date, timeZone: TimeZone) -> [String] {
        [PerfClock.dayStamp(date, timeZone: timeZone),
         PerfClock.timeStamp(date, timeZone: timeZone),
         PerfCodec.formatTimestamp(date)]
    }

    static func yesNo(_ value: Bool?) -> String {
        guard let value else { return "" }
        return value ? "yes" : "no"
    }

    static func number(_ value: Double?, decimals: Int = 1) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.\(decimals)f", value)
    }

    static func msToSeconds(_ value: Int?) -> String {
        guard let value else { return "" }
        return number(Double(value) / 1000)
    }

    public static func roundRows(_ events: [PerfEvent], excluded: Set<String>,
                                 timeZone: TimeZone) -> [[String]] {
        var answers: [String: [PerfEvent]] = [:]
        var results: [String: PerfEvent] = [:]
        for event in events {
            guard let round = event.string("round") else { continue }
            switch event.type {
            case .answerAttempt: answers[round, default: []].append(event)
            case .roundResult: results[round] = event
            default: break
            }
        }
        var rows: [[String]] = []
        for dealt in events where dealt.type == .gameDealt {
            guard let round = dealt.string("round") else { continue }
            let result = results[round]
            let wrong = (answers[round] ?? []).filter { $0.bool("correct") == false }
            let kind = dealt.string("kind").flatMap(ActivityKind.init(rawValue:))
            let outcome = result?.string("outcome") ?? "abandoned"
            let roundAnswers: [PerfEvent] = answers[round] ?? []
            let misses: String = result?.int("misses").map(String.init) ?? String(wrong.count)
            let answerCount: String = result?.int("answers").map(String.init) ?? String(roundAnswers.count)
            let abandonReason: String = result == nil ? "no_result_recorded" : (result?.string("reason") ?? "")
            let wrongChoices: String = wrong.map { $0.string("choice") ?? "" }.joined(separator: "|")
            let wrongTags: String = wrong.map { ($0["tags"]?.stringArray ?? []).joined(separator: "+") }
                .joined(separator: "|")
            let wrongSlots: String = wrong.map { $0.int("slot").map(String.init) ?? "" }.joined(separator: "|")
            let repeatWrong: Int = wrong.filter { $0.bool("repeat_wrong") == true }.count
            let fastWrong: Int = wrong.filter { $0.bool("fast") == true }.count
            var row: [String] = timeColumns(dealt.timestamp, timeZone: timeZone)
            row.append(round)
            row.append(dealt.session)
            row.append(dealt.actor.rawValue)
            row.append(yesNo(PerfFilter.countable(dealt, excludedSessions: excluded)))
            row.append(dealt.int("stars").map(String.init) ?? "")
            row.append(dealt.string("kind") ?? "")
            row.append(kind?.parentCardTitle ?? "")
            row.append(dealt.string("item") ?? "")
            row.append(dealt.string("deal_mode") ?? "")
            row.append(outcome)
            row.append(abandonReason)
            row.append(yesNo(result?.bool("first_try")))
            row.append(misses)
            row.append(answerCount)
            row.append(yesNo(result?.bool("hint_used")))
            row.append(yesNo(result?.bool("assisted")))
            row.append(dealt.int("pending_start").map(String.init) ?? "")
            row.append(result?.int("earned_min").map(String.init) ?? "0")
            row.append(msToSeconds(result?.int("active_ms")))
            row.append(msToSeconds(result?.int("total_ms")))
            row.append(msToSeconds(result?.int("first_tap_ms")))
            row.append(wrongChoices)
            row.append(wrongTags)
            row.append(wrongSlots)
            row.append(String(repeatWrong))
            row.append(String(fastWrong))
            row.append(result?.int("mash_taps").map(String.init) ?? "")
            row.append(result?.int("steps_before_first_miss").map(String.init) ?? "")
            row.append(dealt.app)
            rows.append(row)
        }
        return rows
    }

    public static func videoRows(_ events: [PerfEvent], excluded: Set<String>, titles: [String: String],
                                 timeZone: TimeZone) -> [[String]] {
        var ends: [String: PerfEvent] = [:]
        for event in events where event.type == .videoEnd {
            if let play = event.string("play") { ends[play] = event }
        }
        let starts = events.filter { $0.type == .videoStart }
        var rows: [[String]] = []
        for (index, start) in starts.enumerated() {
            guard let play = start.string("play") else { continue }
            let end = ends[play]
            let video = start.string("video") ?? ""
            let resumeSaved = end?.bool("resume_saved") == true
            var resumedLater = ""
            if resumeSaved {
                if let next = starts[(index + 1)...].first(where: { $0.actor != .parentPreview }) {
                    resumedLater = yesNo(next.string("source") == "continue" && next.string("video") == video)
                }
            }
            let duration: Double? = end?.double("duration_s") ?? start.double("duration_s")
            let completion: String = end?.double("completion").map { number($0 * 100, decimals: 0) } ?? ""
            var row: [String] = timeColumns(start.timestamp, timeZone: timeZone)
            row.append(play)
            row.append(start.session)
            row.append(start.actor.rawValue)
            row.append(yesNo(PerfFilter.countable(start, excludedSessions: excluded)))
            row.append(start.string("visa_source") ?? "")
            row.append(video)
            row.append(titles[video] ?? "")
            row.append(start.string("source") ?? "")
            row.append(start.string("visit") ?? "")
            row.append(start.int("page").map(String.init) ?? "")
            row.append(start.int("slot").map(String.init) ?? "")
            row.append(start.int("deck_size").map(String.init) ?? "")
            row.append(start.int("ms_on_page").map(String.init) ?? "")
            row.append(number(start.double("start_s")))
            row.append(end?.string("reason") ?? "no_end_recorded")
            row.append(yesNo(end?.bool("completed")))
            row.append(end == nil ? "" : yesNo(resumeSaved))
            row.append(resumedLater)
            row.append(number(end?.double("watched_s")))
            row.append(number(end?.double("wall_s")))
            row.append(number(end?.double("max_pos_s")))
            row.append(number(duration))
            row.append(completion)
            row.append(end?.string("telemetry") ?? "")
            row.append(start.app)
            rows.append(row)
        }
        return rows
    }

    public static func impressionRows(_ events: [PerfEvent], excluded: Set<String>, titles: [String: String],
                                      timeZone: TimeZone) -> [[String]] {
        var picked = Set<String>()
        for event in events where event.type == .videoPick && event.bool("accepted") == true {
            picked.insert("\(event.string("visit") ?? "")|\(event.int("page") ?? -1)|\(event.string("video") ?? "")")
        }
        var rows: [[String]] = []
        for event in events where event.type == .videoImpressions {
            let visit = event.string("visit") ?? ""
            let page = event.int("page") ?? 0
            for (slot, id) in (event["ids"]?.stringArray ?? []).enumerated() {
                rows.append(timeColumns(event.timestamp, timeZone: timeZone) + [
                    visit,
                    event.session,
                    event.actor.rawValue,
                    yesNo(PerfFilter.countable(event, excludedSessions: excluded)),
                    String(page),
                    String(slot),
                    id,
                    titles[id] ?? "",
                    event.string("via") ?? "",
                    yesNo(picked.contains("\(visit)|\(page)|\(id)"))
                ])
            }
        }
        return rows
    }

    static func dailyGameRows(_ rollup: PerfRollup) -> [[String]] {
        var rows: [[String]] = []
        for day in rollup.days.keys.sorted() {
            guard let summary = rollup.days[day] else { continue }
            for key in summary.games.keys.sorted() {
                guard let stats = summary.games[key] else { continue }
                let parts = key.split(separator: "|").map(String.init)
                let kind = parts.first ?? ""
                rows.append([
                    day, kind, ActivityKind(rawValue: kind)?.parentCardTitle ?? "",
                    parts.count > 1 ? parts[1] : "",
                    String(stats.deals), String(stats.answered), String(stats.firstTry), String(stats.misses),
                    String(stats.solved), String(stats.zeroed), String(stats.abandoned), String(stats.hinted),
                    number(Double(stats.activeMs) / 1000)
                ])
            }
        }
        return rows
    }

    static func dailyVideoRows(_ rollup: PerfRollup, titles: [String: String]) -> [[String]] {
        var rows: [[String]] = []
        for day in rollup.days.keys.sorted() {
            guard let summary = rollup.days[day] else { continue }
            for id in summary.videos.keys.sorted() {
                guard let stats = summary.videos[id] else { continue }
                rows.append([
                    day, id, titles[id] ?? "",
                    String(stats.impressions), String(stats.picks), String(stats.plays),
                    String(stats.completions), String(stats.timeUpCuts), String(stats.resumedPlays),
                    number(stats.watchedSeconds / 60)
                ])
            }
        }
        return rows
    }

    public static let readme = """
    Visa Games 表現紀錄匯出 / Performance records export
    ====================================================

    入面有小朋友嘅紀錄，請勿上載到公開網站或 GitHub。
    Contains your child's records. Do not upload to public sites or GitHub.

    紀錄只存喺呢部 Mac，唔會上網。 / Records stay on this Mac. Nothing goes online.
    日期時間係香港時間（HKT）；ts_utc 係 UTC。 / Dates and times are Hong Kong time; ts_utc is UTC.

    counted = yes：小朋友自己玩，會計入表現。
    counted = no：家長試玩、試播、測試一分鐘簽證、「家長測試中」或者「唔計呢段」，唔計。
    counted = yes is the child's own play. counted = no is parent playtest, preview, test visa,
    parent test mode, or a session marked "don't count".

    actor
      child             小朋友 / the child
      parent_uat        家長測試中 / parent test mode (switch on)
      parent_test_visa  測試一分鐘簽證 / parent 1-minute test visa
      parent_playtest   家長試玩 / parent game playtest
      parent_preview    家長試播 / parent video preview

    rounds.csv — 每局一行 / one row per round
      outcome           solved 完成 · zeroed 油用晒 · abandoned 未完成
      first_try         第一下就啱 / right on the first tap
      misses            錯咗幾多次 / wrong taps
      pending_start_min 車票分鐘 / ticket minutes; earned_min 最後得到嘅簽證分鐘 / visa minutes earned
      active_s          答題時間（唔計停一停同家長時間）/ answering time without pauses or parent time
      first_tap_s       第一下用咗幾耐 / time to the first tap
      wrong_choices     錯咗揀咗邊個（| 分隔）/ wrong picks (| separated)
      wrong_tags        錯嘅類型，例如 same_shape+diff_color / confusion tags
      wrong_slots       錯嘅位置（0 = 最左）/ screen slot of each wrong pick (0 = leftmost)
      mash_taps         停一停時撳咗幾多下 / taps during the think pause

    videos.csv — 每次播片一行 / one row per video play
      source            pick 揀片 · continue 繼續睇 · after_parent 家長返回後再播 · parent_preview 試播
      page, slot        揀片時喺第幾頁、第幾格（0 起計，4×2 由左至右、由上至下）/ picker page and slot (0-based)
      stop_reason       ended 睇完 · visa_expired 簽證時間到 · budget_exhausted 觀看時間用完 ·
                        nav_blocked 撳咗 YouTube 連結被擋 · parent_unlock 家長打開設定 ·
                        preview_stopped 試播停止 · allowlist_removed 片被移除 ·
                        reset_storage 重設儲存 · storage_failure 儲存失敗 · superseded 被新播放取代 ·
                        terminate 離開程式 · no_end_recorded 冇結束紀錄（例如斷電）
      completed         睇完成條片 / reached the end
      resume_saved      時間到停咗，有記低進度 / stopped by time, position saved
      resumed_later     之後有冇揀「繼續睇」/ later continued with 繼續睇
      watched_s         真正播咗幾多秒 / seconds actually played
      telemetry         full 有播放資料 · wall_only 冇播放資料（用時鐘估）

    video_impressions.csv — 揀片畫面每格一行 / one row per card shown on a picker page
      picked            呢頁有冇揀呢條片 / picked from this page

    daily_games.csv / daily_videos.csv — 超過 90 日嘅每日摘要 / daily summaries after 90 days
    """
}
