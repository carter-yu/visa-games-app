import Foundation

// Weekly report W1 (weekly-report design §9.6): one canonical JSON text for the weekly model,
// so a golden fixture can be compared byte for byte and a remake for the same `dataUntil`
// gives the same bytes. Rules (also in Tests/VisaCoreTests/Fixtures/weekly-2026-10-19/README.md):
// keys sorted by UTF-8 bytes, two-space indent, `": "` after keys, `\n` line ends and one final
// newline; integers in plain decimal; every Double with exactly 6 decimals (POSIX `%.6f`, never
// "-0.000000"); nil as `null`; strings escape only `"`, `\` and control characters.

public enum WeeklyJSON {
    public static let decimals = 6

    public static func encode(_ value: PerfValue) -> String {
        let posix = Locale(identifier: "en_US_POSIX")
        var out = ""
        write(value, indent: 0, locale: posix, into: &out)
        out.append("\n")
        return out
    }

    public static func number(_ value: Double, locale: Locale = Locale(identifier: "en_US_POSIX")) -> String {
        guard value.isFinite else { return "null" }
        let text = String(format: "%.\(decimals)f", locale: locale, value)
        if text.hasPrefix("-"), text.dropFirst().allSatisfy({ $0 == "0" || $0 == "." }) {
            return String(text.dropFirst())
        }
        return text
    }

    public static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out.append("\\\"")
            case "\\": out.append("\\\\")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            case "\u{08}": out.append("\\b")
            case "\u{0C}": out.append("\\f")
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out.append("\\u" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out.append("\"")
        return out
    }

    static func write(_ value: PerfValue, indent: Int, locale: Locale, into out: inout String) {
        switch value {
        case .null:
            out.append("null")
        case .bool(let flag):
            out.append(flag ? "true" : "false")
        case .int(let integer):
            out.append(String(integer))
        case .double(let fraction):
            out.append(number(fraction, locale: locale))
        case .string(let text):
            out.append(quoted(text))
        case .array(let items):
            guard !items.isEmpty else {
                out.append("[]")
                return
            }
            out.append("[\n")
            for (offset, item) in items.enumerated() {
                out.append(String(repeating: " ", count: indent + 2))
                write(item, indent: indent + 2, locale: locale, into: &out)
                out.append(offset + 1 < items.count ? ",\n" : "\n")
            }
            out.append(String(repeating: " ", count: indent))
            out.append("]")
        case .object(let fields):
            guard !fields.isEmpty else {
                out.append("{}")
                return
            }
            out.append("{\n")
            let keys = fields.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            for (offset, key) in keys.enumerated() {
                out.append(String(repeating: " ", count: indent + 2))
                out.append(quoted(key))
                out.append(": ")
                write(fields[key] ?? .null, indent: indent + 2, locale: locale, into: &out)
                out.append(offset + 1 < keys.count ? ",\n" : "\n")
            }
            out.append(String(repeating: " ", count: indent))
            out.append("}")
        }
    }

    // MARK: Values

    static func real(_ value: Double?) -> PerfValue {
        guard let value else { return .null }
        return .double(value)
    }

    static func minutes(_ ms: Int) -> PerfValue {
        .double(Double(ms) / 60_000)
    }

    static func estimate(_ estimate: PerfMastery.Estimate?) -> PerfValue {
        guard let estimate else { return .null }
        var o: [String: PerfValue] = [:]
        o["p0"] = .double(estimate.prior)
        o["alpha"] = .double(estimate.alpha)
        o["beta"] = .double(estimate.beta)
        o["mean"] = .double(estimate.mean)
        o["sd"] = .double(estimate.sd)
        o["m"] = .double(estimate.mastery)
        o["lo"] = .double(estimate.masteryLow)
        o["hi"] = .double(estimate.masteryHigh)
        return .object(o)
    }

    static func counts(_ counts: WeeklyCounts, type: WeeklyRoundType, key: String, value: Int) -> PerfValue {
        var o: [String: PerfValue] = [:]
        o[key] = .int(value)
        o["rounds"] = .int(counts.rounds)
        switch type {
        case .quiz:
            o["answered"] = .int(counts.answered)
            o["first_try"] = .int(counts.firstTry)
        case .practice:
            o["finished"] = .int(counts.finished)
            o["smooth_defined"] = .int(counts.smoothDefined)
            o["smooth"] = .int(counts.smooth)
        }
        return .object(o)
    }

