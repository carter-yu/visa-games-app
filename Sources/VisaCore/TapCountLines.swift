import Foundation

/// v0.29.0: the language a tap-count card speaks and shows (the three English cards are the same
/// games as 一架一架數; only the words change).
public enum TapCountLanguage: String, Equatable, Sendable, CaseIterable {
    case cantonese
    case english
}

/// Every word the child sees or hears in a tap-count round, in the card's language.
///
/// Cantonese returns `TapCountCopy` unchanged (Chinese line + small English line). English returns
/// `TapCountEnglishCopy`: English only (main line + an English small line where the copy has one,
/// otherwise empty), spoken by the en-GB voice. Views and the model ask this for words and never branch on the language themselves, so
/// the game logic (and any guidance added later) is shared by both versions.
public struct TapCountLines: Equatable, Sendable {
    public let language: TapCountLanguage

    public init(_ language: TapCountLanguage) { self.language = language }

    public init(kind: ActivityKind) { self.language = kind.tapCountLanguage ?? .cantonese }

    private var en: Bool { language == .english }
    private typealias E = TapCountEnglishCopy

    // MARK: Spoken (also the header / tray lines)

    public func allPrompt(_ scene: TapCountScene) -> SpokenPrompt { en ? E.allPrompt(scene) : TapCountCopy.allPrompt(scene) }
    public func number(_ n: Int) -> SpokenPrompt { en ? E.number(n) : TapCountCopy.number(n) }
    public func total(_ n: Int, scene: TapCountScene) -> SpokenPrompt {
        en ? E.total(n, scene: scene) : TapCountCopy.total(n, scene: scene)
    }
    public func cuePrompt(_ n: Int) -> SpokenPrompt { en ? E.number(n) : TapCountCopy.cuePrompt(n) }
    public func donePrompt(_ n: Int, scene: TapCountScene) -> SpokenPrompt {
        en ? E.donePrompt(n, scene: scene) : TapCountCopy.donePrompt(n, scene: scene)
    }
    public func tracePrompt(_ n: Int) -> SpokenPrompt { en ? E.tracePrompt(n) : TapCountCopy.tracePrompt(n) }
    public func countedTracePrompt(_ n: Int, pick: Bool) -> SpokenPrompt {
        en ? E.countedTracePrompt(n, pick: pick) : TapCountCopy.countedTracePrompt(n, pick: pick)
    }
    public var traceNext: SpokenPrompt { en ? E.traceNext : TapCountCopy.traceNext }
    public func traceDonePrompt(_ n: Int) -> SpokenPrompt { en ? E.traceDonePrompt(n) : TapCountCopy.traceDonePrompt(n) }
    public func pickPrompt(_ n: Int) -> SpokenPrompt { en ? E.pickPrompt(n) : TapCountCopy.pickPrompt(n) }
    public var noneYet: SpokenPrompt { en ? E.noneYet : TapCountCopy.noneYet }
    public func recount(_ k: Int) -> SpokenPrompt { en ? E.recount(k) : TapCountCopy.recount(k) }
    public func need(_ n: Int) -> SpokenPrompt { en ? E.need(n) : TapCountCopy.need(n) }
    public var eraserNudge: SpokenPrompt { en ? E.eraserNudge : TapCountCopy.eraserNudge }
    public func demo(_ n: Int) -> SpokenPrompt { en ? E.demo(n) : TapCountCopy.demo(n) }
    /// Numeral trace coaching (the 畫形狀 engine's lines).
    public var cornerPrompt: SpokenPrompt { en ? E.cornerPrompt : ShapeTraceCopy.cornerPrompt }
    public var offPathPrompt: SpokenPrompt { en ? E.offPathPrompt : ShapeTraceCopy.offPathPrompt }
    public var wrongStartPrompt: SpokenPrompt { en ? E.wrongStartPrompt : ShapeTraceCopy.wrongStartPrompt }
    public var reversePrompt: SpokenPrompt { en ? E.reversePrompt : ShapeTraceCopy.reversePrompt }

