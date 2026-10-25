import Foundation

// Weekly report W1 (weekly-report design §4.1–4.9, §9.6): the round index (game_dealt ⨝
// round_result) and the per-week metrics the later slices rank, word and draw. Pure and
// deterministic: the same events, rollup and window always give the same model.

/// Round, star or day counts (§4.4 quiz, §4.5 practice).
public struct WeeklyCounts: Sendable, Equatable {
    public var rounds = 0
    /// Quiz: rounds with `answers > 0`, and of those right first time.
    public var answered = 0
    public var firstTry = 0
    /// Practice: solved rounds, those with a defined smooth result, and the smooth ones.
    public var finished = 0
    public var smoothDefined = 0
    public var smooth = 0

    public init() {}

    mutating func add(_ round: WeeklyRound) {
        rounds += 1
        switch round.type {
        case .quiz:
            if round.answered { answered += 1 }
            if round.firstTry { firstTry += 1 }
        case .practice:
            if round.outcome == .solved { finished += 1 }
            if let isSmooth = round.smooth {
                smoothDefined += 1
                if isSmooth { smooth += 1 }
            }
        }
    }
}

/// One counted round: a countable `game_dealt` in the window joined with its last
/// `round_result` seen by the cut-off (§4.1, §4.2).
public struct WeeklyRound: Sendable, Equatable {
    public enum Outcome: String, Sendable, Equatable {
        case solved, zeroed, abandoned
        /// The app moved on without writing a result (power cut, crash): unfinished.
        case noResult = "no_result"
    }

    public var round: String
    public var kind: String
    public var type: WeeklyRoundType
    public var dealtAt: Date
    /// 0 = Monday … 6 = Sunday, by the deal time.
    public var day: Int
    public var session: String
    /// 1…3.
    public var stars: Int
    public var outcome: Outcome
    /// Quiz only: `answers > 0`.
    public var answered: Bool
    /// Quiz only: answered and `first_try == true`.
    public var firstTry: Bool
    /// Quiz only (§4.3). Nil: unknown kind without `game_dealt.chance`.
    public var chance: Double?
    public var misses: Int
    /// Quiz only: answered with `hint_used` or `assisted`.
    public var helped: Bool
    public var activeMs: Int?
    /// `total_ms` capped at 10 minutes (§4.6); 0 without a result.
    public var gameMs: Int
    /// `earned_min` of a solved round, else 0.
    public var earnedMinutes: Int
    /// Practice only, solved: the §4.5 rule; nil when undefined.
    public var smooth: Bool?
    /// Practice only, solved: `guide_helps` when written.
    public var guideHelps: Int?
}

/// §4.4 / §4.5 per game kind. A kind dealt both ways (guided roads under `lineMatch` before
/// v0.24.1) gets one row per type, so quiz and practice never mix.
public struct WeeklyKindMetrics: Sendable, Equatable {
    public var kind: String
    public var type: WeeklyRoundType
    public var area: WeeklyArea
    /// Practice rows only.
    public var family: WeeklyPracticeFamily?
    /// §4.9: first countable round ever (raw days and rollup) falls in this window.
    public var isNew = false
    public var rounds = 0
    public var solved = 0
    public var zeroed = 0
    /// `abandoned` results plus rounds without a result.
    public var unfinished = 0
    public var noResult = 0
    public var daysPlayed = 0
    /// ★, ★★, ★★★.
    public var stars: [WeeklyCounts] = Array(repeating: WeeklyCounts(), count: 3)
    /// Monday … Sunday.
    public var cells: [WeeklyCounts] = Array(repeating: WeeklyCounts(), count: WeeklyWindow.dayCount)
    public var answered = 0
    public var firstTry = 0
    /// False when an answered round has no chance (unknown kind): raw first-try only.
    public var chanceKnown = true
    public var misses = 0
    public var helped = 0
    public var medianActiveSeconds: Double?
    public var wrongAttempts = 0
    public var fastWrong = 0
    /// Shown only with ≥ 3 wrong attempts and a share ≥ 50 % (§4.4).
    public var topWrongTag: String?
    public var topWrongTagCount = 0
    public var smoothDefined = 0
    public var smooth = 0
    public var guideHelpsTotal = 0
    public var guideHelpsRounds = 0
    /// This week only, every round weight 1 (§4.4 / §4.5). Nil without evidence or chance.
    public var estimate: PerfMastery.Estimate?