    static func group(_ group: WeeklyGroupMetrics) -> [String: PerfValue] {
        var o: [String: PerfValue] = [:]
        o["rounds"] = .int(group.rounds)
        o["quiz_rounds"] = .int(group.quizRounds)
        o["practice_rounds"] = .int(group.practiceRounds)
        o["quiz_answered"] = .int(group.answered)
        o["quiz_first_try"] = .int(group.firstTry)
        o["quiz_rate"] = real(group.quizRate)
        o["quiz_expected"] = .double(group.expected)
        o["quiz_expected_answered"] = .int(group.expectedAnswered)
        o["quiz_chance_mean"] = real(group.chanceMean)
        o["quiz_adjusted"] = real(group.adjusted)
        o["practice_finished"] = .int(group.finished)
        o["practice_smooth_defined"] = .int(group.smoothDefined)
        o["practice_smooth"] = .int(group.smooth)
        o["practice_rate"] = real(group.practiceRate)
        return o
    }

    static func family(_ family: WeeklyPracticeFamily, _ group: WeeklyGroupMetrics) -> PerfValue {
        var o: [String: PerfValue] = [:]
        o["family"] = .string(family.rawValue)
        o["rounds"] = .int(group.rounds)
        o["finished"] = .int(group.finished)
        o["smooth_defined"] = .int(group.smoothDefined)
        o["smooth"] = .int(group.smooth)
        o["rate"] = real(group.practiceRate)
        return .object(o)
    }
}

extension WeeklyRound {
    public var json: PerfValue {
        let quiz = type == .quiz
        var o: [String: PerfValue] = [:]
        o["round"] = .string(round)
        o["kind"] = .string(kind)
        o["type"] = .string(type.rawValue)
        o["day"] = .int(day)
        o["stars"] = .int(stars)
        o["outcome"] = .string(outcome.rawValue)
        o["game_ms"] = .int(gameMs)
        o["visa_min"] = .int(earnedMinutes)
        o["answered"] = quiz ? PerfValue.bool(answered) : PerfValue.null
        o["first_try"] = quiz ? PerfValue.bool(firstTry) : PerfValue.null
        o["chance"] = WeeklyJSON.real(chance)
        o["smooth"] = PerfValue.optionalBool(smooth)
        return .object(o)
    }
}

extension WeeklyKindMetrics {
    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["kind"] = .string(kind)
        o["type"] = .string(type.rawValue)
        o["area"] = .string(area.rawValue)
        o["family"] = PerfValue.optionalString(family?.rawValue)
        o["new"] = .bool(isNew)
        o["rounds"] = .int(rounds)
        o["solved"] = .int(solved)
        o["zeroed"] = .int(zeroed)
        o["unfinished"] = .int(unfinished)
        o["no_result"] = .int(noResult)
        o["days_played"] = .int(daysPlayed)
        o["estimate"] = WeeklyJSON.estimate(estimate)
        var starList: [PerfValue] = []
        for (offset, counts) in stars.enumerated() {
            starList.append(WeeklyJSON.counts(counts, type: type, key: "stars", value: offset + 1))
        }
        o["stars"] = .array(starList)
        var dayList: [PerfValue] = []
        for (offset, counts) in cells.enumerated() where counts.rounds > 0 {
            dayList.append(WeeklyJSON.counts(counts, type: type, key: "day", value: offset))
        }
        o["days"] = .array(dayList)
        switch type {
        case .quiz:
            o["answered"] = .int(answered)
            o["first_try"] = .int(firstTry)
            o["rate"] = WeeklyJSON.real(rate)
            o["chance_known"] = .bool(chanceKnown)
            o["expected"] = WeeklyJSON.real(expected)
            o["chance_mean"] = WeeklyJSON.real(chanceMean)
            o["adjusted"] = WeeklyJSON.real(adjusted)
            o["misses"] = .int(misses)
            o["misses_per_round"] = WeeklyJSON.real(missesPerRound)
            o["helped"] = .int(helped)
            o["help_rate"] = WeeklyJSON.real(helpRate)
            o["median_active_s"] = WeeklyJSON.real(medianActiveSeconds)
            o["wrong_attempts"] = .int(wrongAttempts)
            o["fast_wrong"] = .int(fastWrong)
            o["fast_wrong_share"] = WeeklyJSON.real(fastWrongShare)
            o["top_wrong_tag"] = PerfValue.optionalString(topWrongTag)
            o["top_wrong_tag_count"] = .int(topWrongTagCount)
        case .practice:
            o["finished"] = .int(solved)
            o["smooth_defined"] = .int(smoothDefined)
            o["smooth"] = .int(smooth)
            o["rate"] = WeeklyJSON.real(rate)
            o["guide_helps_mean"] = WeeklyJSON.real(guideHelpsMean)
            o["help_heavy"] = .bool(helpHeavy)
        }
        return .object(o)
    }
}

