import Foundation

// Weekly report W2 (weekly-report design §4.10, §3 page 5): week-over-week words, the ⚙ settings
// marker and the "what changed in the app" data. Pure value code; integer rules are compared in
// integers. ADR 0022 records the choices made where the design left room.

/// §4.10: ↑ 明顯進步, ↓ 明顯少咗, ≈ 差唔多, 「變化未夠肯定」.
public enum WeeklyChange: String, Sendable, Equatable, Hashable, CaseIterable {
    case up, down, same, unsure
}

/// A rate this week (k1 / n1) against last week (k0 / n0).
public struct WeeklyRateComparison: Sendable, Equatable {
    public var k1: Int
    public var n1: Int
    public var k0: Int
    public var n0: Int
    /// Nil when a week has fewer than 5 rounds: the old value in grey, no arrow.
    public var change: WeeklyChange?

    public init(k1: Int, n1: Int, k0: Int, n0: Int) {
        self.k1 = k1
        self.n1 = n1
        self.k0 = k0
        self.n0 = n0
        self.change = WeeklyComparison.rateChange(k1: k1, n1: n1, k0: k0, n0: n0)
    }
}

/// A count, or a duration in milliseconds, this week against last week.
public struct WeeklyCountComparison: Sendable, Equatable {
    public var current: Int
    public var previous: Int
    /// `up` / `down` (「明顯」) or nil (both values, no word).
    public var change: WeeklyChange?

    public init(current: Int, previous: Int, daysCurrent: Int, daysPrevious: Int) {
        self.current = current
        self.previous = previous
        self.change = WeeklyComparison.countChange(current: current, previous: previous, daysCurrent: daysCurrent,
                                                   daysPrevious: daysPrevious)
    }
}

/// A kind with a clear ↑ / ↓ and no ⚙ (page 5 "clear changes", `win.rise`).
public struct WeeklyClearChange: Sendable, Equatable {
    public var kind: String
    public var type: WeeklyRoundType
    public var change: WeeklyChange

    public init(kind: String, type: WeeklyRoundType, change: WeeklyChange) {
        self.kind = kind
        self.type = type
        self.change = change
    }
}

/// §4.10 for the tiles, areas, practice families and kinds.
public struct WeeklyComparison: Sendable, Equatable {
    /// Rates need ≥ 5 rounds in both weeks.
    public static let minimumRounds = 5
    /// 「明顯」 on counts and minutes needs ≥ 4 days played in both weeks.
    public static let minimumDays = 4

    /// No record before the report week (`wr.baseline`).
    public var baseline: Bool
    public var previousCoveredDays: Int
    public var daysPlayed: WeeklyCountComparison
    public var rounds: WeeklyCountComparison
    public var gameMs: WeeklyCountComparison
    public var videoMs: WeeklyCountComparison
    /// Right first time over all quiz rows; smooth over all practice rows.
    public var quiz: WeeklyRateComparison
    public var practice: WeeklyRateComparison
    /// Quiz right first time per area; smooth per practice family.
    public var areas: [WeeklyArea: WeeklyRateComparison]
    public var families: [WeeklyPracticeFamily: WeeklyRateComparison]
    /// Kinds with ↑ / ↓ and no ⚙, in row order.
    public var clearChanges: [WeeklyClearChange]

    /// ↑ / ↓ when |Δ| ≥ 0.20 and |Δ| ≥ 1.0 × SE (pooled p̄); ≈ when |Δ| < 0.20; else unsure.
    public static func rateChange(k1: Int, n1: Int, k0: Int, n0: Int) -> WeeklyChange? {
        guard n1 >= minimumRounds, n0 >= minimumRounds else { return nil }
        let d = k1 * n0 - k0 * n1  // Δ · n1 · n0
        let n = n1 * n0
        if 5 * abs(d) < n { return .same }
        // |Δ| ≥ SE  ⟺  Δ² ≥ p̄(1 − p̄)(1/n1 + 1/n0)  ⟺  d² · m ≥ k(m − k) · n
        let k = k1 + k0, m = n1 + n0
        let lhs = Double(d) * Double(d) * Double(m)
        let rhs = Double(k * (m - k)) * Double(n)
        if lhs < rhs { return .unsure }
        return d > 0 ? .up : .down
    }

