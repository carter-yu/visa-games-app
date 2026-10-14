import Foundation

// v0.22.0 (design §7 / §8.2): performance facts come from the dealt question, not from one
// fixed catalog item per kind. Old v0.20–v0.21 lines have no `gen` / `level`; they decode as
// `fixed_v0` with no level, so old and new rounds stay separable (D9) without a new schema.

/// Facts about one dealt question, fixed at deal time: item, generation, level, guess
/// chance, the slots as drawn, and the confusion tags / asset of every choice.
public struct PerfDealFacts: Sendable, Equatable {
    public var item: String
    /// `QuestionGeneration.fixed` or `.variants`.
    public var gen: String
    /// Question tier for generated kinds; nil for fixed items.
    public var level: ActivityLevel?
    public var chance: Double
    /// Choice ids left-to-right as drawn for the deal seed.
    public var slots: [String]
    public var correctChoice: String?
    public var tagsByChoice: [String: [String]]
    public var assetByChoice: [String: String]
    /// Kind-specific `game_dealt` fields (v0.23.0 連一連: category, pairs, items, tolerance…).
    public var extraDealtFields: [String: PerfValue]

    public init(item: String, gen: String, level: ActivityLevel?, chance: Double, slots: [String],
                correctChoice: String?, tagsByChoice: [String: [String]], assetByChoice: [String: String],
                extraDealtFields: [String: PerfValue] = [:]) {
        self.item = item
        self.gen = gen
        self.level = level
        self.chance = chance
        self.slots = slots
        self.correctChoice = correctChoice
        self.tagsByChoice = tagsByChoice
        self.assetByChoice = assetByChoice
        self.extraDealtFields = extraDealtFields
    }

    public func tags(for choice: String) -> [String] { tagsByChoice[choice] ?? [] }
    public func asset(for choice: String) -> String? { assetByChoice[choice] }

    /// Extra `game_dealt` fields (`gen`, and `level` when the question has one, plus any
    /// kind-specific fields).
    public var dealtFields: [String: PerfValue] {
        var fields = extraDealtFields
        fields["gen"] = .string(gen)
        if let level { fields["level"] = .int(level.rawValue) }
        return fields
    }
}

extension PerfChoiceCatalog {
    /// The fixed v0 item of `kind` (every kind not generated yet, and parent fallbacks).
    public static func facts(kind: ActivityKind, seed: String) -> PerfDealFacts {
        var tags: [String: [String]] = [:]
        var assets: [String: String] = [:]
        for choice in allChoices(for: kind) {
            let choiceTags = PerfChoiceCatalog.tags(kind: kind, choice: choice)
            if !choiceTags.isEmpty { tags[choice] = choiceTags }
            if let asset = asset(kind: kind, choice: choice) { assets[choice] = asset }
        }
        return PerfDealFacts(item: item(for: kind), gen: QuestionGeneration.fixed, level: nil,
                             chance: chance(for: kind), slots: slots(kind: kind, seed: seed),
                             correctChoice: correctChoice(for: kind), tagsByChoice: tags, assetByChoice: assets)
    }

    /// A dealt count question (generated or the fixed item). Slots match `presentedChoiceCounts`.
    public static func facts(count question: CountQuestion, seed: String) -> PerfDealFacts {
        var tags: [String: [String]] = [:]
        for value in question.choiceCounts where value != question.correctCount {
            tags["count-\(value)"] = CountVehiclesGenerator.tags(chosen: value, correct: question.correctCount)
        }
        return PerfDealFacts(
            item: question.itemID,
            gen: question.variant == nil ? QuestionGeneration.fixed : QuestionGeneration.variants,
            level: question.variant?.level,
            chance: 1.0 / Double(max(question.choiceCounts.count, 1)),
            slots: question.presentedChoiceCounts(seed: seed).map { "count-\($0)" },
            correctChoice: "count-\(question.correctCount)",
            tagsByChoice: tags,
            assetByChoice: [:]
        )
    }

