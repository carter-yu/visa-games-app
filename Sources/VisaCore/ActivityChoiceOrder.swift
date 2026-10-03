import Foundation

/// Presentation order for one dealt question.
/// Correct-answer identity stays on the question. Only the slot order changes.
/// The permutation is a pure function of `(items, seed)` via `SeededGenerator`
/// (not the process-global random source), so a SwiftUI refresh or a wrong tap
/// cannot reshuffle as long as the deal seed stays put.
public enum ActivityChoiceOrder {
    public static func shuffled<T>(_ items: [T], using rng: inout some RandomNumberGenerator) -> [T] {
        var copy = items
        guard copy.count > 1 else { return copy }
        for index in stride(from: copy.count - 1, through: 1, by: -1) {
            let swap = Int.random(in: 0...index, using: &rng)
            copy.swapAt(index, swap)
        }
        return copy
    }

    /// Same seed and items always return the same order.
    public static func shuffled<T>(_ items: [T], seed: String) -> [T] {
        var rng = SeededGenerator(seed: seedValue(seed))
        return shuffled(items, using: &rng)
    }

    /// FNV-1a 64. Stable across launches. Zero is left for `SeededGenerator` to remap.
    public static func seedValue(_ seed: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

extension TwoPictureQuestion {
    public func presentedOptions(seed: String) -> [ActivityOption] {
        ActivityChoiceOrder.shuffled(options, seed: "twoPicture|\(seed)")
    }
}

extension FindSameQuestion {
    public func presentedOptions(seed: String) -> [ActivityOption] {
        ActivityChoiceOrder.shuffled(options, seed: "findSame|\(seed)")
    }
}

extension CountQuestion {
    /// Number buttons are separate slots, not an ascending number line.
    public func presentedChoiceCounts(seed: String) -> [Int] {
        ActivityChoiceOrder.shuffled(choiceCounts, seed: "count|\(seed)")
    }
}

extension SequenceQuestion {
    /// Starting slots only. `orderedAssetIDs` remains the short→long tap order.
    public func presentedAssetIDs(seed: String) -> [String] {
        ActivityChoiceOrder.shuffled(orderedAssetIDs, seed: "sequence|\(seed)")
    }
}

extension HalfMatchQuestion {
    public func presentedOptions(seed: String) -> [ActivityOption] {
        ActivityChoiceOrder.shuffled(options, seed: "halfMatch|\(seed)")
    }
}

extension ShapeCousinQuestion {
    public func presentedOptions(seed: String) -> [ActivityOption] {
        ActivityChoiceOrder.shuffled(options, seed: "shapeCousin|\(seed)")
    }
}

extension CapacityCompareQuestion {
    public func presentedOptions(seed: String) -> [ActivityOption] {
        ActivityChoiceOrder.shuffled(options, seed: "capacity|\(seed)")
    }
}

extension MoreFewerQuestion {
    /// Which lot is drawn first. `correctSide` still names the lot, not the screen slot.
    public func presentedSides(seed: String) -> [ParkingLotSide] {
        ActivityChoiceOrder.shuffled([ParkingLotSide.left, .right], seed: "moreFewer|\(seed)")
    }
}

extension ShadowMatchQuestion {
    public func presentedOptions(seed: String) -> [ActivityOption] {
        ActivityChoiceOrder.shuffled(options, seed: "shadow|\(seed)")
    }
}

extension EmptyBayQuestion {
    public func presentedBays(seed: String) -> [EmptyBaySlot] {
        ActivityChoiceOrder.shuffled(bays, seed: "emptyBay|\(seed)")
    }
}