    /// 「明顯」 only with ≥ 4 days played in both weeks and |Δ| ≥ 25 % of last week.
    public static func countChange(current: Int, previous: Int, daysCurrent: Int, daysPrevious: Int) -> WeeklyChange? {
        guard daysCurrent >= minimumDays, daysPrevious >= minimumDays, current != previous,
              abs(current - previous) * 4 >= previous else { return nil }
        return current > previous ? .up : .down
    }

    /// ⚙ when the ★★★ share of a row's rounds moved by ≥ 30 points between the weeks.
    static func starShift(previous: WeeklyKindMetrics?, current: WeeklyKindMetrics) -> WeeklySettingChange? {
        guard let previous, previous.rounds > 0, current.rounds > 0, previous.stars.count == 3,
              current.stars.count == 3 else { return nil }
        let p3 = previous.stars[2].rounds, c3 = current.stars[2].rounds
        let p = previous.rounds, c = current.rounds
        guard 10 * abs(c3 * p - p3 * c) >= 3 * c * p else { return nil }
        return .stars(previous: p3, previousRounds: p, current: c3, currentRounds: c)
    }

    /// Kinds a `config_change` applies to: its settings family, or the kind of an `assignment`.
    public static func kinds(forConfig what: String, kind: String?) -> [String] {
        if what == "assignment" { return kind.map { [$0] } ?? [] }
        let member: (ActivityKind) -> Bool
        if what.hasPrefix("lineMatch_") {
            member = { $0.isLineMatchFamily }
        } else if what.hasPrefix("shapeTrace_") {
            member = { $0.isShapeTraceFamily }
        } else if what.hasPrefix("tapCount_") {
            member = { $0.isTapCountFamily }
        } else {
            return []
        }
        return ActivityCatalog.playableKinds.filter(member).map(\.rawValue)
    }

    init(current: WeeklyWindowMetrics, previous: WeeklyWindowMetrics, games: [WeeklyGame]) {
        let days = current.daysPlayed, before = previous.daysPlayed
        baseline = previous.coveredDays == 0
        previousCoveredDays = previous.coveredDays
        daysPlayed = WeeklyCountComparison(current: days, previous: before, daysCurrent: days, daysPrevious: before)
        rounds = WeeklyCountComparison(current: current.totals.rounds, previous: previous.totals.rounds,
                                       daysCurrent: days, daysPrevious: before)
        gameMs = WeeklyCountComparison(current: current.quizMs + current.practiceMs,
                                       previous: previous.quizMs + previous.practiceMs, daysCurrent: days,
                                       daysPrevious: before)
        videoMs = WeeklyCountComparison(current: current.videoMs, previous: previous.videoMs, daysCurrent: days,
                                        daysPrevious: before)
        quiz = WeeklyRateComparison(k1: current.totals.firstTry, n1: current.totals.answered,
                                    k0: previous.totals.firstTry, n0: previous.totals.answered)
        practice = WeeklyRateComparison(k1: current.totals.smooth, n1: current.totals.smoothDefined,
                                        k0: previous.totals.smooth, n0: previous.totals.smoothDefined)
        var areas: [WeeklyArea: WeeklyRateComparison] = [:]
        for area in WeeklyArea.allCases {
            let now = current.areas[area] ?? WeeklyGroupMetrics(), then = previous.areas[area] ?? WeeklyGroupMetrics()
            areas[area] = WeeklyRateComparison(k1: now.firstTry, n1: now.answered, k0: then.firstTry, n0: then.answered)
        }
        self.areas = areas
        var families: [WeeklyPracticeFamily: WeeklyRateComparison] = [:]
        for family in WeeklyPracticeFamily.allCases {
            let now = current.families[family] ?? WeeklyGroupMetrics()
            let then = previous.families[family] ?? WeeklyGroupMetrics()
            families[family] = WeeklyRateComparison(k1: now.smooth, n1: now.smoothDefined, k0: then.smooth,
                                                    n0: then.smoothDefined)
        }
        self.families = families
        clearChanges = games.compactMap { game -> WeeklyClearChange? in
            guard let change = game.wow.change, change == .up || change == .down, game.settings.isEmpty else {
                return nil
            }
            return WeeklyClearChange(kind: game.kind, type: game.type, change: change)
        }
    }
}

