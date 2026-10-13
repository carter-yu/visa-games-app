import Foundation

/// Design §3.4–3.7 (v0.21.0): small-sample-safe mastery per game kind, labels, fuel-out
/// flag and the 7-day trend. Pure value code; the worked examples in §3.9 are test fixtures.
public enum PerfMastery {
    /// Decision 15A.
    public static let halfLifeDays = 7.0
    /// n0 pseudo-rounds in the Beta prior.
    public static let priorRounds = 4.0
    /// One-sided 80% normal quantile (P20 / P80).
    public static let z80 = 0.8416
    /// Decision 14A: fewer than 5 answered rounds → 未夠數據.
    public static let minimumRounds = 5
    /// Σw below this → data too old → 未夠數據.
    public static let minimumWeight = 3.0
    /// The pooled prior stays at 0.5 until the child has this much weighted data overall.
    public static let pooledMinimumWeight = 20.0

    /// 0.5 ^ (age / H). Age is HKT calendar days between the round and today.
    public static func weight(ageDays: Double, halfLife: Double = halfLifeDays) -> Double {
        pow(0.5, max(0, ageDays) / halfLife)
    }

    /// Clamp((x − c) / (1 − c), 0, 1).
    public static func chanceCorrected(_ x: Double, chance c: Double) -> Double {
        guard c < 1 else { return 0 }
        return min(max((x - c) / (1 - c), 0), 1)
    }

    /// Weighted first-try evidence for one kind.
    public struct Evidence: Equatable, Sendable {
        /// Answered rounds (unweighted), used for the 5-round minimum.
        public var rounds: Int
        /// Σ w_i · y_i.
        public var success: Double
        /// Σ w_i · (1 − y_i).
        public var failure: Double

        public init(rounds: Int = 0, success: Double = 0, failure: Double = 0) {
            self.rounds = rounds
            self.success = success
            self.failure = failure
        }

        public var weight: Double { success + failure }

        public mutating func add(ageDays: Double, firstTry: Bool, count: Int = 1) {
            guard count > 0 else { return }
            let w = PerfMastery.weight(ageDays: ageDays) * Double(count)
            rounds += count
            if firstTry { success += w } else { failure += w }
        }
    }

    public struct Estimate: Equatable, Sendable {
        public var chance: Double
        public var prior: Double
        public var alpha0: Double
        public var beta0: Double
        public var alpha: Double
        public var beta: Double
        /// Posterior mean p̂ (first-try right, with guessing).
        public var mean: Double
        public var sd: Double
        /// Chance-corrected mastery m̂, m20, m80.
        public var mastery: Double
        public var masteryLow: Double
        public var masteryHigh: Double
    }

    /// Beta–Binomial posterior with prior p0 = c + (1 − c)·m̄ and n0 pseudo-rounds.
    public static func estimate(chance c: Double, pooled mbar: Double, evidence: Evidence) -> Estimate {
        let p0 = c + (1 - c) * mbar
        let a0 = priorRounds * p0
        let b0 = priorRounds * (1 - p0)
        let a = a0 + evidence.success
        let b = b0 + evidence.failure
        let n = a + b
        let mean = a / n
        let sd = (a * b / (n * n * (n + 1))).squareRoot()
        let low = min(max(mean - z80 * sd, 0), 1)
        let high = min(max(mean + z80 * sd, 0), 1)
        return Estimate(
            chance: c, prior: p0, alpha0: a0, beta0: b0, alpha: a, beta: b, mean: mean, sd: sd,
            mastery: chanceCorrected(mean, chance: c),
            masteryLow: chanceCorrected(low, chance: c),
            masteryHigh: chanceCorrected(high, chance: c)
        )
    }

