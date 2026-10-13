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
              var rollup = try? JSONDecoder().decode(PerfRollup.self, from: data),
              rollup.rollupSchema >= 1, rollup.rollupSchema <= PerfRollup.currentSchema else { return PerfRollup() }
        // v0.21: schema 1 files load with the new counters at 0 and are rewritten as 2.
        rollup.rollupSchema = PerfRollup.currentSchema
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
    /// 1 = v0.20; 2 = v0.21 (active-time histogram, impressions by page, picks per slot,
    /// expected picks, picker paging counts). Older files decode with the new counters at 0.
    public static let currentSchema = 2

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
    /// Schema 2: counted picker visits whose deck had ≥ 2 pages, and how many of those
    /// reached page 2 (paging rate, §7.3).
    public var multiPageVisits: Int
    public var pagedVisits: Int

    public init(games: [String: PerfGameDayStats] = [:], videos: [String: PerfVideoDayStats] = [:],
                uncountedRounds: Int = 0, uncountedPlays: Int = 0, multiPageVisits: Int = 0, pagedVisits: Int = 0) {
        self.games = games
        self.videos = videos
        self.uncountedRounds = uncountedRounds
        self.uncountedPlays = uncountedPlays
        self.multiPageVisits = multiPageVisits
        self.pagedVisits = pagedVisits
    }

    enum CodingKeys: String, CodingKey {
        case games, videos
        case uncountedRounds = "uncounted_rounds"
        case uncountedPlays = "uncounted_plays"
        case multiPageVisits = "multi_page_visits"
        case pagedVisits = "paged_visits"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        games = try c.decodeIfPresent([String: PerfGameDayStats].self, forKey: .games) ?? [:]
        videos = try c.decodeIfPresent([String: PerfVideoDayStats].self, forKey: .videos) ?? [:]
        uncountedRounds = try c.decodeIfPresent(Int.self, forKey: .uncountedRounds) ?? 0
        uncountedPlays = try c.decodeIfPresent(Int.self, forKey: .uncountedPlays) ?? 0
        multiPageVisits = try c.decodeIfPresent(Int.self, forKey: .multiPageVisits) ?? 0
        pagedVisits = try c.decodeIfPresent(Int.self, forKey: .pagedVisits) ?? 0
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
    /// Schema 2: solved rounds by active seconds, bins `activeBinUpperSeconds` (+ overflow).
    public var activeHistogram: [Int] = Array(repeating: 0, count: PerfGameDayStats.activeBinUpperSeconds.count + 1)

    /// < 5 s, < 10 s, < 20 s, < 40 s, < 80 s, ≥ 80 s.
    public static let activeBinUpperSeconds: [Double] = [5, 10, 20, 40, 80]

    public static func activeBin(ms: Int) -> Int {
        let seconds = Double(ms) / 1000
        return activeBinUpperSeconds.firstIndex(where: { seconds < $0 }) ?? activeBinUpperSeconds.count
    }

    public init() {}

    enum CodingKeys: String, CodingKey {
        case deals, answered, misses, solved, zeroed, abandoned, hinted
        case firstTry = "first_try"
        case activeMs = "active_ms"
        case activeHistogram = "active_hist"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deals = try c.decodeIfPresent(Int.self, forKey: .deals) ?? 0
        answered = try c.decodeIfPresent(Int.self, forKey: .answered) ?? 0
        firstTry = try c.decodeIfPresent(Int.self, forKey: .firstTry) ?? 0
        misses = try c.decodeIfPresent(Int.self, forKey: .misses) ?? 0
        solved = try c.decodeIfPresent(Int.self, forKey: .solved) ?? 0
        zeroed = try c.decodeIfPresent(Int.self, forKey: .zeroed) ?? 0
        abandoned = try c.decodeIfPresent(Int.self, forKey: .abandoned) ?? 0
        hinted = try c.decodeIfPresent(Int.self, forKey: .hinted) ?? 0
        activeMs = try c.decodeIfPresent(Int.self, forKey: .activeMs) ?? 0
        let bins = Self.activeBinUpperSeconds.count + 1
        let hist = try c.decodeIfPresent([Int].self, forKey: .activeHistogram) ?? []
        activeHistogram = hist.count == bins ? hist : Array(repeating: 0, count: bins)
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
    /// Time-up stops whose saved position was later used through 繼續睇.
    public var timeUpResumedLater = 0
    public var navGuardStops = 0
    /// Plays with no player samples (`telemetry: none`).
    public var noTelemetryPlays = 0
    public var watchedSeconds: Double = 0
    /// Schema 2: impressions by page (index 0–3, last bucket = page 4 or later).
    public var impressionsByPage: [Int] = Array(repeating: 0, count: PerfVideoDayStats.pageBuckets)
    /// Schema 2: accepted picks by 4×2 slot (0–7, row-major).
    public var picksBySlot: [Int] = Array(repeating: 0, count: 8)
    /// Schema 2: expected picks E with π = 1 (§7.3), so labels survive the raw prune.
    public var expectedPicks: Double = 0

    public static let pageBuckets = 4

    public init() {}

    enum CodingKeys: String, CodingKey {
        case impressions, picks, plays, completions
        case timeUpCuts = "time_up_cuts"
        case resumedPlays = "resumed_plays"
        case timeUpResumedLater = "time_up_resumed_later"
        case navGuardStops = "nav_guard_stops"
        case noTelemetryPlays = "no_telemetry_plays"
        case watchedSeconds = "watched_s"
        case impressionsByPage = "impressions_by_page"
        case picksBySlot = "picks_by_slot"
        case expectedPicks = "expected_picks"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        impressions = try c.decodeIfPresent(Int.self, forKey: .impressions) ?? 0
        picks = try c.decodeIfPresent(Int.self, forKey: .picks) ?? 0
        plays = try c.decodeIfPresent(Int.self, forKey: .plays) ?? 0
        completions = try c.decodeIfPresent(Int.self, forKey: .completions) ?? 0
        timeUpCuts = try c.decodeIfPresent(Int.self, forKey: .timeUpCuts) ?? 0
        resumedPlays = try c.decodeIfPresent(Int.self, forKey: .resumedPlays) ?? 0
        timeUpResumedLater = try c.decodeIfPresent(Int.self, forKey: .timeUpResumedLater) ?? 0
        navGuardStops = try c.decodeIfPresent(Int.self, forKey: .navGuardStops) ?? 0
        noTelemetryPlays = try c.decodeIfPresent(Int.self, forKey: .noTelemetryPlays) ?? 0
        watchedSeconds = try c.decodeIfPresent(Double.self, forKey: .watchedSeconds) ?? 0
        let pages = try c.decodeIfPresent([Int].self, forKey: .impressionsByPage) ?? []
        impressionsByPage = pages.count == Self.pageBuckets ? pages : Array(repeating: 0, count: Self.pageBuckets)
        let slots = try c.decodeIfPresent([Int].self, forKey: .picksBySlot) ?? []
        picksBySlot = slots.count == 8 ? slots : Array(repeating: 0, count: 8)
        expectedPicks = try c.decodeIfPresent(Double.self, forKey: .expectedPicks) ?? 0
    }
}

/// 「之後繼續睇」 link for a time-up stop (design §7.1).
public enum PerfResumeLink: String, Sendable, Equatable {
    /// A later child play of the same video started from 繼續睇.
    case yes
    /// The saved position was cleared first (揀片睇, another card, ended, removal, storage reset).
    case no
    /// The position is still saved.
    case pending
    /// No position was saved.
    case notApplicable = "n/a"

    /// `ordered` must be `PerfCodec.ordered`; `endIndex` is the `video_end` line.
    public static func resolve(_ ordered: [PerfEvent], endIndex: Int) -> PerfResumeLink {
        let end = ordered[endIndex]
        guard end.bool("resume_saved") == true, let video = end.string("video") else { return .notApplicable }
        for event in ordered[(endIndex + 1)...] {
            switch event.type {
            case .videoStart where event.actor != .parentPreview && event.string("video") == video
                && event.string("source") != "after_parent":
                return event.string("source") == "continue" ? .yes : .no
            case .resumeCleared where event.string("video") == video:
                return .no
            default:
                continue
            }
        }
        return .pending
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
        // Schema 2 picker state: cards shown per visit (for E with π = 1) and paging.
        var shownInVisit: [String: [String]] = [:]
        var multiPageVisitDay: [String: String] = [:]
        var pagedVisits: Set<String> = []
        for (index, event) in ordered.enumerated() {
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
                    case "solved":
                        stats.solved += 1
                        stats.activeHistogram[PerfGameDayStats.activeBin(ms: outcome.int("active_ms") ?? 0)] += 1
                    case "zeroed": stats.zeroed += 1
                    default: stats.abandoned += 1
                    }
                } else {
                    stats.abandoned += 1
                }
                summary.games[key] = stats
            case .pickerVisit where counted:
                if let visit = event.string("visit"), (event.int("page_count") ?? 1) >= 2, multiPageVisitDay[visit] == nil {
                    multiPageVisitDay[visit] = day
                    summary.multiPageVisits += 1
                }
            case .videoImpressions where counted:
                let page = event.int("page") ?? 0
                let bucket = min(max(page, 0), PerfVideoDayStats.pageBuckets - 1)
                for id in event["ids"]?.stringArray ?? [] {
                    summary.videos[id, default: PerfVideoDayStats()].impressions += 1
                    summary.videos[id, default: PerfVideoDayStats()].impressionsByPage[bucket] += 1
                }
                if let visit = event.string("visit") {
                    shownInVisit[visit, default: []].append(contentsOf: event["ids"]?.stringArray ?? [])
                    if page >= 1, let visitDay = multiPageVisitDay[visit], !pagedVisits.contains(visit) {
                        pagedVisits.insert(visit)
                        if visitDay == day { summary.pagedVisits += 1 } else { result[visitDay]?.pagedVisits += 1 }
                    }
                }
            case .videoPick where counted && event.bool("accepted") == true:
                if let id = event.string("video") {
                    summary.videos[id, default: PerfVideoDayStats()].picks += 1
                    if let slot = event.int("slot"), (0..<8).contains(slot) {
                        summary.videos[id, default: PerfVideoDayStats()].picksBySlot[slot] += 1
                    }
                    if let visit = event.string("visit") {
                        let shown = Array(Set(shownInVisit[visit] ?? []))
                        if !shown.isEmpty {
                            let share = 1.0 / Double(shown.count)
                            for card in shown { summary.videos[card, default: PerfVideoDayStats()].expectedPicks += share }
                        }
                    }
                }
            case .videoStart:
                guard counted else {
                    summary.uncountedPlays += 1
                    break
                }
                // The reload after parent mode continues the same play (design §7.1): not a new play.
                if let id = event.string("video"), event.string("source") != "after_parent" {
                    summary.videos[id, default: PerfVideoDayStats()].plays += 1
                    if event.string("source") == "continue" {
                        summary.videos[id, default: PerfVideoDayStats()].resumedPlays += 1
                    }
                }
            case .videoEnd where counted:
                guard let id = event.string("video") else { break }
                var stats = summary.videos[id] ?? PerfVideoDayStats()
                let reason = event.string("stop_reason").flatMap(PerfVideoStopReason.init(rawValue:))
                if reason == .ended { stats.completions += 1 }
                if reason == .navGuard { stats.navGuardStops += 1 }
                if reason?.isTimeUp == true {
                    stats.timeUpCuts += 1
                    if PerfResumeLink.resolve(ordered, endIndex: index) == .yes { stats.timeUpResumedLater += 1 }
                }
                if event.string("telemetry") == "none" { stats.noTelemetryPlays += 1 }
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

        public init(folded: [String], deleted: [String]) {
            self.folded = folded
            self.deleted = deleted
        }
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
