import Foundation

// Weekly report W2 (weekly-report design §5.1–5.5, D4 A, D5 A): who qualifies, the weekly tier,
// the going-well and still-learning lists with proportional quiz / practice slots, the star rule
// and the fixed-question flags. Pure value code over W1 rows; ADR 0022 records the choices made
// where the design left room.

/// §5.1 / §5.2: the status of one game row this week.
public enum WeeklyTier: String, Sendable, Equatable, Hashable, CaseIterable {
    case goingWell = "going_well"
    case learning
    case needsPractice = "needs_practice"
    /// Played, but fewer than 5 answered (quiz) or smooth-defined (practice) rounds.
    case insufficient
    /// An unknown practice family, or a quiz kind without a known chance (「未有評分方法」).
    case noMethod = "no_method"

    /// Qualified rows have one of the three ranked tiers.
    public var isQualified: Bool {
        switch self {
        case .goingWell, .learning, .needsPractice: return true
        case .insufficient, .noMethod: return false
        }
    }
}

/// Where page 4 lists a row. Every row has exactly one place.
public enum WeeklyPlacement: String, Sendable, Equatable, Hashable, CaseIterable {
    case top
    case stillLearning = "still_learning"
    case alsoWell = "also_well"
    case alsoLearning = "also_learning"
    case insufficient
}

/// Why a row is on the 數據唔夠 list (§5.1, §5.3).
public enum WeeklyInsufficientReason: String, Sendable, Equatable, Hashable, CaseIterable {
    /// n < 5: 「再玩 {5 − n} 局就排名」.
    case tooFew = "too_few"
    /// Qualified and not going well, but played on one day only: 「全部喺同一日玩，下星期再睇」.
    case oneDay = "one_day"
    /// 「未有評分方法」.
    case noMethod = "no_method"
}

/// What the ranking reads off one game row.
public struct WeeklyScore: Sendable, Equatable {
    public var kind: String
    public var type: WeeklyRoundType
    /// Answered (quiz) or smooth-defined (practice) rounds: §5.1 `n`.
    public var n: Int
    /// Right first time (quiz) or smooth (practice).
    public var k: Int
    public var daysPlayed: Int
    public var tier: WeeklyTier
    /// m20 / m80 (quiz) or s20 / s80 (practice); 0 when not qualified.
    public var low: Double
    public var high: Double

    public init(kind: String, type: WeeklyRoundType, n: Int, k: Int, daysPlayed: Int, tier: WeeklyTier,
                low: Double = 0, high: Double = 0) {
        self.kind = kind
        self.type = type
        self.n = n
        self.k = k
        self.daysPlayed = daysPlayed
        self.tier = tier
        self.low = low
        self.high = high
    }

    /// §5.1 and §5.2 for a W1 row. `chanceMissing`: a quiz round of the row has no chance.
    public init(_ row: WeeklyKindMetrics, chanceMissing: Bool) {
        let quiz = row.type == .quiz
        let n = quiz ? row.answered : row.smoothDefined
        let hasMethod = quiz ? row.chanceKnown && !chanceMissing : row.family != nil
        var tier = WeeklyTier.insufficient
        if !hasMethod {
            tier = .noMethod
        } else if n >= WeeklyRanking.minimumRounds, let estimate = row.estimate {
            tier = WeeklyRanking.tier(type: row.type, estimate: estimate, zeroed: row.zeroed, helpHeavy: row.helpHeavy)
        }
        let qualified = tier.isQualified
        self.init(kind: row.kind, type: row.type, n: n, k: quiz ? row.firstTry : row.smooth,
                  daysPlayed: row.daysPlayed, tier: tier,
                  low: qualified ? (row.estimate?.masteryLow ?? 0) : 0,
                  high: qualified ? (row.estimate?.masteryHigh ?? 0) : 0)
    }
}

