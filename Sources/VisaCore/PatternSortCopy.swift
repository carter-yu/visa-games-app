import Foundation

// patterns-sorting P0 (design §3.6, §4.6, Appendix A): every new child and parent line, HK Traditional + English.
// A line has a short display text for the one-line bubble (inside the §5.6 budget) and, where it differs, a spoken
// sequence (row words that light their item). Readbacks are never shown in the bubble. Keys are stable and built from
// the content, so a recorded `Voice/<key>.m4a` can replace a fixed line or a word with no code change. No 喎.

/// One child line: the bubble text, its English subtitle, and its clip key.
public struct PatternSortLine: Sendable, Equatable {
    public let key: String
    public let zh: String
    public let en: String

    public init(_ key: String, _ zh: String, _ en: String) {
        self.key = key
        self.zh = zh
        self.en = en
    }

    /// The prompt the bubble shows and the queued voice path speaks.
    public var prompt: SpokenPrompt { SpokenPrompt(key: key, traditionalChinese: zh, english: en) }
    /// The line as one unit of a spoken sequence.
    public func unit(light: Int? = nil) -> ReadThroughUnit { ReadThroughUnit(key: key, text: zh, kind: .line, light: light) }
}

/// 分類 · 邊個唔同類 (Appendix A).
public enum OddOneOutCopy {
    /// The read-through lights the emblem or the category sign (not a card).
    public static let panelLight = -1

    public static let intro = PatternSortLine("odd.intro", "有一個同其他唔一樣！", "One is not like the others!")
    /// The generic prompt where the other cards are identical, at 標準 and 少啲 (design §4.2 / §5.2).
    public static let generic = PatternSortLine("odd.prompt", "邊個唔同類呀？", "Which one doesn't belong?")
    public static let done = PatternSortLine("odd.done", "你睇得好細心！", "You looked so carefully!")
    public static let idle = PatternSortLine("patternSort.idle", "試吓揀一個！", "Try picking one!")

    /// Named prompts (多啲 at ★ / ★★; every level in category and ★★★ rounds).
    public static func named(_ target: OddOneOutTarget) -> PatternSortLine {
        let key = "odd.prompt.named.\(target.code)"
        switch target {
        case .colour: return PatternSortLine(key, "邊個嘅顏色唔一樣呀？", "Which one is a different colour?")
        case .size: return PatternSortLine(key, "邊個嘅大細唔一樣呀？", "Which one is a different size?")
        case .shape: return PatternSortLine(key, "邊個嘅形狀唔一樣呀？", "Which one is a different shape?")
        case .kind: return PatternSortLine(key, "邊架係另一款車呀？", "Which one is a different kind of vehicle?")
        case .facing: return PatternSortLine(key, "邊架車頭向另一邊呀？", "Which one faces the other way?")
        case .category(.site): return PatternSortLine(key, "邊架唔係地盤車呀？", "Which one is not a construction vehicle?")
        case .category: return PatternSortLine(key, "邊個唔係車呀？", "Which one is not a vehicle?")
        }
    }

    public static func prompt(_ q: OddOneOutQuestion, guidance: TapCountGuidanceLevel) -> PatternSortLine {
        q.isNamed(guidance) ? named(q.target) : generic
    }

    /// Group value and odd value on the target, as words.
    static func sizeWord(_ size: PatternSortSize) -> String { size == .small ? "細嘅" : "大嘅" }

    static func plural(_ piece: PatternSortPiece) -> String {
        switch piece.en {
        case "bus": return "buses"
        default: return piece.en + "s"
        }
    }

