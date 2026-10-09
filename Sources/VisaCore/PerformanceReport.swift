import Foundation

// Design §3, §7.3–7.4, §8.4 (v0.21.0): the parent 表現 report. Built off-main, once per
// open / 更新, from the raw JSONL plus the daily rollup (rollup days are used only when the
// raw file for that day is gone). Pure value code so it can be unit-tested on Linux.

public enum PerfReportWindow: String, Sendable, Equatable, CaseIterable {
    case days30
    case all

    public static let days = 30

    public var zh: String { self == .days30 ? "近 30 日" : "全部" }
    public var en: String { self == .days30 ? "Last 30 days" : "All" }

    func contains(ageDays: Int) -> Bool {
        self == .all || ageDays < Self.days
    }
}

public struct PerfStarCounts: Sendable, Equatable {
    public var stars: Int
    public var rounds = 0
    public var answered = 0
    public var firstTry = 0
    public var fuelOuts = 0

    public init(stars: Int) { self.stars = stars }
}

public struct PerfGameRow: Sendable, Equatable, Identifiable {
    public var kind: ActivityKind
    public var id: String { kind.rawValue }
    public var chance: Double
    public var label: PerfMastery.Label
    /// All retained answered rounds (decayed evidence; drives the label).
    public var evidence: PerfMastery.Evidence
    public var estimate: PerfMastery.Estimate
    public var roundsMissing: Int
    /// Window counts.
    public var deals = 0
    public var answered = 0
    public var firstTry = 0
    public var solved = 0
    public var zeroed = 0
    public var abandoned = 0
    public var hinted = 0
    public var stars: [PerfStarCounts] = (1...3).map { PerfStarCounts(stars: $0) }
    /// Last 10 rounds, oldest first (raw data only).
    public var dots: [PerfRoundDot] = []
    public var fuelOutFlag: Int?
    public var trend: PerfMastery.Trend?
    public var medianActiveSeconds: Double?
    public var medianFirstTapSeconds: Double?
    public var lastPlayed: Date?
    public var topWrongTag: String?
    public var topWrongTagShare: Double?

    public var firstTryRate: Double? { answered > 0 ? Double(firstTry) / Double(answered) : nil }
    public var hasAnyRounds: Bool { evidence.rounds > 0 || deals > 0 }
}

public struct PerfVideoRow: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var label: PerfVideoAppeal.Label = .notShown
    public var impressions = 0
    public var impressionsFirstPage = 0
    public var impressionsLater = 0
    public var visitsShown = 0
    public var picks = 0
    public var expected: Double = 0
    public var plays = 0
    public var continues = 0
    public var completions = 0
    public var timeUpStops = 0
    public var timeUpResumedLater = 0
    public var navGuardStops = 0
    public var parentStops = 0
    public var noTelemetryPlays = 0
    public var resumesOffered = 0
    public var resumesUsed = 0
    public var watchedSeconds: Double = 0
    public var lastPicked: Date?
    public var firstSeen: Date?

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    public var appeal: Double { PerfVideoAppeal.appeal(observed: picks, expected: expected) }
    public var watchedMinutes: Int { Int((watchedSeconds / 60).rounded()) }
}

public struct PerfReportSession: Sendable, Equatable, Identifiable {
    public var id: String
    public var start: Date
    public var end: Date
    public var rounds: Int
    public var plays: Int
    /// Any UAT / test-visa activity (already not counted).
    public var tested: Bool
    public var excluded: Bool
}

public struct PerfReport: Sendable, Equatable {
    public var builtAt: Date
    public var window: PerfReportWindow
    public var eventCount: Int
    public var pooledPrior: Double
    public var games: [PerfGameRow]
    public var videos: [PerfVideoRow]
    /// Counted picker visits whose deck had ≥ 2 pages, and how many reached page 2.
    public var multiPageVisits: Int
    public var pagedVisits: Int
    /// Accepted picks per 4×2 slot (window).
    public var slotPicks: [Int]
    public var noTelemetryPlays: Int
    public var navGuardStops: Int
    public var sessions: [PerfReportSession]