    var expectedSum = 0.0
    var activeSeconds: [Double] = []
    var tagCounts: [String: Int] = [:]

    init(kind: String, type: WeeklyRoundType) {
        self.kind = kind
        self.type = type
        self.area = WeeklyArea.of(kind: kind)
        self.family = type == .practice ? WeeklyPracticeFamily.of(kind: kind) : nil
    }

    /// Σ chance over answered rounds (E).
    public var expected: Double? { type == .quiz && chanceKnown ? expectedSum : nil }

    public var chanceMean: Double? {
        guard type == .quiz, answered > 0, let expected else { return nil }
        return expected / Double(answered)
    }

    /// clamp((firstTry − E) / (answered − E), 0, 1).
    public var adjusted: Double? {
        type == .quiz ? WeeklyMetricsBuilder.adjusted(firstTry: firstTry, answered: answered, expected: expected) : nil
    }

    /// Quiz: right first time / answered. Practice: smooth / smoothDefined.
    public var rate: Double? {
        switch type {
        case .quiz: return WeeklyMetricsBuilder.ratio(firstTry, answered)
        case .practice: return WeeklyMetricsBuilder.ratio(smooth, smoothDefined)
        }
    }

    public var missesPerRound: Double? { WeeklyMetricsBuilder.ratio(misses, answered) }
    public var helpRate: Double? { WeeklyMetricsBuilder.ratio(helped, answered) }
    public var fastWrongShare: Double? { WeeklyMetricsBuilder.ratio(fastWrong, wrongAttempts) }
    public var guideHelpsMean: Double? { WeeklyMetricsBuilder.ratio(guideHelpsTotal, guideHelpsRounds) }

    /// §4.5: mean `guide_helps` ≥ 2.
    public var helpHeavy: Bool {
        guideHelpsRounds > 0 && guideHelpsTotal >= WeeklyMetricsBuilder.helpHeavyMeanHelps * guideHelpsRounds
    }

    /// Unweighted week evidence: first tries (quiz) or smooth rounds (practice).
    public var evidence: PerfMastery.Evidence {
        switch type {
        case .quiz:
            return PerfMastery.Evidence(rounds: answered, success: Double(firstTry), failure: Double(answered - firstTry))
        case .practice:
            return PerfMastery.Evidence(rounds: smoothDefined, success: Double(smooth),
                                        failure: Double(smoothDefined - smooth))
        }
    }

    mutating func add(_ round: WeeklyRound) {
        rounds += 1
        stars[round.stars - 1].add(round)
        cells[round.day].add(round)
        switch round.outcome {
        case .solved: solved += 1
        case .zeroed: zeroed += 1
        case .abandoned: unfinished += 1
        case .noResult:
            unfinished += 1
            noResult += 1
        }
        switch type {
        case .quiz:
            if round.answered {
                answered += 1
                if round.firstTry { firstTry += 1 }
                if round.helped { helped += 1 }
                if let chance = round.chance { expectedSum += chance } else { chanceKnown = false }
            }
            misses += round.misses
            if round.outcome == .solved, let ms = round.activeMs { activeSeconds.append(Double(ms) / 1000) }
        case .practice:
            if let isSmooth = round.smooth {
                smoothDefined += 1
                if isSmooth { smooth += 1 }
            }
            if let helps = round.guideHelps {
                guideHelpsTotal += helps
                guideHelpsRounds += 1
            }
        }
    }

