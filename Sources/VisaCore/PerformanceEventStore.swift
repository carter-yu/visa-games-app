import Foundation

/// Hong Kong time for day buckets, file names and CSV columns (no daylight saving).
public enum PerfClock {
    public static var hongKong: TimeZone {
        TimeZone(identifier: "Asia/Hong_Kong") ?? TimeZone(secondsFromGMT: 8 * 3600)!
    }

    public static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// "2026-10-09" in `timeZone`.
    public static func dayStamp(_ date: Date, timeZone: TimeZone) -> String {
        let parts = calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// "18:02:07" in `timeZone`.
    public static func timeStamp(_ date: Date, timeZone: TimeZone) -> String {
        let parts = calendar(timeZone).dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// Start of the given day stamp in `timeZone`.
    public static func date(fromDayStamp stamp: String, timeZone: TimeZone) -> Date? {
        let pieces = stamp.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        var components = DateComponents()
        components.year = pieces[0]
        components.month = pieces[1]
        components.day = pieces[2]
        return calendar(timeZone).date(from: components)
    }

    /// Day stamp `days` calendar days before `stamp`.
    public static func dayStamp(_ stamp: String, minusDays days: Int, timeZone: TimeZone) -> String? {
        guard let start = date(fromDayStamp: stamp, timeZone: timeZone),
              let shifted = calendar(timeZone).date(byAdding: .day, value: -days, to: start) else { return nil }
        return dayStamp(shifted, timeZone: timeZone)
    }
}

/// `~/Library/Application Support/VisaGames/stats/` — one append-only file per HKT day:
/// `events-YYYY-MM-DD.jsonl`, plus `rollup-v1.json` (daily summaries of pruned days)
/// and `exports/`. Separate from `state.json`; never mirrored into the repo `logs/`.
/// Not thread-safe by itself: the app calls it from one serial queue.
public struct PerfEventStore: Sendable {
    public let directory: URL
    public let timeZone: TimeZone

    public init(directory: URL, timeZone: TimeZone = PerfClock.hongKong) {
        self.directory = directory
        self.timeZone = timeZone
    }

    /// Default location next to `state.json`.
    public static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("VisaGames/stats", isDirectory: true)
    }

    public static let filePrefix = "events-"
    public static let fileSuffix = ".jsonl"

    public var rollupURL: URL { directory.appendingPathComponent("rollup-v1.json") }
    public var exportsDirectory: URL { directory.appendingPathComponent("exports", isDirectory: true) }

    public func fileURL(day: String) -> URL {
        directory.appendingPathComponent("\(Self.filePrefix)\(day)\(Self.fileSuffix)")
    }

    public func day(for event: PerfEvent) -> String {
        PerfClock.dayStamp(event.timestamp, timeZone: timeZone)
    }

    /// Appends whole lines (each ends with "\n") to the HKT-day file of each event.
    public func append(_ events: [PerfEvent], synchronize: Bool = false) throws {
        guard !events.isEmpty else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var byDay: [(String, [String])] = []
        for event in events {
            let line = try PerfCodec.encodeLine(event)
            let day = day(for: event)
            if let index = byDay.firstIndex(where: { $0.0 == day }) {
                byDay[index].1.append(line)
            } else {
                byDay.append((day, [line]))
            }
        }
        for (day, lines) in byDay {
            let url = fileURL(day: day)
            if !fm.fileExists(atPath: url.path) {
                guard fm.createFile(atPath: url.path, contents: nil) else { throw StoreError.cannotCreate }
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
            if synchronize { try handle.synchronize() }
        }
    }

    /// Day stamps of event files, oldest first. Unrelated files are ignored.
    public func eventDays() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name -> String? in
            guard name.hasPrefix(Self.filePrefix), name.hasSuffix(Self.fileSuffix) else { return nil }
            let day = String(name.dropFirst(Self.filePrefix.count).dropLast(Self.fileSuffix.count))
            return PerfClock.date(fromDayStamp: day, timeZone: timeZone) == nil ? nil : day
        }.sorted()
    }

    public struct ReadResult: Sendable, Equatable {
        public var events: [PerfEvent]
        public var skipped: Int
    }

    /// Reads the given days (default all). Torn or newer-schema lines are skipped and counted.
    public func read(days: [String]? = nil) -> ReadResult {
        var events: [PerfEvent] = []
        var skipped = 0
        for day in days ?? eventDays() {
            guard let data = try? Data(contentsOf: fileURL(day: day)) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            let decoded = PerfCodec.decodeLines(text)
            events += decoded.events
            skipped += decoded.skipped
        }
        return ReadResult(events: PerfCodec.ordered(events), skipped: skipped)
    }

