import Foundation

// Weekly report W2 (weekly-report design §12 W2): the ranking (§5), week over week (§4.10), wins
// (§6.5) and the "what changed" data (page 5) built on the W1 model, plus one canonical JSON text
// with the W1 `WeeklyJSON` rules, so the golden fixtures compare it byte for byte. Pure and
// deterministic: the same events, rollup and window always give the same analysis.

/// One game row this week (W1 row order: catalog order, quiz before practice).
public struct WeeklyGame: Sendable, Equatable {
    public var kind: String
    public var type: WeeklyRoundType
    public var area: WeeklyArea
    public var family: WeeklyPracticeFamily?
    public var isNew: Bool
    public var rounds: Int
    /// Answered (quiz) or smooth-defined (practice) rounds: §5.1 `n`.
    public var n: Int
    /// Right first time (quiz) or smooth (practice).
    public var k: Int
    public var daysPlayed: Int
    /// Fuel-outs.
    public var zeroed: Int
    public var helpHeavy: Bool
    /// Quiz: Σ chance / answered; nil for practice or without a chance.
    public var chance: Double?
    /// W1's week estimate (m̂, m20, m80 or ŝ, s20, s80), kept even when the row is not ranked.
    public var estimate: PerfMastery.Estimate?
    public var tier: WeeklyTier
    public var placement: WeeklyPlacement
    /// §5.5 「同一題」: the dominant `gen` this week is `fixed_v0`.
    public var fixedQuestion: Bool
    /// §5.5 memorised flag: a fixed quiz kind, answered ≥ 10, right first time ≥ 90 %.
    public var memorised: Bool
    /// Rounds per ★, ★★, ★★★.
    public var stars: [Int]
    /// §5.4 `bot.stars`; nil when it does not fire.
    public var starRule: WeeklyStarRule?
    /// §4.10 ⚙; empty when there is no marker.
    public var settings: [WeeklySettingChange]
    public var wow: WeeklyRateComparison
}

/// W2 output: the W1 model plus everything page 4 and page 5 rank, compare and list.
public struct WeeklyAnalysis: Sendable, Equatable {
    public static let analysisVersion = 1

    public var model: WeeklyModel
    public var games: [WeeklyGame]
    public var ranking: WeeklyRanking
    public var comparison: WeeklyComparison
    /// Every win that applies, in priority order.
    public var winCandidates: [WeeklyWin]
    public var changes: WeeklyChanges

    /// The wins shown (at most 3).
    public var wins: [WeeklyWin] { Array(winCandidates.prefix(WeeklyWin.maximum)) }

    public func game(kind: String, type: WeeklyRoundType) -> WeeklyGame? {
        games.first { $0.kind == kind && $0.type == type }
    }
}

public enum WeeklyAnalysisBuilder {
    /// Exclusions, settings and history are read from every event passed in; rounds, results and
    /// changes only up to the cut-off (W1 rules, ADR 0021 / 0022).
    public static func build(events: [PerfEvent], rollup: PerfRollup, window: WeeklyWindow) -> WeeklyAnalysis {
        let ordered = PerfCodec.ordered(events)
        let excluded = PerfFilter.excludedSessions(in: ordered)
        let index = WeeklyMetricsBuilder.Index(ordered: ordered, excluded: excluded, rollup: rollup)
        let model = WeeklyMetricsBuilder.build(ordered: ordered, index: index, window: window)
        return analyse(model: model, ordered: ordered, index: index, rollup: rollup)
    }

