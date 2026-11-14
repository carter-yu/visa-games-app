import Foundation

// Hanzi H4 parent copy (0.40.0 / 88): design hanzi-tap v2 § Parent settings, the coach-vs-reveal section ("two
// settings must remain separate") and the Parent rows of § Child and parent copy. HK Traditional + English, never
// Simplified. The 描字提示 labels live in one table (`HanziParentCopy.coachLabels`): D9's three Hanzi labels (教, 提 and
// an off word) are Carter's open choice against build 80's 開／關 wording, so the table keeps the labels the app
// already shows for this enum.

/// One 描字提示 choice: the persisted coach level, its button label and its parent detail line.
public struct HanziCoachLabel: Equatable, Sendable {
    public let level: TapCountGuidanceLevel
    /// The button label (one place to change it).
    public let short: String
    /// D9's parent detail line, without a label prefix (the label is shown before it).
    public let detail: String
    public let english: String
}

public enum HanziParentCopy {
    // MARK: 描字提示 — the one label table

    public static let coachTitle = "描字提示"
    public static let coachEnglish = "Writing help"
    /// Shown once under the row: the level is Hanzi's own.
    public static let coachScope = "只影響中文字；數字同英文字母用返自己嘅描字提示。"
    public static let coachScopeEnglish = "Chinese characters only; numbers and letters keep their own tracing help."
    /// The default choice (D9: 「提 — default」 is `standard`).
    public static let coachDefault = TapCountGuidanceLevel.standard
    public static let defaultMark = "預設"

    /// Labels: the ones the app shows for `TapCountGuidanceLevel` today (多啲／標準／少啲). Details: D9's lines, with
    /// the 「提：」 prefix of the `standard` line dropped because the label is shown before every detail.
    public static let coachLabels: [HanziCoachLabel] = [
        HanziCoachLabel(level: .more, short: "多啲", detail: "次次先睇示範；卡住 1 秒就幫。",
                        english: "More: a demo every time; help after 1 s"),
        HanziCoachLabel(level: .standard, short: "標準", detail: "卡住 2 秒就幫；識寫咗就收少啲提示。",
                        english: "Standard: help after 2 s; less help once learned"),
        HanziCoachLabel(level: .less, short: "少啲", detail: "收起路牌同頭燈；卡住 8 秒仲有影子車。",
                        english: "Less: no signs or headlights; a ghost car still helps after 8 s")
    ]

    public static func coach(_ level: TapCountGuidanceLevel) -> HanziCoachLabel {
        switch level {
        case .more: return coachLabels[0]
        case .standard: return coachLabels[1]
        case .less: return coachLabels[2]
        }
    }

    /// The detail line under the buttons: 「標準（預設）：卡住 2 秒就幫；識寫咗就收少啲提示。」.
    public static func coachLine(_ level: TapCountGuidanceLevel) -> String {
        let label = coach(level)
        return "\(label.short)\(level == coachDefault ? "（\(defaultMark)）" : "")：\(label.detail)"
    }

    // MARK: 中文字設定 rows

    public static let settingsTitle = "中文字設定"
    public static let settingsSubtitle = "Chinese characters · Shared by Find & flip and Find & write"
    /// Design: 「預設關閉」；「未試玩」；「試玩一次先開星」.
    public static let defaultOff = "翻字卡同搵完寫預設關閉；每張卡要自己試玩一次先開星。"
    public static let defaultOffEnglish = "Both cards start off; each card needs its own playtest before a star can be turned on."

    public static let weekTitle = "今星期"
    public static let weekEnglish = "This week"
    public static let weekDetail = "撳一下揀，再撳一下取消；最少揀 3 個字。"
    public static let weekDetailEnglish = "Tap to choose, tap again to remove; choose at least 3 characters."
    public static let weekMinimum = "最少要揀 3 個字。"
    public static let weekMinimumEnglish = "Choose at least 3 characters."
    public static let findOnlyTitle = "只做陪襯"
    public static let findOnlyEnglish = "Extra cards only"
    public static let findOnlyDetail = "呢啲字只會喺卡上出現，唔會叫小朋友搵，亦唔會寫。"
    public static let findOnlyDetailEnglish = "These appear on the cards only: never asked, never written."

    public static let reviewTitle = "溫習"
    public static let reviewEnglish = "Review"
    /// Design: 溫習「每 4 輪 1 輪」.
    public static let reviewOn = "每 4 輪 1 輪"
    public static let reviewOnEnglish = "1 in 4 rounds"
    public static let reviewOffEnglish = "Off"

