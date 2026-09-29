import Foundation

/// A line the guide speaks. Cantonese is spoken; English is only a small parent subtitle.
/// `key` names the future recorded clip (UX Phase 5).
public struct SpokenPrompt: Equatable, Sendable {
    public let key: String
    public let traditionalChinese: String
    public let english: String

    public init(key: String, traditionalChinese: String, english: String) {
        self.key = key
        self.traditionalChinese = traditionalChinese
        self.english = english
    }

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

    public static let allDepotLines: [SpokenPrompt] = [depotPickTicket]

    /// All interim spoken lines (Depot + UX P2/P3). Extended in UX Phase 5 with recorded clips.
    public static let allUXLines: [SpokenPrompt] = [
        depotPickTicket, stamped, departGo, almostHome, timesUpPark, emptyAllowlist
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
public enum CantoneseVoicePicker {
    public static func isHongKongCantonese(_ language: String) -> Bool {
        language.lowercased().replacingOccurrences(of: "_", with: "-") == "zh-hk"
    }

    public static func pick(from voices: [SpeechVoiceInfo]) -> SpeechVoiceInfo? {
        voices
            .filter { isHongKongCantonese($0.language) }
            .sorted { $0.qualityRank != $1.qualityRank ? $0.qualityRank > $1.qualityRank : $0.identifier < $1.identifier }
            .first
    }
}