    mutating func addWrong(_ attempt: PerfEvent) {
        wrongAttempts += 1
        if attempt.bool("fast") == true { fastWrong += 1 }
        for tag in attempt["tags"]?.stringArray ?? [] { tagCounts[tag, default: 0] += 1 }
    }

    mutating func finish() {
        medianActiveSeconds = PerfReportBuilder.median(activeSeconds)
        daysPlayed = cells.filter { $0.rounds > 0 }.count
        // Most common tag; ties go to the first in UTF-8 order.
        let top = tagCounts.min { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key.utf8.lexicographicallyPrecedes(rhs.key.utf8)
        }
        if let top, wrongAttempts >= WeeklyMetricsBuilder.topTagMinimumWrongs, 2 * top.value >= wrongAttempts {
            topWrongTag = top.key
            topWrongTagCount = top.value
        }
    }
}

/// One day of the window (§4.6, §4.7).
public struct WeeklyDayMetrics: Sendable, Equatable {
    public var index: Int
    public var date: String
    /// Rounds, quiz answered / first try, practice finished / smooth.
    public var counts = WeeklyCounts()
    public var quizRounds = 0
    public var practiceRounds = 0
    /// Σ capped `total_ms`.
    public var quizMs = 0
    public var practiceMs = 0
    /// Σ `video_end.watched_s` (ms), plus the last `video_progress` of a play without an end.
    public var videoMs = 0
    /// A play had no `video_end` (「約」).
    public var videoEstimated = false
    /// Countable `video_start` except `after_parent` reloads.
    public var plays = 0
    public var visaMinutes = 0
    /// Distinct sessions of counted rounds and plays.
    public var sessions: Set<String> = []
    /// Kinds whose first-ever round is on this day.
    public var newKinds: [String] = []

    init(index: Int, date: String) {
        self.index = index
        self.date = date
    }

    public var rounds: Int { counts.rounds }
    public var gameMs: Int { quizMs + practiceMs }
    public var played: Bool { counts.rounds > 0 || plays > 0 }

    mutating func add(_ round: WeeklyRound) {
        counts.add(round)
        switch round.type {
        case .quiz:
            quizRounds += 1
            quizMs += round.gameMs
        case .practice:
            practiceRounds += 1
            practiceMs += round.gameMs
        }
        visaMinutes += round.earnedMinutes
        if !round.session.isEmpty { sessions.insert(round.session) }
    }
}

/// Sums over kind rows: an area, a practice family, a whole window (§4.8).
public struct WeeklyGroupMetrics: Sendable, Equatable {
    public var rounds = 0
    public var quizRounds = 0
    public var practiceRounds = 0
    public var answered = 0
    public var firstTry = 0
    /// Σ E over quiz rows whose chance is known, with their answered and first-try counts.
    public var expected = 0.0
    public var expectedAnswered = 0
    public var expectedFirstTry = 0
    public var finished = 0
    public var smoothDefined = 0
    public var smooth = 0

    public init() {}

    public var quizRate: Double? { WeeklyMetricsBuilder.ratio(firstTry, answered) }
    /// "Lucky guesses ~E%" (§4.8).
    public var chanceMean: Double? { expectedAnswered > 0 ? expected / Double(expectedAnswered) : nil }
    public var adjusted: Double? {
        WeeklyMetricsBuilder.adjusted(firstTry: expectedFirstTry, answered: expectedAnswered, expected: expected)
    }
    public var practiceRate: Double? { WeeklyMetricsBuilder.ratio(smooth, smoothDefined) }

    mutating func add(_ row: WeeklyKindMetrics) {
        rounds += row.rounds
        switch row.type {
        case .quiz:
            quizRounds += row.rounds
            answered += row.answered
            firstTry += row.firstTry
            if let rowExpected = row.expected {
                expected += rowExpected
                expectedAnswered += row.answered
                expectedFirstTry += row.firstTry
            }
        case .practice:
            practiceRounds += row.rounds
            finished += row.solved
            smoothDefined += row.smoothDefined
            smooth += row.smooth
        }
    }
}