    static func analyse(model: WeeklyModel, ordered: [PerfEvent], index: WeeklyMetricsBuilder.Index,
                        rollup: PerfRollup) -> WeeklyAnalysis {
        let current = model.current, previous = model.previous
        let currentSignatures = WeeklySignature.scan(index, window: current.window)
        let previousSignatures = WeeklySignature.scan(index, window: previous.window)
        let configs = WeeklyConfigEvent.collect(ordered, cutoff: model.window.cutoff, timeZone: model.window.timeZone)

        var games: [WeeklyGame] = []
        var scores: [WeeklyScore] = []
        for row in current.kinds {
            let key = WeeklySignature.Key(kind: row.kind, type: row.type)
            let before = previous.kinds.first { $0.kind == row.kind && $0.type == row.type }
            let chanceMissing = current.rounds.contains { $0.kind == row.kind && $0.type == .quiz && $0.chance == nil }
            let score = WeeklyScore(row, chanceMissing: chanceMissing)
            scores.append(score)

            var settings: [WeeklySettingChange] = []
            for config in configs where config.timestamp >= previous.window.start && config.kinds.contains(row.kind) {
                settings.append(.config(what: config.what, value: config.value, star: config.star, date: config.date))
            }
            settings += WeeklySignature.changes(previous: previousSignatures[key], current: currentSignatures[key])
            if let shift = WeeklyComparison.starShift(previous: before, current: row) { settings.append(shift) }

            let fixed = currentSignatures[key]?.dominant["gen"] == QuestionGeneration.fixed
            let k0 = before.map { $0.type == .quiz ? $0.firstTry : $0.smooth } ?? 0
            let n0 = before.map { $0.type == .quiz ? $0.answered : $0.smoothDefined } ?? 0
            games.append(WeeklyGame(
                kind: row.kind, type: row.type, area: row.area, family: row.family, isNew: row.isNew,
                rounds: row.rounds, n: score.n, k: score.k, daysPlayed: row.daysPlayed, zeroed: row.zeroed,
                helpHeavy: row.helpHeavy,
                chance: row.chanceMean, estimate: row.estimate, tier: score.tier, placement: .insufficient,
                fixedQuestion: fixed,
                memorised: row.type == .quiz && fixed && WeeklyFixedQuestion.isMemorised(k: score.k, n: score.n),
                stars: row.stars.map(\.rounds), starRule: WeeklyStarRule.evaluate(row), settings: settings,
                wow: WeeklyRateComparison(k1: score.k, n1: score.n, k0: k0, n0: n0)
            ))
        }
        let ranking = WeeklyRanking.rank(scores)
        for at in games.indices {
            games[at].placement = ranking.placement(kind: games[at].kind, type: games[at].type)
        }
        let comparison = WeeklyComparison(current: current, previous: previous, games: games)
        let facts = WeeklyWinFacts(index: index, rollup: rollup, window: model.window)
        let changes = WeeklyChanges(model: model, ordered: ordered, configs: configs, current: currentSignatures,
                                    previous: previousSignatures)
        return WeeklyAnalysis(model: model, games: games, ranking: ranking, comparison: comparison,
                              winCandidates: WeeklyWin.candidates(current: current, games: games, facts: facts),
                              changes: changes)
    }
}

// MARK: Canonical JSON (W1 `WeeklyJSON` rules; ids in English)

extension WeeklyRateComparison {
    var fields: [String: PerfValue] {
        var o: [String: PerfValue] = [:]
        o["k1"] = .int(k1)
        o["n1"] = .int(n1)
        o["k0"] = .int(k0)
        o["n0"] = .int(n0)
        o["change"] = PerfValue.optionalString(change?.rawValue)
        return o
    }

    public var json: PerfValue { .object(fields) }
}

extension WeeklyCountComparison {
    /// `minutes`: the values are milliseconds, written as minutes.
    public func json(minutes: Bool) -> PerfValue {
        var o: [String: PerfValue] = [:]
        o["current"] = minutes ? WeeklyJSON.minutes(current) : .int(current)
        o["previous"] = minutes ? WeeklyJSON.minutes(previous) : .int(previous)
        o["change"] = PerfValue.optionalString(change?.rawValue)
        return .object(o)
    }
}

extension WeeklyKindLists {
    var fields: [String: PerfValue] {
        ["quiz": PerfValue.strings(quiz), "practice": PerfValue.strings(practice)]
    }

    public var json: PerfValue { .object(fields) }
}

extension WeeklyInsufficient {
    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["kind"] = .string(kind)
        o["type"] = .string(type.rawValue)
        o["reason"] = .string(reason.rawValue)
        o["n"] = .int(n)
        o["k"] = .int(k)
        o["days_played"] = .int(daysPlayed)
        o["more"] = .int(more)
        return .object(o)
    }
}

