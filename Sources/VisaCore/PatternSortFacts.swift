import Foundation

// patterns-sorting P0 (design §6.1, §6.2, T8): what `game_dealt`, `answer_attempt` and `round_result` record for
// the four new cards. No new event type: kind fields ride on `extraDealtFields` and `roundResultExtra`. The
// condition fields (`ladder_step`, `materials` / `methods`, `voice`, `read_through`, and the result's `guide_level`)
// feed the weekly ⚙ signature; content fields change by seed and stay out of it.

public enum PatternSortFacts {
    /// The catalogue's reference choice ids (generated rounds write their own slots).
    public static func referenceChoices(_ kind: ActivityKind) -> [String] {
        switch kind {
        case .patternNext: return (0..<3).map { "choice-\($0)" }
        case .oddOneOut: return (0..<4).map { "card-\($0)" }
        case .sortGarages: return ["garage-0", "garage-1"]
        default: return (0..<3).map { "piece-\($0)" }
        }
    }

    public static func onOff(_ flag: Bool) -> PerfValue { .string(flag ? "on" : "off") }

    /// The condition fields every quiz deal writes (design §6.1).
    static func conditions(step: PatternSortStep, voice: Bool, readThrough: Bool) -> [String: PerfValue] {
        ["ladder_step": .string(step.code), "voice": onOff(voice), "read_through": onOff(readThrough)]
    }

    // MARK: 邊個唔同類

    public static func facts(oddOneOut q: OddOneOutQuestion, methods: String, voice: Bool, readThrough: Bool) -> PerfDealFacts {
        var extra = conditions(step: q.step, voice: voice, readThrough: readThrough)
        extra["methods"] = .string(methods)
        extra["odd_attr"] = .string(q.target.code)
        extra["noise_attr"] = .string(q.item.noise?.rawValue ?? "none")
        extra["cards"] = .strings(q.cards.map(\.code))
        extra["piece"] = .string(q.cards.allSatisfy { $0.piece.shape != nil } ? "block" : "vehicle")
        extra["chance"] = .double(q.chance)
        var tags: [String: [String]] = [:]
        var assets: [String: String] = [:]
        for (index, look) in q.cards.enumerated() {
            assets["card-\(index)"] = look.code
            let wrong = oddOneOutTags(q, card: index)
            if !wrong.isEmpty { tags["card-\(index)"] = wrong }
        }
        return PerfDealFacts(item: q.itemID, gen: QuestionGeneration.variants, level: q.level, chance: q.chance,
                             slots: q.slots, correctChoice: q.correctChoice, tagsByChoice: tags, assetByChoice: assets,
                             extraDealtFields: extra)
    }

    /// A wrong card's tags: `odd_same_<target>` names what it shares with the group, and `screen_order` (跟位置撳) when
    /// it is the first card on screen. The right card has none. Namespaced (astra R1): the approved `same_shape` means
    /// 同款唔同色 in the older games; the new tags have no weekly words until P3, so no weekly line names them.
    public static func oddOneOutTags(_ q: OddOneOutQuestion, card: Int) -> [String] {
        guard card != q.answer, q.cards.indices.contains(card) else { return [] }
        var tags = ["odd_same_\(q.target.isCategory ? "group" : q.target.code)"]
        if card == 0 { tags.append("screen_order") }
        return tags
    }

    // MARK: 接落去

    public static func facts(pattern q: PatternQuestion, materials: PatternSortMaterials, voice: Bool,
                             readThrough: Bool) -> PerfDealFacts {
        var extra = conditions(step: q.step, voice: voice, readThrough: readThrough)
        extra["materials"] = .string(materials.rawValue)
        extra["pattern_unit"] = .string(q.row.unit.rawValue)
        extra["pattern_task"] = .string(q.row.task.rawValue)
        extra["pattern_attr"] = .string(q.attribute.rawValue)
        extra["piece"] = .string(q.material == .shapes ? "block" : "vehicle")
        extra["n_slots"] = .int(q.row.n)
        extra["gap_index"] = .int(q.row.blanks.first ?? q.row.n - 1)
        extra["chance"] = .double(q.chance)
        var tags: [String: [String]] = [:]
        var assets: [String: String] = [:]
        for (index, look) in q.choices.enumerated() {
            assets["choice-\(index)"] = look.code
            let wrong = patternTags(q, blank: 0, choice: index)
            if !wrong.isEmpty { tags["choice-\(index)"] = wrong }
        }
        return PerfDealFacts(item: q.itemID, gen: QuestionGeneration.variants, level: q.level, chance: q.chance,
                             slots: q.choiceIDs, correctChoice: q.answers.first.map { "choice-\($0)" },
                             tagsByChoice: tags, assetByChoice: assets, extraDealtFields: extra)
    }