    public static let guardTitle = "易混字護欄"
    public static let guardEnglish = "Look-alike guard"
    public static let guardDetail = "個字第一次冇幫手又搵啱晒之前，易混嘅字（例如上同下）唔會同佢放埋一版。\nUntil a character has one clean find, its look-alikes (such as 上 and 下) stay off its board."

    /// 寫字格 (D3's parent choice, H4.1): 田字格 or 米字格. 米字格 is the default since Carter's 2026-11-14 「加米字格」
    /// (D3 had 田字格, with 米字格 OFF); `HanziTapSettings.defaults.grid` carries the 預設 mark.
    public static let gridTitle = "寫字格"
    public static let gridEnglish = "Writing grid"
    public static let gridTianzi = "田字格"
    public static let gridTianziEnglish = "Square grid"
    public static let gridMizi = "米字格"
    public static let gridMiziEnglish = "Diagonal grid"

    public static func gridName(_ grid: HanziWritingGrid) -> String {
        switch grid {
        case .tianzi: return gridTianzi
        case .mizi: return gridMizi
        }
    }

    public static func gridNameEnglish(_ grid: HanziWritingGrid) -> String {
        switch grid {
        case .tianzi: return gridTianziEnglish
        case .mizi: return gridMiziEnglish
        }
    }

    /// The detail line under the two choices: 「米字格（預設）：…」. 田字格 keeps D3's reason (v1: diagonals compete
    /// with 撇／捺 and the headlights); 米字格 says what the diagonals are for.
    public static func gridLine(_ grid: HanziWritingGrid) -> String {
        let mark = grid == HanziTapSettings.defaults.grid ? "（\(defaultMark)）" : ""
        switch grid {
        case .tianzi: return "\(gridTianzi)\(mark)：方框加中間十字；冇斜線，唔會同撇、捺同頭燈爭位。"
        case .mizi: return "\(gridMizi)\(mark)：田字格再加兩條斜線，幫手對準字嘅位置同平衡。"
        }
    }

    public static func gridLineEnglish(_ grid: HanziWritingGrid) -> String {
        switch grid {
        case .tianzi: return "Square grid: the box and its centre cross; no diagonals to compete with slanting strokes and the headlights."
        case .mizi: return "Diagonal grid: the square grid plus two diagonals, to help with position and balance."
        }
    }

    /// Design: 「筆順動畫：跟現有設定」. The existing setting is shown, never copied or changed here.
    public static let strokeOrderTitle = "筆順動畫"
    public static let strokeOrderEnglish = "Stroke-order animation"
    public static func strokeOrderNow(_ setting: StrokeOrderSetting) -> String {
        "跟現有設定（而家：\(StrokeOrderCopy.short(setting))）"
    }
    public static let strokeOrderNowEnglish = "Follows the existing setting"
    public static let strokeOrderWhere = "喺「一架一架數 · 數字設定」改；中文字設定唔會改佢。"
    public static let strokeOrderWhereEnglish = "Change it in Tap & Count settings; the Chinese character settings never change it."

    public static let jyutpingTitle = "粵拼"
    public static let jyutpingEnglish = "Jyutping"
    public static let jyutpingDetail = "開咗先喺字卡下面顯示。\nShown under the character card only when on."
    public static let audioTitle = "廣東話語音"
    public static let audioEnglish = "Cantonese voice"
    public static let audioDetail = "開咗先出聲，文字提示照常顯示。只用已安裝嘅香港粵語語音；冇就唔出聲。\nSpeaks only when on; text prompts always show. Uses an installed Hong Kong Cantonese voice only; silent if there is none."

    /// The pack failed to load (fail closed: no Hanzi kind is dealt), so there is nothing to choose from.
    public static let packUnavailable = "中文字卡讀唔到，暫時改唔到中文字設定。\nThe Chinese character cards couldn't be read, so these settings can't be changed."
    public static let saveNote = "儲存咗先會用；未儲存嘅改動唔會套用。"
    public static let saveNoteEnglish = "Changes apply only after Save; unsaved changes are not used."
    public static func status(hasChanges: Bool) -> String { hasChanges ? "未儲存" : "已儲存" }
    public static func statusEnglish(hasChanges: Bool) -> String { hasChanges ? "Unsaved changes" : "Saved" }

    // MARK: Parent cards

    /// The card's suggested star (D1: ★ find, ★★ find then write); any star may still be ticked after the playtest.
    public static func suggestedStar(_ kind: ActivityKind) -> String? {
        switch kind {
        case .tapHanziAll: return "建議 ★ / Suggested ★"
        case .tapHanziWrite: return "建議 ★★ / Suggested ★★"
        default: return nil
        }
    }