extension WeeklyRanking {
    static func slots(_ slots: [Int]) -> PerfValue {
        .object(["quiz": .int(slots.first ?? 0), "practice": .int(slots.count > 1 ? slots[1] : 0)])
    }

    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["ranked"] = .bool(ranked)
        o["qualified"] = .object(["quiz": .int(qualifiedQuiz), "practice": .int(qualifiedPractice)])
        var topFields = top.fields
        topFields["size"] = .int(topSize)
        topFields["slots"] = Self.slots(topSlots)
        o["top"] = .object(topFields)
        var stillFields = stillLearning.fields
        stillFields["size"] = .int(stillLearningSize)
        stillFields["slots"] = Self.slots(stillLearningSlots)
        stillFields["candidates"] = .int(stillLearningCandidates)
        o["still_learning"] = .object(stillFields)
        o["also_well"] = alsoWell.json
        o["also_learning"] = alsoLearning.json
        o["insufficient"] = .array(insufficient.map(\.json))
        return .object(o)
    }
}

extension WeeklyStarRule {
    public var json: PerfValue {
        .object(["k3": .int(k3), "n3": .int(n3), "k12": .int(k12), "n12": .int(n12)])
    }
}

extension WeeklySettingChange {
    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        switch self {
        case .config(let what, let value, let star, let date):
            o["reason"] = .string("config")
            o["what"] = .string(what)
            o["value"] = PerfValue.optionalString(value)
            o["star"] = PerfValue.optionalInt(star)
            o["date"] = .string(date)
        case .signature(let field, let from, let to):
            o["reason"] = .string("signature")
            o["field"] = .string(field)
            o["old"] = .string(from)
            o["new"] = .string(to)
        case .stars(let previous, let previousRounds, let current, let currentRounds):
            o["reason"] = .string("stars")
            o["previous"] = .int(previous)
            o["previous_rounds"] = .int(previousRounds)
            o["current"] = .int(current)
            o["current_rounds"] = .int(currentRounds)
        }
        return .object(o)
    }
}

extension WeeklyGame {
    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["kind"] = .string(kind)
        o["type"] = .string(type.rawValue)
        o["area"] = .string(area.rawValue)
        o["family"] = PerfValue.optionalString(family?.rawValue)
        o["new"] = .bool(isNew)
        o["rounds"] = .int(rounds)
        o["n"] = .int(n)
        o["k"] = .int(k)
        o["rate"] = WeeklyJSON.real(WeeklyMetricsBuilder.ratio(k, n))
        o["chance"] = WeeklyJSON.real(chance)
        o["m"] = WeeklyJSON.real(estimate?.mastery)
        o["lo"] = WeeklyJSON.real(estimate?.masteryLow)
        o["hi"] = WeeklyJSON.real(estimate?.masteryHigh)
        o["tier"] = .string(tier.rawValue)
        o["placement"] = .string(placement.rawValue)
        o["days_played"] = .int(daysPlayed)
        o["zeroed"] = .int(zeroed)
        o["help_heavy"] = .bool(helpHeavy)
        o["fixed_question"] = .bool(fixedQuestion)
        o["memorised"] = .bool(memorised)
        o["stars"] = .array(stars.map { PerfValue.int($0) })
        o["star_rule"] = starRule?.json ?? .null
        o["settings"] = .array(settings.map(\.json))
        o["wow"] = wow.json
        return .object(o)
    }
}

extension WeeklyComparison {
    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["baseline"] = .bool(baseline)
        o["previous_covered_days"] = .int(previousCoveredDays)
        o["days_played"] = daysPlayed.json(minutes: false)
        o["rounds"] = rounds.json(minutes: false)
        o["game_min"] = gameMs.json(minutes: true)
        o["video_min"] = videoMs.json(minutes: true)
        o["quiz"] = quiz.json
        o["practice"] = practice.json
        o["areas"] = .array(WeeklyArea.allCases.map { area -> PerfValue in
            var fields = (areas[area] ?? WeeklyRateComparison(k1: 0, n1: 0, k0: 0, n0: 0)).fields
            fields["area"] = .string(area.rawValue)
            return .object(fields)
        })
        o["families"] = .array(WeeklyPracticeFamily.allCases.map { family -> PerfValue in
            var fields = (families[family] ?? WeeklyRateComparison(k1: 0, n1: 0, k0: 0, n0: 0)).fields
            fields["family"] = .string(family.rawValue)
            return .object(fields)
        })
        o["clear_changes"] = .array(clearChanges.map { change -> PerfValue in
            .object(["kind": .string(change.kind), "type": .string(change.type.rawValue),
                     "change": .string(change.change.rawValue)])
        })
        return .object(o)
    }
}

