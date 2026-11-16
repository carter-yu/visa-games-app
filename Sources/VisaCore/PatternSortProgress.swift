import Foundation

// patterns-sorting P0 (design §3.2, §4.2, §4.3, §5.2, §5.3, D4): the within-tier step ladder of the three quiz
// cards, its eligibility under the settings, and the automatic read-through rule. The star stays the tier (D1
// rule) and visa minutes are untouched; a parent playtest reads the child's step but never writes it.

/// A step of a tier: `L2.b` (also the `ladder_step` deal field; not `step`, which the convoy's answers use).
public struct PatternSortStep: Hashable, Sendable, Codable, Comparable {
    public let level: ActivityLevel
    /// 0 = a, 1 = b, 2 = c.
    public let index: Int

    public init(_ level: ActivityLevel, _ index: Int) {
        self.level = level
        self.index = index
    }

    public var letter: String { ["a", "b", "c"][min(max(index, 0), 2)] }
    public var code: String { "\(level.code).\(letter)" }

    public init?(code: String) {
        let parts = code.split(separator: ".").map(String.init)
        guard parts.count == 2, parts[0].count == 2, parts[0].hasPrefix("L"),
              let raw = Int(parts[0].dropFirst()), let level = ActivityLevel(rawValue: raw),
              let index = ["a", "b", "c"].firstIndex(of: parts[1]) else { return nil }
        self.init(level, index)
    }

    public static func < (lhs: PatternSortStep, rhs: PatternSortStep) -> Bool {
        (lhs.level, lhs.index) < (rhs.level, rhs.index)
    }
}

/// The step tables of design §3.2 (接落去), §4.2 (邊個唔同類) and §4.3 (分車房).
public enum PatternSortLadder {
    /// The tier's steps in order (自己排 has none: practice, pinned).
    public static func steps(_ kind: ActivityKind, _ level: ActivityLevel) -> [PatternSortStep] {
        let count: Int
        switch kind {
        case .patternNext: count = level == .l1 ? 2 : 3
        case .oddOneOut: count = 3
        case .sortGarages: count = 2
        default: count = 0
        }
        return (0..<count).map { PatternSortStep(level, $0) }
    }

    /// The 分類方法 a step needs, one of (design §4.2 / §4.3 "Needs method"). 接落去 steps exist for both materials,
    /// so they need none.
    public static func needs(_ kind: ActivityKind, _ step: PatternSortStep) -> [PatternSortMethod] {
        switch (kind, step.level, step.index) {
        case (.oddOneOut, .l1, 0): return [.colour]
        case (.oddOneOut, .l1, 1): return [.size]
        case (.oddOneOut, .l1, 2): return [.shape]
        case (.oddOneOut, .l2, 0): return [.kind]
        case (.oddOneOut, .l2, 1): return [.group]
        case (.oddOneOut, .l2, 2): return [.colour, .size, .shape]
        case (.oddOneOut, .l3, 0): return [.group]
        case (.oddOneOut, .l3, 1): return [.colour, .size, .shape]
        case (.oddOneOut, .l3, 2): return [.facing]
        case (.sortGarages, .l1, 0): return [.colour, .shape, .kind]
        case (.sortGarages, .l1, 1): return [.size]
        case (.sortGarages, .l2, 0): return [.kind, .shape, .group]
        case (.sortGarages, .l2, 1): return [.colour, .size]
        case (.sortGarages, .l3, 0): return [.colour, .size, .shape, .kind]
        case (.sortGarages, .l3, 1): return [.group]
        default: return []
        }
    }

    /// A step is eligible when one of the methods it needs is on (接落去: always).
    public static func isEligible(_ kind: ActivityKind, _ step: PatternSortStep, methods: Set<PatternSortMethod>) -> Bool {
        kind == .patternNext || needs(kind, step).contains(where: methods.contains)
    }

    public static func eligibleSteps(_ kind: ActivityKind, _ level: ActivityLevel,
                                     methods: Set<PatternSortMethod>) -> [PatternSortStep] {
        steps(kind, level).filter { isEligible(kind, $0, methods: methods) }
    }

