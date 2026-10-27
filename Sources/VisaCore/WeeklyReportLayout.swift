import Foundation

// Weekly report W4 (weekly-report design §9.2, §13 items 10–11): a deterministic estimate of how tall the
// open-ended pages get, so page 4 and page 6 can pick a denser variant before their content would run past the
// fixed 794 × 1123 px section. Text widths come from a per-character em table (CJK and other non-ASCII 1 em,
// Latin 0.28–0.86 em); wrapped lines count against 92 % of a box's width; line heights are the px values of the
// CSS. Integers only (tenths of a px). Checked against headless Chrome on the fixtures and heavier weeks (ADR
// 0024). Keep in step with `reference_html.py`.

extension WeeklyReportHTML {
    /// A font size and line height, in tenths of a px, as in `WeeklyReportCSS`.
    struct TextStyle {
        let font: Int
        let line: Int
    }

    /// Page 4 variants, tried in order: normal with full 數據唔夠 rows (≤ 6 entries) or two columns, then two
    /// columns, then dense, then dense without the "how we rank" note.
    struct Page4Variant: Equatable {
        let dense: Bool
        let columns: Bool
        let method: Bool
    }

    /// Content box of a page is 1123 − 72 − 57 = 994 px; a variant is used while its estimate is ≤ 960 px.
    static let contentBudget = 9_600
    /// Percent of a box's width a wrapped line is assumed to fill.
    static let lineSlack = 92

    static let narrowASCII: Set<UInt32> = Set("iljftr.,:;'|!I()[]{} ".unicodeScalars.map(\.value))
    static let wideASCII: Set<UInt32> = Set("mwMW%@".unicodeScalars.map(\.value))

    static let rowName = TextStyle(font: 120, line: 150)
    static let rowNameEN = TextStyle(font: 92, line: 120)
    static let factStyle = TextStyle(font: 112, line: 145)
    static let factEN = TextStyle(font: 90, line: 120)
    static let factStars = TextStyle(font: 88, line: 115)
    static let commentStyle = TextStyle(font: 109, line: 144)
    static let commentEN = TextStyle(font: 89, line: 116)
    static let statusStyle = TextStyle(font: 115, line: 158)
    static let statusEN = TextStyle(font: 93, line: 121)
    static let alsoStyle = TextStyle(font: 104, line: 145)
    static let alsoEN = TextStyle(font: 90, line: 120)
    static let itemName = TextStyle(font: 107, line: 134)
    static let itemNameEN = TextStyle(font: 88, line: 134)
    static let itemComment = TextStyle(font: 99, line: 129)
    static let itemCommentEN = TextStyle(font: 85, line: 110)
    static let methodStyle = TextStyle(font: 99, line: 138)
    static let methodEN = TextStyle(font: 88, line: 114)
    static let denseRowName = TextStyle(font: 110, line: 135)
    static let denseRowNameEN = TextStyle(font: 86, line: 110)
    static let denseFact = TextStyle(font: 102, line: 130)
    static let denseFactEN = TextStyle(font: 84, line: 110)
    static let denseFactStars = TextStyle(font: 82, line: 105)
    static let denseComment = TextStyle(font: 100, line: 130)
    static let denseCommentEN = TextStyle(font: 82, line: 106)
    static let denseAlso = TextStyle(font: 96, line: 130)
    static let denseAlsoEN = TextStyle(font: 84, line: 110)
    static let recTitle = TextStyle(font: 120, line: 160)
    static let recTitleEN = TextStyle(font: 96, line: 125)
    static let recWhy = TextStyle(font: 100, line: 135)
    static let recWhyEN = TextStyle(font: 90, line: 120)
    static let recParam = TextStyle(font: 93, line: 125)
    static let denseRecTitle = TextStyle(font: 110, line: 145)
    static let denseRecTitleEN = TextStyle(font: 90, line: 115)
    static let denseRecWhy = TextStyle(font: 94, line: 125)
    static let denseRecWhyEN = TextStyle(font: 84, line: 110)
    static let denseRecParam = TextStyle(font: 86, line: 115)
    static let glossStyle = TextStyle(font: 100, line: 135)
    static let glossEN = TextStyle(font: 88, line: 115)
    static let denseGloss = TextStyle(font: 94, line: 125)
    static let denseGlossEN = TextStyle(font: 82, line: 105)
    static let privacyStyle = TextStyle(font: 96, line: 130)
    static let privacyEN = TextStyle(font: 88, line: 115)
    /// h2 with its margin, h3 with its margin, a list head with its rule, the gap before a page-6 section.
    static let h2Block = 290
    static let h3Block = 230
    static let rankHeadBlock = 270
    static let sectionGap = 110

