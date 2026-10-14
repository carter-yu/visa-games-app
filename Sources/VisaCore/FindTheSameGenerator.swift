import Foundation

/// Generated facts behind a find-the-same question (nil on the fixed v0 catalog item).
public struct FindSameVariant: Sendable, Codable, Equatable {
    public var level: ActivityLevel
    public var target: VehicleLook
    /// Stable item id, e.g. `findTheSame.L2.hkTaxi.vs.fireEngine-nyTaxi` (design §1.4).
    public var itemID: String
    public var hintTraditionalChinese: String

    public init(level: ActivityLevel, target: VehicleLook, itemID: String, hintTraditionalChinese: String) {
        self.level = level
        self.target = target
        self.itemID = itemID
        self.hintTraditionalChinese = hintTraditionalChinese
    }
}

/// findTheSame variants (design §7) with progressive distractor similarity by ★ tier.
/// Hero PNGs only (no recolouring), so colour comes with the vehicle type.
///
/// - L1: both distractors share neither paint nor body family with the target ("far apart").
/// - L2: each distractor shares exactly one of paint / body (同色唔同款 or 同款唔同色).
/// - L3: all three are the target's vehicle; each distractor differs in exactly one detail
///   (facing, or the star / flag sticker).
///
/// Every tier: exactly one option equals the target, all options are distinct, and the
/// lookalike pair (yellow taxi / yellow toy car) is never in one question.
public enum FindTheSameGenerator: ActivityQuestionGenerator {
    public static let kind: ActivityKind = .findTheSame
    public static let optionCount = 3

    /// One dealable item: target plus two distractors (unordered; slots shuffle separately).
    public struct Item: Sendable, Equatable {
        public var level: ActivityLevel
        public var target: VehicleLook
        public var distractors: [VehicleLook]

        public var itemID: String {
            let others = distractors.map(\.code).sorted().joined(separator: "-")
            return "findTheSame.\(level.code).\(target.code).vs.\(others)"
        }
    }

    public static func make(seed: String, level: ActivityLevel, avoidingItem: String?) -> FindSameQuestion {
        avoiding(seed: seed, avoidingItem: avoidingItem) { build(seed: $0, level: level) }
    }

    public static func itemID(of question: FindSameQuestion) -> String {
        question.variant?.itemID ?? question.completionID
    }

    /// Every item of a tier (enumerated once; the deal picks one uniformly by seed).
    public static func items(_ level: ActivityLevel) -> [Item] {
        switch level {
        case .l1: return l1Items
        case .l2: return l2Items
        case .l3: return l3Items
        }
    }

    static let l1Items: [Item] = heroItems(level: .l1) { $0.sharedSalientFeatures(with: $1) == 0 }
    static let l2Items: [Item] = heroItems(level: .l2) { $0.sharedSalientFeatures(with: $1) == 1 }
    static let l3Items: [Item] = detailItems()

    /// L1 / L2: plain heroes; `related(target, candidate)` says which distractors fit the tier.
    private static func heroItems(level: ActivityLevel,
                                  related: (HeroVehicle, HeroVehicle) -> Bool) -> [Item] {
        var result: [Item] = []
        let all = HeroVehicle.allCases
        for target in all {
            let candidates = all.filter { $0 != target && !$0.isLookalike(of: target) && related(target, $0) }
            for i in candidates.indices {
                for j in candidates.indices where j > i {
                    let a = candidates[i]
                    let b = candidates[j]
                    guard !a.isLookalike(of: b) else { continue }
                    result.append(Item(level: level, target: VehicleLook(vehicle: target),
                                       distractors: [VehicleLook(vehicle: a), VehicleLook(vehicle: b)]))
                }
            }
        }
        return result
    }

    /// L3: same vehicle; each distractor is one detail away from the target.
    private static func detailItems() -> [Item] {
        let decors: [VehicleDecor?] = [nil] + VehicleDecor.allCases.map { Optional($0) }
        var result: [Item] = []
        for vehicle in HeroVehicle.allCases {
            for mirrored in [false, true] {
                for decor in decors {
                    let target = VehicleLook(vehicle: vehicle, mirrored: mirrored, decor: decor)
                    var neighbours = [VehicleLook(vehicle: vehicle, mirrored: !mirrored, decor: decor)]
                    for other in decors where other != decor {
                        neighbours.append(VehicleLook(vehicle: vehicle, mirrored: mirrored, decor: other))
                    }
                    for i in neighbours.indices {
                        for j in neighbours.indices where j > i {
                            result.append(Item(level: .l3, target: target, distractors: [neighbours[i], neighbours[j]]))
                        }
                    }
                }
            }
        }
        return result
    }