    /// Empty-pool guard (design §5.3): the tier's 形狀 step, because blocks can always be drawn.
    public static func shapeFallback(_ kind: ActivityKind, _ level: ActivityLevel) -> PatternSortStep {
        switch (kind, level) {
        case (.oddOneOut, .l1): return PatternSortStep(.l1, 2)
        case (.oddOneOut, .l2): return PatternSortStep(.l2, 2)
        case (.oddOneOut, .l3): return PatternSortStep(.l3, 1)
        default: return PatternSortStep(level, 0)
        }
    }
}

/// How a finished round moves the ladder (design §5.3). Abandoned rounds are not recorded.
public enum PatternSortRoundOutcome: String, Sendable, Equatable {
    /// Solved with no miss.
    case firstTry
    /// Solved after a miss, without the hint.
    case solved
    /// Solved only after the hint.
    case hinted
    /// Out of fuel (back to the depot).
    case fuelOut
}

/// One (card, tier): the stored step and its two runs, bound to the step that earned them.
public struct PatternSortTierProgress: Codable, Equatable, Sendable {
    public var step: Int
    /// The step index the two runs were earned at (nil: no run yet). With skipping, a round can be dealt at another
    /// step than `step`; a round at any other step than `runStep` starts both runs over (astra R1).
    public var runStep: Int?
    public var firstTryRun: Int
    public var hintedRun: Int
    public var lastPlayed: Date?

    public init(step: Int = 0, runStep: Int? = nil, firstTryRun: Int = 0, hintedRun: Int = 0, lastPlayed: Date? = nil) {
        self.step = step
        self.runStep = runStep
        self.firstTryRun = firstTryRun
        self.hintedRun = hintedRun
        self.lastPlayed = lastPlayed
    }
}

/// `VisaGames.patternSortProgress.v1`: the step ladder of every quiz card × tier.
public struct PatternSortProgress: Codable, Equatable, Sendable {
    /// 2 first-try rounds in a row: the 識咗 constant (`TapCountGuideData`), re-declared here, not shared.
    public static let upAfter = 2
    /// 2 rounds in a row solved only after a hint.
    public static let downAfterHinted = 2
    /// After 14 days without the card, one step back, once (warm-up).
    public static let warmUpDays = 14.0

    public var tiers: [String: PatternSortTierProgress]

    public init(tiers: [String: PatternSortTierProgress] = [:]) { self.tiers = tiers }

    public static func key(_ kind: ActivityKind, _ level: ActivityLevel) -> String { "\(kind.rawValue).\(level.code)" }

    public func state(_ kind: ActivityKind, _ level: ActivityLevel) -> PatternSortTierProgress {
        tiers[Self.key(kind, level)] ?? PatternSortTierProgress()
    }

    /// Design §5.3 skipping: the stored step if eligible, else the nearest eligible step below it, else above.
    /// Nil only with no eligible step (the caller then uses `PatternSortLadder.shapeFallback`).
    public func liveStep(_ kind: ActivityKind, _ level: ActivityLevel, methods: Set<PatternSortMethod>) -> PatternSortStep? {
        let all = PatternSortLadder.steps(kind, level)
        guard !all.isEmpty else { return nil }
        let stored = min(max(state(kind, level).step, 0), all.count - 1)
        let eligible = { (index: Int) in PatternSortLadder.isEligible(kind, all[index], methods: methods) }
        if eligible(stored) { return all[stored] }
        if let below = (0..<stored).reversed().first(where: eligible) { return all[below] }
        if let above = (stored + 1..<all.count).first(where: eligible) { return all[above] }
        return nil
    }

    /// Design §5.2: whether a round dealt now at `step` (the live step, or the 形狀 fallback) gets the automatic
    /// read-through (written as `read_through`). 多啲 always; 少啲 never; 標準 until that step's own first-try run
    /// reaches 2 (a run earned at another step never counts).
    public func readThrough(_ kind: ActivityKind, _ step: PatternSortStep, guidance: TapCountGuidanceLevel) -> Bool {
        switch guidance {
        case .more: return true
        case .less: return false
        case .standard:
            let tier = state(kind, step.level)
            return tier.runStep != step.index || tier.firstTryRun < Self.upAfter
        }
    }