    /// A dealt find-the-same question. Generated tags come from the look difference
    /// (`diff:*`); the fixed item keeps its v0.20 tags so old and new rows read the same way.
    public static func facts(findSame question: FindSameQuestion, seed: String) -> PerfDealFacts {
        guard let variant = question.variant else {
            var fixed = Self.facts(kind: .findTheSame, seed: seed)
            fixed.slots = question.presentedOptions(seed: seed).map(\.id)
            return fixed
        }
        var tags: [String: [String]] = [:]
        var assets: [String: String] = [:]
        for option in question.options {
            assets[option.id] = option.assetID
            guard option.id != question.correctOptionID, let look = VehicleLook(assetID: option.assetID) else {
                continue
            }
            tags[option.id] = FindTheSameGenerator.tags(option: look, target: variant.target)
        }
        return PerfDealFacts(
            item: question.itemID,
            gen: QuestionGeneration.variants,
            level: variant.level,
            chance: 1.0 / Double(max(question.options.count, 1)),
            slots: question.presentedOptions(seed: seed).map(\.id),
            correctChoice: question.correctOptionID,
            tagsByChoice: tags,
            assetByChoice: assets
        )
    }
}

extension PerfChoiceCatalog {
    /// A dealt 連一連 question (v0.23.0). One `answer_attempt` per judged 完成 with choice
    /// `submit`; its tags come from the wrong lines (`LineMatchBoard.submitRecord`). Slots are
    /// the right column top → bottom; chance is guessing every line: 1 / pairs!.
    public static func facts(lineMatch question: LineMatchQuestion, settings: LineMatchSettings) -> PerfDealFacts {
        let factorial = (1...max(1, question.pairCount)).reduce(1, *)
        var extra: [String: PerfValue] = [
            "category": .string(question.category.rawValue),
            "pairs": .int(question.pairCount),
            "items": .strings(question.pairs.map(\.key)),
            "tolerance": .string(settings.tolerance.rawValue),
            "category_mix": .string(settings.mixDescription)
        ]
        if let object = question.countObject { extra["object"] = .string(object.rawValue) }
        return PerfDealFacts(
            item: question.itemID,
            gen: QuestionGeneration.variants,
            level: question.level,
            chance: 1.0 / Double(factorial),
            slots: question.rightKeys,
            correctChoice: LineMatchSubmit.choice,
            tagsByChoice: [:],
            assetByChoice: [:],
            extraDealtFields: extra
        )
    }
}

/// Choice id of a judged 連一連 完成 in `answer_attempt`.
public enum LineMatchSubmit {
    public static let choice = "submit"
}

/// Reading `gen` / `level` back from records, and keeping them apart in the daily rollup.
public enum PerfQuestionGeneration {
    /// `stats_marker.what` written once when variant questions go live (design §7).
    public static let markerWhat = QuestionGeneration.variants

    /// `gen` of a `game_dealt` event. Lines written before v0.22.0 have none → `fixed_v0`.
    public static func gen(of dealt: PerfEvent) -> String {
        dealt.string("gen") ?? QuestionGeneration.fixed
    }

    /// `level` of a `game_dealt` event (nil on fixed items and old lines).
    public static func level(of dealt: PerfEvent) -> ActivityLevel? {
        dealt.int("level").flatMap(ActivityLevel.init(rawValue:))
    }

    public static func isVariant(_ dealt: PerfEvent) -> Bool {
        gen(of: dealt) != QuestionGeneration.fixed
    }

    /// First `stats_marker{what: variants_v1}` (the go-live line), if any.
    public static func variantsMarker(in events: [PerfEvent]) -> PerfEvent? {
        PerfCodec.ordered(events).first { $0.type == .statsMarker && $0.string("what") == markerWhat }
    }

    /// Rollup key. Fixed rounds keep the v0.20 `kind|stars` key; generated rounds add the
    /// generation (`kind|stars|variants_v1`). Older readers split on `|` and use the first
    /// two parts, so they still read the new keys.
    public static func rollupKey(kind: String, stars: Int, gen: String) -> String {
        gen == QuestionGeneration.fixed ? "\(kind)|\(stars)" : "\(kind)|\(stars)|\(gen)"
    }

    public static func parseRollupKey(_ key: String) -> (kind: String, stars: Int?, gen: String) {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let stars = parts.count > 1 ? Int(parts[1]) : nil
        let gen = parts.count > 2 && !parts[2].isEmpty ? parts[2] : QuestionGeneration.fixed
        return (parts.first ?? "", stars, gen)
    }
}