extension WeeklyDayMetrics {
    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["index"] = .int(index)
        o["date"] = .string(date)
        o["rounds"] = .int(counts.rounds)
        o["quiz_rounds"] = .int(quizRounds)
        o["quiz_answered"] = .int(counts.answered)
        o["quiz_first_try"] = .int(counts.firstTry)
        o["practice_rounds"] = .int(practiceRounds)
        o["practice_finished"] = .int(counts.finished)
        o["practice_smooth_defined"] = .int(counts.smoothDefined)
        o["practice_smooth"] = .int(counts.smooth)
        o["quiz_min"] = WeeklyJSON.minutes(quizMs)
        o["practice_min"] = WeeklyJSON.minutes(practiceMs)
        o["game_min"] = WeeklyJSON.minutes(gameMs)
        o["video_min"] = WeeklyJSON.minutes(videoMs)
        o["video_estimated"] = .bool(videoEstimated)
        o["plays"] = .int(plays)
        o["visa_min"] = .int(visaMinutes)
        o["sessions"] = .int(sessions.count)
        o["new_kinds"] = PerfValue.strings(newKinds)
        return .object(o)
    }
}

extension WeeklyWindowMetrics {
    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["week_start"] = .string(window.weekStartStamp)
        o["week_end"] = .string(window.weekEndStamp)
        o["data_until"] = .string(PerfCodec.formatTimestamp(window.cutoff))
        o["covered_days"] = .int(coveredDays)
        o["partial"] = .bool(partial)
        o["open_at_cutoff"] = .int(openAtCutoff)
        var excluded: [String: PerfValue] = [:]
        excluded["total"] = .int(excludedTotal)
        excluded["by_reason"] = .object(excludedRounds.mapValues { PerfValue.int($0) })
        o["excluded_rounds"] = .object(excluded)
        var pooled: [String: PerfValue] = [:]
        pooled["quiz"] = .double(pooledQuiz)
        pooled["practice"] = .double(pooledPractice)
        o["pooled"] = .object(pooled)
        o["stars"] = .array(stars.map { PerfValue.int($0) })
        o["new_kinds"] = PerfValue.strings(newKinds)
        o["days"] = .array(days.map(\.json))
        o["kinds"] = .array(kinds.map(\.json))
        o["areas"] = .array(WeeklyArea.allCases.map { area -> PerfValue in
            var fields = WeeklyJSON.group(areas[area] ?? WeeklyGroupMetrics())
            fields["area"] = .string(area.rawValue)
            return .object(fields)
        })
        o["families"] = .array(WeeklyPracticeFamily.allCases.map { family -> PerfValue in
            WeeklyJSON.family(family, families[family] ?? WeeklyGroupMetrics())
        })
        var totalsFields = WeeklyJSON.group(totals)
        totalsFields["days_played"] = .int(daysPlayed)
        totalsFields["sessions"] = .int(sessionCount)
        totalsFields["plays"] = .int(plays)
        totalsFields["quiz_min"] = WeeklyJSON.minutes(quizMs)
        totalsFields["practice_min"] = WeeklyJSON.minutes(practiceMs)
        totalsFields["game_min"] = WeeklyJSON.minutes(quizMs + practiceMs)
        totalsFields["video_min"] = WeeklyJSON.minutes(videoMs)
        totalsFields["video_estimated"] = .bool(videoEstimated)
        totalsFields["visa_min"] = .int(visaMinutes)
        o["totals"] = .object(totalsFields)
        o["rounds"] = .array(rounds.map(\.json))
        return .object(o)
    }
}

extension WeeklyWeekTotals {
    public var json: PerfValue {
        var o = WeeklyJSON.group(totals)
        o["week_start"] = .string(weekStart)
        o["current"] = .bool(isCurrent)
        o["partial"] = .bool(partial)
        o["open_at_cutoff"] = .int(openAtCutoff)
        return .object(o)
    }
}

extension WeeklyModel {
    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["builder"] = .int(Self.builderVersion)
        o["time_zone"] = .string(window.timeZone.identifier)
        o["week_start"] = .string(window.weekStartStamp)
        o["data_until"] = .string(PerfCodec.formatTimestamp(window.cutoff))
        o["current"] = current.json
        o["previous"] = previous.json
        o["weeks"] = .array(weeks.map(\.json))
        return .object(o)
    }

    /// The canonical text (`WeeklyJSON`): what the golden fixture compares and what a later
    /// slice can keep beside the PDF (D11).
    public func canonicalJSON() -> String {
        WeeklyJSON.encode(json)
    }
}