/// §4.10 ⚙: why a row's week-over-week cell carries the settings marker. A ⚙ row keeps its
/// numbers but never feeds a clear change or `win.rise`.
public enum WeeklySettingChange: Sendable, Equatable {
    /// A `config_change` for the row's settings family or its star assignment, seen from the
    /// start of last week to the cut-off.
    case config(what: String, value: String?, star: Int?, date: String)
    /// The dominant value of a deal field (or `round_result.guide_level`) moved between the weeks.
    case signature(field: String, old: String, new: String)
    /// The ★★★ share of the row's rounds moved by ≥ 30 points.
    case stars(previous: Int, previousRounds: Int, current: Int, currentRounds: Int)
}

/// §4.10 dominant deal signature of one row in one window.
public struct WeeklySignature: Sendable, Equatable {
    /// The deal fields the design names, in its order.
    public static let dealFields = [
        "gen", "level", "tolerance", "shape_trace_level", "trace_scaffold", "range", "count_voice", "english",
        "direction_coaching", "stop_coaching", "slant_enabled", "dot_style", "category_mix", "shape_mix"
    ]
    /// Read from the round's result instead of its deal.
    public static let resultFields = ["guide_level"]

    /// Most common value per field over the row's countable deals in the window; ties go to the
    /// value used last. A field no deal wrote is missing. `gen` defaults to `fixed_v0`.
    public var dominant: [String: String]
    /// Every deal with a `level` had level == its star: the ★★★ rule covers those levels.
    public var levelFollowsStars: Bool

    /// A field value as text; arrays, objects and null have none.
    public static func text(_ value: PerfValue?) -> String? {
        switch value {
        case .string(let text)?: return text
        case .int(let number)?: return String(number)
        case .bool(let flag)?: return flag ? "true" : "false"
        case .double(let number)?: return WeeklyJSON.number(number)
        default: return nil
        }
    }

    /// Changed fields, old (last week) → new (this week); both weeks need a value.
    static func changes(previous: WeeklySignature?, current: WeeklySignature?) -> [WeeklySettingChange] {
        guard let previous, let current else { return [] }
        var changes: [WeeklySettingChange] = []
        for field in dealFields + resultFields {
            if field == "level", previous.levelFollowsStars, current.levelFollowsStars { continue }
            guard let old = previous.dominant[field], let new = current.dominant[field], old != new else { continue }
            changes.append(.signature(field: field, old: old, new: new))
        }
        return changes
    }

    struct Key: Hashable {
        let kind: String
        let type: WeeklyRoundType
    }

    private struct Tally {
        /// field → value → (count, position of the last deal with it).
        var counts: [String: [String: (count: Int, last: Int)]] = [:]
        var levelFollowsStars = true

        mutating func add(_ field: String, _ value: String, at position: Int) {
            var values = counts[field] ?? [:]
            values[value] = (count: (values[value]?.count ?? 0) + 1, last: position)
            counts[field] = values
        }

