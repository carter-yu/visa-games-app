import Foundation

/// Question tier (design §1.1, D1 locked by Carter 2026-10-13: option A).
/// The ticket's stars are also the question tier: ★ = L1 入門, ★★ = L2 學緊, ★★★ = L3 挑戰.
/// Visa length per star is unchanged (5 / 10 / 15 minutes, `ChildDifficulty`).
public enum ActivityLevel: Int, CaseIterable, Sendable, Codable, Hashable, Comparable {
    case l1 = 1, l2 = 2, l3 = 3

    /// Out-of-range stars clamp (0 = a deal without a ticket → L1).
    public init(stars: Int) {
        self = ActivityLevel(rawValue: min(max(stars, 1), 3)) ?? .l1
    }

    public init(_ difficulty: ChildDifficulty) {
        self.init(stars: difficulty.rawValue)
    }

    /// "L1" / "L2" / "L3" — used in item ids and logs.
    public var code: String { "L\(rawValue)" }

    /// Parent-facing star string (★ / ★★ / ★★★).
    public var stars: String { String(repeating: "★", count: rawValue) }

    /// L1 → L2 → L3 → L1 (parent playtest walks the tiers).
    public var cycled: ActivityLevel { ActivityLevel(rawValue: rawValue % 3 + 1) ?? .l1 }

    public static func < (lhs: ActivityLevel, rhs: ActivityLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Deterministic randomness for question generators (design §1.4).
/// FNV-1a of `salt|seed` → SplitMix64 (`SeededGenerator`). Bounded integers use our own
/// rejection sampling instead of `Int.random(in:using:)`, so a toolchain update cannot change
/// which question a recorded seed regenerates. Never touches the process-global random source.
public struct QuestionRNG: RandomNumberGenerator, Sendable {
    private var base: SeededGenerator

    public init(seed: String, salt: String) {
        base = SeededGenerator(seed: ActivityChoiceOrder.seedValue("\(salt)|\(seed)"))
    }

    public mutating func next() -> UInt64 { base.next() }

    /// Uniform in `0..<bound` (unbiased).
    public mutating func below(_ bound: Int) -> Int {
        precondition(bound > 0, "QuestionRNG.below needs a positive bound")
        let b = UInt64(bound)
        // 2^64 mod b; values at or above 2^64 - r would bias the low residues.
        let r = (UInt64.max % b &+ 1) % b
        if r == 0 { return Int(next() % b) }
        let limit = 0 &- r
        while true {
            let value = next()
            if value < limit { return Int(value % b) }
        }
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + below(range.upperBound - range.lowerBound + 1)
    }

    public mutating func pick<T>(_ items: [T]) -> T {
        items[below(items.count)]
    }

    /// Fisher–Yates with `below`.
    public mutating func shuffled<T>(_ items: [T]) -> [T] {
        var copy = items
        guard copy.count > 1 else { return copy }
        for index in stride(from: copy.count - 1, through: 1, by: -1) {
            copy.swapAt(index, below(index + 1))
        }
        return copy
    }

    /// `count` distinct elements in random order.
    public mutating func sample<T>(_ items: [T], count: Int) -> [T] {
        Array(shuffled(items).prefix(max(0, count)))
    }

    /// Uniform double in `-1...1` (layout jitter).
    public mutating func signedUnit() -> Double {
        Double(below(2_001) - 1_000) / 1_000
    }
}

/// Design §1.4: a question is a pure function of `(seed, level, avoidingItem)`, so the
/// performance recorder can rebuild exactly what the child saw from the round seed.
public protocol ActivityQuestionGenerator {
    associatedtype Question
    static var kind: ActivityKind { get }
    static func make(seed: String, level: ActivityLevel, avoidingItem: String?) -> Question
    static func itemID(of question: Question) -> String
}

extension ActivityQuestionGenerator {
    /// Same kind never deals the same item twice in a row (§1.4 `avoidingItem`).
    /// Re-rolls on a derived seed; bounded so a degenerate pool still deals.
    static func avoiding(seed: String, avoidingItem: String?, build: (String) -> Question) -> Question {
        var question = build(seed)
        guard let avoidingItem else { return question }
        var attempt = 0
        while itemID(of: question) == avoidingItem, attempt < QuestionGeneration.maxRerolls {
            attempt += 1
            question = build("\(seed)#\(attempt)")
        }
        return question
    }
}

/// Which question source dealt a round. Written to `game_dealt.gen` so rounds dealt from
/// one fixed catalog item (v0.7 – v0.21) stay separable from generated variants (design §7, D9).
public enum QuestionGeneration {
    /// One fixed catalog item per kind. Also what an old `game_dealt` line without `gen` means.
    public static let fixed = "fixed_v0"
    /// Seeded variants with ★-tier levels (v0.22.0, design §7).
    public static let variants = "variants_v1"
    /// Kinds whose questions come from a generator in this version.
    public static let generatedKinds: [ActivityKind] = [.countVehicles, .findTheSame, .lineMatchGuidedStraight, .lineMatchGuidedBridge, .lineMatch]

    public static let maxRerolls = 8

    public static func isGenerated(_ kind: ActivityKind) -> Bool {
        generatedKinds.contains(kind)
    }
}