/// Everything W1 knows about one window.
public struct WeeklyWindowMetrics: Sendable, Equatable {
    public var window: WeeklyWindow
    /// Days that started before the cut-off and end after the first record (D1 partial weeks).
    public var coveredDays: Int
    /// Counted rounds, in record order.
    public var rounds: [WeeklyRound]
    public var days: [WeeklyDayMetrics]
    /// Catalog order (unknown kinds last, by name); quiz before practice.
    public var kinds: [WeeklyKindMetrics]
    public var areas: [WeeklyArea: WeeklyGroupMetrics]
    public var families: [WeeklyPracticeFamily: WeeklyGroupMetrics]
    public var totals: WeeklyGroupMetrics
    /// §4.1 rounds dealt in the window that do not count, by actor (`excluded_session` for
    /// child rounds in a 「唔計呢段」 session).
    public var excludedRounds: [String: Int]
    /// Dealt before the cut-off, no result by then and the app still on it: not counted.
    public var openAtCutoff: Int
    /// m̄_w over this week's quiz kinds and p̄_w over its practice kinds.
    public var pooledQuiz: Double
    public var pooledPractice: Double
    public var newKinds: [String]
    /// Counted rounds per ★ (ticket mix).
    public var stars: [Int]

    public var partial: Bool { coveredDays < WeeklyWindow.dayCount }
    public var daysPlayed: Int { days.filter(\.played).count }
    public var plays: Int { days.reduce(0) { $0 + $1.plays } }
    public var sessionCount: Int { days.reduce(into: Set<String>()) { $0.formUnion($1.sessions) }.count }
    public var quizMs: Int { days.reduce(0) { $0 + $1.quizMs } }
    public var practiceMs: Int { days.reduce(0) { $0 + $1.practiceMs } }
    public var videoMs: Int { days.reduce(0) { $0 + $1.videoMs } }
    public var videoEstimated: Bool { days.contains(where: \.videoEstimated) }
    public var visaMinutes: Int { days.reduce(0) { $0 + $1.visaMinutes } }
    public var excludedTotal: Int { excludedRounds.values.reduce(0, +) }
}

/// One bar of the week-by-week charts (§4.2 trend weeks).
public struct WeeklyWeekTotals: Sendable, Equatable {
    public var weekStart: String
    public var isCurrent: Bool
    public var partial: Bool
    public var openAtCutoff: Int
    public var totals: WeeklyGroupMetrics

    init(_ metrics: WeeklyWindowMetrics, isCurrent: Bool) {
        self.weekStart = metrics.window.weekStartStamp
        self.isCurrent = isCurrent
        self.partial = metrics.partial
        self.openAtCutoff = metrics.openAtCutoff
        self.totals = metrics.totals
    }
}

/// W1 output: this week, last week and the trend weeks.
public struct WeeklyModel: Sendable, Equatable {
    public static let builderVersion = 1

    public var window: WeeklyWindow
    public var current: WeeklyWindowMetrics
    /// d−7…d−1, always seen up to its end.
    public var previous: WeeklyWindowMetrics
    /// Up to 6 earlier weeks that have any raw record, oldest first, then this week.
    public var weeks: [WeeklyWeekTotals]
}

public enum WeeklyMetricsBuilder {
    /// §4.6: one round adds at most 10 minutes of game time.
    public static let gameMsCap = 600_000
    public static let trendWeeks = 6
    public static let topTagMinimumWrongs = 3
    public static let helpHeavyMeanHelps = 2