    public var pagingRate: Double? {
        multiPageVisits > 0 ? Double(pagedVisits) / Double(multiPageVisits) : nil
    }

    /// Pick share per slot, summing to 1 (nil before any pick).
    public var slotShares: [Double]? {
        let total = slotPicks.reduce(0, +)
        guard total > 0 else { return nil }
        return slotPicks.map { Double($0) / Double(total) }
    }

    /// Nothing countable at all → the 未有紀錄 empty state.
    public var isEmpty: Bool {
        !games.contains(where: \.hasAnyRounds) && !videos.contains(where: { $0.impressions > 0 || $0.plays > 0 })
    }

    /// 一眼睇: up to 3 熟手 and 3 要多練 (sorted rows), plus the fuel flags.
    public var glanceConfident: [PerfGameRow] { Array(games.filter { $0.label == .confident }.prefix(3)) }
    public var glancePractise: [PerfGameRow] { Array(games.filter { $0.label == .practise }.prefix(3)) }
    public var glanceFavourites: [PerfVideoRow] { Array(videos.filter { $0.label == .favourite }.prefix(3)) }
}

public enum PerfReportBuilder {
    public static let dotCount = 10
    public static let sessionDays = 7
    public static let sessionLimit = 5

    /// `videos` is the allowlist (id, parent label) in display order.
    public static func build(events: [PerfEvent], rollup: PerfRollup, videos: [(id: String, title: String)],
                             now: Date, window: PerfReportWindow,
                             timeZone: TimeZone = PerfClock.hongKong) -> PerfReport {
        let ordered = PerfCodec.ordered(events)
        let excluded = PerfFilter.excludedSessions(in: ordered)
        let clock = DayClock(timeZone: timeZone, now: now)

        var rawDays: Set<Int> = []
        for event in ordered { rawDays.insert(clock.day(event.timestamp)) }

        let games = gameRows(ordered: ordered, excluded: excluded, rollup: rollup, rawDays: rawDays,
                             clock: clock, window: window)
        var video = videoRows(ordered: ordered, excluded: excluded, rollup: rollup, rawDays: rawDays,
                              clock: clock, window: window, videos: videos)
        video.sessions = sessions(ordered: ordered, excluded: excluded, clock: clock)
        return PerfReport(
            builtAt: now, window: window, eventCount: events.count, pooledPrior: games.pooled,
            games: games.rows, videos: video.rows, multiPageVisits: video.multiPage, pagedVisits: video.paged,
            slotPicks: video.slotPicks, noTelemetryPlays: video.noTelemetry, navGuardStops: video.navGuard,
            sessions: video.sessions
        )
    }

    // MARK: Day arithmetic (HKT has no DST; offsets are taken per instant anyway)

    struct DayClock {
        let timeZone: TimeZone
        let today: Int

        init(timeZone: TimeZone, now: Date) {
            self.timeZone = timeZone
            self.today = Self.dayIndex(now, timeZone)
        }

        static func dayIndex(_ date: Date, _ timeZone: TimeZone) -> Int {
            let local = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
            return Int((local / 86_400).rounded(.down))
        }

        func day(_ date: Date) -> Int { Self.dayIndex(date, timeZone) }
        func age(_ date: Date) -> Int { max(0, today - day(date)) }

        func day(stamp: String) -> Int? {
            guard let date = PerfClock.date(fromDayStamp: stamp, timeZone: timeZone) else { return nil }
            return day(date.addingTimeInterval(12 * 3600))
        }
    }

