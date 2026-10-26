import Foundation

// Weekly report W3 (weekly-report design §6.2): the typed slots, the one formatter and the rendered
// sentence with its traceable numbers. Every number a template prints is rounded here in integers
// (half up) and recorded as (path, value), so `testEveryNumberTraceable` can re-scan the text. Pure
// value code: no host locale, time zone or calendar is read.

/// One printed number and where it comes from (design §6.2 `traceable`).
public struct WeeklyTraceable: Sendable, Equatable {
    /// `metrics.` (the W1 model JSON), `analysis.` (the W2 analysis JSON), `facts.` (the facts block of
    /// the text JSON), or a `copy.` / `rule.` constant (`WeeklyTextCatalog.constants`). A suffix says how
    /// the value was printed: `#pct` whole percent, `#1dp` one decimal, `#h` / `#m` hours and minutes,
    /// `#count` the number of entries.
    public var path: String
    /// The number as printed, without leading zeros ("7" for the "07" of "2 h 07 min").
    public var value: String

    public init(path: String, value: String) {
        self.path = path
        self.value = value
    }

    public var json: PerfValue {
        .object(["path": .string(path), "value": .string(value)])
    }
}

/// One rendered sentence, or a fragment of one, in Hong Kong Traditional Chinese and English.
public struct WeeklySentence: Sendable, Equatable {
    /// The template id (`WeeklyTemplates`); empty for a joined fragment.
    public var id: String
    public var zh: String
    public var en: String
    public var traceable: [WeeklyTraceable]
    /// Text inserted unchanged (video titles, the child's name, ids of unknown games). It is not our
    /// copy, so the number, word and Traditional-only checks skip it.
    public var verbatim: [String]
    /// Rendering problems (unknown template, missing or mistyped slot). Never in the JSON; the checks
    /// require none.
    public var problems: [String]

    public init(id: String = "", zh: String = "", en: String = "", traceable: [WeeklyTraceable] = [],
                verbatim: [String] = [], problems: [String] = []) {
        self.id = id
        self.zh = zh
        self.en = en
        self.traceable = traceable
        self.verbatim = verbatim
        self.problems = problems
    }

    public static let empty = WeeklySentence()

    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["id"] = .string(id)
        o["zh"] = .string(zh)
        o["en"] = .string(en)
        o["traceable"] = .array(traceable.map(\.json))
        o["verbatim"] = PerfValue.strings(verbatim)
        return .object(o)
    }

    /// The parts joined by `zh` and `en` separators.
    public static func joined(_ parts: [WeeklySentence], zh: String, en: String) -> WeeklySentence {
        WeeklySentence(id: "", zh: parts.map(\.zh).joined(separator: zh), en: parts.map(\.en).joined(separator: en),
                       traceable: parts.flatMap(\.traceable), verbatim: parts.flatMap(\.verbatim),
                       problems: parts.flatMap(\.problems))
    }

    /// English "a, b and c". Chinese is joined by `zh`, with `zhLast` before the last part when given.
    public static func listed(_ parts: [WeeklySentence], zh: String = "、", zhLast: String? = nil) -> WeeklySentence {
        guard parts.count > 1, let last = parts.last else { return joined(parts, zh: zh, en: ", ") }
        let head = Array(parts.dropLast())
        let zhText = head.map(\.zh).joined(separator: zh) + (zhLast ?? zh) + last.zh
        let enText = head.map(\.en).joined(separator: ", ") + " and " + last.en
        return WeeklySentence(id: "", zh: zhText, en: enText, traceable: parts.flatMap(\.traceable),
                              verbatim: parts.flatMap(\.verbatim), problems: parts.flatMap(\.problems))
    }
}

/// §6.2 slot types. A template declares one type per slot; the renderer reports a value of another type.
public enum WeeklySlotType: String, Sendable, Equatable, CaseIterable {
    case int
    case percent
    case decimal
    case seconds
    case minutes
    case gameName
    case tagName
    case starMix
    case dayName
    case range
    /// Fixed words from the catalogue (labels, names); never digits.
    case words
    /// A fragment rendered from another template.
    case text
    /// Provider or parent text shown as recorded.
    case verbatim
}

