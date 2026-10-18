import Foundation

/// v0.28.2: text the Cantonese system voice reads, which can differ from what is shown on screen.
///
/// macOS Sinji reads the sentence-final particle 喎 as 窩 (wo1, high level). Carter wants it to
/// sound like 禍 (low; sentence-final wo5 / wo6). Measured on the Mac mini through
/// AVSpeechSynthesizer (the app's path) with Sinji, the final syllable's median pitch was:
/// 「要八架喎！」 240 Hz, the same as the 窩 control (242 Hz); 「要八架禍！」 179 Hz, about 5 semitones
/// lower. 禍 has the single Cantonese reading wo6, so the substitution behaves the same in every
/// sentence. Only the spoken string changes; the screen keeps 喎, and recorded clips are untouched.
public enum CantoneseSpeech {
    /// Shown character → character the system voice should read instead.
    public static let substitutions: [(shown: Character, spoken: Character)] = [
        ("喎", "禍"),
    ]

    public static func spoken(_ text: String) -> String {
        String(text.map { ch in substitutions.first { $0.shown == ch }?.spoken ?? ch })
    }
}