    /// Exclusions are read from every event passed in (as of making the report, §9.6); rounds,
    /// results and plays only up to each window's cut-off.
    public static func build(events: [PerfEvent], rollup: PerfRollup, window: WeeklyWindow) -> WeeklyModel {
        let ordered = PerfCodec.ordered(events)
        let excluded = PerfFilter.excludedSessions(in: ordered)
        let index = Index(ordered: ordered, excluded: excluded, rollup: rollup)
        return build(ordered: ordered, index: index, window: window)
    }

    /// The same model from records already ordered and indexed, so W2 reads one index.
    static func build(ordered: [PerfEvent], index: Index, window: WeeklyWindow) -> WeeklyModel {
        let current = metrics(index, window: window)
        let previousWindow = window.shifted(weeks: -1)
        let previous = metrics(index, window: previousWindow)

        let trend = (1...trendWeeks).reversed().map { window.shifted(weeks: -$0) }
        var hasData = Array(repeating: false, count: trend.count)
        if let first = trend.first {
            for event in ordered where event.timestamp >= first.start && event.timestamp < window.start {
                for (slot, week) in trend.enumerated() where event.timestamp < week.end {
                    hasData[slot] = true
                    break
                }
            }
        }
        var weeks: [WeeklyWeekTotals] = []
        for (slot, week) in trend.enumerated() where hasData[slot] {
            let seen = week == previousWindow ? previous : metrics(index, window: week)
            weeks.append(WeeklyWeekTotals(seen, isCurrent: false))
        }
        weeks.append(WeeklyWeekTotals(current, isCurrent: true))
        return WeeklyModel(window: window, current: current, previous: previous, weeks: weeks)
    }

    static func ratio(_ part: Int, _ whole: Int) -> Double? {
        whole > 0 ? Double(part) / Double(whole) : nil
    }

    /// clamp((firstTry − E) / (answered − E), 0, 1); nil without chance or room above it.
    static func adjusted(firstTry: Int, answered: Int, expected: Double?) -> Double? {
        guard let expected, answered > 0 else { return nil }
        let room = Double(answered) - expected
        guard room > 0 else { return nil }
        return min(max((Double(firstTry) - expected) / room, 0), 1)
    }

    /// Index in `ActivityCatalog.playableKinds`; unknown kinds after every known one.
    static func catalogRank(_ kind: String) -> Int {
        ActivityKind(rawValue: kind).flatMap { ActivityCatalog.playableKinds.firstIndex(of: $0) } ?? Int.max
    }

    // MARK: Index (one pass over the ordered records)

    struct Index {
        struct Dealt {
            let event: PerfEvent
            let countable: Bool
            let round: String
            let kind: String
        }

        var dealt: [Dealt] = []
        /// `round_result` lines per round id, in record order.
        var results: [String: [PerfEvent]] = [:]
        /// Countable wrong `answer_attempt` lines per round id.
        var wrongAttempts: [String: [PerfEvent]] = [:]
        var videoStarts: [PerfEvent] = []
        var videoEnds: [PerfEvent] = []
        /// `video_end` times per play id (any actor).
        var endedPlays: [String: [Date]] = [:]
        /// Countable `video_progress` lines per play id.
        var progress: [String: [PerfEvent]] = [:]
        var launchStart: [String: Date] = [:]
        /// `stats_marker{cleared}` times, oldest first.
        var cleared: [Date] = []
        /// Countable deal times per kind (§4.9 "ever").
        var dealtTimes: [String: [Date]] = [:]
        /// Rollup days with deals, per kind.
        var rollupDays: [String: [String]] = [:]
        var firstEvent: Date?