    public func loadRollup() -> PerfRollup {
        guard let data = try? Data(contentsOf: rollupURL),
              let rollup = try? JSONDecoder().decode(PerfRollup.self, from: data),
              rollup.rollupSchema == PerfRollup.currentSchema else { return PerfRollup() }
        return rollup
    }

    public func saveRollup(_ rollup: PerfRollup) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(rollup).write(to: rollupURL, options: .atomic)
    }

    /// 「清除表現紀錄」: deletes raw events, summaries and exports. Nothing outside `stats/`.
    public func clear() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        for name in try fm.contentsOfDirectory(atPath: directory.path) {
            try fm.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    public enum StoreError: Error { case cannotCreate }
}

/// Daily summaries kept after raw events expire (decision 2A: raw 90 days).
public struct PerfRollup: Codable, Equatable, Sendable {
    public static let currentSchema = 1

    public var rollupSchema: Int
    /// Days already folded. A listed day whose raw file still exists is deleted without
    /// folding again (crash between the rollup write and the delete).
    public var foldedDays: [String]
    public var days: [String: PerfDaySummary]

    public init(foldedDays: [String] = [], days: [String: PerfDaySummary] = [:]) {
        self.rollupSchema = Self.currentSchema
        self.foldedDays = foldedDays
        self.days = days
    }

    enum CodingKeys: String, CodingKey {
        case rollupSchema = "rollup_schema"
        case foldedDays = "folded_days"
        case days
    }
}

public struct PerfDaySummary: Codable, Equatable, Sendable {
    /// Key "kind|stars", e.g. "findTheSame|2". Countable child rounds only.
    public var games: [String: PerfGameDayStats]
    /// Key video id. Countable child activity only.
    public var videos: [String: PerfVideoDayStats]
    public var uncountedRounds: Int
    public var uncountedPlays: Int

    public init(games: [String: PerfGameDayStats] = [:], videos: [String: PerfVideoDayStats] = [:],
                uncountedRounds: Int = 0, uncountedPlays: Int = 0) {
        self.games = games
        self.videos = videos
        self.uncountedRounds = uncountedRounds
        self.uncountedPlays = uncountedPlays
    }

    enum CodingKeys: String, CodingKey {
        case games, videos
        case uncountedRounds = "uncounted_rounds"
        case uncountedPlays = "uncounted_plays"
    }
}

public struct PerfGameDayStats: Codable, Equatable, Sendable {
    public var deals = 0
    public var answered = 0
    public var firstTry = 0
    public var misses = 0
    public var solved = 0
    public var zeroed = 0
    public var abandoned = 0
    public var hinted = 0
    public var activeMs = 0

    public init() {}

    enum CodingKeys: String, CodingKey {
        case deals, answered, misses, solved, zeroed, abandoned, hinted
        case firstTry = "first_try"
        case activeMs = "active_ms"
    }
}

public struct PerfVideoDayStats: Codable, Equatable, Sendable {
    /// Times the card was fully drawn on a picker page shown to the child.
    public var impressions = 0
    public var picks = 0
    public var plays = 0
    public var completions = 0
    /// Stopped because the visa or the viewing bank ran out.
    public var timeUpCuts = 0
    /// Starts through 繼續睇.
    public var resumedPlays = 0
    public var watchedSeconds: Double = 0

    public init() {}

    enum CodingKeys: String, CodingKey {
        case impressions, picks, plays, completions
        case timeUpCuts = "time_up_cuts"
        case resumedPlays = "resumed_plays"
        case watchedSeconds = "watched_s"
    }
}