        var signature: WeeklySignature {
            var dominant: [String: String] = [:]
            for (field, values) in counts {
                var best: (value: String, count: Int, last: Int)?
                for (value, seen) in values {
                    if let current = best,
                       current.count > seen.count || (current.count == seen.count && current.last > seen.last) {
                        continue
                    }
                    best = (value: value, count: seen.count, last: seen.last)
                }
                if let best { dominant[field] = best.value }
            }
            return WeeklySignature(dominant: dominant, levelFollowsStars: levelFollowsStars)
        }
    }

    /// Countable deals in `window`, per (kind, type) row; results seen by the window's cut-off.
    static func scan(_ index: WeeklyMetricsBuilder.Index, window: WeeklyWindow) -> [Key: WeeklySignature] {
        var tallies: [Key: Tally] = [:]
        for (position, entry) in index.dealt.enumerated() where entry.countable {
            let dealt = entry.event
            guard window.contains(dealt.timestamp) else { continue }
            let key = Key(kind: entry.kind, type: WeeklyRoundType.of(dealt: dealt))
            var tally = tallies[key] ?? Tally()
            for field in dealFields {
                let value: String? = field == "gen" ? PerfQuestionGeneration.gen(of: dealt) : text(dealt[field])
                if let value { tally.add(field, value, at: position) }
            }
            if let level = dealt.int("level"), level != min(max(dealt.int("stars") ?? 1, 1), 3) {
                tally.levelFollowsStars = false
            }
            if let result = index.result(for: entry.round, cutoff: window.cutoff) {
                for field in resultFields {
                    if let value = text(result[field]) { tally.add(field, value, at: position) }
                }
            }
            tallies[key] = tally
        }
        return tallies.mapValues(\.signature)
    }
}

/// A `config_change` seen by the cut-off, in record order.
struct WeeklyConfigEvent {
    let position: Int
    let timestamp: Date
    /// HKT day stamp.
    let date: String
    let what: String
    let kind: String?
    /// `value` as text (`assignment` writes a Bool).
    let value: String?
    let flag: Bool?
    /// `assignment` only.
    let star: Int?
    let kinds: [String]

    static func collect(_ ordered: [PerfEvent], cutoff: Date, timeZone: TimeZone) -> [WeeklyConfigEvent] {
        var events: [WeeklyConfigEvent] = []
        for (position, event) in ordered.enumerated() where event.type == .configChange && event.timestamp <= cutoff {
            guard let what = event.string("what"), !what.isEmpty else { continue }
            let kind = event.string("kind")
            events.append(WeeklyConfigEvent(
                position: position, timestamp: event.timestamp,
                date: PerfClock.dayStamp(event.timestamp, timeZone: timeZone), what: what, kind: kind,
                value: WeeklySignature.text(event["value"]), flag: event.bool("value"),
                star: what == "assignment" ? event.int("star") : nil,
                kinds: WeeklyComparison.kinds(forConfig: what, kind: kind)
            ))
        }
        return events
    }
}

/// Page 5 "What changed in the app" (§3; design §9.6 `changes`), as data only.
public struct WeeklyChanges: Sendable, Equatable {
    /// An `app` value seen in the window, on days `firstDay … lastDay` (0 = Monday).
    public struct Version: Sendable, Equatable {
        public var app: String
        public var firstDay: Int
        public var lastDay: Int
    }

    /// A settings `config_change` this week; `old` is the value of the last earlier change with
    /// the same `what` (nil when none was recorded).
    public struct Setting: Sendable, Equatable {
        public var date: String
        public var what: String
        public var old: String?
        public var new: String?
        public var kinds: [String]
    }

    /// A star assignment that differs at the end of the week from before its first toggle.
    public struct Assignment: Sendable, Equatable {
        public var date: String
        public var kind: String
        public var star: Int
        public var on: Bool
    }

    /// A row whose dominant `gen` moved between the weeks.
    public struct Generation: Sendable, Equatable {
        public var kind: String
        public var type: WeeklyRoundType
        public var old: String
        public var new: String
    }