        init(ordered: [PerfEvent], excluded: Set<String>, rollup: PerfRollup) {
            for event in ordered {
                if firstEvent.map({ event.timestamp < $0 }) ?? true { firstEvent = event.timestamp }
                if launchStart[event.launch].map({ event.timestamp < $0 }) ?? true {
                    launchStart[event.launch] = event.timestamp
                }
                switch event.type {
                case .gameDealt:
                    let countable = PerfFilter.countable(event, excludedSessions: excluded)
                    let kind = event.string("kind") ?? "unknown"
                    dealt.append(Dealt(event: event, countable: countable, round: event.string("round") ?? "",
                                       kind: kind))
                    if countable { dealtTimes[kind, default: []].append(event.timestamp) }
                case .roundResult:
                    if let round = event.string("round"), !round.isEmpty { results[round, default: []].append(event) }
                case .answerAttempt:
                    if event.bool("correct") == false, PerfFilter.countable(event, excludedSessions: excluded),
                       let round = event.string("round"), !round.isEmpty {
                        wrongAttempts[round, default: []].append(event)
                    }
                case .videoStart:
                    if PerfFilter.countable(event, excludedSessions: excluded) { videoStarts.append(event) }
                case .videoProgress:
                    if PerfFilter.countable(event, excludedSessions: excluded), let play = event.string("play") {
                        progress[play, default: []].append(event)
                    }
                case .videoEnd:
                    if let play = event.string("play") { endedPlays[play, default: []].append(event.timestamp) }
                    if PerfFilter.countable(event, excludedSessions: excluded) { videoEnds.append(event) }
                case .statsMarker:
                    if event.string("what") == "cleared" { cleared.append(event.timestamp) }
                default:
                    break
                }
            }
            cleared.sort()
            for (stamp, summary) in rollup.days {
                for (key, stats) in summary.games where stats.deals > 0 {
                    rollupDays[PerfQuestionGeneration.parseRollupKey(key).kind, default: []].append(stamp)
                }
            }
        }

        /// The last result of `round` seen by `cutoff`.
        func result(for round: String, cutoff: Date) -> PerfEvent? {
            guard !round.isEmpty else { return nil }
            return results[round]?.last { $0.timestamp <= cutoff }
        }

        /// A deal without a result is lost (unfinished) once the app has moved on before the
        /// cut-off: relaunched, or dealt another non-playtest round. Otherwise it is still open.
        func isLost(at position: Int, cutoff: Date) -> Bool {
            let deal = dealt[position].event
            for (launch, started) in launchStart where launch != deal.launch && started > deal.timestamp {
                if started <= cutoff { return true }
            }
            var next = position + 1
            while next < dealt.count, dealt[next].event.launch == deal.launch {
                let later = dealt[next].event
                if later.actor != .parentPlaytest && later.timestamp <= cutoff { return true }
                next += 1
            }
            return false
        }

        /// §4.9: a countable deal before the window, or a rollup day with deals before it,
        /// after the last `stats_marker{cleared}` seen by the cut-off.
        func hasHistory(kind: String, before window: WeeklyWindow) -> Bool {
            let reset = cleared.last { $0 <= window.cutoff }
            for time in dealtTimes[kind] ?? [] where time < window.start {
                if let reset, time < reset { continue }
                return true
            }
            let resetStamp = reset.map { PerfClock.dayStamp($0, timeZone: window.timeZone) }
            for stamp in rollupDays[kind] ?? [] where stamp < window.weekStartStamp {
                if let resetStamp, stamp < resetStamp { continue }
                return true
            }
            return false
        }
    }

    // MARK: One window