public enum PerfSummaries {
    /// Daily summaries for `days` (HKT) from `events`, with `excluded` sessions dropped.
    public static func daySummaries(events: [PerfEvent], days: Set<String>, excluded: Set<String>,
                                    timeZone: TimeZone) -> [String: PerfDaySummary] {
        var result: [String: PerfDaySummary] = [:]
        let ordered = PerfCodec.ordered(events)
        var results: [String: PerfEvent] = [:]
        for event in ordered where event.type == .roundResult {
            if let round = event.string("round") { results[round] = event }
        }
        for event in ordered {
            let day = PerfClock.dayStamp(event.timestamp, timeZone: timeZone)
            guard days.contains(day) else { continue }
            let counted = PerfFilter.countable(event, excludedSessions: excluded)
            var summary = result[day] ?? PerfDaySummary()
            switch event.type {
            case .gameDealt:
                guard counted else {
                    summary.uncountedRounds += 1
                    break
                }
                let key = "\(event.string("kind") ?? "unknown")|\(event.int("stars") ?? 0)"
                var stats = summary.games[key] ?? PerfGameDayStats()
                stats.deals += 1
                if let round = event.string("round"), let outcome = results[round] {
                    let answers = outcome.int("answers") ?? 0
                    if answers > 0 { stats.answered += 1 }
                    if outcome.bool("first_try") == true { stats.firstTry += 1 }
                    stats.misses += outcome.int("misses") ?? 0
                    if outcome.bool("hint_used") == true { stats.hinted += 1 }
                    stats.activeMs += outcome.int("active_ms") ?? 0
                    switch outcome.string("outcome") {
                    case "solved": stats.solved += 1
                    case "zeroed": stats.zeroed += 1
                    default: stats.abandoned += 1
                    }
                } else {
                    stats.abandoned += 1
                }
                summary.games[key] = stats
            case .videoImpressions where counted:
                for id in event["ids"]?.stringArray ?? [] {
                    summary.videos[id, default: PerfVideoDayStats()].impressions += 1
                }
            case .videoPick where counted && event.bool("accepted") == true:
                if let id = event.string("video") { summary.videos[id, default: PerfVideoDayStats()].picks += 1 }
            case .videoStart:
                guard counted else {
                    summary.uncountedPlays += 1
                    break
                }
                if let id = event.string("video") {
                    summary.videos[id, default: PerfVideoDayStats()].plays += 1
                    if event.string("source") == "continue" {
                        summary.videos[id, default: PerfVideoDayStats()].resumedPlays += 1
                    }
                }
            case .videoEnd where counted:
                guard let id = event.string("video") else { break }
                var stats = summary.videos[id] ?? PerfVideoDayStats()
                switch event.string("reason") {
                case PerfVideoStopReason.ended.rawValue: stats.completions += 1
                case PerfVideoStopReason.visaExpired.rawValue, PerfVideoStopReason.budgetExhausted.rawValue:
                    stats.timeUpCuts += 1
                default: break
                }
                stats.watchedSeconds += event.double("watched_s") ?? 0
                summary.videos[id] = stats
            default:
                break
            }
            result[day] = summary
        }
        return result
    }
}

/// Decision 2A: raw events for 90 days, then daily summaries kept until 「清除表現紀錄」.
public enum PerfRetention {
    public static let rawDays = 90

    public struct Outcome: Equatable, Sendable {
        public var folded: [String]
        public var deleted: [String]
    }

    /// Days strictly older than the last `rawDays` HKT calendar days (today included).
    public static func expiredDays(_ days: [String], today: String, rawDays: Int = rawDays,
                                   timeZone: TimeZone) -> [String] {
        guard let firstKept = PerfClock.dayStamp(today, minusDays: rawDays - 1, timeZone: timeZone) else {
            return []
        }
        return days.filter { $0 < firstKept }
    }

    /// Idempotent: write the rollup (atomic) first, then delete the folded raw files.
    @discardableResult
    public static func prune(store: PerfEventStore, now: Date, rawDays: Int = rawDays) throws -> Outcome {
        let today = PerfClock.dayStamp(now, timeZone: store.timeZone)
        let allDays = store.eventDays()
        let expired = expiredDays(allDays, today: today, rawDays: rawDays, timeZone: store.timeZone)
        guard !expired.isEmpty else { return Outcome(folded: [], deleted: []) }
        var rollup = store.loadRollup()
        let toFold = expired.filter { !rollup.foldedDays.contains($0) }
        if !toFold.isEmpty {
            let all = store.read(days: allDays).events
            let excluded = PerfFilter.excludedSessions(in: all)
            let summaries = PerfSummaries.daySummaries(
                events: all, days: Set(toFold), excluded: excluded, timeZone: store.timeZone
            )
            for day in toFold {
                rollup.days[day] = summaries[day] ?? PerfDaySummary()
                rollup.foldedDays.append(day)
            }
            rollup.foldedDays.sort()
            try store.saveRollup(rollup)
        }
        for day in expired {
            try? FileManager.default.removeItem(at: store.fileURL(day: day))
        }
        return Outcome(folded: toFold, deleted: expired)
    }
}