    /// A wrong choice for blank `blank` (index into the blanks): `repeat_last` (the item just before the blank),
    /// `wrong_phase` (another unit of the row), `not_in_pattern` (the outside piece), `screen_order` (the first card).
    public static func patternTags(_ q: PatternQuestion, blank: Int, choice: Int) -> [String] {
        guard q.row.blanks.indices.contains(blank), q.choices.indices.contains(choice),
              choice != q.answers[blank] else { return [] }
        let look = q.choices[choice]
        let slot = q.row.blanks[blank]
        var tags: [String] = []
        if slot > 0, q.units[q.row.letter(at: slot - 1)] == look { tags.append("repeat_last") }
        if q.units.contains(look) { tags.append("wrong_phase") } else { tags.append("not_in_pattern") }
        if choice == 0 { tags.append("screen_order") }
        return tags
    }

    // MARK: 分車房

    public static func facts(sort q: SortGaragesQuestion, methods: String, voice: Bool, readThrough: Bool) -> PerfDealFacts {
        var extra = conditions(step: q.step, voice: voice, readThrough: readThrough)
        extra["methods"] = .string(methods)
        extra["sort_attr"] = .string(q.rule.code)
        extra["noise_attr"] = .string((q.helper ?? q.noise)?.rawValue ?? "none")
        extra["items"] = .strings(q.queue.map(\.code))
        extra["examples"] = .strings(q.examples.map(\.code))
        extra["chance"] = .double(q.chance)
        return PerfDealFacts(item: q.itemID, gen: QuestionGeneration.variants, level: q.level, chance: q.chance,
                             slots: q.choiceIDs, correctChoice: nil, tagsByChoice: [:], assetByChoice: [:],
                             extraDealtFields: extra)
    }

    /// A wrong garage for queue item `item`: `repeat_last_garage` when it is where the previous vehicle went.
    public static func sortTags(_ q: SortGaragesQuestion, item: Int, garage: Int) -> [String] {
        guard q.garages.indices.contains(item), garage != q.garages[item] else { return [] }
        return item > 0 && q.garages[item - 1] == garage ? ["repeat_last_garage"] : []
    }

    // MARK: 自己排

    public static func facts(make p: PatternMakePalette, materials: PatternSortMaterials, voice: Bool) -> PerfDealFacts {
        PerfDealFacts(item: p.itemID, gen: QuestionGeneration.variants, level: nil, chance: 1,
                      slots: p.pieces.indices.map { "piece-\($0)" }, correctChoice: nil, tagsByChoice: [:],
                      assetByChoice: [:],
                      extraDealtFields: ["palette": .strings(p.pieces.map(\.code)), "n_slots": .int(PatternMakeGenerator.slots),
                                         "materials": .string(materials.rawValue), "voice": onOff(voice),
                                         "practice": .string("pattern_make")])
    }

    // MARK: round_result extras

    public static func resultFields(oddOneOut board: OddOneOutBoard, guidance: TapCountGuidanceLevel) -> [String: PerfValue] {
        ["guide_level": .string(guidance.rawValue), "misses": .int(board.misses), "hint_used": .bool(board.assisted),
         "first_try": .bool(board.firstTry)]
    }

    public static func resultFields(pattern round: PatternRound, guidance: TapCountGuidanceLevel) -> [String: PerfValue] {
        ["guide_level": .string(guidance.rawValue), "slots_filled": .int(round.filled.count)]
    }

    public static func resultFields(sort board: SortGaragesBoard, guidance: TapCountGuidanceLevel) -> [String: PerfValue] {
        ["guide_level": .string(guidance.rawValue), "placed": .int(board.placed.count), "misplaced": .int(board.misses)]
    }

    public static func resultFields(make board: PatternMakeBoard) -> [String: PerfValue] {
        ["made_unit": .string(board.detected?.rawValue ?? "none"), "made_length": .int(board.placed.count),
         "undos": .int(board.undos)]
    }

    /// The ladder outcome of a finished round (abandoned rounds are not recorded).
    public static func outcome(misses: Int, assisted: Bool) -> PatternSortRoundOutcome {
        assisted ? .hinted : misses == 0 ? .firstTry : .solved
    }
}
