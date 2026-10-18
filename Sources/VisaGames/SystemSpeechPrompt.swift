import AVFoundation
import VisaCore

/// Interim Cantonese voice from the Mac's installed zh-HK / yue-HK system voice (ADR 0007).
/// Stays silent when no Hong Kong Cantonese voice is installed; it never falls back to Mandarin.
/// Recorded clips replace it in UX Phase 5.
@MainActor
final class SystemSpeechPrompt {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    /// v0.24.0 guided 連一連 cue: the English word after the Cantonese one (en-GB first, D6).
    private let englishVoice: AVSpeechSynthesisVoice?
    /// Recorded clips playing or scheduled (kept alive until they finish).
    private var clipPlayers: [AVAudioPlayer] = []
    /// Device time the last scheduled clip ends (clips queue like the synthesizer does).
    private var clipQueueEndsAt: TimeInterval = 0

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
        let english = EnglishVoicePicker.pick(from: candidates)
        englishVoice = english.flatMap { AVSpeechSynthesisVoice(identifier: $0.identifier) }
            ?? AVSpeechSynthesisVoice(language: "en-GB")
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
        let utterance = AVSpeechUtterance(string: CantoneseSpeech.spoken(prompt.traditionalChinese))
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.volume = 1.0
        synthesizer.speak(utterance)
        VisaGamesLog.append("voice speak — 朗讀 key=\(prompt.key) voice=\(voice.name)")
    }

    /// Guided 連一連 road done: the Cantonese word, then the English word (「眼睛、eye」).
    /// With no Hong Kong Cantonese voice nothing is spoken at all (the bubble still shows);
    /// it never falls back to Mandarin.
    func speakWordCue(_ cue: SpokenPrompt, then follow: SpokenPrompt? = nil) {
        guard let voice else {
            VisaGamesLog.append("voice skip — 無粵語語音 key=\(cue.key)")
            return
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let word = AVSpeechUtterance(string: CantoneseSpeech.spoken(cue.traditionalChinese))
        word.voice = voice
        word.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        word.postUtteranceDelay = 0.2
        synthesizer.speak(word)
        if let englishVoice, !cue.english.isEmpty {
            let english = AVSpeechUtterance(string: cue.english)
            english.voice = englishVoice
            english.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
            english.postUtteranceDelay = follow == nil ? 0 : 0.3
            synthesizer.speak(english)
        }
        if let follow {
            // v0.25.0 畫直線: the next line's start words, in Cantonese only.
            let line = AVSpeechUtterance(string: CantoneseSpeech.spoken(follow.traditionalChinese))
            line.voice = voice
            line.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
            synthesizer.speak(line)
        }
        VisaGamesLog.append(
            "voice cue — 朗讀 key=\(cue.key) voice=\(voice.name) english=\(englishVoice?.name ?? "none")"
        )
    }

    /// v0.28.0 一架一架數 (ADR 0017): queue a word after whatever is playing, so rapid taps are all
    /// counted (「一、二、三」) instead of cutting each other off. A recorded clip
    /// `Resources/Voice/<key>.m4a` (Carter's own voice, later) wins over the system voice; the
    /// English word follows when `english` is given. Nothing here can crash or block: a missing
    /// clip falls back to the system voice, and with no Cantonese voice the word is simply not said.
    func speakQueued(_ prompt: SpokenPrompt, english: String? = nil, interrupt: Bool = false) {
        if interrupt { stop() }
        if playClips(zhKey: prompt.key, english: english) { return }
        guard let voice else {
            VisaGamesLog.append("voice skip — 無粵語語音 key=\(prompt.key)")
            return
        }
        let word = AVSpeechUtterance(string: CantoneseSpeech.spoken(prompt.traditionalChinese))
        word.voice = voice
        word.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        word.postUtteranceDelay = english == nil ? 0.05 : 0.2
        synthesizer.speak(word)
        if let english, !english.isEmpty, let englishVoice {
            let utterance = AVSpeechUtterance(string: english)
            utterance.voice = englishVoice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
            synthesizer.speak(utterance)
        }
    }

    /// Recorded clips: `Voice/<key>.m4a` in the app bundle, English as `Voice/<key>.en.m4a`.
    /// False when the Cantonese clip is missing (the caller then uses the system voice).
    private func playClips(zhKey: String, english: String?) -> Bool {
        guard let url = Bundle.main.url(forResource: zhKey, withExtension: "m4a", subdirectory: "Voice"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        let start = max(player.deviceCurrentTime, clipQueueEndsAt)
        player.prepareToPlay()
        guard player.play(atTime: start) else { return false }
        clipPlayers = clipPlayers.filter(\.isPlaying) + [player]
        clipQueueEndsAt = start + player.duration + 0.1
        if english != nil,
           let enURL = Bundle.main.url(forResource: zhKey + ".en", withExtension: "m4a", subdirectory: "Voice"),
           let enPlayer = try? AVAudioPlayer(contentsOf: enURL) {
            enPlayer.prepareToPlay()
            if enPlayer.play(atTime: clipQueueEndsAt + 0.1) {
                clipPlayers.append(enPlayer)
                clipQueueEndsAt += 0.1 + enPlayer.duration
            }
        }
        return true
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        for player in clipPlayers { player.stop() }
        clipPlayers = []
        clipQueueEndsAt = 0
    }
}

extension SystemSpeechPrompt: ActivityAudioPrompting {
    nonisolated func speakPrompt(traditionalChinese: String, english: String) {
        Task { @MainActor in
            self.speak(SpokenPrompt(key: "activity.prompt", traditionalChinese: traditionalChinese, english: english))
        }
    }
}