    // MARK: Screen only (main line, small line; the small line is empty in English)

    public var familyTitle: String { en ? E.familyTitle : TapCountCopy.familyTitle }
    public func chipSubtitle(_ kind: ActivityKind) -> String { en ? E.chipSubtitle(kind) : TapCountCopy.chipSubtitle(kind) }
    /// Count word in the bubble beside the latest badge.
    public func countWord(_ n: Int) -> String { en ? E.countWord(n) : TapCountNumber.zh(n) }
    /// Reveal bubble 「四、」 + optional 「four」 (加英文); English: 「Four!」 alone.
    public func revealBubble(_ n: Int, addEnglish: Bool) -> (String, String?) {
        en ? (E.countWord(n), nil) : ("\(TapCountNumber.zh(n))、", addEnglish ? TapCountNumber.en(n) : nil)
    }
    /// Recount bubble words: 「一、」「二、」… 「四。」 then 「四架。」.
    /// English shows digits ("1, 2, 3, 4"): ten words do not fit the bubble, and the voice says the words.
    public func recountWord(_ index: Int, last: Bool) -> String {
        en ? "\(index)" + (last ? "" : ", ") : TapCountNumber.zh(index) + (last ? "。" : "、")
    }
    public func recountTotal(_ k: Int) -> String { en ? E.recountTotal(k) : "\(TapCountNumber.zh(k))架。" }
    /// The small line under 「要三架喎！」 (empty in English: the main line is already English).
    public func recountSubline(_ k: Int, target: Int) -> String {
        en ? "" : (1...max(k, 1)).map(TapCountNumber.enCapitalised).joined(separator: ", ") + ". " + TapCountCopy.need(target).english
    }
    public func remaining(_ n: Int) -> (String, String) {
        en ? (E.remaining(n), "") : (TapCountCopy.remainingTraditionalChinese(n), TapCountCopy.remainingEnglish(n))
    }
    public var legendTapped: (String, String) { en ? E.legendTapped : (TapCountCopy.legendTapped, TapCountCopy.legendTappedEnglish) }
    public var legendNotYet: (String, String) { en ? E.legendNotYet : (TapCountCopy.legendNotYet, TapCountCopy.legendNotYetEnglish) }
    public var legendStart: (String, String) { en ? E.legendStart : (TapCountCopy.legendStart, TapCountCopy.legendStartEnglish) }
    public var legendStop: (String, String) { en ? E.legendStop : (TapCountCopy.legendStop, TapCountCopy.legendStopEnglish) }
    public var legendStrokeNumber: (String, String) {
        en ? E.legendStrokeNumber : (TapCountCopy.legendStrokeNumber, TapCountCopy.legendStrokeNumberEnglish)
    }
    public var legendStrokeDone: (String, String) {
        en ? E.legendStrokeDone : (TapCountCopy.legendStrokeDone, TapCountCopy.legendStrokeDoneEnglish)
    }
    public var stepTap: String { en ? E.stepTap : TapCountCopy.stepTap }
    public func stepPick(_ n: Int) -> String { en ? E.stepPick(n) : TapCountCopy.stepPick(n) }
    public func stepTrace(_ n: Int) -> String { en ? E.stepTrace(n) : TapCountCopy.stepTrace(n) }
    public var traceStatus: (String, String) {
        en ? E.traceStatus : (TapCountCopy.traceStatusTraditionalChinese, TapCountCopy.traceStatusEnglish)
    }
    public var offPathStatus: (String, String) {
        en ? (E.offPathPrompt.english, E.offPathSmall) : (ShapeTraceCopy.offPathTraditionalChinese, ShapeTraceCopy.offPathEnglish)
    }
    public var lastStrokeHat: (String, String) {
        en ? E.lastStrokeHat : (TapCountCopy.lastStrokeHatTraditionalChinese, TapCountCopy.lastStrokeHatEnglish)
    }
    public func countedChip(_ n: Int, pick: Bool) -> (top: String, bottom: String) {
        en ? E.countedChip(n, pick: pick) : TapCountCopy.countedChip(n, pick: pick)
    }
    public var allTappedTray: (String, String) { en ? (E.allTappedTray, "") : (TapCountCopy.allTappedTray, TapCountCopy.allTappedTrayEnglish) }
    public var stampNextTray: (String, String) { en ? (E.stampNextTray, "") : (TapCountCopy.stampNextTray, TapCountCopy.stampNextTrayEnglish) }
    public var noMissTray: (String, String) { en ? (E.noMissTray, "") : (TapCountCopy.noMissTray, TapCountCopy.noMissTrayEnglish) }
    public func visaTray(_ minutes: Int, firstTry: Bool) -> (String, String) {
        en ? (E.visaTray(minutes), firstTry ? E.firstTryTray : "")
           : (TapCountCopy.visaTray(minutes), firstTry ? TapCountCopy.firstTryTrayEnglish : TapCountCopy.visaTrayEnglish(minutes))
    }
    public func strokesDoneTray(_ n: Int, scene: TapCountScene, pick: Bool = false) -> (String, String) {
        en ? E.strokesDoneTray(n, scene: scene, pick: pick)
           : (TapCountCopy.strokesDoneTray(n, scene: scene), TapCountCopy.strokesDoneTrayEnglish(n, scene: scene))
    }
    public var eraser: (String, String) { en ? E.eraser : (TapCountCopy.eraserTraditionalChinese, TapCountCopy.eraserEnglish) }
    public var ok: (String, String) { en ? (TapCountCopy.okLabel, E.okSub) : (TapCountCopy.okLabel, TapCountCopy.okSub) }
    /// 「叮」 star (tram) / 「嘟」 horn mark beside a tapped vehicle.
    public func tapMark(tram: Bool) -> String { en ? (tram ? E.tapMarkTram : E.tapMarkHorn) : (tram ? "叮" : "嘟") }
    /// Think Pause card in the tray (★★★ wrong answer).
    public var thinkPause: (String, String) {
        en ? E.thinkPause : (WrongAnswerCopy.thinkPauseTraditionalChinese, WrongAnswerCopy.thinkPauseEnglish)
    }
    public var fuelHalved: String { en ? E.fuelHalved : WrongAnswerCopy.fuelHalvedTraditionalChinese }
    public func fuelDropLine(from before: Int, to after: Int) -> String {
        en ? E.fuelDropLine(from: before, to: after) : TapCountCopy.fuelDropLine(from: before, to: after)
    }
    /// Visa ticket badge words: 「分鐘」 and 「簽證 Visa」.
    public var minutesWord: String { en ? E.minutesWord : "分鐘" }
    public var visaWord: String { en ? E.visaWord : "簽證 Visa" }

