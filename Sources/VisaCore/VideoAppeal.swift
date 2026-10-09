import Foundation

/// Design §7.3–7.4 (v0.21.0): exposure-adjusted appeal and video labels. Labels come only from
/// picks (O) and exposure (E); watching outcomes (finishes, time-up stops, minutes) never
/// change a label (decision 8, replaced by Carter).
public enum PerfVideoAppeal {
    /// Below this, π = 1 for every slot.
    public static let slotModelMinimumPicks = 30
    public static let enoughExpected = 2.5
    public static let windowDays = 30

    /// (O + 1) / (E + 1): 1.0 = as expected, 2.0 = twice as often.
    public static func appeal(observed: Int, expected: Double) -> Double {
        (Double(observed) + 1) / (max(0, expected) + 1)
    }

    /// One picker cell: page (0 = first page, 1 = any later page) × slot 0–7.
    public struct Cell: Hashable, Sendable {
        public var laterPage: Bool
        public var slot: Int

        public init(page: Int, slot: Int) {
            self.laterPage = page > 0
            self.slot = slot
        }
    }

    /// π(slot, page): 1 everywhere until `slotModelMinimumPicks` picks exist; then the
    /// smoothed pick rate of the cell, (picks + 1) / (impressions + 1).
    public struct SlotModel: Sendable, Equatable {
        public var picks: [Cell: Int]
        public var impressions: [Cell: Int]

        public init(picks: [Cell: Int] = [:], impressions: [Cell: Int] = [:]) {
            self.picks = picks
            self.impressions = impressions
        }

        public var totalPicks: Int { picks.values.reduce(0, +) }

        public func weight(_ cell: Cell) -> Double {
            guard totalPicks >= PerfVideoAppeal.slotModelMinimumPicks else { return 1 }
            return (Double(picks[cell] ?? 0) + 1) / (Double(impressions[cell] ?? 0) + 1)
        }
    }

    /// e_v for every card shown before the pick: π(v) / Σ π(u).
    public static func expectedShares(shown: [(video: String, cell: Cell)], model: SlotModel) -> [String: Double] {
        var weights: [String: Double] = [:]
        for card in shown {
            // A card seen on two pages counts once, with its best spot.
            weights[card.video] = max(weights[card.video] ?? 0, model.weight(card.cell))
        }
        let total = weights.values.reduce(0, +)
        guard total > 0 else { return [:] }
        return weights.mapValues { $0 / total }
    }

    public enum Label: String, Sendable, Equatable, CaseIterable {
        case favourite
        case sometimes
        case rare
        case seenNever
        case insufficient
        case notShown

        public var zh: String {
            switch self {
            case .favourite: return "好鍾意"
            case .sometimes: return "間中揀"
            case .rare: return "少揀"
            case .seenNever: return "見過未揀過"
            case .insufficient: return "未夠數據"
            case .notShown: return "未出過"
            }
        }

        public var en: String {
            switch self {
            case .favourite: return "Picked often"
            case .sometimes: return "Sometimes"
            case .rare: return "Rarely picked"
            case .seenNever: return "Seen, never picked"
            case .insufficient: return "Not enough data yet"
            case .notShown: return "Not shown yet"
            }
        }
    }

    /// §7.4: the first matching rule wins.
    public static func label(impressions: Int, observed: Int, expected: Double) -> Label {
        if impressions == 0 { return .notShown }
        if observed == 0 && expected >= enoughExpected { return .seenNever }
        if expected < enoughExpected { return .insufficient }
        let a = appeal(observed: observed, expected: expected)
        if a <= 0.4 && expected >= 3 { return .rare }
        if a >= 2.0 && observed >= 4 { return .favourite }
        return .sometimes
    }
}
