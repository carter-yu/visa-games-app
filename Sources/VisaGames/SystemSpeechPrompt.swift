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
    /// patterns-sorting P1: the one spoken sequence (`speakSequence`) and the delegate that reports its utterances.
    private var sequence: SpeechSequenceState?
    private let sequenceDelegate = SpeechSequenceDelegate()

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
        synthesizer.delegate = sequenceDelegate
        sequenceDelegate.report = { [weak self] id, phase in self?.sequenceUtterance(id, phase) }
    }

    var isAvailable: Bool { voice != nil }

    func speak(_ prompt: SpokenPrompt) {
        if prompt.language == .english { speakEnglish(prompt, queued: false); return }
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
        if cue.language == .english {
            speakEnglish(cue, queued: false)
            if let follow { speakEnglish(follow, queued: true) }
            return
        }
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
        if prompt.language == .english { speakEnglish(prompt, queued: true); return }
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

    /// v0.29.0 English tap-count cards: English only, by the en-GB voice. A recorded clip
    /// `Voice/<key>.m4a` (English keys start `en.`) wins; with no clip and no English voice
    /// nothing is said and nothing crashes or waits (the screen line still shows).
    private func speakEnglish(_ prompt: SpokenPrompt, queued: Bool) {
        if !queued, synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        if playClips(zhKey: prompt.key, english: nil) { return }
        guard let englishVoice, !prompt.english.isEmpty else {
            VisaGamesLog.append("voice skip — no English voice key=\(prompt.key)")
            return
        }
        let utterance = AVSpeechUtterance(string: prompt.english)
        utterance.voice = englishVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.88
        utterance.postUtteranceDelay = queued ? 0.05 : 0
        synthesizer.speak(utterance)
        VisaGamesLog.append("voice speak — English key=\(prompt.key) voice=\(englishVoice.name)")
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

    /// A sequence's deadline (astra R2): stops it — its utterances and its clips — only while it is still the current
    /// sequence for `deal` and `generation` (`ReadThroughDeadline.stopsSpeech`); a newer sequence, the other lane's, or
    /// none is left alone. Like `stop()`, it reports a cancel, never an end.
    @discardableResult
    func stopSequence(deal: String, generation: Int) -> Bool {
        guard ReadThroughDeadline.stopsSpeech(currentDeal: sequence?.deal, currentGeneration: sequence?.generation,
                                              deal: deal, generation: generation) else { return false }
        stop()
        return true
    }

    func stop() {
        // A stopped sequence reports a cancel, never an end (clips fire no callback of their own when stopped).
        if let state = sequence {
            sequence = nil
            state.onEvent(.cancelled(deal: state.deal, generation: state.generation))
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        for player in clipPlayers { player.stop() }
        clipPlayers = []
        clipQueueEndsAt = 0
    }
}

// MARK: - patterns-sorting P1: spoken sequences (design §5.4)

/// What a sequence reports, tagged with the deal and the speech generation it was started for: the model ignores
/// an old one. A cancel only clears the light; it is never an end.
enum SpeechSequenceEvent: Equatable, Sendable {
    case unitStarted(index: Int, deal: String, generation: Int)
    case finished(deal: String, generation: Int)
    case cancelled(deal: String, generation: Int)
}

struct SpeechSequenceState {
    let deal: String
    let generation: Int
    let engine: ReadThroughEngine
    let count: Int
    let onEvent: @MainActor (SpeechSequenceEvent) -> Void
    /// System voice: each utterance's unit (kept alive so its identifier is not reused).
    var utterances: [ObjectIdentifier: Int] = [:]
    var retained: [AVSpeechUtterance] = []
}

/// The synthesizer's delegate (there was none before P1). It only forwards which utterance started, finished or was
/// cancelled; `SystemSpeechPrompt` ignores every utterance outside its current sequence.
final class SpeechSequenceDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    enum Phase: Sendable { case started, finished, cancelled }
    /// Set once on the main actor, read there only.
    var report: (@MainActor (ObjectIdentifier, Phase) -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        forward(utterance, .started)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        forward(utterance, .finished)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        forward(utterance, .cancelled)
    }

    private func forward(_ utterance: AVSpeechUtterance, _ phase: Phase) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.report?(id, phase) }
    }
}

extension SystemSpeechPrompt {
    /// A recorded clip for `key` in the app bundle (`Voice/<key>.m4a`).
    static func clipURL(_ key: String) -> URL? {
        Bundle.main.url(forResource: key, withExtension: "m4a", subdirectory: "Voice")
    }