    public var versions: [Version]
    public var settings: [Setting]
    public var assignments: [Assignment]
    public var generations: [Generation]
    public var quizRounds: WeeklyCountComparison
    public var practiceRounds: WeeklyCountComparison
    /// Counted rounds per ★ this week and last week.
    public var stars: [Int]
    public var previousStars: [Int]
    public var excludedRounds: [String: Int]
    public var openAtCutoff: Int

    public var excludedTotal: Int { excludedRounds.values.reduce(0, +) }

    init(model: WeeklyModel, ordered: [PerfEvent], configs: [WeeklyConfigEvent],
         current: [WeeklySignature.Key: WeeklySignature], previous: [WeeklySignature.Key: WeeklySignature]) {
        let window = model.window
        var seen: [String: (first: Date, firstDay: Int, lastDay: Int)] = [:]
        for event in ordered where !event.app.isEmpty && window.contains(event.timestamp) {
            guard let day = window.dayIndex(event.timestamp) else { continue }
            if var app = seen[event.app] {
                if event.timestamp < app.first { app.first = event.timestamp }
                app.firstDay = min(app.firstDay, day)
                app.lastDay = max(app.lastDay, day)
                seen[event.app] = app
            } else {
                seen[event.app] = (first: event.timestamp, firstDay: day, lastDay: day)
            }
        }
        versions = seen.sorted { lhs, rhs in
            lhs.value.first != rhs.value.first ? lhs.value.first < rhs.value.first
                : lhs.key.utf8.lexicographicallyPrecedes(rhs.key.utf8)
        }.map { Version(app: $0.key, firstDay: $0.value.firstDay, lastDay: $0.value.lastDay) }

        var settings: [Setting] = []
        for (offset, config) in configs.enumerated() where config.what != "assignment" {
            guard window.contains(config.timestamp) else { continue }
            let old = configs[..<offset].last { $0.what == config.what }?.value
            settings.append(Setting(date: config.date, what: config.what, old: old, new: config.value,
                                    kinds: config.kinds))
        }
        self.settings = settings

        struct Toggle {
            let kind: String
            let star: Int
            let first: Bool
            var last: Bool
            var position: Int
            var date: String
        }
        var toggles: [Toggle] = []
        for config in configs where config.what == "assignment" && window.contains(config.timestamp) {
            guard let kind = config.kind, let star = config.star, let on = config.flag else { continue }
            if let at = toggles.firstIndex(where: { $0.kind == kind && $0.star == star }) {
                toggles[at].last = on
                toggles[at].position = config.position
                toggles[at].date = config.date
            } else {
                toggles.append(Toggle(kind: kind, star: star, first: on, last: on, position: config.position,
                                      date: config.date))
            }
        }
        // Every toggle flips the star, so the state before the first one was `!first`.
        assignments = toggles.filter { $0.first == $0.last }.sorted { $0.position < $1.position }
            .map { Assignment(date: $0.date, kind: $0.kind, star: $0.star, on: $0.last) }

        generations = model.current.kinds.compactMap { row -> Generation? in
            let key = WeeklySignature.Key(kind: row.kind, type: row.type)
            guard let old = previous[key]?.dominant["gen"], let new = current[key]?.dominant["gen"], old != new else {
                return nil
            }
            return Generation(kind: row.kind, type: row.type, old: old, new: new)
        }

        let days = model.current.daysPlayed, before = model.previous.daysPlayed
        quizRounds = WeeklyCountComparison(current: model.current.totals.quizRounds,
                                           previous: model.previous.totals.quizRounds, daysCurrent: days,
                                           daysPrevious: before)
        practiceRounds = WeeklyCountComparison(current: model.current.totals.practiceRounds,
                                               previous: model.previous.totals.practiceRounds, daysCurrent: days,
                                               daysPrevious: before)
        stars = model.current.stars
        previousStars = model.previous.stars
        excludedRounds = model.current.excludedRounds
        openAtCutoff = model.current.openAtCutoff
    }
}
