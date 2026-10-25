import Foundation

// Weekly report W1 (weekly-report design §4.2–4.5, D1): the report week and the static facts
// the weekly metrics read off each round. Pure value code; nothing here reads the host time
// zone, calendar or locale.

/// One report week: Monday 00:00 to Sunday 24:00, Hong Kong time (D1).
/// `cutoff` is `dataUntil` (§4.2): when the report is made, capped at the end of Sunday.
public struct WeeklyWindow: Sendable, Equatable {
    public static let dayCount = 7

    /// Monday 00:00.
    public let start: Date
    /// The next Monday 00:00 (not part of the week).
    public let end: Date
    /// Events after this moment are not seen. Never later than `end`.
    public let cutoff: Date
    /// The start of each day, then `end` (8 values).
    public let dayStarts: [Date]
    /// "2026-10-19" … "2026-10-25".
    public let dayStamps: [String]
    public let timeZone: TimeZone

    public static var hongKong: TimeZone { TimeZone(identifier: "Asia/Hong_Kong")! }

    /// Gregorian, Monday-first, POSIX locale: the same weeks on any Mac.
    public static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }

    /// The week containing `date`, seen up to `dataUntil` (nil = the whole week).
    public init(containing date: Date, dataUntil: Date? = nil, timeZone: TimeZone = WeeklyWindow.hongKong) {
        let calendar = Self.calendar(timeZone)
        let day = calendar.startOfDay(for: date)
        // `.weekday` is 1 = Sunday … 7 = Saturday whatever `firstWeekday` says.
        let sinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -sinceMonday, to: day) ?? day
        var starts: [Date] = []
        for offset in 0...Self.dayCount {
            starts.append(calendar.date(byAdding: .day, value: offset, to: monday)
                          ?? monday.addingTimeInterval(Double(offset) * 86_400))
        }
        let end = starts[Self.dayCount]
        self.start = starts[0]
        self.end = end
        self.cutoff = min(dataUntil ?? end, end)
        self.dayStarts = starts
        self.dayStamps = starts.prefix(Self.dayCount).map { PerfClock.dayStamp($0, timeZone: timeZone) }
        self.timeZone = timeZone
    }

    /// `weekStart` is a "2026-10-19" day stamp; any day of a week selects that week.
    public init?(weekStart stamp: String, dataUntil: Date? = nil, timeZone: TimeZone = WeeklyWindow.hongKong) {
        guard let date = PerfClock.date(fromDayStamp: stamp, timeZone: timeZone) else { return nil }
        self.init(containing: date, dataUntil: dataUntil, timeZone: timeZone)
    }

    /// The whole week `weeks` weeks later (negative = earlier), seen up to its end.
    public func shifted(weeks: Int) -> WeeklyWindow {
        let calendar = Self.calendar(timeZone)
        let monday = calendar.date(byAdding: .day, value: 7 * weeks, to: start)
            ?? start.addingTimeInterval(Double(7 * weeks) * 86_400)
        return WeeklyWindow(containing: monday, timeZone: timeZone)
    }

    public var weekStartStamp: String { dayStamps[0] }
    public var weekEndStamp: String { dayStamps[Self.dayCount - 1] }

    /// 0 = Monday … 6 = Sunday; nil outside the week.
    public func dayIndex(_ date: Date) -> Int? {
        guard date >= start, date < end else { return nil }
        for index in 0..<Self.dayCount where date < dayStarts[index + 1] {
            return index
        }
        return nil
    }

    /// §4.2 `inWindow`: inside the week and not after `cutoff`.
    public func contains(_ date: Date) -> Bool {
        date >= start && date < end && date <= cutoff
    }
}

/// §4.3: quiz rounds have a right answer to guess; practice rounds (tracing, tap to count,
/// guided roads) do not, and never feed a first-try rate.
public enum WeeklyRoundType: String, Sendable, Equatable, Hashable, CaseIterable {
    case quiz
    case practice

    /// Reuses the review's practice-only rule unchanged.
    public static func of(dealt: PerfEvent) -> WeeklyRoundType {
        PerfQuestionGeneration.isPracticeOnly(dealt) ? .practice : .quiz
    }
}

/// §7.2 area map (static; no schema change). Kinds outside the map are shown under `other`.
public enum WeeklyArea: String, Sendable, Equatable, Hashable, CaseIterable {
    case numbers, matching, comparing, pen, letters, other

    public var zh: String {
        switch self {
        case .numbers: return "數字・數量"
        case .matching: return "觀察・配對"
        case .comparing: return "比較・概念"
        case .pen: return "手眼・畫線"
        case .letters: return "字母"
        case .other: return "其他"
        }
    }

    public var en: String {
        switch self {
        case .numbers: return "Numbers & quantity"
        case .matching: return "Looking & matching"
        case .comparing: return "Comparing & concepts"
        case .pen: return "Pen control & tracing"
        case .letters: return "Letters"
        case .other: return "Other"
        }
    }