    /// The explain line (the reveal's first line).
    public static func correct(_ q: OddOneOutQuestion) -> PatternSortLine {
        let odd = q.cards[q.answer]
        let group = q.cards[q.answer == 0 ? 1 : 0]
        switch q.target {
        case .colour:
            return PatternSortLine("odd.correct.colour.\(odd.colour.rawValue).\(group.colour.rawValue)",
                                   "啱喇！佢係\(odd.colour.zh)，其他係\(group.colour.zh)。",
                                   "Yes! It's \(odd.colour.en); the others are \(group.colour.en).")
        case .size:
            return PatternSortLine("odd.correct.size.\(odd.size.rawValue)",
                                   "啱喇！佢係\(sizeWord(odd.size))，其他係\(sizeWord(group.size))。",
                                   "Yes! It's \(odd.size.en); the others are \(group.size.en).")
        case .shape:
            return PatternSortLine("odd.correct.shape.\(odd.piece.code).\(group.piece.code)",
                                   "啱喇！佢係\(odd.piece.zh)，其他係\(group.piece.zh)。",
                                   "Yes! It's a \(odd.piece.en); the others are \(plural(group.piece)).")
        case .kind:
            return PatternSortLine("odd.correct.kind.\(odd.piece.code).\(group.piece.code)",
                                   "啱喇！佢係\(odd.piece.zh)，其他係\(group.piece.zh)。",
                                   "Yes! A \(odd.piece.en); the others are \(plural(group.piece)).")
        case .facing:
            return PatternSortLine("odd.correct.facing", "啱喇！佢車頭向另一邊。", "Yes! It faces the other way.")
        case .category(.site):
            return PatternSortLine("odd.correct.site.\(odd.piece.code)", "啱喇！\(odd.piece.zh)唔係地盤車。",
                                   "Yes! A \(odd.piece.en) isn't a construction vehicle.")
        case .category:
            return PatternSortLine("odd.correct.vehicle.\(odd.piece.code)", "啱喇！\(odd.piece.zh)唔係車。",
                                   "Yes! A \(odd.piece.en) is not a vehicle.")
        }
    }

    /// The tapped card is like the others (it names what was tapped, as the letter and 中文字 boards do).
    public static func wrong(_ q: OddOneOutQuestion, card: Int) -> PatternSortLine {
        let look = q.cards[min(max(card, 0), q.cards.count - 1)]
        let classifier = look.piece.classifier
        let kindCode = look.piece.model == nil ? "block" : "vehicle"
        switch q.target {
        case .colour:
            return PatternSortLine("odd.wrong.colour.\(look.colour.rawValue).\(kindCode)",
                                   "呢\(classifier)同其他一樣，都係\(look.colour.zh)。",
                                   "This one is like the others: \(look.colour.en).")
        case .size:
            return PatternSortLine("odd.wrong.size.\(look.size.rawValue).\(kindCode)",
                                   "呢\(classifier)同其他一樣，都係\(sizeWord(look.size))。",
                                   "This one is like the others: \(look.size.en).")
        case .shape, .kind:
            return PatternSortLine("odd.wrong.\(q.target.code).\(look.piece.code)",
                                   "呢\(classifier)同其他一樣，都係\(look.piece.zh)。",
                                   "This one is like the others: a \(look.piece.en).")
        case .facing:
            return PatternSortLine("odd.wrong.facing", "呢架同其他一樣，車頭向同一邊。",
                                   "This one faces the same way as the others.")
        case .category(.site):
            return PatternSortLine("odd.wrong.site", "呢架都係地盤車。", "This one is a construction vehicle too.")
        case .category:
            return PatternSortLine("odd.wrong.vehicle", "呢架都係車。", "This one is a vehicle too.")
        }
    }

    /// The auto-hint's line (the hint also lights the answer).
    public static func hint(_ target: OddOneOutTarget) -> PatternSortLine {
        let key = "odd.hint.\(target.isCategory ? "group" : target.code)"
        switch target {
        case .colour: return PatternSortLine(key, "睇吓顏色。", "Look at the colours.")
        case .size: return PatternSortLine(key, "睇吓大細。", "Look at the sizes.")
        case .shape: return PatternSortLine(key, "睇吓形狀。", "Look at the shapes.")
        case .kind: return PatternSortLine(key, "睇吓係咩車。", "Look at the kinds.")
        case .facing: return PatternSortLine(key, "睇吓車頭向邊。", "Look which way they face.")
        case .category: return PatternSortLine(key, "諗吓佢哋做咩用。", "Think what they're for.")
        }
    }