extension WeeklyWin {
    public var json: PerfValue {
        var o: [String: PerfValue] = ["id": .string(id)]
        switch self {
        case .newGame(let kind):
            o["kind"] = .string(kind)
        case .numeral(let numerals):
            o["numerals"] = .array(numerals.map { PerfValue.int($0) })
        case .streak(let kind, let run):
            o["kind"] = .string(kind)
            o["run"] = .int(run)
        case .rise(let kind, let type, let k0, let n0, let k1, let n1):
            o["kind"] = .string(kind)
            o["type"] = .string(type.rawValue)
            o["k0"] = .int(k0)
            o["n0"] = .int(n0)
            o["k1"] = .int(k1)
            o["n1"] = .int(n1)
        case .firstSmooth(let kind, let day):
            o["kind"] = .string(kind)
            o["day"] = .int(day)
        case .firstTry(let kind, let earlier, let day):
            o["kind"] = .string(kind)
            o["earlier"] = .int(earlier)
            o["day"] = .int(day)
        case .cleanDay(let day, let rounds):
            o["day"] = .int(day)
            o["rounds"] = .int(rounds)
        case .noFuelOut(let rounds):
            o["rounds"] = .int(rounds)
        }
        return .object(o)
    }
}

extension WeeklyChanges {
    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["versions"] = .array(versions.map { version -> PerfValue in
            .object(["app": .string(version.app), "first_day": .int(version.firstDay),
                     "last_day": .int(version.lastDay)])
        })
        o["config"] = .array(settings.map { setting -> PerfValue in
            .object(["date": .string(setting.date), "what": .string(setting.what),
                     "old": PerfValue.optionalString(setting.old), "new": PerfValue.optionalString(setting.new),
                     "kinds": PerfValue.strings(setting.kinds)])
        })
        o["assignment"] = .array(assignments.map { change -> PerfValue in
            .object(["date": .string(change.date), "kind": .string(change.kind), "star": .int(change.star),
                     "on": .bool(change.on)])
        })
        o["gen"] = .array(generations.map { change -> PerfValue in
            .object(["kind": .string(change.kind), "type": .string(change.type.rawValue), "old": .string(change.old),
                     "new": .string(change.new)])
        })
        var mix: [String: PerfValue] = [:]
        mix["quiz_rounds"] = quizRounds.json(minutes: false)
        mix["practice_rounds"] = practiceRounds.json(minutes: false)
        mix["stars"] = .object(["current": .array(stars.map { PerfValue.int($0) }),
                                "previous": .array(previousStars.map { PerfValue.int($0) })])
        o["mix"] = .object(mix)
        var excluded: [String: PerfValue] = [:]
        excluded["total"] = .int(excludedTotal)
        excluded["by_reason"] = .object(excludedRounds.mapValues { PerfValue.int($0) })
        excluded["open_at_cutoff"] = .int(openAtCutoff)
        o["excluded_rounds"] = .object(excluded)
        return .object(o)
    }
}

extension WeeklyAnalysis {
    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["analysis"] = .int(Self.analysisVersion)
        o["builder"] = .int(WeeklyModel.builderVersion)
        o["time_zone"] = .string(model.window.timeZone.identifier)
        o["week_start"] = .string(model.window.weekStartStamp)
        o["previous_week_start"] = .string(model.previous.window.weekStartStamp)
        o["data_until"] = .string(PerfCodec.formatTimestamp(model.window.cutoff))
        o["pooled"] = .object(["quiz": .double(model.current.pooledQuiz),
                               "practice": .double(model.current.pooledPractice)])
        o["games"] = .array(games.map(\.json))
        o["ranking"] = ranking.json
        o["comparison"] = comparison.json
        o["wins"] = .array(wins.map(\.json))
        o["win_candidates"] = .array(winCandidates.map(\.json))
        o["changes"] = changes.json
        return .object(o)
    }

    /// The canonical text the W2 golden fixtures compare (W1 `WeeklyJSON` rules).
    public func canonicalJSON() -> String {
        WeeklyJSON.encode(json)
    }
}