/// Kind ids grouped by type: 答題 first, then 練習 (§5.3: cross-type order is not claimed).
public struct WeeklyKindLists: Sendable, Equatable {
    public var quiz: [String]
    public var practice: [String]

    public init(quiz: [String] = [], practice: [String] = []) {
        self.quiz = quiz
        self.practice = practice
    }

    public var all: [String] { quiz + practice }
    public var count: Int { quiz.count + practice.count }

    public func contains(kind: String, type: WeeklyRoundType) -> Bool {
        (type == .quiz ? quiz : practice).contains(kind)
    }
}

/// One row of the 數據唔夠 list.
public struct WeeklyInsufficient: Sendable, Equatable {
    public var kind: String
    public var type: WeeklyRoundType
    public var reason: WeeklyInsufficientReason
    public var n: Int
    public var k: Int
    public var daysPlayed: Int

    /// Rounds still needed to rank (too few only).
    public var more: Int { reason == .tooFew ? max(0, WeeklyRanking.minimumRounds - n) : 0 }
}

/// §5.3: the page-4 lists.
public struct WeeklyRanking: Sendable, Equatable {
    /// §5.1: the approved 5-round minimum.
    public static let minimumRounds = PerfMastery.minimumRounds
    public static let listSize = 5
    /// D5 A: still learning needs play on ≥ 2 distinct days.
    public static let minimumDays = 2
    /// §3 page 4: with fewer qualified games the lists are replaced by 「今個星期玩得太少，未排名。」.
    public static let minimumQualified = 2

    public var qualifiedQuiz: Int
    public var qualifiedPractice: Int
    /// T = min(5, ceil(E / 2)).
    public var topSize: Int
    /// Largest-remainder slots [quiz, practice] before spill-over.
    public var topSlots: [Int]
    public var top: WeeklyKindLists
    public var stillLearningCandidates: Int
    /// B = min(5, candidates).
    public var stillLearningSize: Int
    public var stillLearningSlots: [Int]
    public var stillLearning: WeeklyKindLists
    /// Qualified rows in neither list: 「其他都做得好」 / 「其他仲學緊」.
    public var alsoWell: WeeklyKindLists
    public var alsoLearning: WeeklyKindLists
    public var insufficient: [WeeklyInsufficient]

    public var ranked: Bool { qualifiedQuiz + qualifiedPractice >= Self.minimumQualified }

    public func placement(kind: String, type: WeeklyRoundType) -> WeeklyPlacement {
        if top.contains(kind: kind, type: type) { return .top }
        if stillLearning.contains(kind: kind, type: type) { return .stillLearning }
        if alsoWell.contains(kind: kind, type: type) { return .alsoWell }
        if alsoLearning.contains(kind: kind, type: type) { return .alsoLearning }
        return .insufficient
    }

    // MARK: Rules

    /// §5.2, the cut-offs of the approved labels (perf-review-design §3.5) on this week only.
    public static func tier(type: WeeklyRoundType, estimate: PerfMastery.Estimate, zeroed: Int,
                            helpHeavy: Bool) -> WeeklyTier {
        let m = estimate.mastery
        if (m <= 0.35 && estimate.masteryHigh <= 0.55) || (type == .quiz && zeroed >= 2 && m < 0.70)
            || (type == .practice && helpHeavy && m < 0.70) {
            return .needsPractice
        }
        if m >= 0.70 && estimate.masteryLow >= 0.50 { return .goingWell }
        return .learning
    }

    /// T = min(5, ceil(E / 2)).
    public static func topSize(qualified: Int) -> Int {
        min(listSize, (max(0, qualified) + 1) / 2)
    }

    /// Largest remainder in integers; equal remainders go to the earlier entry (quiz).
    public static func largestRemainder(total: Int, weights: [Int]) -> [Int] {
        let sum = weights.reduce(0, +)
        guard total > 0, sum > 0 else { return weights.map { _ in 0 } }
        var slots = weights.map { total * $0 / sum }
        let remainders = weights.map { total * $0 % sum }
        let order = weights.indices.sorted { lhs, rhs in
            remainders[lhs] != remainders[rhs] ? remainders[lhs] > remainders[rhs] : lhs < rhs
        }
        var left = total - slots.reduce(0, +)
        for index in order where left > 0 {
            slots[index] += 1
            left -= 1
        }
        return slots
    }