    /// The automatic read-through (design §5.2): the rule line with the emblem or sign lit, then the prompt.
    public static func readThrough(_ q: OddOneOutQuestion, guidance: TapCountGuidanceLevel) -> [ReadThroughUnit] {
        [intro.unit(light: panelLight), prompt(q, guidance: guidance).unit()]
    }

    /// The finish reveal: the explain line, then 「你睇得好細心！」.
    public static func reveal(_ q: OddOneOutQuestion) -> [ReadThroughUnit] { [correct(q).unit(), done.unit()] }

    /// The category sign's word (車 / 地盤車) and grey anchor model; nil on the emblem rounds.
    public static func sign(_ q: OddOneOutQuestion) -> (word: String, english: String, anchor: PatternSortPiece)? {
        guard case .category(let category) = q.target else { return nil }
        return (category.zh, category.en, category.anchor)
    }
}

/// 跟住排 · 接落去 (Appendix A; the UI is P2).
public enum PatternCopy {
    public static let intro = PatternSortLine("pattern.intro", "睇吓啲車點樣排隊！", "Look how they line up!")
    public static let nextVehicle = PatternSortLine("pattern.next.vehicle", "跟住係邊架車呀？", "Which vehicle comes next?")
    public static let nextShape = PatternSortLine("pattern.next.shape", "跟住係乜嘢形狀呀？", "Which shape comes next?")
    public static let nextSize = PatternSortLine("pattern.next.size", "跟住係大定細呀？", "Big or small next?")
    public static let addTwo = PatternSortLine("pattern.addTwo", "再排兩個！", "Add two more!")
    public static let oneMore = PatternSortLine("pattern.oneMore", "仲有一個！", "One more!")
    public static let gap = PatternSortLine("pattern.gap", "中間漏咗一個，係邊個呀？", "One is missing in the middle. Which one?")
    public static let correct = PatternSortLine("pattern.correct", "啱喇！", "Yes!")
    public static let hint = PatternSortLine("pattern.hint", "一齊讀！", "Let's read it together!")
    public static let done = PatternSortLine("pattern.done", "排得好整齊！", "Lined up so neatly!")
    static let thenWhat = PatternSortLine("pattern.readThrough.next", "跟住呢？", "")
    static let whichMissing = PatternSortLine("pattern.readThrough.gap", "漏咗邊個呀？", "")

    public static func prompt(_ q: PatternQuestion) -> PatternSortLine {
        if q.row.task == .fill { return gap }
        if q.attribute == .size { return nextSize }
        return q.material == .shapes ? nextShape : nextVehicle
    }

    /// The word a row item is read as: its piece, with 大 / 細 when size is what changes.
    public static func word(_ look: PatternSortLook, attribute: PatternAttribute) -> (zh: String, en: String) {
        attribute == .size ? (look.size.zh + look.piece.zh, "\(look.size.en) \(look.piece.en)") : (look.piece.zh, look.piece.en)
    }

    /// Slot `slot`'s word, lighting that slot (clip key `pattern.word.<piece>` or `pattern.word.<size>.<piece>`).
    static func wordUnit(_ q: PatternQuestion, slot: Int) -> ReadThroughUnit {
        let look = q.units[q.row.letter(at: slot)]
        let code = q.attribute == .size ? "\(look.size.rawValue).\(look.piece.code)" : look.piece.code
        return ReadThroughUnit(key: "pattern.word.\(code)", text: word(look, attribute: q.attribute).zh, kind: .word, light: slot)
    }

    /// The read-through: each shown item's word with its light, then 「跟住呢？」 (or 「漏咗邊個呀？」 for a gap).
    public static func readThrough(_ q: PatternQuestion) -> [ReadThroughUnit] {
        q.row.visible.map { wordUnit(q, slot: $0) } + [(q.row.task == .fill ? whichMissing : thenWhat).unit()]
    }

    /// The reveal: 「啱喇！」, the whole row's words with the light, then 「排得好整齊！」.
    public static func reveal(_ q: PatternQuestion) -> [ReadThroughUnit] {
        [correct.unit()] + (0..<q.row.n).map { wordUnit(q, slot: $0) } + [done.unit()]
    }

