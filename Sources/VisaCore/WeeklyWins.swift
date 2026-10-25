import Foundation

// Weekly report W2 (weekly-report design §6.5): the wins catalogue, evaluated in its priority order.
// Ids and parameters only; the sentences are W3. ADR 0022 records the choices made where the design
// left room.

/// One win (at most 3 are shown, in the order of the cases).
public enum WeeklyWin: Sendable, Equatable {
    /// The kind is new this week (§4.9).
    case newGame(kind: String)
    /// Numerals whose first-ever round with `guide_learned_before == 1` is this week, ascending.
    case numeral(numerals: [Int])
    /// The longest right-first-time run of a quiz kind this week (≥ 5); one win, the longest run.
    case streak(kind: String, run: Int)
    /// A clear ↑ (§4.10) without ⚙.
    case rise(kind: String, type: WeeklyRoundType, k0: Int, n0: Int, k1: Int, n1: Int)
    /// The first-ever smooth round of a practice kind, on `day` (0 = Monday).
    case firstSmooth(kind: String, day: Int)
    /// The first-ever right-first-time round of a quiz kind after `earlier` (≥ 3) answered rounds.
    case firstTry(kind: String, earlier: Int, day: Int)
    /// The day with the most quiz rounds (≥ 5) all right first time.
    case cleanDay(day: Int, rounds: Int)
    /// ≥ 20 quiz rounds and no fuel-out.
    case noFuelOut(rounds: Int)

    public static let maximum = 3
    public static let streakMinimum = 5
    public static let firstTryMinimumEarlier = 3
    public static let cleanDayMinimum = 5
    public static let noFuelOutMinimum = 20

    public var id: String {
        switch self {
        case .newGame: return "win.newGame"
        case .numeral: return "win.numeral"
        case .streak: return "win.streak"
        case .rise: return "win.rise"
        case .firstSmooth: return "win.firstSmooth"
        case .firstTry: return "win.firstTry"
        case .cleanDay: return "win.cleanDay"
        case .noFuelOut: return "win.noFuelOut"
        }
    }

    /// Every win that applies, in priority order (per-kind wins in row order).
    static func candidates(current: WeeklyWindowMetrics, games: [WeeklyGame], facts: WeeklyWinFacts) -> [WeeklyWin] {
        var wins: [WeeklyWin] = current.newKinds.map { WeeklyWin.newGame(kind: $0) }

        let numerals = facts.learnedThisWeek.subtracting(facts.learnedBefore).sorted()
        if !numerals.isEmpty { wins.append(.numeral(numerals: numerals)) }

        var best: (kind: String, run: Int)?
        for row in current.kinds where row.type == .quiz {
            var run = 0, longest = 0
            for round in current.rounds where round.kind == row.kind && round.type == .quiz && round.answered {
                run = round.firstTry ? run + 1 : 0
                longest = max(longest, run)
            }
            if longest >= streakMinimum, longest > (best?.run ?? 0) { best = (kind: row.kind, run: longest) }
        }
        if let best { wins.append(.streak(kind: best.kind, run: best.run)) }

        for game in games where game.wow.change == .up && game.settings.isEmpty {
            wins.append(.rise(kind: game.kind, type: game.type, k0: game.wow.k0, n0: game.wow.n0, k1: game.wow.k1,
                              n1: game.wow.n1))
        }

        for row in current.kinds where row.type == .practice && row.smooth > 0 && !facts.smooth.contains(row.kind) {
            let first = current.rounds.first { $0.kind == row.kind && $0.type == .practice && $0.smooth == true }
            if let first { wins.append(.firstSmooth(kind: row.kind, day: first.day)) }
        }

        for row in current.kinds where row.type == .quiz && row.firstTry > 0 && !facts.firstTry.contains(row.kind) {
            var earlier = facts.answered[row.kind] ?? 0
            for round in current.rounds where round.kind == row.kind && round.type == .quiz && round.answered {
                if round.firstTry {
                    if earlier >= firstTryMinimumEarlier {
                        wins.append(.firstTry(kind: row.kind, earlier: earlier, day: round.day))
                    }
                    break
                }
                earlier += 1
            }
        }

        var clean: (day: Int, rounds: Int)?
        for day in current.days where day.quizRounds >= cleanDayMinimum && day.counts.firstTry == day.quizRounds {
            if day.quizRounds > (clean?.rounds ?? 0) { clean = (day: day.index, rounds: day.quizRounds) }
        }
        if let clean { wins.append(.cleanDay(day: clean.day, rounds: clean.rounds)) }

        let zeroed = current.kinds.filter { $0.type == .quiz }.reduce(0) { $0 + $1.zeroed }
        if current.totals.quizRounds >= noFuelOutMinimum, zeroed == 0 {
            wins.append(.noFuelOut(rounds: current.totals.quizRounds))
        }
        return wins
    }
}

/// What the "first-ever" wins need from before the report week: countable raw rounds after the
/// last `stats_marker{cleared}` (results seen before the week starts), plus rollup days for quiz
/// rounds. The rollup keeps no smooth or numeral facts.
struct WeeklyWinFacts {
    /// Quiz kinds: answered rounds before the week.
    var answered: [String: Int] = [:]
    /// Quiz kinds with a right-first-time round before the week.
    var firstTry: Set<String> = []
    /// Practice kinds with a smooth round before the week.
    var smooth: Set<String> = []
    var learnedBefore: Set<Int> = []
    /// Numerals with `guide_learned_before == 1` on a counted round this week.
    var learnedThisWeek: Set<Int> = []

    init(index: WeeklyMetricsBuilder.Index, rollup: PerfRollup, window: WeeklyWindow) {
        let reset = index.cleared.last { $0 <= window.cutoff }
        for entry in index.dealt where entry.countable {
            let dealt = entry.event
            if dealt.timestamp < window.start {
                if let reset, dealt.timestamp < reset { continue }
                guard let result = index.result(for: entry.round, cutoff: window.start) else { continue }
                switch WeeklyRoundType.of(dealt: dealt) {
                case .quiz:
                    if (result.int("answers") ?? 0) > 0 {
                        answered[entry.kind, default: 0] += 1
                        if result.bool("first_try") == true { firstTry.insert(entry.kind) }
                    }
                case .practice:
                    if WeeklySmooth.evaluate(kind: entry.kind, result: result) == true { smooth.insert(entry.kind) }
                }
                if let numeral = Self.learnedNumeral(dealt: dealt, result: result) { learnedBefore.insert(numeral) }
            } else if window.contains(dealt.timestamp),
                      let result = index.result(for: entry.round, cutoff: window.cutoff),
                      let numeral = Self.learnedNumeral(dealt: dealt, result: result) {
                learnedThisWeek.insert(numeral)
            }
        }
        let resetStamp = reset.map { PerfClock.dayStamp($0, timeZone: window.timeZone) }
        for (stamp, summary) in rollup.days where stamp < window.weekStartStamp {
            if let resetStamp, stamp < resetStamp { continue }
            for (key, stats) in summary.games where !PerfQuestionGeneration.isGuidedRollupKey(key) {
                let kind = PerfQuestionGeneration.parseRollupKey(key).kind
                answered[kind, default: 0] += stats.answered
                if stats.firstTry > 0 { firstTry.insert(kind) }
            }
        }
    }

    /// The numeral of a round that started with it already learned (`guide_learned_before`).
    static func learnedNumeral(dealt: PerfEvent, result: PerfEvent) -> Int? {
        guard WeeklyField.flag(result["guide_learned_before"]) == true else { return nil }
        return result.int("numeral") ?? dealt.int("numeral")
    }
}