    static func metrics(_ index: Index, window: WeeklyWindow) -> WeeklyWindowMetrics {
        var rounds: [WeeklyRound] = []
        var excludedRounds: [String: Int] = [:]
        var openAtCutoff = 0
        for (position, entry) in index.dealt.enumerated() {
            let dealt = entry.event
            guard window.contains(dealt.timestamp), let day = window.dayIndex(dealt.timestamp) else { continue }
            guard entry.countable else {
                excludedRounds[dealt.actor == .child ? "excluded_session" : dealt.actor.rawValue, default: 0] += 1
                continue
            }
            let result = index.result(for: entry.round, cutoff: window.cutoff)
            if result == nil && !index.isLost(at: position, cutoff: window.cutoff) {
                openAtCutoff += 1
                continue
            }
            rounds.append(makeRound(entry, type: WeeklyRoundType.of(dealt: dealt), day: day, result: result))
        }

        struct RowKey: Hashable {
            let kind: String
            let type: WeeklyRoundType
        }
        var rows: [WeeklyKindMetrics] = []
        var rowIndex: [RowKey: Int] = [:]
        for round in rounds {
            let key = RowKey(kind: round.kind, type: round.type)
            let at: Int
            if let existing = rowIndex[key] {
                at = existing
            } else {
                at = rows.count
                rowIndex[key] = at
                rows.append(WeeklyKindMetrics(kind: round.kind, type: round.type))
            }
            rows[at].add(round)
            guard round.type == .quiz, !round.round.isEmpty else { continue }
            for attempt in index.wrongAttempts[round.round] ?? [] where attempt.timestamp <= window.cutoff {
                rows[at].addWrong(attempt)
            }
        }
        for at in rows.indices { rows[at].finish() }
        rows.sort { lhs, rhs in
            let left = catalogRank(lhs.kind), right = catalogRank(rhs.kind)
            if left != right { return left < right }
            if lhs.kind != rhs.kind { return lhs.kind.utf8.lexicographicallyPrecedes(rhs.kind.utf8) }
            return lhs.type == .quiz && rhs.type == .practice
        }

        let quizPool = rows.compactMap { row -> (chance: Double, evidence: PerfMastery.Evidence)? in
            guard row.type == .quiz, row.answered > 0, let mean = row.chanceMean else { return nil }
            return (chance: mean, evidence: row.evidence)
        }
        let practicePool = rows.compactMap { row -> (chance: Double, evidence: PerfMastery.Evidence)? in
            guard row.type == .practice, row.family != nil, row.smoothDefined > 0 else { return nil }
            return (chance: 0, evidence: row.evidence)
        }
        let pooledQuiz = PerfMastery.pooledPrior(quizPool)
        let pooledPractice = PerfMastery.pooledPrior(practicePool)
        for at in rows.indices {
            switch rows[at].type {
            case .quiz:
                if rows[at].answered > 0, let mean = rows[at].chanceMean {
                    rows[at].estimate = PerfMastery.estimate(chance: mean, pooled: pooledQuiz, evidence: rows[at].evidence)
                }
            case .practice:
                if rows[at].family != nil, rows[at].smoothDefined > 0 {
                    rows[at].estimate = PerfMastery.estimate(chance: 0, pooled: pooledPractice,
                                                             evidence: rows[at].evidence)
                }
            }
        }

        var newKinds: [String] = []
        var seenKinds: Set<String> = []
        for row in rows where !seenKinds.contains(row.kind) {
            seenKinds.insert(row.kind)
            if !index.hasHistory(kind: row.kind, before: window) { newKinds.append(row.kind) }
        }
        for at in rows.indices { rows[at].isNew = newKinds.contains(rows[at].kind) }

        var days = (0..<WeeklyWindow.dayCount).map { WeeklyDayMetrics(index: $0, date: window.dayStamps[$0]) }
        for round in rounds { days[round.day].add(round) }
        for kind in newKinds {
            if let first = rounds.filter({ $0.kind == kind }).min(by: { $0.dealtAt < $1.dealtAt }) {
                days[first.day].newKinds.append(kind)
            }
        }
        for start in index.videoStarts where window.contains(start.timestamp) {
            guard let day = window.dayIndex(start.timestamp) else { continue }
            if start.string("source") != "after_parent" {
                days[day].plays += 1
                if !start.session.isEmpty { days[day].sessions.insert(start.session) }
            }
            // §4.6: a play without a `video_end` (power cut) counts its last `video_progress`.
            guard let play = start.string("play"), !play.isEmpty,
                  !(index.endedPlays[play] ?? []).contains(where: { $0 <= window.cutoff }) else { continue }
            let last = (index.progress[play] ?? []).last { $0.timestamp <= window.cutoff }
            let at = last.flatMap { window.dayIndex($0.timestamp) } ?? day
            days[at].videoMs += watchedMs(last?.double("watched_s"))
            days[at].videoEstimated = true
        }
        for end in index.videoEnds where window.contains(end.timestamp) {
            guard let day = window.dayIndex(end.timestamp) else { continue }
            days[day].videoMs += watchedMs(end.double("watched_s"))
        }

        var areas: [WeeklyArea: WeeklyGroupMetrics] = [:]
        var families: [WeeklyPracticeFamily: WeeklyGroupMetrics] = [:]
        var totals = WeeklyGroupMetrics()
        for row in rows {
            areas[row.area, default: WeeklyGroupMetrics()].add(row)
            if let family = row.family { families[family, default: WeeklyGroupMetrics()].add(row) }
            totals.add(row)
        }
        var stars = [0, 0, 0]
        for round in rounds { stars[round.stars - 1] += 1 }
        let coveredDays: Int
        if let first = index.firstEvent {
            coveredDays = (0..<WeeklyWindow.dayCount).filter {
                window.dayStarts[$0] < window.cutoff && window.dayStarts[$0 + 1] > first
            }.count
        } else {
            coveredDays = 0
        }
        return WeeklyWindowMetrics(
            window: window, coveredDays: coveredDays, rounds: rounds, days: days, kinds: rows, areas: areas,
            families: families, totals: totals, excludedRounds: excludedRounds, openAtCutoff: openAtCutoff,
            pooledQuiz: pooledQuiz, pooledPractice: pooledPractice, newKinds: newKinds, stars: stars
        )
    }