    public static func wrong(_ look: PatternSortLook, attribute: PatternAttribute) -> PatternSortLine {
        let word = word(look, attribute: attribute)
        let code = attribute == .size ? "\(look.size.rawValue).\(look.piece.code)" : look.piece.code
        return PatternSortLine("pattern.wrong.\(code)", "呢\(look.piece.classifier)係\(word.zh)。", "That one is the \(word.en).")
    }
}

/// 跟住排 · 自己排 (Appendix A; the UI is P5).
public enum PatternMakeCopy {
    public static let intro = PatternSortLine("make.intro", "到你排車隊！", "Your turn to make a line!")
    public static let prompt = PatternSortLine("make.prompt", "揀一個，排落條路度。", "Pick one for the road.")
    /// The 退返一格 button's label (not spoken).
    public static let undo = PatternSortLine("make.undo", "退返一格", "Undo")
    public static let pattern = PatternSortLine("make.pattern", "你自己排咗一個規律！", "You made your own pattern!")
    public static let free = PatternSortLine("make.free", "好靚嘅車隊！", "What a lovely line!")

    /// The readback with the light, then the detector's line.
    public static func reveal(_ board: PatternMakeBoard) -> [ReadThroughUnit] {
        board.placed.enumerated().map { slot, index in
            let look = board.palette.pieces[index]
            return ReadThroughUnit(key: "pattern.word.\(look.piece.code)", text: look.piece.zh, kind: .word, light: slot)
        } + [(board.detected == nil ? free : pattern).unit()]
    }
}

/// 分類 · 分車房 (Appendix A; the UI is P4).
public enum SortCopy {
    public static let intro = PatternSortLine("sort.intro", "幫啲車泊入啱嘅車房！", "Park each one in the right garage!")
    public static let prompt = PatternSortLine("sort.prompt", "呢個去邊間車房呀？", "Which garage for this one?")
    public static let correct = PatternSortLine("sort.correct", "泊好喇！", "Parked!")
    public static let hint = PatternSortLine("sort.hint", "睇吓車房個牌。", "Look at the garage signs.")
    public static let done = PatternSortLine("sort.done", "全部泊好晒！", "All parked!")

    /// A garage sign's word: the rule's value.
    public static func signWord(_ q: SortGaragesQuestion, garage: Int) -> (zh: String, en: String) {
        let sign = q.signs[min(max(garage, 0), 1)]
        if let colour = PatternSortColour(rawValue: sign) { return (colour.zh, colour.en) }
        if let size = PatternSortSize(rawValue: sign) { return (size.zh, size.en) }
        if let category = PatternSortCategory(rawValue: sign) { return (category.zh, category.en) }
        if let piece = PatternSortPiece(code: sign) { return (piece.zh, piece.en) }
        return (sign, sign)
    }

    public static func rule(_ q: SortGaragesQuestion) -> PatternSortLine {
        let a = signWord(q, garage: 0), b = signWord(q, garage: 1)
        return PatternSortLine("sort.rule.\(q.signs.joined(separator: "."))", "\(a.zh)泊呢間，\(b.zh)泊嗰間。",
                               "\(a.en.prefix(1).uppercased() + a.en.dropFirst()) here, \(b.en) there.")
    }

    public static func wrong(_ q: SortGaragesQuestion, garage: Int) -> PatternSortLine {
        let value = signWord(q, garage: garage)
        let zh = q.rule == .size ? value.zh + "嘅" : value.zh
        return PatternSortLine("sort.wrong.\(q.signs[min(max(garage, 0), 1)])", "呢個係\(zh)。", "This one is \(value.en).")
    }
}