    /// Takes up to each type's slots; spare slots go to the other type, quiz first.
    static func fill<Item>(slots: [Int], pools: [[Item]]) -> [[Item]] {
        var take = zip(slots, pools).map { pair in min(pair.0, pair.1.count) }
        var spare = slots.reduce(0, +) - take.reduce(0, +)
        for index in pools.indices where spare > 0 {
            let extra = min(spare, pools[index].count - take[index])
            take[index] += extra
            spare -= extra
        }
        return pools.indices.map { Array(pools[$0].prefix(take[$0])) }
    }

    /// Going well: lower bound high to low, then more rounds, a higher raw rate, catalog order.
    static func topOrder(_ lhs: WeeklyScore, _ rhs: WeeklyScore) -> Bool {
        if lhs.low != rhs.low { return lhs.low > rhs.low }
        if lhs.n != rhs.n { return lhs.n > rhs.n }
        let left = lhs.k * rhs.n, right = rhs.k * lhs.n
        if left != right { return left > right }
        return catalogOrder(lhs.kind, rhs.kind)
    }

    /// Still learning: upper bound low to high, then more rounds, a lower raw rate, catalog order.
    static func stillLearningOrder(_ lhs: WeeklyScore, _ rhs: WeeklyScore) -> Bool {
        if lhs.high != rhs.high { return lhs.high < rhs.high }
        if lhs.n != rhs.n { return lhs.n > rhs.n }
        let left = lhs.k * rhs.n, right = rhs.k * lhs.n
        if left != right { return left < right }
        return catalogOrder(lhs.kind, rhs.kind)
    }