    static func build(seed: String, level: ActivityLevel) -> FindSameQuestion {
        var rng = QuestionRNG(seed: seed, salt: "gen.findTheSame.\(level.code)")
        let pool = items(level)
        let item = pool[rng.below(pool.count)]
        return question(for: item)
    }

    /// Catalog order: target first, then distractors. `presentedOptions(seed:)` shuffles slots.
    public static func question(for item: Item) -> FindSameQuestion {
        let looks = [item.target] + item.distractors
        let options = looks.map { look in
            ActivityOption(id: optionID(look), assetID: look.assetID,
                           labelTraditionalChinese: look.labelTraditionalChinese,
                           labelEnglish: look.labelEnglish)
        }
        let promptZH: String
        let promptEN: String
        if item.level == .l3 {
            promptZH = "搵一模一樣嘅！邊架同上面完全一樣？"
            promptEN = "Find the exact same one! Which one matches above?"
        } else {
            promptZH = "搵同一個！邊架同上面一樣？"
            promptEN = "Find the same! Which one matches above?"
        }
        let variant = FindSameVariant(level: item.level, target: item.target, itemID: item.itemID,
                                      hintTraditionalChinese: hint(for: item))
        return FindSameQuestion(
            promptTraditionalChinese: promptZH,
            promptEnglish: promptEN,
            targetAssetID: item.target.assetID,
            options: options,
            correctOptionID: optionID(item.target),
            completionID: item.itemID,
            variant: variant
        )
    }

    public static func optionID(_ look: VehicleLook) -> String { "find-\(look.code)" }

    /// Hint names what to look at (design §5 hint table): the vehicle on L1 / L2,
    /// the differing details on L3.
    static func hint(for item: Item) -> String {
        let target = item.target.vehicle
        let en = target.nameEnglish.lowercased()
        switch item.level {
        case .l1:
            return "提示：搵\(target.nameTraditionalChinese)。 / Hint: look for the \(en)."
        case .l2:
            return "提示：顏色同車款都要一樣，搵\(target.nameTraditionalChinese)。 / Hint: same colour and same shape: look for the \(en)."
        case .l3:
            let features = Set(item.distractors.flatMap { $0.differences(from: item.target) })
            var zh: [String] = []
            var english: [String] = []
            if features.contains(.facing) {
                zh.append("車頭向邊")
                english.append("which way it faces")
            }
            if features.contains(.decor) {
                zh.append("有冇星星同旗仔")
                english.append("the star and the flag")
            }
            return "提示：睇吓\(zh.joined(separator: "，同埋"))。 / Hint: check \(english.joined(separator: " and "))."
        }
    }

    /// Confusion tags of a wrong option, derived from its difference to the target
    /// (design §5: `diff:*` plus the shared part). The right option has none.
    public static func tags(option: VehicleLook, target: VehicleLook) -> [String] {
        let diffs = option.differences(from: target)
        guard !diffs.isEmpty else { return [] }
        var tags: [String] = []
        for feature in diffs {
            if feature == .decor {
                let name = option.decor?.rawValue ?? target.decor?.rawValue ?? "none"
                tags.append("diff:decor:\(name)")
            } else {
                tags.append("diff:\(feature.rawValue)")
            }
        }
        if option.vehicle == target.vehicle {
            tags.append("same_type")
        } else {
            if option.vehicle.paint == target.vehicle.paint { tags.append("same_color") }
            if option.vehicle.body == target.vehicle.body { tags.append("same_shape") }
        }
        return tags
    }
}

extension FindSameQuestion {
    /// Hint line for this question (generated variants say what to look at).
    public var hintTraditionalChinese: String {
        variant?.hintTraditionalChinese ?? ActivityCatalog.hintTraditionalChinese(for: .findTheSame)
    }

    /// Item id written to `game_dealt.item`.
    public var itemID: String { variant?.itemID ?? completionID }

    /// Exactly one option looks like the target (asset ids encode the full look).
    public var hasExactlyOneMatch: Bool {
        options.filter { $0.assetID == targetAssetID }.count == 1
    }
}
