import AVFoundation
import VisaCore

/// Interim Cantonese voice from the Mac's installed zh-HK / yue-HK system voice (ADR 0007).
/// Stays silent when no Hong Kong Cantonese voice is installed; it never falls back to Mandarin.
/// Recorded clips replace it in UX Phase 5.
@MainActor
final class SystemSpeechPrompt {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?

    init() {
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let candidates = installed.map {
            SpeechVoiceInfo(identifier: $0.identifier, name: $0.name, language: $0.language, qualityRank: $0.quality.rawValue)
        }
        var picked = CantoneseVoicePicker.pick(from: candidates)
        var resolved: AVSpeechSynthesisVoice? = picked.flatMap { AVSpeechSynthesisVoice(identifier: $0.identifier) }

        // macOS often lists Sinji as `yue-HK` (missed by older zh-HK-only filters) or omits it
        // from speechVoices() until requested by language tag.
        if resolved == nil {
            for tag in ["zh-HK", "yue-HK", "zh_HK", "yue_HK"] {
                if let byLang = AVSpeechSynthesisVoice(language: tag),
                   CantoneseVoicePicker.isHongKongCantonese(byLang.language) {
                    resolved = byLang
                    picked = SpeechVoiceInfo(
                        identifier: byLang.identifier,
                        name: byLang.name,
                        language: byLang.language,
                        qualityRank: byLang.quality.rawValue
                    )
                    break
                }
            }
        }

        voice = resolved
        let cantonese = candidates.filter { CantoneseVoicePicker.isHongKongCantonese($0.language) }.map(\.name)
        let pickedName = picked?.name ?? "none"
        let pickedLang = picked?.language ?? "none"
        VisaGamesLog.append(
            "voice — 語音 zh-HK/yue-HK picked=\(pickedName) lang=\(pickedLang) installed=\(cantonese)"
        )
    }

    var isAvailable: Bool { voice != nil }

    func speak(_ prompt: SpokenPrompt) {
        guard let voice else {
            VisaGamesLog.append("voice skip — 無粵語語音 key=\(prompt.key)")
            return
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: prompt.traditionalChinese)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.volume = 1.0
        synthesizer.speak(utterance)
        VisaGamesLog.append("voice speak — 朗讀 key=\(prompt.key) voice=\(voice.name)")
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}

extension SystemSpeechPrompt: ActivityAudioPrompting {
    nonisolated func speakPrompt(traditionalChinese: String, english: String) {
        Task { @MainActor in
            self.speak(SpokenPrompt(key: "activity.prompt", traditionalChinese: traditionalChinese, english: english))
        }
    }
}