    public static let cardDefaultOff = "預設關閉 / Off by default"
    public static let starsLocked = "試玩一次先開星 / Playtest once to unlock the stars"

    /// What each card measures: finding is the recognition measure, guided writing is practice.
    public static func cardDetail(_ kind: ActivityKind) -> String? {
        switch kind {
        case .tapHanziAll:
            return "只計搵字：冇揀錯卡就搵啱晒，先算第一次認啱。\nFinding only: both found with no wrong card counts as recognised first time."
        case .tapHanziWrite:
            return "搵字計認字；之後寫字係練習：提示同再示範唔算搵錯，亦唔扣時間。\nFinding is the recognition measure; the writing after it is practice: its help and re-demos are never finding misses and cost no time."
        default: return nil
        }
    }

    // MARK: 表現 (review)

    public static let reportTitle = "中文字：搵字同寫字分開計 / Chinese characters: finding and writing counted separately"
    public static let reportFinding = "搵字（認字）/ Finding (recognition)"
    public static let reportWriting = "寫字（練習，唔算錯）/ Writing (practice, never a miss)"
    public static let reportEmpty = "未有中文字紀錄。 / No Chinese character records yet."
    public static let reportNoWrites = "未有寫字紀錄。 / No writing recorded yet."
    /// H3 records no separate stroke skip: a pen-down on a later start is a wrong start.
    public static let reportStrokeSkip = "跳筆：冇獨立紀錄（計入起點錯）。 / Stroke skips: not recorded separately (counted as wrong starts)."
    /// Every Hanzi round of the period is past the raw records (`PerfRetention.rawDays` days): the 表現 row counts it,
    /// but only daily totals remain, so it has no detail line. History, not 「未有中文字紀錄」.
    public static func reportDetailNotKept(_ rounds: Int) -> String {
        "呢段時間有 \(rounds) 局中文字，但逐局紀錄只留 \(PerfRetention.rawDays) 日，而家只剩每日總數，冇細項。\n"
            + "Rounds in this period: \(rounds). Round records are kept for \(PerfRetention.rawDays) days only, "
            + "so just daily totals remain and there is no detail."
    }
    /// Some rounds of the period are retained, the rest only rolled up: the lines below count the retained ones.
    public static func reportRolledUp(_ rounds: Int) -> String {
        "另外 \(rounds) 局只剩每日總數（逐局紀錄只留 \(PerfRetention.rawDays) 日），下面冇計。\n"
            + "Rounds with daily totals only: \(rounds) (round records are kept for \(PerfRetention.rawDays) days); "
            + "the lines below leave them out."
    }
}

/// The depot screen when a ticket cannot be dealt (`LetterTicketDesk.unavailable`; its title lines stay in
/// `LetterUnavailableTicketView`): which settings to check. Letters keep their build-79 line; a Hanzi ticket names
/// 中文字設定 and its card.
public enum TicketUnavailableCopy {
    public struct Lines: Equatable, Sendable {
        public let advice: String
        public let adviceEnglish: String
        /// The Hanzi cards that could not be dealt (`parentCardTitle`); empty for letters.
        public let cards: [String]

        public init(advice: String, adviceEnglish: String, cards: [String]) {
            self.advice = advice
            self.adviceEnglish = adviceEnglish
            self.cards = cards
        }
    }

    /// `kinds`: what could not be dealt (`LetterTicketDesk.unavailableKinds`); no Hanzi kind → the letter line.
    public static func lines(for kinds: [ActivityKind]) -> Lines {
        let hanzi = ActivityCatalog.playableKinds.filter { kind in kinds.contains(kind) && kind.isTapHanziFamily }
        let cards = hanzi.map(\.parentCardTitle)
        if hanzi.isEmpty {
            return Lines(advice: "叫大人長按右下角，睇吓字母設定。",
                         adviceEnglish: "Ask a grown-up to hold the bottom-right corner and check the letter settings.",
                         cards: [])
        }
        if kinds.contains(where: { $0.isTapLetterFamily }) {
            return Lines(advice: "叫大人長按右下角，睇吓字母同中文字設定。",
                         adviceEnglish: "Ask a grown-up to hold the bottom-right corner and check the letter and Chinese character settings.",
                         cards: cards)
        }
        return Lines(advice: "叫大人長按右下角，睇吓中文字設定。",
                     adviceEnglish: "Ask a grown-up to hold the bottom-right corner and check the Chinese character settings.",
                     cards: cards)
    }
}