    // MARK: Text widths

    /// Width of `text` in thousandths of an em: space 0.28, digits 0.56, m w M W % @ 0.86, narrow Latin
    /// (i l j f t r . , : ; ' | ! I ( ) [ ] { }) 0.32, other capitals 0.68, other ASCII 0.54, anything else 1 em
    /// (CJK, full-width punctuation, ★, ·, –). Also the unit of the overflow budgets.
    public static func emWidth(_ text: String) -> Int {
        var total = 0
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value == 32 {
                total += 280
            } else if value >= 48 && value <= 57 {
                total += 560
            } else if wideASCII.contains(value) {
                total += 860
            } else if narrowASCII.contains(value) {
                total += 320
            } else if value >= 65 && value <= 90 {
                total += 680
            } else if value < 128 {
                total += 540
            } else {
                total += 1000
            }
        }
        return total
    }

    /// Width of `text` in tenths of a px at font size `font` (tenths of a px), rounded up.
    static func textWidth(_ text: String, _ font: Int) -> Int {
        (emWidth(text) * font + 999) / 1000
    }

    /// Wrapped lines of `text` in a box `width` px wide (0 for empty text).
    static func lines(_ text: String, _ style: TextStyle, _ width: Int) -> Int {
        guard !text.isEmpty else { return 0 }
        let usable = width * lineSlack / 10
        return max(1, (textWidth(text, style.font) + usable - 1) / usable)
    }

    /// Lines of `text` after an inline prefix `prefix` tenths of a px wide (badges, a tag).
    static func linesAfter(_ prefix: Int, _ text: String, _ style: TextStyle, _ width: Int) -> Int {
        let usable = width * lineSlack / 10
        return max(1, (prefix + textWidth(text, style.font) + usable - 1) / usable)
    }

    static func height(_ text: String, _ style: TextStyle, _ width: Int) -> Int {
        lines(text, style, width) * style.line
    }

    static func height(_ zh: String, _ en: String, _ zhStyle: TextStyle, _ enStyle: TextStyle, _ width: Int) -> Int {
        height(zh, zhStyle, width) + height(en, enStyle, width)
    }

    static func height(_ sentences: [WeeklySentence], _ zhStyle: TextStyle, _ enStyle: TextStyle, _ width: Int) -> Int {
        var total = 0
        for sentence in sentences {
            total += height(sentence.zh, sentence.en, zhStyle, enStyle, width)
        }
        return total
    }

    /// Badges are inline blocks: text at 8 px plus 12.3 px of padding, border and margin each.
    static func badgesWidth(_ game: WeeklyGame) -> Int {
        var total = 0
        for badge in badgeTexts(game) {
            total += textWidth(badge.text, 80) + 123
        }
        return total
    }

    // MARK: Page 4

    static func estimateRankRow(_ game: WeeklyGame, _ text: WeeklyGameText, dense: Bool) -> Int {
        let nameStyle = dense ? denseRowName : rowName
        let nameEN = dense ? denseRowNameEN : rowNameEN
        let fact = dense ? denseFact : factStyle
        let factENStyle = dense ? denseFactEN : factEN
        let stars = dense ? denseFactStars : factStars
        let comment = dense ? denseComment : commentStyle
        let commentENStyle = dense ? denseCommentEN : commentEN
        let name = gameName(game.kind)
        var nameHeight = linesAfter(badgesWidth(game), name.zh, nameStyle, 196) * nameStyle.line
        nameHeight += height(name.en, nameEN, 196)
        var factHeight = height(factTail(game), stars, 155)
        if let sentence = text.fact {
            factHeight += height(sentence.zh, sentence.en, fact, factENStyle, 155)
        }
        let commentHeight = height(text.short, comment, commentENStyle, 315)
        let padding = dense ? 47 : 87
        return max(nameHeight, factHeight, commentHeight) + padding
    }

    static func estimateAlso(_ sentence: WeeklySentence?, dense: Bool) -> Int {
        guard let sentence else { return 0 }
        let zhStyle = dense ? denseAlso : alsoStyle
        let enStyle = dense ? denseAlsoEN : alsoEN
        return 60 + height(sentence.zh, sentence.en, zhStyle, enStyle, 688)
    }

    static func estimateInsufficient(_ c: WeeklyHTMLContext, columns: Bool) -> Int {
        let entries = c.analysis.ranking.insufficient
        guard !entries.isEmpty else { return 0 }
        var total = rankHeadBlock
        if !columns {
            for entry in entries {
                guard let game = c.game(entry.kind, entry.type), let text = c.text(entry.kind, entry.type) else { continue }
                let name = gameName(game.kind)
                var nameHeight = linesAfter(badgesWidth(game), name.zh, rowName, 196) * rowName.line
                nameHeight += height(name.en, rowNameEN, 196)
                total += max(nameHeight, height(text.short, commentStyle, commentEN, 481)) + 87
            }
            return total + 100
        }
        var heights: [Int] = []
        for entry in entries {
            guard let game = c.game(entry.kind, entry.type), let text = c.text(entry.kind, entry.type) else { continue }
            let name = gameName(game.kind)
            var nameWidth = badgesWidth(game) + textWidth(name.zh, itemName.font)
            nameWidth += textWidth(" " + name.en, itemNameEN.font)
            let usable = 334 * lineSlack / 10
            let nameHeight = max(1, (nameWidth + usable - 1) / usable) * itemName.line
            heights.append(nameHeight + height(text.short, itemComment, itemCommentEN, 334) + 67)
        }
        var index = 0
        while index < heights.count {
            if index + 1 < heights.count {
                total += max(heights[index], heights[index + 1])
            } else {
                total += heights[index]
            }
            index += 2
        }
        return total + 100
    }

    static func estimateMethod() -> Int {
        let method = label("p4.method", ["min": num(minimumRounds), "days": num(WeeklyRanking.minimumDays)])
        var total = 80 + 140 + 40
        total += height(method.zh, methodStyle, 664)
        total += height(method.en, methodEN, 664)
        return total
    }

    static func estimatePage4(_ c: WeeklyHTMLContext, _ variant: Page4Variant) -> Int {
        let ranking = c.analysis.ranking
        let text = c.report.ranking
        var total = h2Block
        if c.current.kinds.isEmpty || !ranking.ranked {
            let status = c.current.kinds.isEmpty ? label("none.games") : words(text.status)
            total += 80 + height(status.zh, status.en, statusStyle, statusEN, 688)
        } else {
            let sections: [(lists: WeeklyKindLists, also: WeeklySentence?, top: Bool)] = [
                (lists: ranking.top, also: text.alsoWell, top: true),
                (lists: ranking.stillLearning, also: text.alsoLearning, top: false)
            ]
            for section in sections {
                total += rankHeadBlock
                if section.top, let status = text.status {
                    total += 80 + height(status.zh, status.en, statusStyle, statusEN, 688)
                }
                if !section.top && section.lists.count == 0 {
                    let none = label("wr.bottom.none")
                    total += 80 + height(none.zh, none.en, statusStyle, statusEN, 688)
                }
                let groups: [(kinds: [String], type: WeeklyRoundType)] = [
                    (kinds: section.lists.quiz, type: .quiz), (kinds: section.lists.practice, type: .practice)
                ]
                for group in groups {
                    for kind in group.kinds {
                        guard let game = c.game(kind, group.type), let gameText = c.text(kind, group.type) else { continue }
                        total += estimateRankRow(game, gameText, dense: variant.dense)
                    }
                }
                total += estimateAlso(section.also, dense: variant.dense)
                total += variant.dense ? 60 : 100
            }
        }
        total += estimateInsufficient(c, columns: variant.columns)
        if variant.method && !c.current.kinds.isEmpty {
            total += estimateMethod()
        }
        return total
    }

    static func page4Variant(_ c: WeeklyHTMLContext) -> Page4Variant {
        let firstColumns = c.analysis.ranking.insufficient.count > insufficientRowsMax
        let variants = [
            Page4Variant(dense: false, columns: firstColumns, method: true),
            Page4Variant(dense: false, columns: true, method: true),
            Page4Variant(dense: true, columns: true, method: true),
            Page4Variant(dense: true, columns: true, method: false)
        ]
        for variant in variants where estimatePage4(c, variant) <= contentBudget {
            return variant
        }
        return variants[variants.count - 1]
    }

    // MARK: Page 6

    static func estimateRec(_ zh: String, _ en: String, why: WeeklyWords?, params: [String], dense: Bool,
                            prefix: Int = 0) -> Int {
        let title = dense ? denseRecTitle : recTitle
        let titleEN = dense ? denseRecTitleEN : recTitleEN
        let why1 = dense ? denseRecWhy : recWhy
        let whyEN = dense ? denseRecWhyEN : recWhyEN
        let param = dense ? denseRecParam : recParam
        var total = dense ? 67 : 107
        total += linesAfter(prefix, zh, title, 688) * title.line
        total += height(en, titleEN, 688)
        if let why, !why.zh.isEmpty {
            total += 20
            total += height(why.zh, why.en, why1, whyEN, 688)
        }
        for line in params {
            total += 20
            total += height(line, param, 688)
        }
        return total
    }

    static func estimateGlossary(dense: Bool) -> Int {
        let zhStyle = dense ? denseGloss : glossStyle
        let enStyle = dense ? denseGlossEN : glossEN
        var total = dense ? 140 : 170
        total += 11 + h3Block + 40
        let entries = WeeklyReportLabels.glossaryEntries()
        var index = 0
        while index < entries.count {
            var row = 0
            for entry in entries[index..<min(index + 2, entries.count)] {
                let entryHeight = height(entry.term + "：" + entry.zh, entry.en, zhStyle, enStyle, 332)
                row = max(row, entryHeight)
            }
            total += row + (dense ? 20 : 30)
            index += 2
        }
        return total
    }

    static func estimatePage6(_ c: WeeklyHTMLContext, dense: Bool, glossaryHere: Bool) -> Int {
        let report = c.report
        var total = h2Block + h3Block
        for item in report.family {
            let why = label("p6.because", ["because": words(item.because)])
            total += estimateRec(item.text.zh, item.text.en, why: why, params: [], dense: dense)
        }
        for sentence in [report.praise, report.familyNone] {
            if let sentence {
                total += estimateRec(sentence.zh, sentence.en, why: nil, params: [], dense: dense)
            }
        }
        total += dense ? 70 : sectionGap
        total += h3Block
        let tag = textWidth(label("p6.decide").zh, 85) + 130
        for item in report.app {
            let why = label("p6.why", ["because": words(item.because), "check": words(item.check)])
            total += estimateRec(item.text.zh, item.text.en, why: why, params: item.settings.map(\.en), dense: dense,
                                 prefix: tag)
        }
        if let none = report.appNone {
            total += estimateRec(none.zh, none.en, why: nil, params: [], dense: dense)
        }
        if !report.questions.isEmpty {
            total += dense ? 70 : sectionGap
            total += h3Block
            for question in report.questions {
                let note = question.note.map { words($0) }
                total += estimateRec(question.question.zh, question.question.en, why: note, params: [], dense: dense)
            }
        }
        if !glossaryHere {
            total += estimateGlossary(dense: dense)
        }
        let privacy = label("wr.privacy")
        total += 110 + 8 + 80
        total += height(privacy.zh, privacy.en, privacyStyle, privacyEN, 688)
        return total
    }

    /// Page 6 is dense when its normal estimate passes the budget (the densest layout is the last resort).
    static func page6Dense(_ c: WeeklyHTMLContext, glossaryHere: Bool) -> Bool {
        estimatePage6(c, dense: false, glossaryHere: glossaryHere) > contentBudget
    }
}
