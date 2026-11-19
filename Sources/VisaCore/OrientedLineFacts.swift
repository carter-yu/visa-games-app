import Foundation

// 畫直線・四方 deal facts (four-direction design §9). Written under the new kind only: 畫直線 · 熱身's deals and
// results keep exactly the fields they had.

public enum OrientedLineFacts {
    /// `trace_rule` of every new-card deal and result: connected coverage on direction-free progress (design §5.1);
    /// `off_path_count` counts lateral exits only.
    public static let traceRule = "connected_coverage_v2"

    /// The lines in drawing order: `line1`, `line2`, `line3`.
    public static func slots(_ question: OrientedLineQuestion) -> [String] {
        question.lines.indices.map { "line\($0 + 1)" }
    }
}

extension PerfChoiceCatalog {
    /// A dealt 畫直線・四方 round. Practice only, like 畫直線 · 熱身 (chance 1, no correct choice, `match_mode: guided`),
    /// recorded from the round's own snapshot: `line_shape`, `line_direction`, `line_help` and the card's own
    /// `tolerance`. It never writes `direction_coaching`, `slant_enabled`, `stop_coaching`, `dot_style` or `shape_mix`:
    /// those belong to the shared 畫形狀設定, and its lookups must never see new-card values (design §9).
    public static func facts(orientedLines question: OrientedLineQuestion) -> PerfDealFacts {
        let extra: [String: PerfValue] = [
            "practice": .string("shape_trace"),
            "shapes": .strings(question.lines.map(\.variant.factToken)),
            "slots_drawn": .strings(OrientedLineFacts.slots(question)),
            "footprints": .strings(question.lines.map(\.footprint.code)),
            "shape_trace_level": .string(ActivityLevel.l1.code),
            "tolerance": .string(question.dealt.tolerance.rawValue),
            "line_shape": .string(question.dealt.lineShape.rawValue),
            "line_direction": .string(question.dealt.lineDirection.rawValue),
            "line_help": .string(question.dealt.lineHelp.rawValue),
            "trace_rule": .string(OrientedLineFacts.traceRule),
            LineMatchMode.fieldKey: .string(LineMatchMode.guided.rawValue)
        ]
        return PerfDealFacts(item: question.itemID, gen: QuestionGeneration.variants, level: .l1, chance: 1,
                             slots: OrientedLineFacts.slots(question), correctChoice: nil, tagsByChoice: [:],
                             assetByChoice: [:], extraDealtFields: extra)
    }
}