    // MARK: Games

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    static func gameRows(ordered: [PerfEvent], excluded: Set<String>, rollup: PerfRollup, rawDays: Set<Int>,
                         clock: DayClock, window: PerfReportWindow) -> (rows: [PerfGameRow], pooled: Double) {
        struct Acc {
            var evidence = PerfMastery.Evidence()
            var deals = 0, answered = 0, firstTry = 0, solved = 0, zeroed = 0, abandoned = 0, hinted = 0
            var stars = (1...3).map { PerfStarCounts(stars: $0) }
            var dots: [PerfRoundDot] = []
            var trend: [(ageDays: Int, firstTry: Bool)] = []
            var active: [Double] = []
            var firstTap: [Double] = []
            var lastPlayed: Date?
            var wrongTags: [String: Int] = [:]
            var wrongAttempts = 0
        }
        var acc: [ActivityKind: Acc] = [:]
        var results: [String: PerfEvent] = [:]
        for event in ordered where event.type == .roundResult {
            if let round = event.string("round") { results[round] = event }
        }
        var roundKind: [String: ActivityKind] = [:]

        for event in ordered {
            switch event.type {
            case .gameDealt:
                guard PerfFilter.countable(event, excludedSessions: excluded),
                      let kind = event.string("kind").flatMap(ActivityKind.init(rawValue:)) else { continue }
                let round = event.string("round") ?? ""
                roundKind[round] = kind
                let age = clock.age(event.timestamp)
                let result = results[round]
                let answered = (result?.int("answers") ?? 0) > 0
                let firstTry = result?.bool("first_try") == true
                let outcome = result?.string("outcome")
                let dot: PerfRoundDot = {
                    switch outcome {
                    case "solved": return firstTry ? .firstTry : .retried
                    case "zeroed": return .fuelOut
                    default: return .unfinished
                    }
                }()
                var a = acc[kind] ?? Acc()
                if answered {
                    a.evidence.add(ageDays: Double(age), firstTry: firstTry)
                    a.trend.append((age, firstTry))
                }
                a.dots.append(dot)
                if a.dots.count > dotCount { a.dots.removeFirst(a.dots.count - dotCount) }
                a.lastPlayed = max(a.lastPlayed ?? event.timestamp, event.timestamp)
                if window.contains(ageDays: age) {
                    a.deals += 1
                    let star = min(max(event.int("stars") ?? 1, 1), 3) - 1
                    a.stars[star].rounds += 1
                    if answered {
                        a.answered += 1
                        a.stars[star].answered += 1
                    }
                    if firstTry && answered {
                        a.firstTry += 1
                        a.stars[star].firstTry += 1
                    }
                    switch outcome {
                    case "solved":
                        a.solved += 1
                        if let ms = result?.int("active_ms") { a.active.append(Double(ms) / 1000) }
                    case "zeroed":
                        a.zeroed += 1
                        a.stars[star].fuelOuts += 1
                    case "abandoned": a.abandoned += 1
                    default: break
                    }
                    if result?.bool("hint_used") == true { a.hinted += 1 }
                    if let ms = result?.int("first_tap_ms") { a.firstTap.append(Double(ms) / 1000) }
                }
                acc[kind] = a
            case .answerAttempt:
                guard event.bool("correct") == false,
                      PerfFilter.countable(event, excludedSessions: excluded),
                      let kind = event.string("round").flatMap({ roundKind[$0] }),
                      window.contains(ageDays: clock.age(event.timestamp)) else { continue }
                acc[kind, default: Acc()].wrongAttempts += 1
                for tag in event["tags"]?.stringArray ?? [] {
                    acc[kind, default: Acc()].wrongTags[tag, default: 0] += 1
                }
            default:
                continue
            }
        }

        // Pruned days come from the rollup (counts only; no dots, timings or tags).
        for (stamp, summary) in rollup.days {
            guard let day = clock.day(stamp: stamp), !rawDays.contains(day) else { continue }
            let age = max(0, clock.today - day)
            for (key, stats) in summary.games {
                let parts = key.split(separator: "|")
                guard let first = parts.first, let kind = ActivityKind(rawValue: String(first)) else { continue }
                let star = min(max(parts.count > 1 ? Int(parts[1]) ?? 1 : 1, 1), 3) - 1
                var a = acc[kind] ?? Acc()
                a.evidence.add(ageDays: Double(age), firstTry: true, count: stats.firstTry)
                a.evidence.add(ageDays: Double(age), firstTry: false, count: max(0, stats.answered - stats.firstTry))
                for _ in 0..<min(stats.firstTry, 50) where age < 14 { a.trend.append((age, true)) }
                for _ in 0..<min(max(0, stats.answered - stats.firstTry), 50) where age < 14 { a.trend.append((age, false)) }
                if window.contains(ageDays: age) {
                    a.deals += stats.deals
                    a.answered += stats.answered
                    a.firstTry += stats.firstTry
                    a.solved += stats.solved
                    a.zeroed += stats.zeroed
                    a.abandoned += stats.abandoned
                    a.hinted += stats.hinted
                    a.stars[star].rounds += stats.deals
                    a.stars[star].answered += stats.answered
                    a.stars[star].firstTry += stats.firstTry
                    a.stars[star].fuelOuts += stats.zeroed
                }
                acc[kind] = a
            }
        }

        let kinds = ActivityCatalog.playableKinds
        let pooled = PerfMastery.pooledPrior(kinds.map { kind in
            (chance: PerfChoiceCatalog.chance(for: kind), evidence: acc[kind]?.evidence ?? PerfMastery.Evidence())
        })
        var rows: [PerfGameRow] = kinds.map { kind in
            let a = acc[kind] ?? Acc()
            let chance = PerfChoiceCatalog.chance(for: kind)
            let estimate = PerfMastery.estimate(chance: chance, pooled: pooled, evidence: a.evidence)
            let fuelOutsInLastFive = a.dots.suffix(5).filter { $0 == .fuelOut }.count
            let label = PerfMastery.label(evidence: a.evidence, estimate: estimate, fuelOutsInLastFive: fuelOutsInLastFive)
            var row = PerfGameRow(kind: kind, chance: chance, label: label, evidence: a.evidence, estimate: estimate,
                                  roundsMissing: PerfMastery.roundsMissing(a.evidence))
            row.deals = a.deals
            row.answered = a.answered
            row.firstTry = a.firstTry
            row.solved = a.solved
            row.zeroed = a.zeroed
            row.abandoned = a.abandoned
            row.hinted = a.hinted
            row.stars = a.stars
            row.dots = a.dots
            row.fuelOutFlag = PerfMastery.fuelOutFlag(lastOutcomes: a.dots)
            row.trend = PerfMastery.trend(a.trend)
            row.medianActiveSeconds = median(a.active)
            row.medianFirstTapSeconds = median(a.firstTap)
            row.lastPlayed = a.lastPlayed
            if let top = a.wrongTags.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }), a.wrongAttempts > 0 {
                row.topWrongTag = top.key
                row.topWrongTagShare = Double(top.value) / Double(a.wrongAttempts)
            }
            return row
        }
        rows.sort { lhs, rhs in
            if lhs.label.sortRank != rhs.label.sortRank { return lhs.label.sortRank < rhs.label.sortRank }
            if lhs.label == .insufficient {
                if lhs.evidence.rounds != rhs.evidence.rounds { return lhs.evidence.rounds > rhs.evidence.rounds }
            } else if lhs.estimate.mastery != rhs.estimate.mastery {
                return lhs.estimate.mastery < rhs.estimate.mastery
            }
            return kinds.firstIndex(of: lhs.kind) ?? 0 < kinds.firstIndex(of: rhs.kind) ?? 0
        }
        return (rows, pooled)
    }

    // MARK: Videos

    struct VideoResult {
        var rows: [PerfVideoRow]
        var multiPage = 0
        var paged = 0
        var slotPicks = Array(repeating: 0, count: 8)
        var noTelemetry = 0
        var navGuard = 0
        var sessions: [PerfReportSession] = []
    }

    static func videoRows(ordered: [PerfEvent], excluded: Set<String>, rollup: PerfRollup, rawDays: Set<Int>,
                          clock: DayClock, window: PerfReportWindow,
                          videos: [(id: String, title: String)]) -> VideoResult {
        // Pass 1: slot model over every counted raw picker event in the window (§7.3).
        var model = PerfVideoAppeal.SlotModel()
        for event in ordered where (event.type == .videoImpressions || event.type == .videoPick)
            && PerfFilter.countable(event, excludedSessions: excluded)
            && window.contains(ageDays: clock.age(event.timestamp)) {
            let page = event.int("page") ?? 0
            if event.type == .videoImpressions {
                for slot in (event["ids"]?.stringArray ?? []).indices {
                    model.impressions[PerfVideoAppeal.Cell(page: page, slot: slot), default: 0] += 1
                }
            } else if event.bool("accepted") == true, let slot = event.int("slot") {
                model.picks[PerfVideoAppeal.Cell(page: page, slot: slot), default: 0] += 1
            }
        }

        var rows: [String: PerfVideoRow] = [:]
        for video in videos { rows[video.id] = PerfVideoRow(id: video.id, title: video.title) }
        var result = VideoResult(rows: [])
        var shown: [String: [(video: String, cell: PerfVideoAppeal.Cell)]] = [:]
        var shownVisits: [String: Set<String>] = [:]
        var multiPageVisits: Set<String> = []
        var pagedVisits: Set<String> = []
        // Time-up stops with a saved resume point, waiting for the next start of that video.
        var pendingTimeUp: [String: Bool] = [:]

        func row(_ id: String) -> PerfVideoRow? { rows[id] }

        for event in ordered {
            let counted = PerfFilter.countable(event, excludedSessions: excluded)
            // Resume linkage looks at every non-preview start, like PerfResumeLink.
            if event.type == .videoStart, event.actor != .parentPreview,
               event.string("source") != "after_parent", let id = event.string("video"),
               let wasCounted = pendingTimeUp.removeValue(forKey: id) {
                if wasCounted && event.string("source") == "continue" { rows[id]?.timeUpResumedLater += 1 }
            }
            if event.type == .resumeCleared, let id = event.string("video") { pendingTimeUp[id] = nil }
            guard counted else { continue }
            let inWindow = window.contains(ageDays: clock.age(event.timestamp))
            switch event.type {
            case .pickerVisit:
                guard inWindow, let visit = event.string("visit") else { continue }
                if (event.int("page_count") ?? 1) >= 2 { multiPageVisits.insert(visit) }
            case .videoImpressions:
                guard inWindow, let visit = event.string("visit") else { continue }
                let page = event.int("page") ?? 0
                if page >= 1, multiPageVisits.contains(visit) { pagedVisits.insert(visit) }
                for (slot, id) in (event["ids"]?.stringArray ?? []).enumerated() {
                    shown[visit, default: []].append((id, PerfVideoAppeal.Cell(page: page, slot: slot)))
                    guard var r = row(id) else { continue }
                    r.impressions += 1
                    if page == 0 { r.impressionsFirstPage += 1 } else { r.impressionsLater += 1 }
                    if shownVisits[id, default: []].insert(visit).inserted { r.visitsShown += 1 }
                    if r.firstSeen == nil { r.firstSeen = event.timestamp }
                    rows[id] = r
                }
            case .videoPick:
                guard inWindow, event.bool("accepted") == true, let id = event.string("video") else { continue }
                if let slot = event.int("slot"), (0..<8).contains(slot) { result.slotPicks[slot] += 1 }
                if let visit = event.string("visit") {
                    let shares = PerfVideoAppeal.expectedShares(shown: shown[visit] ?? [], model: model)
                    for (card, share) in shares { rows[card]?.expected += share }
                }
                rows[id]?.picks += 1
                rows[id]?.lastPicked = event.timestamp
            case .videoStart:
                guard inWindow, let id = event.string("video") else { continue }
                let source = event.string("source")
                guard source != "after_parent" else { continue }
                rows[id]?.plays += 1
                if source == "continue" { rows[id]?.continues += 1 }
            case .videoEnd:
                guard let id = event.string("video") else { continue }
                let reason = PerfVideoStopReason(rawValue: event.string("stop_reason") ?? "") ?? .unknown
                if reason.isTimeUp, event.bool("resume_saved") == true, inWindow {
                    pendingTimeUp[id] = true
                }
                guard inWindow else { continue }
                if reason == .ended { rows[id]?.completions += 1 }
                if reason.isTimeUp { rows[id]?.timeUpStops += 1 }
                if reason == .navGuard {
                    rows[id]?.navGuardStops += 1
                    result.navGuard += 1
                }
                if reason == .parentUnlock { rows[id]?.parentStops += 1 }
                if event.string("telemetry") == "none" {
                    rows[id]?.noTelemetryPlays += 1
                    result.noTelemetry += 1
                }
                rows[id]?.watchedSeconds += event.double("watched_s") ?? 0
            case .resumeOffered:
                if inWindow, let id = event.string("video") { rows[id]?.resumesOffered += 1 }
            case .resumeUsed:
                if inWindow, event.string("choice") == "continue", let id = event.string("video") {
                    rows[id]?.resumesUsed += 1
                }
            default:
                continue
            }
        }
        result.multiPage = multiPageVisits.count
        result.paged = pagedVisits.count

        for (stamp, summary) in rollup.days {
            guard let day = clock.day(stamp: stamp), !rawDays.contains(day),
                  window.contains(ageDays: max(0, clock.today - day)) else { continue }
            result.multiPage += summary.multiPageVisits
            result.paged += summary.pagedVisits
            for (id, stats) in summary.videos {
                for (slot, n) in stats.picksBySlot.enumerated() where slot < 8 { result.slotPicks[slot] += n }
                result.navGuard += stats.navGuardStops
                result.noTelemetry += stats.noTelemetryPlays
                guard var r = rows[id] else { continue }
                r.impressions += stats.impressions
                let first = stats.impressionsByPage.first ?? 0
                if stats.impressionsByPage.reduce(0, +) == stats.impressions {
                    r.impressionsFirstPage += first
                    r.impressionsLater += stats.impressions - first
                } else {
                    r.impressionsFirstPage += stats.impressions
                }
                r.picks += stats.picks
                r.expected += stats.expectedPicks
                r.plays += stats.plays
                r.continues += stats.resumedPlays
                r.completions += stats.completions
                r.timeUpStops += stats.timeUpCuts
                r.timeUpResumedLater += stats.timeUpResumedLater
                r.navGuardStops += stats.navGuardStops
                r.noTelemetryPlays += stats.noTelemetryPlays
                r.watchedSeconds += stats.watchedSeconds
                rows[id] = r
            }
        }

        var list: [PerfVideoRow] = videos.compactMap { rows[$0.id] }
        for index in list.indices {
            list[index].label = PerfVideoAppeal.label(impressions: list[index].impressions,
                                                      observed: list[index].picks, expected: list[index].expected)
        }
        let order = Dictionary(videos.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        list.sort { lhs, rhs in
            let lNot = lhs.label == .notShown, rNot = rhs.label == .notShown
            if lNot != rNot { return rNot }
            if !lNot, abs(lhs.appeal - rhs.appeal) > 1e-12 { return lhs.appeal > rhs.appeal }
            return order[lhs.id] ?? 0 < order[rhs.id] ?? 0
        }
        result.rows = list
        return result
    }

    // MARK: Sessions (最近玩過)

    static func sessions(ordered: [PerfEvent], excluded: Set<String>, clock: DayClock) -> [PerfReportSession] {
        let childSide: Set<PerfActor> = [.child, .parentUAT, .parentTestVisa]
        var map: [String: PerfReportSession] = [:]
        for event in ordered where childSide.contains(event.actor) && !event.session.isEmpty {
            guard clock.today - clock.day(event.timestamp) < sessionDays else { continue }
            var s = map[event.session] ?? PerfReportSession(
                id: event.session, start: event.timestamp, end: event.timestamp, rounds: 0, plays: 0,
                tested: false, excluded: excluded.contains(event.session))
            s.start = min(s.start, event.timestamp)
            s.end = max(s.end, event.timestamp)
            if event.actor != .child { s.tested = true }
            if event.type == .gameDealt { s.rounds += 1 }
            if event.type == .videoStart, event.string("source") != "after_parent" { s.plays += 1 }
            map[event.session] = s
        }
        return Array(map.values.filter { $0.rounds + $0.plays > 0 }
            .sorted { $0.start > $1.start }.prefix(sessionLimit))
    }
}
