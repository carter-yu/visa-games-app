import Foundation

/// Static facts about each catalog item for performance records (v0.20.0):
/// item id, chance level, screen slots, option assets and confusion tags (design §4.2).
/// Pure functions of the catalog and the round's deal seed — the same `presented*`
/// functions the child views use — so a recorded slot is the slot the child saw.
public enum PerfChoiceCatalog {
    /// Catalog `completionID` of the one item each kind deals today.
    public static func item(for kind: ActivityKind) -> String {
        switch kind {
        case .twoPictureChoose: return ActivityCatalog.twoPictureQuestion().completionID
        case .findTheSame: return ActivityCatalog.findSameQuestion().completionID
        case .countVehicles: return ActivityCatalog.countQuestion().completionID
        case .sequenceShortToLong: return ActivityCatalog.sequenceQuestion().completionID
        case .halfMatch: return ActivityCatalog.halfMatchQuestion().completionID
        case .shapeCousin: return ActivityCatalog.shapeCousinQuestion().completionID
        case .capacityCompare: return ActivityCatalog.capacityCompareQuestion().completionID
        case .moreFewer: return ActivityCatalog.moreFewerQuestion().completionID
        case .shadowMatch: return ActivityCatalog.shadowMatchQuestion().completionID
        case .emptyBay: return ActivityCatalog.emptyBayQuestion().completionID
        }
    }

    /// Chance of a first-try right answer by guessing (design §3.3).
    public static func chance(for kind: ActivityKind) -> Double {
        switch kind {
        case .twoPictureChoose, .capacityCompare, .moreFewer:
            return 0.5
        case .findTheSame, .countVehicles, .halfMatch, .shapeCousin, .shadowMatch, .emptyBay:
            return 1.0 / 3.0
        case .sequenceShortToLong:
            return 1.0 / 24.0
        }
    }

    /// Choice ids left-to-right as drawn for this deal seed.
    public static func slots(kind: ActivityKind, seed: String) -> [String] {
        switch kind {
        case .twoPictureChoose:
            return ActivityCatalog.twoPictureQuestion().presentedOptions(seed: seed).map(\.id)
        case .findTheSame:
            return ActivityCatalog.findSameQuestion().presentedOptions(seed: seed).map(\.id)
        case .countVehicles:
            return ActivityCatalog.countQuestion().presentedChoiceCounts(seed: seed).map { "count-\($0)" }
        case .sequenceShortToLong:
            return ActivityCatalog.sequenceQuestion().presentedAssetIDs(seed: seed)
        case .halfMatch:
            return ActivityCatalog.halfMatchQuestion().presentedOptions(seed: seed).map(\.id)
        case .shapeCousin:
            return ActivityCatalog.shapeCousinQuestion().presentedOptions(seed: seed).map(\.id)
        case .capacityCompare:
            return ActivityCatalog.capacityCompareQuestion().presentedOptions(seed: seed).map(\.id)
        case .moreFewer:
            return ActivityCatalog.moreFewerQuestion().presentedSides(seed: seed).map { "lot-\($0.rawValue)" }
        case .shadowMatch:
            return ActivityCatalog.shadowMatchQuestion().presentedOptions(seed: seed).map(\.id)
        case .emptyBay:
            return ActivityCatalog.emptyBayQuestion().presentedBays(seed: seed).map(\.id)
        }
    }

    /// Every selectable choice id of the kind's item, in catalog order.
    public static func allChoices(for kind: ActivityKind) -> [String] {
        switch kind {
        case .twoPictureChoose: return ActivityCatalog.twoPictureQuestion().options.map(\.id)
        case .findTheSame: return ActivityCatalog.findSameQuestion().options.map(\.id)
        case .countVehicles: return ActivityCatalog.countQuestion().choiceCounts.map { "count-\($0)" }
        case .sequenceShortToLong: return ActivityCatalog.sequenceQuestion().orderedAssetIDs
        case .halfMatch: return ActivityCatalog.halfMatchQuestion().options.map(\.id)
        case .shapeCousin: return ActivityCatalog.shapeCousinQuestion().options.map(\.id)
        case .capacityCompare: return ActivityCatalog.capacityCompareQuestion().options.map(\.id)
        case .moreFewer: return ["lot-left", "lot-right"]
        case .shadowMatch: return ActivityCatalog.shadowMatchQuestion().options.map(\.id)
        case .emptyBay: return ActivityCatalog.emptyBayQuestion().bays.map(\.id)
        }
    }