    // MARK: Numeral-formation guidance (v0.30.0; Opus spec, TapCountGuideData)

    private typealias G = TapCountGuideData

    /// Fills `{N}` (digit), `{zhN}` (一…十), `{EnN}` / `{enN}` (English word).
    private func fill(_ text: String, _ n: Int) -> String {
        text.replacingOccurrences(of: "{zhN}", with: TapCountNumber.zh(n))
            .replacingOccurrences(of: "{EnN}", with: TapCountNumber.enCapitalised(n))
            .replacingOccurrences(of: "{enN}", with: TapCountNumber.en(n))
            .replacingOccurrences(of: "{N}", with: "\(n)")
    }

    private func spoken(_ line: TapCountGuideLine, key: String, _ n: Int) -> SpokenPrompt {
        en ? .englishOnly(key: "en.tapCount.guide.\(key)", fill(line.en, n))
           : SpokenPrompt(key: "tapCount.guide.\(key)", traditionalChinese: fill(line.zh, n), english: fill(line.zhSub, n))
    }

    private func pair(_ line: TapCountGuideLine, _ n: Int = 0) -> (String, String) {
        en ? (fill(line.en, n), fill(line.enSub, n)) : (fill(line.zh, n), fill(line.zhSub, n))
    }

    /// Demo rhyme, one line per beat (said as the ghost car starts that beat).
    public func guideBeats(_ n: Int) -> [SpokenPrompt] {
        (G.numeral(n)?.beats ?? []).enumerated().map { spoken($0.element.line, key: "\(n).beat\($0.offset + 1)", n) }
    }
    /// Said as the ghost car merges into the real car (「到你喇！」).
    public func guideMerge(_ n: Int) -> SpokenPrompt? {
        G.numeral(n).map { spoken($0.merge, key: "\(n).merge", n) }
    }
    /// Just-in-time cue lines, in the spec's cue order.
    public func guideCues(_ n: Int) -> [SpokenPrompt] {
        (G.numeral(n)?.cues ?? []).enumerated().map { spoken($0.element.line, key: "\(n).cue\($0.offset + 1)", n) }
    }
    /// Two-stroke numerals: said as the car hops to the next stroke.
    public func guideHop(_ n: Int) -> SpokenPrompt? {
        G.numeral(n)?.hop.map { spoken($0, key: "\(n).hop", n) }
    }
    /// Tray line on the last stroke of a two-stroke numeral.
    public func guideLastStroke(_ n: Int) -> (String, String)? {
        G.numeral(n)?.lastStroke.map { pair($0, n) }
    }
    public func guideWatchFirst(_ n: Int) -> SpokenPrompt { spoken(G.copy.watchFirst, key: "watchFirst.\(n)", n) }
    public func guideYourTurn(_ n: Int) -> SpokenPrompt { spoken(G.copy.yourTurn, key: "yourTurn.\(n)", n) }
    public func guideRedemo(_ n: Int) -> SpokenPrompt { spoken(G.copy.redemo, key: "redemo.\(n)", n) }
    public var guideTrayDemo: (String, String) { pair(G.copy.trayDemo) }
    public var guideTrayTrace: (String, String) { pair(G.copy.trayTrace) }
    public var guideTrayStall: (String, String) { pair(G.copy.trayStall) }
    public var guideLegendDemoCar: (String, String) { pair(G.copy.legendDemoCar) }
    public var guideLegendRoute: (String, String) { pair(G.copy.legendRoute) }
    public var guideLegendHeadlights: (String, String) { pair(G.copy.legendHeadlights) }
    public var guideLegendAhead: (String, String) { pair(G.copy.legendAhead) }
    public var guideLegendStop: (String, String) { pair(G.copy.legendStop) }
    public var guideLegendStrokeOrder: (String, String) { pair(G.copy.legendStrokeOrder) }
    public var guideLegendHop: (String, String) { pair(G.copy.legendHop) }
    /// The word on the octagon stop sign.
    public var guideStopWord: String { en ? G.copy.stopWordEn : G.copy.stopWordZh }