    /// `ActivityCatalog.playableKinds` order; unknown kinds last, by UTF-8.
    static func catalogOrder(_ lhs: String, _ rhs: String) -> Bool {
        let left = WeeklyMetricsBuilder.catalogRank(lhs), right = WeeklyMetricsBuilder.catalogRank(rhs)
        if left != right { return left < right }
        return lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    /// Quiz before practice, then too few / one day / no method, then more rounds, catalog order.
    static func insufficientOrder(_ lhs: WeeklyInsufficient, _ rhs: WeeklyInsufficient) -> Bool {
        if lhs.type != rhs.type { return lhs.type == .quiz }
        let reasons = WeeklyInsufficientReason.allCases
        let left = reasons.firstIndex(of: lhs.reason) ?? 0, right = reasons.firstIndex(of: rhs.reason) ?? 0
        if left != right { return left < right }
        if lhs.n != rhs.n { return lhs.n > rhs.n }
        return catalogOrder(lhs.kind, rhs.kind)
    }

    /// §5.3. Every score lands in exactly one place (`placement(kind:type:)`).
    public static func rank(_ scores: [WeeklyScore]) -> WeeklyRanking {
        let qualified = scores.filter { $0.tier.isQualified }
        let pools = [qualified.filter { $0.type == .quiz }, qualified.filter { $0.type == .practice }]
        let weights = pools.map(\.count)

        let size = topSize(qualified: qualified.count)
        let topSlots = largestRemainder(total: size, weights: weights)
        let topPicked = fill(slots: topSlots, pools: pools.map { pool in
            pool.filter { $0.tier != .needsPractice }.sorted(by: Self.topOrder)
        })
        let top = WeeklyKindLists(quiz: topPicked[0].map(\.kind), practice: topPicked[1].map(\.kind))

        let candidates = pools.map { pool in
            pool.filter { score in
                !top.contains(kind: score.kind, type: score.type)
                    && (score.tier == .learning || score.tier == .needsPractice)
                    && score.daysPlayed >= minimumDays
            }.sorted(by: Self.stillLearningOrder)
        }
        let candidateCount = candidates[0].count + candidates[1].count
        let bottomSize = min(listSize, candidateCount)
        let bottomSlots = largestRemainder(total: bottomSize, weights: weights)
        let bottomPicked = fill(slots: bottomSlots, pools: candidates)
        let stillLearning = WeeklyKindLists(quiz: bottomPicked[0].map(\.kind), practice: bottomPicked[1].map(\.kind))

        var well: [[String]] = [[], []]
        var learning: [[String]] = [[], []]
        var insufficient: [WeeklyInsufficient] = []
        for (slot, pool) in pools.enumerated() {
            let rest = pool.filter {
                !top.contains(kind: $0.kind, type: $0.type) && !stillLearning.contains(kind: $0.kind, type: $0.type)
            }
            well[slot] = rest.filter { $0.tier == .goingWell }.sorted(by: Self.topOrder).map(\.kind)
            learning[slot] = rest.filter { $0.tier != .goingWell && $0.daysPlayed >= minimumDays }
                .sorted(by: Self.stillLearningOrder).map(\.kind)
            for score in rest where score.tier != .goingWell && score.daysPlayed < minimumDays {
                insufficient.append(WeeklyInsufficient(kind: score.kind, type: score.type, reason: .oneDay, n: score.n,
                                                       k: score.k, daysPlayed: score.daysPlayed))
            }
        }
        for score in scores where !score.tier.isQualified {
            insufficient.append(WeeklyInsufficient(kind: score.kind, type: score.type,
                                                   reason: score.tier == .noMethod ? .noMethod : .tooFew, n: score.n,
                                                   k: score.k, daysPlayed: score.daysPlayed))
        }
        insufficient.sort(by: Self.insufficientOrder)

        return WeeklyRanking(
            qualifiedQuiz: weights[0], qualifiedPractice: weights[1], topSize: size, topSlots: topSlots, top: top,
            stillLearningCandidates: candidateCount, stillLearningSize: bottomSize, stillLearningSlots: bottomSlots,
            stillLearning: stillLearning, alsoWell: WeeklyKindLists(quiz: well[0], practice: well[1]),
            alsoLearning: WeeklyKindLists(quiz: learning[0], practice: learning[1]), insufficient: insufficient
        )
    }
}

/// §5.4 `bot.stars`: ★★★ has ≥ 3 answered rounds and its right-first-time rate is ≥ 30 points
/// below ★ and ★★ together (quiz rows only).
public struct WeeklyStarRule: Sendable, Equatable {
    public static let minimumTopAnswered = 3

    public var k3: Int
    public var n3: Int
    public var k12: Int
    public var n12: Int

    public static func evaluate(_ row: WeeklyKindMetrics) -> WeeklyStarRule? {
        guard row.type == .quiz, row.stars.count == 3 else { return nil }
        let n3 = row.stars[2].answered, k3 = row.stars[2].firstTry
        let n12 = row.stars[0].answered + row.stars[1].answered
        let k12 = row.stars[0].firstTry + row.stars[1].firstTry
        // k12 / n12 − k3 / n3 ≥ 0.30, in integers.
        guard n3 >= minimumTopAnswered, n12 > 0, 10 * (k12 * n3 - k3 * n12) >= 3 * n12 * n3 else { return nil }
        return WeeklyStarRule(k3: k3, n3: n3, k12: k12, n12: n12)
    }
}

/// §5.5 fixed questions.
public enum WeeklyFixedQuestion {
    /// `flag.memorised` (perf-review-design §8.5): answered ≥ 10 and right first time ≥ 90 %.
    public static let memorisedMinimumAnswered = 10

    public static func isMemorised(k: Int, n: Int) -> Bool {
        n >= memorisedMinimumAnswered && 10 * k >= 9 * n
    }
}
