import Foundation

/// A line the guide speaks. Cantonese is spoken; English is only a small parent subtitle.
/// `key` names the future recorded clip (UX Phase 5).
/// The voice a prompt is spoken in.
public enum SpokenLanguage: String, Equatable, Sendable {
    case cantonese
    case english
}

public struct SpokenPrompt: Equatable, Sendable {
    public let key: String
    public let traditionalChinese: String
    public let english: String
    /// v0.29.0: which voice says it. `.english` prompts (the English tap-count cards) are spoken
    /// in English only by the en-GB voice, with `english` as both the words and the screen text.
    public let language: SpokenLanguage

    public init(key: String, traditionalChinese: String, english: String) {
        self.key = key
        self.traditionalChinese = traditionalChinese
        self.english = english
        self.language = .cantonese
    }

    /// An English-only line (shown and spoken in English; no Chinese at all).
    public static func englishOnly(key: String, _ text: String) -> SpokenPrompt {
        SpokenPrompt(key: key, english: text)
    }

    private init(key: String, english: String) {
        self.key = key
        self.traditionalChinese = ""
        self.english = english
        self.language = .english
    }

    /// Big screen line: Chinese for Cantonese prompts, the English line for English ones.
    public var mainText: String { language == .english ? english : traditionalChinese }
    /// Small screen line under it (Cantonese prompts only).
    public var subText: String? { language == .english || english.isEmpty ? nil : english }

    public static let depotPickTicket = SpokenPrompt(
        key: "depot.pickTicket", traditionalChinese: "揀一張車票！", english: "Pick a ticket!")

    public static let stamped = SpokenPrompt(
        key: "stamp.stamped", traditionalChinese: "蓋印！", english: "Stamped!")

    public static let departGo = SpokenPrompt(
        key: "stamp.go", traditionalChinese: "出發！", english: "Go!")

    public static let almostHome = SpokenPrompt(
        key: "watch.almostHome", traditionalChinese: "快到屋企喇！", english: "Almost home!")

    public static let timesUpPark = SpokenPrompt(
        key: "timesup.park", traditionalChinese: "返車廠瞓覺喇！", english: "Time to park and rest.")

    public static let emptyAllowlist = SpokenPrompt(
        key: "play.emptyAllowlist", traditionalChinese: "未有片睇，返車廠啦！", english: "No video yet — back to the depot!")

    public static let pickVideo = SpokenPrompt(
        key: "play.pickVideo", traditionalChinese: "揀片睇！", english: "Pick a video!")

    /// Resume Choice board (v0.15.0) — paused film + new visa fork.
    public static let resumeChoiceKeepWatching = SpokenPrompt(
        key: "resumeChoice.prompt", traditionalChinese: "仲可以繼續睇！", english: "You can keep watching!")
    public static let resumeChoiceOrPick = SpokenPrompt(
        key: "resumeChoice.orPick", traditionalChinese: "定係揀第二條？", english: "Or pick another?")

    /// Wrong-answer pending-fuel exhausted → Depot (Carter 2026-10-02).
    public static let outOfFuelDepot = SpokenPrompt(
        key: "activity.outOfFuel",
        traditionalChinese: WrongAnswerCopy.returnDepotTraditionalChinese,
        english: WrongAnswerCopy.returnDepotEnglish)

    public static let allDepotLines: [SpokenPrompt] = [depotPickTicket]

    /// All interim spoken lines (Depot + UX P2/P3). Extended in UX Phase 5 with recorded clips.
    public static let allUXLines: [SpokenPrompt] = [
        depotPickTicket, stamped, departGo, pickVideo, almostHome, timesUpPark, emptyAllowlist,
        resumeChoiceKeepWatching, resumeChoiceOrPick, outOfFuelDepot
    ]

    public static func timesUp(for ticket: MissionTicket) -> SpokenPrompt {
        SpokenPrompt(
            key: "timesup.park.\(ticket.difficulty.rawValue)",
            traditionalChinese: "\(ticket.titleTraditionalChinese)返車廠 瞓覺喇！",
            english: "Time to park and rest."
        )
    }
}

/// Installed system voice, as reported by the speech synthesizer.
public struct SpeechVoiceInfo: Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let language: String
    /// 1 default, 2 enhanced, 3 premium.
    public let qualityRank: Int

    public init(identifier: String, name: String, language: String, qualityRank: Int) {
        self.identifier = identifier
        self.name = name
        self.language = language
        self.qualityRank = qualityRank
    }
}

/// Interim voice choice (ADR 0007): Hong Kong Cantonese only. A Mandarin voice reading
/// Traditional Chinese would be the wrong language, so there is no fallback.
///
/// On recent macOS, Sinji’s BCP-47 tag is often `yue-HK` (Yue/Cantonese) rather than
/// legacy `zh-HK`. Both mean HK Cantonese; `zh-CN` / `zh-TW` / `cmn-*` stay rejected.
public enum CantoneseVoicePicker {
    /// Normalized BCP-47 / Apple language tag (`zh_HK` → `zh-hk`).
    public static func normalizedLanguage(_ language: String) -> String {
        language.lowercased().replacingOccurrences(of: "_", with: "-")
    }

    public static func isHongKongCantonese(_ language: String) -> Bool {
        switch normalizedLanguage(language) {
        case "zh-hk", "yue-hk":
            return true
        default:
            return false
        }
    }

    public static func pick(from voices: [SpeechVoiceInfo]) -> SpeechVoiceInfo? {
        voices
            .filter { isHongKongCantonese($0.language) }
            .sorted { $0.qualityRank != $1.qualityRank ? $0.qualityRank > $1.qualityRank : $0.identifier < $1.identifier }
            .first
    }
}

/// English word after the Cantonese word in a guided 連一連 cue (v0.24.0, D6: en-GB).
/// British English first, then any other English voice. Never a Chinese voice. Only used after
/// a Cantonese voice was found: with no Cantonese voice the cue stays silent.
public enum EnglishVoicePicker {
    public static func isEnglish(_ language: String) -> Bool {
        CantoneseVoicePicker.normalizedLanguage(language).hasPrefix("en-")
            || CantoneseVoicePicker.normalizedLanguage(language) == "en"
    }

    public static func isBritish(_ language: String) -> Bool {
        CantoneseVoicePicker.normalizedLanguage(language) == "en-gb"
    }

    public static func pick(from voices: [SpeechVoiceInfo]) -> SpeechVoiceInfo? {
        voices
            .filter { isEnglish($0.language) }
            .sorted { lhs, rhs in
                let lb = isBritish(lhs.language), rb = isBritish(rhs.language)
                if lb != rb { return lb }
                if lhs.qualityRank != rhs.qualityRank { return lhs.qualityRank > rhs.qualityRank }
                return lhs.identifier < rhs.identifier
            }
            .first
    }
}