    /// m̄: the child's pooled chance-corrected first-try rate across kinds, weighted by Σw,
    /// clamped to [0.2, 0.8]; 0.5 while total Σw < 20.
    public static func pooledPrior(_ kinds: [(chance: Double, evidence: Evidence)]) -> Double {
        let total = kinds.reduce(0) { $0 + $1.evidence.weight }
        guard total >= pooledMinimumWeight else { return 0.5 }
        var sum = 0.0
        for entry in kinds where entry.evidence.weight > 0 {
            let rate = entry.evidence.success / entry.evidence.weight
            sum += entry.evidence.weight * chanceCorrected(rate, chance: entry.chance)
        }
        return min(max(sum / total, 0.2), 0.8)
    }

    public enum Label: String, Sendable, Equatable, CaseIterable {
        case practise
        case learning
        case confident
        case insufficient

        public var zh: String {
            switch self {
            case .confident: return "熟手"
            case .learning: return "學緊"
            case .practise: return "要多練"
            case .insufficient: return "未夠數據"
            }
        }

        public var en: String {
            switch self {
            case .confident: return "Confident"
            case .learning: return "Learning"
            case .practise: return "Practise more"
            case .insufficient: return "Not enough data yet"
            }
        }

        /// Review sort order (§8.4): 要多練, 學緊, 熟手, 未夠數據.
        public var sortRank: Int {
            switch self {
            case .practise: return 0
            case .learning: return 1
            case .confident: return 2
            case .insufficient: return 3
            }
        }
    }

    /// §3.5 + §3.6: the first matching rule wins.
    public static func label(evidence: Evidence, estimate: Estimate, fuelOutsInLastFive: Int) -> Label {
        if evidence.rounds < minimumRounds || evidence.weight < minimumWeight { return .insufficient }
        let m = estimate.mastery
        if (m <= 0.35 && estimate.masteryHigh <= 0.55) || (fuelOutsInLastFive >= 2 && m < 0.70) {
            return .practise
        }
        if m >= 0.70 && estimate.masteryLow >= 0.50 { return .confident }
        return .learning
    }

    /// 「仲差 n 次」.
    public static func roundsMissing(_ evidence: Evidence) -> Int {
        max(0, minimumRounds - evidence.rounds)
    }

    /// §3.6: shown when ≥ 2 fuel-outs among the last 5 rounds.
    public static func fuelOutFlag(lastOutcomes: [PerfRoundDot]) -> Int? {
        let fuelOuts = lastOutcomes.suffix(5).filter { $0 == .fuelOut }.count
        return fuelOuts >= 2 ? fuelOuts : nil
    }

    public enum Trend: String, Sendable, Equatable {
        case up, down, flat

        public var zh: String {
            switch self {
            case .up: return "近 7 日進步咗"
            case .down: return "近 7 日少咗答啱"
            case .flat: return "差唔多"
            }
        }

        public var arrow: String {
            switch self {
            case .up: return "↑"
            case .down: return "↓"
            case .flat: return "→"
            }
        }
    }

    /// §3.7: 7-day first-try rate against the previous 7 days; needs ≥ 3 rounds in each week.
    /// `ages` are HKT day ages of answered rounds with their first-try result.
    public static func trend(_ rounds: [(ageDays: Int, firstTry: Bool)]) -> Trend? {
        let recent = rounds.filter { $0.ageDays >= 0 && $0.ageDays < 7 }
        let previous = rounds.filter { $0.ageDays >= 7 && $0.ageDays < 14 }
        guard recent.count >= 3, previous.count >= 3 else { return nil }
        let r = Double(recent.filter(\.firstTry).count) / Double(recent.count)
        let p = Double(previous.filter(\.firstTry).count) / Double(previous.count)
        if r - p >= 0.2 - 1e-9 { return .up }
        if p - r >= 0.2 - 1e-9 { return .down }
        return .flat
    }
}

/// Trend dot for one round (§3.7).
public enum PerfRoundDot: String, Sendable, Equatable {
    /// ● right first time.
    case firstTry
    /// ◐ right after retries.
    case retried
    /// ○ fuel ran out.
    case fuelOut
    /// · unfinished.
    case unfinished

    public var glyph: String {
        switch self {
        case .firstTry: return "●"
        case .retried: return "◐"
        case .fuelOut: return "○"
        case .unfinished: return "·"
        }
    }
}
