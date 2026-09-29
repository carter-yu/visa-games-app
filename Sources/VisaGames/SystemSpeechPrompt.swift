import AVFoundation
import VisaCore

/// Interim Cantonese voice from the Mac's installed zh-HK system voice (ADR 0007).
/// Stays silent when no zh-HK voice is installed; it never falls back to Mandarin.
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
        let picked = CantoneseVoicePicker.pick(from: candidates)
        voice = picked.flatMap { AVSpeechSynthesisVoice(identifier: $0.identifier) }
        let cantonese = candidates.filter { CantoneseVoicePicker.isHongKongCantonese($0.language) }.map(\.name)
        VisaGamesLog.append("voice — 語音 zh-HK picked=\(picked?.name ?? "none") installed=\(cantonese)")
    }

    var isAvailable: Bool { voice != nil }

    func speak(_ prompt: SpokenPrompt) {
        guard let voice else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: prompt.traditionalChinese)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
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