    /// Speaks `units` one by one on one engine (`ReadThroughEngine.choose`: voice off → silent beat; every unit has a
    /// clip → clips; else a zh-HK / yue-HK voice → system voice; else silent beat; a clip that does not load or start
    /// moves the whole sequence off clips) and reports each unit's start and the end, tagged with `deal` and `generation`. It interrupts what was playing first. The caller owns the deadline
    /// (silent length + 4 s, `ReadThroughTiming.deadline`). Never Mandarin; with nothing to speak it is the silent beat.
    @discardableResult
    func speakSequence(_ units: [ReadThroughUnit], deal: String, generation: Int, voiceOn: Bool,
                       onEvent: @escaping @MainActor (SpeechSequenceEvent) -> Void) -> ReadThroughEngine {
        stop()
        var engine = ReadThroughEngine.choose(voiceOn: voiceOn, units: units, hasClip: { Self.clipURL($0) != nil },
                                              cantoneseVoice: voice != nil)
        if engine == .clips, let fallback = playClipSequence(units, deal: deal, generation: generation) {
            VisaGamesLog.append("voice sequence — a clip did not load or start; whole sequence on \(fallback.rawValue)")
            engine = fallback
        }
        var state = SpeechSequenceState(deal: deal, generation: generation, engine: engine, count: units.count,
                                        onEvent: onEvent)
        switch engine {
        case .systemVoice:
            for (index, unit) in units.enumerated() {
                let utterance = AVSpeechUtterance(string: CantoneseSpeech.spoken(unit.text))
                utterance.voice = voice
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
                utterance.postUtteranceDelay = unit.kind == .word ? 0.05 : 0.15
                state.utterances[ObjectIdentifier(utterance)] = index
                state.retained.append(utterance)
                synthesizer.speak(utterance)
            }
        case .clips:
            // Already queued by `playClipSequence`: every unit at its own index, the end after the last clip.
            break
        case .silentBeat:
            for (index, offset) in ReadThroughTiming.beatStarts(units).enumerated() {
                sequenceTimer(after: offset, .unitStarted(index: index, deal: deal, generation: generation))
            }
            sequenceTimer(after: ReadThroughTiming.silentLength(units), .finished(deal: deal, generation: generation))
        }
        sequence = state
        VisaGamesLog.append("voice sequence — 讀一次 engine=\(engine.rawValue) units=\(units.count) generation=\(generation)")
        return engine
    }

    /// The clips engine, all or nothing (`ReadThroughClipPlan`): every unit's clip loads before any plays, then they
    /// queue back to back, so unit i's start lights item i and the end follows the last clip. Returns the engine the
    /// whole sequence falls back to when a clip does not load or start (nothing of it is left playing), nil once the
    /// clips are queued.
    private func playClipSequence(_ units: [ReadThroughUnit], deal: String, generation: Int) -> ReadThroughEngine? {
        let players = units.map { unit in Self.clipURL(unit.key).flatMap { try? AVAudioPlayer(contentsOf: $0) } }
        switch ReadThroughClipPlan.plan(durations: players.map { $0?.duration }, units: units, cantoneseVoice: voice != nil) {
        case .fallback(let engine):
            return engine
        case .clips(let starts, let end):
            let loaded = players.compactMap { $0 }
            loaded.forEach { $0.prepareToPlay() }
            let now = loaded[0].deviceCurrentTime
            for (player, offset) in zip(loaded, starts) {
                guard player.play(atTime: now + offset) else {
                    loaded.forEach { $0.stop() }
                    return ReadThroughEngine.choose(voiceOn: true, units: units, hasClip: { _ in false },
                                                    cantoneseVoice: voice != nil)
                }
            }
            clipPlayers = loaded
            clipQueueEndsAt = now + end
            for (index, offset) in starts.enumerated() {
                sequenceTimer(after: offset, .unitStarted(index: index, deal: deal, generation: generation))
            }
            sequenceTimer(after: end, .finished(deal: deal, generation: generation))
            return nil
        }
    }

    /// A clip-start, clip-end or beat timer: it reports only while its sequence is still the current one (a stopped
    /// or replaced sequence's timers do nothing).
    private func sequenceTimer(after seconds: TimeInterval, _ event: SpeechSequenceEvent) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.sequenceTimerFired(event)
        }
    }

    private func sequenceTimerFired(_ event: SpeechSequenceEvent) {
        guard let state = sequence else { return }
        switch event {
        case .unitStarted(_, let deal, let generation), .cancelled(let deal, let generation):
            guard deal == state.deal, generation == state.generation else { return }
        case .finished(let deal, let generation):
            guard deal == state.deal, generation == state.generation else { return }
            sequence = nil
        }
        state.onEvent(event)
    }

    /// The delegate's report: `didStart` of unit i lights item i; `didFinish` of the last unit ends the sequence;
    /// `didCancel` clears the light (a cancel, never an end). Utterances outside the current sequence are ignored.
    private func sequenceUtterance(_ id: ObjectIdentifier, _ phase: SpeechSequenceDelegate.Phase) {
        guard let state = sequence, state.engine == .systemVoice, let index = state.utterances[id] else { return }
        switch phase {
        case .started:
            state.onEvent(.unitStarted(index: index, deal: state.deal, generation: state.generation))
        case .finished:
            guard index == state.count - 1 else { return }
            sequence = nil
            state.onEvent(.finished(deal: state.deal, generation: state.generation))
        case .cancelled:
            sequence = nil
            state.onEvent(.cancelled(deal: state.deal, generation: state.generation))
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
