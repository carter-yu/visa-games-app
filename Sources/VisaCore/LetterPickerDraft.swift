import Foundation

/// Parent visit state. No persistence occurs until the host explicitly saves `value`.
public struct LetterPickerDraft: Equatable, Sendable {
    public private(set) var saved: LetterSelectionSettings
    public private(set) var value: LetterSelectionSettings

    public init(saved: LetterSelectionSettings) {
        self.saved = saved
        self.value = saved
    }

    public var hasChanges: Bool { value != saved }

    public mutating func toggleFocus(_ letter: String) {
        guard LetterSelectionSettings.isASCII(letter) else { return }
        if value.focusLetters.contains(letter) {
            value.focusLetters.removeAll { $0 == letter }
            value.focusOrder.removeAll { $0 == letter }
        } else {
            guard value.focusLetters.count < 26 else { return }
            value.focusLetters.append(letter)
            value.focusOrder.append(letter)
            value.reviewLetters.removeAll { $0 == letter }
        }
        value.focusLetters.sort()
        value.focusOrder = value.focusLetters
        value.source = "custom"
        if Set(value.focusLetters) == Set(saved.focusLetters),
           value.reviewLetters == saved.reviewLetters, value.mirrorGuard == saved.mirrorGuard {
            value.focusLetters = saved.focusLetters
            value.focusOrder = saved.focusOrder
            value.source = saved.source
        }
    }

    public mutating func replaceFocus(_ letters: [String], source: String) {
        guard !letters.isEmpty else { return }
        value.focusLetters = letters
        value.focusOrder = letters
        value.reviewLetters.removeAll { letters.contains($0) }
        value.source = source
    }

    public mutating func setReviewEvery(_ interval: Int, candidates: [String]) {
        guard interval == 0 || interval == 4 else { return }
        value.reviewEvery = interval
        if interval == 0 { value.reviewLetters = [] }
        else if value.reviewLetters.isEmpty {
            value.reviewLetters = candidates.filter { !value.focusLetters.contains($0) }
        }
    }

    public mutating func refreshReview(_ candidates: [String]) {
        guard value.reviewEvery == 4 else { return }
        value.reviewLetters = candidates.filter { !value.focusLetters.contains($0) }
    }

    public mutating func removeReview(_ letter: String) {
        value.reviewLetters.removeAll { $0 == letter }
        if value.reviewLetters.isEmpty { value.reviewEvery = 0 }
    }

    public mutating func setMirrorGuard(_ enabled: Bool) { value.mirrorGuard = enabled }
    public mutating func cancel() { value = saved }
    public mutating func revert() { value = saved }
    public mutating func acceptSaved(_ newValue: LetterSelectionSettings) {
        saved = newValue
        value = newValue
    }
}