    static func makeRound(_ entry: Index.Dealt, type: WeeklyRoundType, day: Int, result: PerfEvent?) -> WeeklyRound {
        let dealt = entry.event
        let outcome: WeeklyRound.Outcome
        if let result {
            switch result.string("outcome") {
            case "solved": outcome = .solved
            case "zeroed": outcome = .zeroed
            default: outcome = .abandoned
            }
        } else {
            outcome = .noResult
        }
        let quiz = type == .quiz
        let answers = result?.int("answers") ?? 0
        let answered = quiz && answers > 0
        let firstTry = answered && result?.bool("first_try") == true
        let hinted = WeeklyField.flag(result?["hint_used"]) == true || WeeklyField.flag(result?["assisted"]) == true
        let total = result?.int("total_ms") ?? 0
        var smooth: Bool?
        var guideHelps: Int?
        if !quiz, let result, outcome == .solved {
            smooth = WeeklySmooth.evaluate(kind: entry.kind, result: result)
            guideHelps = result.int("guide_helps")
        }
        return WeeklyRound(
            round: entry.round,
            kind: entry.kind,
            type: type,
            dealtAt: dealt.timestamp,
            day: day,
            session: dealt.session,
            stars: min(max(dealt.int("stars") ?? 1, 1), 3),
            outcome: outcome,
            answered: answered,
            firstTry: firstTry,
            chance: quiz ? WeeklyChance.chance(dealt: dealt) : nil,
            misses: quiz ? max(0, result?.int("misses") ?? 0) : 0,
            helped: answered && hinted,
            activeMs: result?.int("active_ms"),
            gameMs: min(max(total, 0), gameMsCap),
            earnedMinutes: outcome == .solved ? max(0, result?.int("earned_min") ?? 0) : 0,
            smooth: smooth,
            guideHelps: guideHelps
        )
    }

    /// Seconds (3 decimals on disk) to whole milliseconds, so sums never depend on order.
    static func watchedMs(_ seconds: Double?) -> Int {
        guard let seconds, seconds.isFinite, seconds > 0 else { return 0 }
        return Int((seconds * 1000).rounded())
    }
}