    /// The child's deal after a long gap: one eligible step back, once (`lastPlayed` moves to `now`).
    @discardableResult
    public mutating func warmUp(_ kind: ActivityKind, _ level: ActivityLevel, methods: Set<PatternSortMethod>,
                                now: Date) -> Bool {
        var tier = state(kind, level)
        guard let last = tier.lastPlayed, now.timeIntervalSince(last) >= Self.warmUpDays * 86_400,
              let live = liveStep(kind, level, methods: methods) else { return false }
        tier.lastPlayed = now
        if let below = neighbour(of: live, kind: kind, methods: methods, up: false) {
            tier.step = below.index
            tier.runStep = nil
            tier.firstTryRun = 0
            tier.hintedRun = 0
        }
        tiers[Self.key(kind, level)] = tier
        return true
    }

    /// A finished child round, recorded at the step it was dealt at, under the 分類方法 it was dealt with (`methods`:
    /// the settings at deal, so a change during the round applies from the next deal through skipping). Up after 2
    /// first-try rounds in a row at that step, down after a fuel-out or 2 hinted rounds in a row there, always to the
    /// next / previous eligible step of the same tier. A step the settings did not make eligible (the 形狀 fallback)
    /// only stamps `lastPlayed`. A playtest never calls this.
    public mutating func record(_ kind: ActivityKind, _ step: PatternSortStep, outcome: PatternSortRoundOutcome,
                                methods: Set<PatternSortMethod>, now: Date) {
        let level = step.level
        var tier = state(kind, level)
        tier.lastPlayed = now
        guard PatternSortLadder.steps(kind, level).contains(step),
              PatternSortLadder.isEligible(kind, step, methods: methods) else {
            tiers[Self.key(kind, level)] = tier
            return
        }
        let live = step
        if tier.runStep != step.index {
            tier.runStep = step.index
            tier.firstTryRun = 0
            tier.hintedRun = 0
        }
        var move: Bool? = nil
        switch outcome {
        case .firstTry:
            tier.firstTryRun += 1
            tier.hintedRun = 0
            if tier.firstTryRun >= Self.upAfter { move = true }
        case .solved:
            tier.firstTryRun = 0
            tier.hintedRun = 0
        case .hinted:
            tier.firstTryRun = 0
            tier.hintedRun += 1
            if tier.hintedRun >= Self.downAfterHinted { move = false }
        case .fuelOut:
            tier.firstTryRun = 0
            move = false
        }
        if let up = move {
            tier.step = live.index
            if let next = neighbour(of: live, kind: kind, methods: methods, up: up) {
                tier.step = next.index
                tier.runStep = nil
                tier.firstTryRun = 0
                tier.hintedRun = 0
            } else if !up {
                tier.hintedRun = 0
            }
        }
        tiers[Self.key(kind, level)] = tier
    }

    /// 由頭開始 (`sort_progress` / `pattern_progress` reset): every tier of `kinds` back to its first step.
    public mutating func reset(_ kinds: [ActivityKind]) {
        for kind in kinds { for level in ActivityLevel.allCases { tiers[Self.key(kind, level)] = nil } }
    }

    private func neighbour(of step: PatternSortStep, kind: ActivityKind, methods: Set<PatternSortMethod>,
                           up: Bool) -> PatternSortStep? {
        let all = PatternSortLadder.steps(kind, step.level)
        let indices = up ? Array(step.index + 1..<all.count) : Array((0..<step.index).reversed())
        return indices.map { all[$0] }.first { PatternSortLadder.isEligible(kind, $0, methods: methods) }
    }
}

/// Fail-closed store: a missing, broken or old blob loads an empty ladder (every tier at its first step).
public struct PatternSortProgressStore {
    public static let key = "VisaGames.patternSortProgress.v1"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> PatternSortProgress {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(PatternSortProgress.self, from: data) else { return PatternSortProgress() }
        return value
    }

    public func save(_ value: PatternSortProgress) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.key) }
    }
}