/// The value of one slot. Numbers carry the path they are traced to.
public enum WeeklySlotValue: Sendable, Equatable {
    case int(Int, path: String)
    /// Already rounded to a whole percent; the template prints the "%".
    case percent(Int, path: String)
    /// One decimal place, given in tenths.
    case decimal(tenths: Int, path: String)
    case seconds(Double, path: String)
    /// Whole minutes: 「2 小時 7 分」 / "2 h 07 min".
    case minutes(Int, path: String)
    /// A game kind: the app's card titles (`ActivityKind.parentCardTitle` / `parentCardEnglish`).
    case game(String)
    /// An approved wrong-answer tag (`WeeklyTextCatalog.tagName`).
    case tag(String)
    /// Rounds per ★, ★★, ★★★.
    case stars([Int], path: String)
    /// 0 = Monday.
    case day(Int)
    /// "1–N" (`TapCountRange.label`).
    case range(Int, path: String)
    case words(zh: String, en: String)
    case text(WeeklySentence)
    case verbatim(String)

    public var type: WeeklySlotType {
        switch self {
        case .int: return .int
        case .percent: return .percent
        case .decimal: return .decimal
        case .seconds: return .seconds
        case .minutes: return .minutes
        case .game: return .gameName
        case .tag: return .tagName
        case .stars: return .starMix
        case .day: return .dayName
        case .range: return .range
        case .words: return .words
        case .text: return .text
        case .verbatim: return .verbatim
        }
    }
}