    /// Every guidance prompt for numeral `n` (tests and the copy check).
    public func allGuidePrompts(_ n: Int) -> [SpokenPrompt] {
        guideBeats(n) + guideCues(n) + [guideMerge(n), guideHop(n)].compactMap { $0 }
            + [guideWatchFirst(n), guideYourTurn(n), guideRedemo(n)]
    }

    /// Every guidance screen pair (tray, legends).
    public var allGuidePairs: [(String, String)] {
        [guideTrayDemo, guideTrayTrace, guideTrayStall, guideLegendDemoCar, guideLegendRoute, guideLegendHeadlights,
         guideLegendAhead, guideLegendStop, guideLegendStrokeOrder, guideLegendHop]
            + (1...10).compactMap { guideLastStroke($0) }
    }

    // MARK: VoiceOver

    public func hearAgain(_ prompt: SpokenPrompt) -> String {
        en ? "Hear it again: \(prompt.english)" : "再聽一次：\(prompt.traditionalChinese) / Hear it again: \(prompt.english)"
    }
    public func minutesLeft(_ n: Int) -> String { en ? "\(n) minutes left" : "剩餘 \(n) 分鐘 / \(n) minutes left" }

    // MARK: Every line (tests: the English cards carry no Chinese at all)

    /// Every string a child can see or hear on these cards, for every numeral, scene and card.
    public var allChildFacingLines: [String] {
        var out: [String] = []
        func add(_ p: SpokenPrompt) { out.append(p.mainText); if let sub = p.subText { out.append(sub) } }
        func add(_ pair: (String, String)) { out.append(pair.0); if !pair.1.isEmpty { out.append(pair.1) } }
        for n in 1...10 {
            for scene in TapCountScene.allCases {
                add(allPrompt(scene)); add(total(n, scene: scene)); add(donePrompt(n, scene: scene))
                add(strokesDoneTray(n, scene: scene)); add(strokesDoneTray(n, scene: scene, pick: true))
            }
            add(number(n)); add(cuePrompt(n)); add(tracePrompt(n)); add(traceDonePrompt(n)); add(pickPrompt(n))
            add(countedTracePrompt(n, pick: true)); add(countedTracePrompt(n, pick: false))
            add(recount(n)); add(need(n)); add(demo(n))
            out.append(countWord(n)); out.append(recountWord(n, last: true)); out.append(recountWord(n, last: false))
            out.append(recountTotal(n))
            let reveal = revealBubble(n, addEnglish: true)
            out.append(reveal.0); if let e = reveal.1 { out.append(e) }
            let sub = recountSubline(n, target: max(1, n - 1)); if !sub.isEmpty { out.append(sub) }
            add(remaining(n)); out.append(stepPick(n)); out.append(stepTrace(n))
            let chip = countedChip(n, pick: true); out.append(chip.top); if !chip.bottom.isEmpty { out.append(chip.bottom) }
            add(visaTray(n, firstTry: true)); add(visaTray(n, firstTry: false))
            out.append(fuelDropLine(from: 2 * n, to: n)); out.append(minutesLeft(n))
        }
        for p in [traceNext, noneYet, eraserNudge, cornerPrompt, offPathPrompt, wrongStartPrompt, reversePrompt] { add(p) }
        for pair in [legendTapped, legendNotYet, legendStart, legendStop, legendStrokeNumber, legendStrokeDone, traceStatus,
                     offPathStatus, lastStrokeHat, allTappedTray, stampNextTray, noMissTray, eraser, ok, thinkPause] {
            add(pair)
        }
        out += [familyTitle, stepTap, tapMark(tram: true), tapMark(tram: false), fuelHalved, minutesWord, visaWord,
                hearAgain(pickPrompt(3))]
        for kind in [ActivityKind.tapCountAll, .tapCountTrace, .tapCountPick] { out.append(chipSubtitle(kind)) }
        // v0.30.0 guidance: rhymes, cues, hop, headers, tray, legends, the stop-sign word.
        for n in 1...10 { for p in allGuidePrompts(n) { add(p) } }
        for pair in allGuidePairs { add(pair) }
        out.append(guideStopWord)
        return out
    }

    /// Every spoken prompt (tests: English prompts are English-only and keyed `en.`).
    public var allSpokenPrompts: [SpokenPrompt] {
        var out: [SpokenPrompt] = [traceNext, noneYet, eraserNudge, cornerPrompt, offPathPrompt, wrongStartPrompt, reversePrompt]
        for n in 1...10 {
            for scene in TapCountScene.allCases { out += [allPrompt(scene), total(n, scene: scene), donePrompt(n, scene: scene)] }
            out += [number(n), cuePrompt(n), tracePrompt(n), traceDonePrompt(n), pickPrompt(n), recount(n), need(n), demo(n),
                    countedTracePrompt(n, pick: true), countedTracePrompt(n, pick: false)]
            out += allGuidePrompts(n)
        }
        return out
    }
}
