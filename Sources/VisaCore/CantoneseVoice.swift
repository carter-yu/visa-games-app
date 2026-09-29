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

    public static let allDepotLines: [SpokenPrompt] = [depotPickTicket]
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