/// The one formatter (§6.2). Integer rounding is half up; nothing depends on the host locale.
public enum WeeklyFormat {
    public static let dayNamesZH = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]
    public static let dayNamesEN = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Whole percent of `k` / `n`, half up; 0 when `n` is 0.
    public static func percent(_ k: Int, of n: Int) -> Int {
        n > 0 ? (200 * k + n) / (2 * n) : 0
    }

    /// A share 0…1 as a whole percent, half up.
    public static func percent(_ share: Double) -> Int {
        guard share.isFinite, share > 0 else { return 0 }
        return Int((share * 100).rounded(.toNearestOrAwayFromZero))
    }

    /// `numerator` / `denominator` in tenths, half up; 0 when the denominator is 0.
    public static func tenths(_ numerator: Int, _ denominator: Int) -> Int {
        denominator > 0 ? (20 * numerator + denominator) / (2 * denominator) : 0
    }

    /// "2.4" from 24 tenths.
    public static func decimal(tenths: Int) -> String {
        let value = max(0, tenths)
        return String(value / 10) + "." + String(value % 10)
    }

    /// Milliseconds to whole minutes, half up.
    public static func minutes(ms: Int) -> Int {
        (max(0, ms) + 30_000) / 60_000
    }

    /// `ms` / `count` milliseconds to whole minutes, half up; 0 when `count` is 0.
    public static func minutes(ms: Int, per count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (2 * max(0, ms) + count * 60_000) / (2 * count * 60_000)
    }

    /// 「2 小時 7 分」, or 「45 分鐘」 under an hour.
    public static func minutesZH(_ minutes: Int) -> String {
        let total = max(0, minutes)
        let hours = total / 60, rest = total % 60
        return hours > 0 ? String(hours) + " 小時 " + String(rest) + " 分" : String(rest) + " 分鐘"
    }

    /// "2 h 07 min", or "45 min" under an hour.
    public static func minutesEN(_ minutes: Int) -> String {
        let total = max(0, minutes)
        let hours = total / 60, rest = total % 60
        guard hours > 0 else { return String(rest) + " min" }
        let padded = rest < 10 ? "0" + String(rest) : String(rest)
        return String(hours) + " h " + padded + " min"
    }

    /// §6.2: one decimal under 10 s, whole seconds from 10 s (both half up).
    public static func seconds(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0.0" }
        if value < 10 {
            let tenths = Int((value * 10).rounded(.toNearestOrAwayFromZero))
            return tenths < 100 ? decimal(tenths: tenths) : "10"
        }
        return String(Int(value.rounded(.toNearestOrAwayFromZero)))
    }

    /// "★★" for 2.
    public static func stars(_ count: Int) -> String {
        String(repeating: "★", count: max(0, count))
    }

    /// "★7 ★★2 ★★★1": rounds per star, stars without rounds left out.
    public static func starMix(_ counts: [Int]) -> String {
        var parts: [String] = []
        for (offset, count) in counts.enumerated() where count > 0 {
            parts.append(stars(offset + 1) + String(count))
        }
        return parts.joined(separator: " ")
    }

    public static func rangeLabel(_ top: Int) -> String {
        "1–" + String(top)
    }

    /// The text of one slot value in both languages, with its numbers and verbatim spans.
    static func piece(_ value: WeeklySlotValue) -> WeeklySentence {
        switch value {
        case .int(let number, path: let path), .percent(let number, path: let path):
            let text = String(number)
            return WeeklySentence(zh: text, en: text, traceable: [WeeklyTraceable(path: path, value: text)])
        case .decimal(tenths: let count, path: let path):
            let text = decimal(tenths: count)
            return WeeklySentence(zh: text, en: text, traceable: [WeeklyTraceable(path: path, value: text)])
        case .seconds(let amount, path: let path):
            let text = seconds(amount)
            return WeeklySentence(zh: text, en: text, traceable: [WeeklyTraceable(path: path, value: text)])
        case .minutes(let amount, path: let path):
            let total = max(0, amount)
            var traceable: [WeeklyTraceable] = []
            if total >= 60 { traceable.append(WeeklyTraceable(path: path + "#h", value: String(total / 60))) }
            traceable.append(WeeklyTraceable(path: path + "#m", value: String(total % 60)))
            return WeeklySentence(zh: minutesZH(total), en: minutesEN(total), traceable: traceable)
        case .game(let kind):
            if let known = ActivityKind(rawValue: kind) {
                return WeeklySentence(zh: known.parentCardTitle, en: known.parentCardEnglish)
            }
            return WeeklySentence(zh: kind, en: kind, verbatim: [kind])
        case .tag(let tag):
            guard let name = WeeklyTextCatalog.tagName(tag) else {
                return WeeklySentence(zh: tag, en: tag, verbatim: [tag], problems: ["tag without an approved name: \(tag)"])
            }
            return WeeklySentence(zh: name.zh, en: name.en)
        case .stars(let counts, path: let path):
            var traceable: [WeeklyTraceable] = []
            for (offset, count) in counts.enumerated() where count > 0 {
                traceable.append(WeeklyTraceable(path: path + "[" + String(offset) + "]", value: String(count)))
            }
            let text = starMix(counts)
            return WeeklySentence(zh: text, en: text, traceable: traceable)
        case .day(let index):
            let day = min(max(index, 0), dayNamesZH.count - 1)
            return WeeklySentence(zh: dayNamesZH[day], en: dayNamesEN[day])
        case .range(let top, path: let path):
            let text = rangeLabel(top)
            return WeeklySentence(zh: text, en: text, traceable: [
                WeeklyTraceable(path: "copy.range.start", value: "1"), WeeklyTraceable(path: path, value: String(top))
            ])
        case .words(zh: let zh, en: let en):
            return WeeklySentence(zh: zh, en: en)
        case .text(let sentence):
            return WeeklySentence(zh: sentence.zh, en: sentence.en, traceable: sentence.traceable,
                                  verbatim: sentence.verbatim, problems: sentence.problems)
        case .verbatim(let text):
            return WeeklySentence(zh: text, en: text, verbatim: [text])
        }
    }

    /// Replaces each `{name}` in one pass, so the text of a value is never read as a placeholder.
    /// Names without a value are reported in `missing`.
    static func fill(_ template: String, _ values: [String: String], missing: inout [String]) -> String {
        var out = ""
        var name = ""
        var inName = false
        for character in template {
            if inName {
                if character == "}" {
                    if let value = values[name] {
                        out += value
                    } else {
                        missing.append(name)
                    }
                    name = ""
                    inName = false
                } else {
                    name.append(character)
                }
            } else if character == "{" {
                inName = true
            } else {
                out.append(character)
            }
        }
        if inName { missing.append(name) }
        return out
    }

    /// Placeholder names of a template text, in order.
    public static func placeholders(_ template: String) -> [String] {
        var names: [String] = []
        var name = ""
        var inName = false
        for character in template {
            if inName {
                if character == "}" {
                    names.append(name)
                    name = ""
                    inName = false
                } else {
                    name.append(character)
                }
            } else if character == "{" {
                inName = true
            }
        }
        return names
    }
}