/// Parent copy: the cards and the minimal 分類設定 panel (design §7, P1).
public enum PatternSortParentCopy {
    public static let sortTitle = "分類設定"
    public static let sortSubtitle = "Sorting settings · 邊個唔同類同分車房共用 / Shared by Odd one out and Two garages"
    public static let methodsTitle = "分類方法"
    public static let methodsEnglish = "Ways to sort"
    public static let methodsDetail = "顏色題只用色盲都分得開嘅配搭（例如藍同黃），唔會用紅同綠。"
    public static let methodsDetailEnglish = "Colour rounds use only colour-blind-safe pairs (such as blue and yellow), never red with green."
    public static let methodsMeaning = "開咗嘅方法先會用嚟出題；關咗嘅方法，卡上面都可能唔同，但唔會用嚟定答案。"
    public static let methodsMeaningEnglish = "Only switched-on ways decide an answer; a switched-off one may still vary on the cards."
    public static let lastPerceptual = "顏色、大細、形狀最少要開一樣。"
    public static let lastPerceptualEnglish = "Keep at least one of colour, size or shape on."
    public static let helpTitle = "提示"
    public static let helpEnglish = "Help"
    public static let audioTitle = HanziParentCopy.audioTitle
    public static let audioEnglish = HanziParentCopy.audioEnglish
    public static let audioDetail = "開咗先出聲，題目照常顯示。只用已安裝嘅香港粵語語音；冇就唔出聲。\nSpeaks only when on; the question always shows. Uses an installed Hong Kong Cantonese voice only; silent if there is none."
    public static let appliesNow = "改咗即刻用。"
    public static let appliesNowEnglish = "Changes apply at once."

    /// The 多啲／標準／少啲 labels are the existing ones (`HanziParentCopy.coachLabels`); the detail lines are this
    /// family's (Appendix A).
    public static func helpDetail(_ level: TapCountGuidanceLevel) -> (zh: String, en: String) {
        switch level {
        case .more: return ("多啲：每局先讀一次；題目講明睇咩；錯一次就顯示提示。",
                            "More: read out every round; the question says what to look at; the hint after one miss.")
        case .standard: return ("標準（預設）：未識之前每局先讀一次；錯兩次先顯示提示。",
                                "Standard (default): read out until learned; the hint after two misses.")
        case .less: return ("少啲：唔讀；錯兩次先顯示提示。", "Less: no read-out; the hint after two misses.")
        }
    }

    public static func suggestedStar(_ kind: ActivityKind) -> String? {
        switch kind {
        case .patternNext, .oddOneOut, .patternMake: return "建議 ★ / Suggested ★"
        case .sortGarages: return "建議 ★★ / Suggested ★★"
        default: return nil
        }
    }

    /// The card's 「預設關閉」 line while no star is on, and its 「試玩一次先開星」 line until its own playtest (the
    /// 中文字 cards' words, design §7).
    public static func defaultOffLine(_ kind: ActivityKind) -> String? {
        kind.isPatternFamily || kind.isSortFamily ? HanziParentCopy.cardDefaultOff : nil
    }

    public static func starsLockedLine(_ kind: ActivityKind) -> String? {
        kind.isPatternFamily || kind.isSortFamily ? HanziParentCopy.starsLocked : nil
    }

    public static func cardDetail(_ kind: ActivityKind) -> String? {
        switch kind {
        case .oddOneOut:
            return "比較：揀錯唔同嘅卡先扣油；同一張錯卡唔會再扣。\nComparing: only a new wrong card costs fuel; the same wrong card never costs again."
        default: return nil
        }
    }

    /// Every parent line, for the copy audits.
    public static var allLines: [String] {
        var lines = [sortTitle, sortSubtitle, methodsTitle, methodsEnglish, methodsDetail, methodsDetailEnglish,
                     methodsMeaning, methodsMeaningEnglish, lastPerceptual, lastPerceptualEnglish, helpTitle,
                     helpEnglish, audioDetail, appliesNow, appliesNowEnglish]
        for level in TapCountGuidanceLevel.allCases { lines += [helpDetail(level).zh, helpDetail(level).en] }
        for method in PatternSortMethod.allCases { lines += [method.zh, method.en] }
        for kind in [ActivityKind.patternNext, .patternMake, .oddOneOut, .sortGarages] {
            lines += [kind.parentCardTitle, kind.parentCardEnglish, kind.parentShortLabel, kind.parentHelpTraditionalChinese,
                      kind.parentHelpEnglish, ActivityCatalog.hintTraditionalChinese(for: kind)]
            lines += [suggestedStar(kind), cardDetail(kind), defaultOffLine(kind), starsLockedLine(kind)].compactMap { $0 }
        }
        return lines
    }
}