    /// The right answer's choice id. Sequence has no single right choice (nil).
    public static func correctChoice(for kind: ActivityKind) -> String? {
        switch kind {
        case .twoPictureChoose: return ActivityCatalog.twoPictureQuestion().correctOptionID
        case .findTheSame: return ActivityCatalog.findSameQuestion().correctOptionID
        case .countVehicles: return "count-\(ActivityCatalog.countQuestion().correctCount)"
        case .sequenceShortToLong: return nil
        case .halfMatch: return ActivityCatalog.halfMatchQuestion().correctOptionID
        case .shapeCousin: return ActivityCatalog.shapeCousinQuestion().correctOptionID
        case .capacityCompare: return ActivityCatalog.capacityCompareQuestion().correctOptionID
        case .moreFewer: return "lot-\(ActivityCatalog.moreFewerQuestion().correctSide.rawValue)"
        case .shadowMatch: return ActivityCatalog.shadowMatchQuestion().correctOptionID
        case .emptyBay: return ActivityCatalog.emptyBayQuestion().correctBayID
        }
    }

    /// Picture asset behind a choice. Nil for numerals and parking lots.
    public static func asset(kind: ActivityKind, choice: String) -> String? {
        func option(_ options: [ActivityOption]) -> String? {
            options.first { $0.id == choice }?.assetID
        }
        switch kind {
        case .twoPictureChoose: return option(ActivityCatalog.twoPictureQuestion().options)
        case .findTheSame: return option(ActivityCatalog.findSameQuestion().options)
        case .countVehicles: return nil
        case .sequenceShortToLong:
            return ActivityCatalog.sequenceQuestion().orderedAssetIDs.contains(choice) ? choice : nil
        case .halfMatch: return option(ActivityCatalog.halfMatchQuestion().options)
        case .shapeCousin: return option(ActivityCatalog.shapeCousinQuestion().options)
        case .capacityCompare: return option(ActivityCatalog.capacityCompareQuestion().options)
        case .moreFewer: return nil
        case .shadowMatch: return option(ActivityCatalog.shadowMatchQuestion().options)
        case .emptyBay:
            guard let bay = ActivityCatalog.emptyBayQuestion().bays.first(where: { $0.id == choice }) else {
                return nil
            }
            return bay.vehicleAssetID ?? "empty"
        }
    }

    /// Static confusion tags of a wrong option (design §4.2). Correct options have none.
    /// Sequence tags depend on the tap context: use `sequenceTags`.
    public static func tags(kind: ActivityKind, choice: String) -> [String] {
        switch (kind, choice) {
        case (.twoPictureChoose, "opt-hktaxi"): return ["same_color", "shorter"]
        case (.findTheSame, "find-nytaxi"): return ["same_shape", "diff_color"]
        case (.findTheSame, "find-fire"): return ["same_color", "diff_shape", "longer"]
        case (.countVehicles, "count-2"): return ["under_by_1"]
        case (.countVehicles, "count-4"): return ["over_by_1"]
        case (.halfMatch, "half-bus"): return ["same_color", "long_vehicle"]
        case (.halfMatch, "half-tanker"): return ["diff_color", "diff_shape"]
        case (.shapeCousin, "shape-cone"): return ["triangle", "warm_color"]
        case (.shapeCousin, "shape-toolbox"): return ["rectangle", "warm_color"]
        case (.capacityCompare, "cap-taxi"): return ["smaller"]
        case (.moreFewer, "lot-left"): return ["fewer", "smaller_vehicles"]
        case (.shadowMatch, "shadow-fire"): return ["long_vehicle"]
        case (.shadowMatch, "shadow-truck"): return ["boxy_outline"]
        case (.emptyBay, "bay-a"), (.emptyBay, "bay-c"): return ["occupied", "vehicle_attraction"]
        default: return []
        }
    }

    /// Wrong convoy tap: `rank_error:<signed>`, `longest_first` when the first tap is the
    /// longest vehicle, `screen_order` when the tapped card was the leftmost untapped slot.
    public static func sequenceTags(
        tapped: String,
        expected: String?,
        tappedSoFar: [String],
        presented: [String]
    ) -> [String] {
        let order = ActivityCatalog.sequenceQuestion().orderedAssetIDs
        guard let expected, tapped != expected,
              let tappedRank = order.firstIndex(of: tapped),
              let expectedRank = order.firstIndex(of: expected) else { return [] }
        var tags = ["rank_error:\(tappedRank - expectedRank)"]
        if tappedSoFar.isEmpty, tapped == order.last { tags.append("longest_first") }
        if let leftmost = presented.first(where: { !tappedSoFar.contains($0) }), leftmost == tapped {
            tags.append("screen_order")
        }
        return tags
    }
}

/// Picker page / slot arithmetic (4×2 pages of `VideoPickerDeck.pageSize`).
public enum PerfPickerPlacement {
    /// (page, slot) for a deck index. Slot is row-major 0–7 on the 4×2 page.
    public static func placement(deckIndex: Int, pageSize: Int = VideoPickerDeck.pageSize) -> (page: Int, slot: Int)? {
        guard deckIndex >= 0, pageSize > 0 else { return nil }
        return (deckIndex / pageSize, deckIndex % pageSize)
    }

    /// Ids fully drawn on `page` (the 15% peek of the next page is not an impression).
    public static func ids(deck: [String], page: Int, pageSize: Int = VideoPickerDeck.pageSize) -> [String] {
        VideoPickerDeck.page(deck, index: page, pageSize: pageSize)
    }
}
