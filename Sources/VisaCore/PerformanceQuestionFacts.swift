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
    ///
    /// v0.24.0: `match_mode` is `free` or `guided`. Guided rounds have no choice to guess
    /// (chance 1, no correct choice) and are practice only (see `PerfQuestionGeneration`).
    public static func facts(lineMatch question: LineMatchQuestion, settings: LineMatchSettings) -> PerfDealFacts {
        let factorial = (1...max(1, question.pairCount)).reduce(1, *)
        let guided = question.isGuided
        var extra: [String: PerfValue] = [
            "category": .string(question.category.rawValue),
            "pairs": .int(question.pairCount),
            "items": .strings(question.pairs.map(\.key)),
            "tolerance": .string(settings.tolerance.rawValue),
            "category_mix": .string(settings.mixDescription),
            LineMatchMode.fieldKey: .string(question.mode.rawValue)
        ]
        if let object = question.countObject { extra["object"] = .string(object.rawValue) }
        return PerfDealFacts(
            item: question.itemID,
            gen: QuestionGeneration.variants,
            level: question.level,
            chance: guided ? 1 : 1.0 / Double(factorial),
            slots: question.rightKeys,
            correctChoice: guided ? nil : LineMatchSubmit.choice,
            tagsByChoice: [:],
            assetByChoice: [:],
            extraDealtFields: extra
        )
    }
}

extension PerfChoiceCatalog {
    /// A dealt 畫線畫形 round (v0.25.0). Practice only (design D10): chance 1, no correct
    /// choice, and `match_mode: guided` so the rollup and review treat it exactly like guided
    /// 連一連 (own `|guided` key, counted on the 引導練習 line, never mastery evidence).
    public static func facts(shapeTrace question: ShapeTraceQuestion, settings: ShapeTraceSettings,
                             tolerance: LineMatchTolerance) -> PerfDealFacts {
        var extra: [String: PerfValue] = [
            "practice": .string("shape_trace"),
            "scene": .string(question.scene.rawValue),
            "shapes": .strings(question.shapes.map(\.kind.rawValue)),
            "slots_drawn": .strings(question.shapes.map(\.slot)),
            "shape_trace_level": .string(question.level.code),
            "tolerance": .string(tolerance.rawValue),
            "direction_coaching": .bool(settings.directionHint),
            "stop_coaching": .bool(settings.cornerStop),
            "slant_enabled": .bool(settings.slantLines),
            "dot_style": .string(settings.dotStyle.rawValue),
            LineMatchMode.fieldKey: .string(LineMatchMode.guided.rawValue)
        ]
        if question.kind != .traceLines { extra["shape_mix"] = .string(settings.mixDescription) }
        return PerfDealFacts(
            item: question.itemID,
            gen: QuestionGeneration.variants,
            level: question.level,
            chance: 1,
            slots: question.shapes.map(\.slot),
            correctChoice: nil,
            tagsByChoice: [:],
            assetByChoice: [:],
            extraDealtFields: extra
        )
    }
}

extension PerfChoiceCatalog {
    /// A dealt 一架一架數 round (v0.28.0, design §3–§5 統計). ★ / ★★ are practice (chance 1, no
    /// correct choice, `match_mode: guided`); ★★★ is judged at OK (`submit`, chance 1/N) and is
    /// mastery evidence.
    public static func facts(tapCount question: TapCountQuestion, settings: TapCountSettings,
                             tolerance: LineMatchTolerance, recentTargets: [Int]) -> PerfDealFacts {
        let pick = question.isPick
        var extra: [String: PerfValue] = [
            "practice": .string(pick ? "tap_count_pick" : "tap_count"),
            "target": .int(question.target),
            "cars": .int(question.count),
            "scene": .string(question.scene.rawValue),
            "vehicles": .strings(question.vehicles.map(\.model.rawValue)),
            "layout": .string(question.layout.code),
            "count_voice": .bool(settings.countVoice),
            "english": .bool(settings.english),
            "range": .int(settings.range.rawValue),
            "recent_targets": .strings(recentTargets.map(String.init)),
            LineMatchMode.fieldKey: .string(pick ? LineMatchMode.free.rawValue : LineMatchMode.guided.rawValue)
        ]
        if question.tracesNumeral {
            extra["numeral"] = .int(question.target)
            extra["strokes"] = .int(NumeralGlyphs.strokes(question.target).count)
            extra["trace_scaffold"] = .string(settings.traceScaffold.code)
            extra["tolerance"] = .string(tolerance.rawValue)
        }
        if pick {
            extra["occupied_bays"] = .strings(question.occupiedBays.map(String.init))
            extra["badge_style"] = .string(settings.badgeStyle.rawValue)
        }
        return PerfDealFacts(
            item: question.itemID,
            gen: QuestionGeneration.variants,
            level: question.level,
            chance: pick ? 1 / Double(max(question.count, 1)) : 1,
            slots: question.occupiedBays.map { "bay-\($0)" },
            correctChoice: pick ? TapCountSubmitChoice.choice : nil,
            tagsByChoice: [:],
            assetByChoice: [:],
            extraDealtFields: extra
        )
    }
}

/// Choice id of a judged 揀啱數 OK in `answer_attempt`.
public enum TapCountSubmitChoice {
    public static let choice = "submit"
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

    /// `match_mode` of a `game_dealt` event. Everything before v0.24.0 (and every other kind)
    /// reads as `free`, so old data is unchanged.
    public static func matchMode(of dealt: PerfEvent) -> LineMatchMode {
        dealt.string(LineMatchMode.fieldKey).flatMap(LineMatchMode.init(rawValue:)) ?? .free
    }

    /// Guided 連一連 rounds are practice exposure: never mastery evidence, never misses
    /// (design "Guided level" → Stats). Review counts them on their own line.
    public static func isPracticeOnly(_ dealt: PerfEvent) -> Bool {
        if let kind = dealt.string("kind").flatMap(ActivityKind.init(rawValue:)),
           kind.isShapeTraceFamily || kind == .tapCountAll || kind == .tapCountTrace { return true }
        return matchMode(of: dealt) == .guided
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

    /// v0.24.0: guided rounds get their own key, `lineMatch|1|variants_v1|guided`, so a
    /// pruned day can never fold them into mastery. Free rounds keep the v0.22 key.
    public static func rollupKey(kind: String, stars: Int, gen: String, matchMode: LineMatchMode) -> String {
        let base = "\(kind)|\(stars)|\(gen)"
        return matchMode == .guided ? "\(base)|\(guidedKeySuffix)" : rollupKey(kind: kind, stars: stars, gen: gen)
    }

    public static let guidedKeySuffix = LineMatchMode.guided.rawValue

    /// True for a guided rollup key (4th part `guided`).
    public static func isGuidedRollupKey(_ key: String) -> Bool {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false)
        return parts.count > 3 && parts[3] == Substring(guidedKeySuffix)
    }

    public static func parseRollupKey(_ key: String) -> (kind: String, stars: Int?, gen: String) {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let stars = parts.count > 1 ? Int(parts[1]) : nil
        let gen = parts.count > 2 && !parts[2].isEmpty ? parts[2] : QuestionGeneration.fixed
        return (parts.first ?? "", stars, gen)
    }
}