    public static func of(kind: String) -> WeeklyArea {
        guard let known = ActivityKind(rawValue: kind) else { return .other }
        switch known {
        case .countVehicles, .moreFewer, .tapCountPick, .tapCountPickEnglish, .tapCountAll, .tapCountTrace,
             .tapCountAllEnglish, .tapCountTraceEnglish:
            return .numbers
        case .twoPictureChoose, .findTheSame, .halfMatch, .shadowMatch, .lineMatch:
            return .matching
        case .capacityCompare, .sequenceShortToLong, .shapeCousin, .emptyBay:
            return .comparing
        case .traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree, .lineMatchGuidedStraight,
             .lineMatchGuidedBridge:
            return .pen
        case .tapLetterAll, .tapLetterWrite:
            return .letters
        }
    }
}

/// §4.5 practice families (chart C2b). Each has a "done smoothly" rule (`WeeklySmooth`).
public enum WeeklyPracticeFamily: String, Sendable, Equatable, Hashable, CaseIterable {
    case lines, shapes, roads, tapAll, tapTrace

    /// Practice rounds only. Guided roads dealt as `lineMatch` before v0.24.1 are roads too.
    public static func of(kind: String) -> WeeklyPracticeFamily? {
        guard let known = ActivityKind(rawValue: kind) else { return nil }
        switch known {
        case .traceLines: return .lines
        case .traceShapesDotted, .traceShapesArrows, .traceShapesFree: return .shapes
        case .lineMatchGuidedStraight, .lineMatchGuidedBridge, .lineMatch: return .roads
        case .tapCountAll, .tapCountAllEnglish: return .tapAll
        case .tapCountTrace, .tapCountTraceEnglish: return .tapTrace
        default: return nil
        }
    }
}

/// §4.3: the chance of a first-try right answer by guessing, per quiz round.
public enum WeeklyChance {
    /// 20! still fits in `Int`.
    static let maxPairs = 20

    /// `game_dealt.chance` when written (optional additive field, §10), else rebuilt from the
    /// dealt fields, else the catalog value. Nil for an unknown kind without `chance`.
    public static func chance(dealt: PerfEvent) -> Double? {
        if let written = dealt.double("chance"), written.isFinite, written > 0, written <= 1 { return written }
        guard let kind = dealt.string("kind").flatMap(ActivityKind.init(rawValue:)) else { return nil }
        switch kind {
        case .lineMatch:
            if let pairs = dealt.int("pairs"), pairs >= 1, pairs <= maxPairs {
                return 1.0 / Double((1...pairs).reduce(1, *))
            }
        case .tapCountPick, .tapCountPickEnglish:
            if let cars = dealt.int("cars"), cars >= 1 { return 1.0 / Double(cars) }
        case .countVehicles, .findTheSame:
            let slots = dealt["slots"]?.stringArray ?? []
            if PerfQuestionGeneration.isVariant(dealt), !slots.isEmpty { return 1.0 / Double(slots.count) }
        default:
            break
        }
        return PerfChoiceCatalog.chance(for: kind)
    }
}

/// Reading flags that some boards write as 1 / 0 integers.
public enum WeeklyField {
    public static func flag(_ value: PerfValue?) -> Bool? {
        switch value {
        case .bool(let flag)?: return flag
        case .int(let number)?: return number != 0
        default: return nil
        }
    }
}

/// §4.5 "done smoothly", from fields the boards already write. D9: first thresholds, to be
/// recalibrated after two weeks of real data.
public enum WeeklySmooth {
    public static let maxInkOutsideRatio = 0.25
    public static let maxErasers = 1
    public static let maxRoadOffPath = 1
    public static let maxTraceOffPath = 1

    /// Nil unless the round was solved, the kind has a rule and every field the rule reads
    /// is there (older versions lack some): such rounds stay out of `smoothDefined`.
    public static func evaluate(kind: String, result: PerfEvent) -> Bool? {
        guard result.string("outcome") == "solved", let known = ActivityKind(rawValue: kind) else { return nil }
        switch known {
        case .traceLines, .traceShapesDotted, .traceShapesArrows:
            guard let done = result.int("shapes_done"), let total = result.int("shapes_total"),
                  let wrongStart = result.int("wrong_start"), let reverse = result.int("reverse_direction"),
                  let offPath = result.int("off_path_count") else { return nil }
            return done == total && wrongStart == 0 && reverse == 0 && offPath <= total
        case .traceShapesFree:
            guard let done = result.int("shapes_done"), let total = result.int("shapes_total"),
                  let erasers = result.int("erasers"), let ink = result.double("ink_outside_ratio") else { return nil }
            return done == total && ink <= maxInkOutsideRatio && erasers <= maxErasers
        case .lineMatchGuidedStraight, .lineMatchGuidedBridge, .lineMatch:
            guard let roads = result.int("roads"), let total = result.int("roads_total"),
                  let wrongStart = result.int("wrong_start"), let offPath = result.int("off_path_count") else {
                return nil
            }
            return roads == total && wrongStart == 0 && offPath <= maxRoadOffPath
        case .tapCountAll, .tapCountAllEnglish:
            guard let recount = result.int("recount_attempts") else { return nil }
            return recount == 0
        case .tapCountTrace, .tapCountTraceEnglish:
            guard let recount = result.int("recount_attempts") else { return nil }
            if let clean = WeeklyField.flag(result["guide_clean"]) { return recount == 0 && clean }
            guard let offPath = result.int("trace_off_path_count"), let wrongStart = result.int("trace_wrong_start") else {
                return nil
            }
            return recount == 0 && offPath <= maxTraceOffPath && wrongStart == 0
        default:
            return nil
        }
    }
}
